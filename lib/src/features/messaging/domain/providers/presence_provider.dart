import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;

/// Constants for the presence system.
///
/// ARCHITECTURE (Inbox Model):
/// - Each user subscribes to ONE topic: "six7-presence-inbox:{myId}"
/// - Heartbeats are published TO each contact's inbox topic
/// - Privacy: Only your contacts can send you presence updates
/// - Blocked contacts are filtered out when publishing
/// - Non-contacts use ad-hoc DHT resolution (cached)
abstract final class PresenceConstants {
  /// Topic prefix for presence inbox.
  /// Format: "six7-presence-inbox:{receiverId}"
  static const String inboxTopicPrefix = 'six7-presence-inbox:';

  /// How often to send heartbeat to contacts (in seconds).
  static const int heartbeatIntervalSec = 30;

  /// How long before a peer is considered offline (in seconds).
  /// Should be > 2x heartbeat interval to allow for network delays.
  static const int offlineThresholdSec = 75;

  /// Cache TTL for ad-hoc presence checks (in seconds).
  static const int adhocCacheTtlSec = 60;

  /// Maximum contacts to send heartbeats to (prevents spam on huge contact lists).
  static const int maxHeartbeatRecipients = 200;
}

/// Presence status for a peer.
enum PresenceStatus {
  /// Peer is currently online (heartbeat received recently).
  online,

  /// Peer was recently online but no recent heartbeat.
  away,

  /// Peer hasn't sent a heartbeat in a while.
  offline,

  /// Presence status is unknown (not subscribed).
  unknown,
}

/// Presence information for a peer.
class PeerPresence {
  const PeerPresence({
    required this.peerId,
    required this.status,
    this.lastSeenMs,
    this.isContact = false,
  });

  final String peerId;
  final PresenceStatus status;
  final int? lastSeenMs;
  final bool isContact;

  /// Returns human-readable last seen text.
  String get lastSeenText {
    if (status == PresenceStatus.online) return 'online';
    if (lastSeenMs == null) return '';

    final lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenMs!);
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return 'a while ago';
  }

  PeerPresence copyWith({
    String? peerId,
    PresenceStatus? status,
    int? lastSeenMs,
    bool? isContact,
  }) {
    return PeerPresence(
      peerId: peerId ?? this.peerId,
      status: status ?? this.status,
      lastSeenMs: lastSeenMs ?? this.lastSeenMs,
      isContact: isContact ?? this.isContact,
    );
  }
}

/// Cached ad-hoc presence check result.
class _CachedPresence {
  _CachedPresence({
    required this.isReachable,
    required this.checkedAtMs,
  });

  final bool isReachable;
  final int checkedAtMs;

  bool get isExpired {
    final age = DateTime.now().millisecondsSinceEpoch - checkedAtMs;
    return age > PresenceConstants.adhocCacheTtlSec * 1000;
  }
}

/// State for the presence system.
class PresenceState {
  const PresenceState({
    this.isPublishing = false,
    this.isSubscribed = false,
    this.peerPresence = const {},
  });

  /// Whether we are currently publishing heartbeats.
  final bool isPublishing;

  /// Whether we are subscribed to our inbox.
  final bool isSubscribed;

  /// Map of peer ID (lowercase) -> presence info for contacts.
  final Map<String, PeerPresence> peerPresence;

  PresenceState copyWith({
    bool? isPublishing,
    bool? isSubscribed,
    Map<String, PeerPresence>? peerPresence,
  }) {
    return PresenceState(
      isPublishing: isPublishing ?? this.isPublishing,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      peerPresence: peerPresence ?? this.peerPresence,
    );
  }
}

/// Provider for the presence system.
final presenceProvider =
    NotifierProvider<PresenceNotifier, PresenceState>(PresenceNotifier.new);

/// Provider for a specific peer's presence status.
/// For contacts: returns real-time presence from heartbeats.
/// For non-contacts: returns cached ad-hoc check or unknown.
final peerPresenceProvider =
    Provider.family<PeerPresence, String>((ref, peerId) {
  final state = ref.watch(presenceProvider);
  final normalizedId = peerId.toLowerCase();

  // Check if we have presence data for this peer
  final presence = state.peerPresence[normalizedId];
  if (presence != null) {
    return presence;
  }

  // No presence data - return unknown (trigger ad-hoc check in UI if needed)
  return PeerPresence(
    peerId: normalizedId,
    status: PresenceStatus.unknown,
  );
});

/// Provider that returns true if a peer is online.
/// Simple boolean for UI use.
final isPeerOnlineProvider = Provider.family<bool, String>((ref, peerId) {
  final presence = ref.watch(peerPresenceProvider(peerId));
  return presence.status == PresenceStatus.online;
});

/// Provider for ad-hoc presence check (non-contacts).
/// Performs DHT resolution with caching.
final adhocPresenceProvider =
    FutureProvider.family<bool, String>((ref, peerId) async {
  // Try to resolve peer via DHT
  final nodeAsync = ref.watch(koriumNodeProvider);

  return nodeAsync.when(
    data: (node) async {
      try {
        final addresses = await node.resolvePeer(peerId: peerId);
        final isReachable = addresses.isNotEmpty;

        // Update presence state with cached result
        ref.read(presenceProvider.notifier)._updateAdhocPresence(
              peerId,
              isReachable,
            );

        return isReachable;
      } catch (_) {
        return false;
      }
    },
    loading: () async => false,
    error: (_, __) async => false,
  );
});

class PresenceNotifier extends Notifier<PresenceState> {
  Timer? _heartbeatTimer;
  Timer? _cleanupTimer;
  String? _myIdentity;

  /// Cache for ad-hoc presence checks (non-contacts).
  final Map<String, _CachedPresence> _adhocCache = {};

  @override
  PresenceState build() {
    // Start listening for presence events
    _setupEventListener();

    // Start the presence cleanup timer
    _startCleanupTimer();
    
    // Auto-start presence publishing when node is bootstrapped
    _setupAutoStart();

    // Clean up on dispose
    ref.onDispose(() {
      _heartbeatTimer?.cancel();
      _cleanupTimer?.cancel();
    });

    return const PresenceState();
  }

  /// Sets up auto-start of presence when node is ready.
  void _setupAutoStart() {
    ref.listen(bootstrapStateProvider, (previous, next) {
      if (next == true && !state.isPublishing) {
        debugPrint('[Presence] Node bootstrapped, starting presence system');
        _startPresenceSystem();
      }
    });
  }

  /// Starts the full presence system (subscribe + publish).
  Future<void> _startPresenceSystem() async {
    await _subscribeToInbox();
    await startPublishing();
    _initializeContactPresence();
  }

  /// Initializes presence state for all contacts (set to unknown initially).
  void _initializeContactPresence() {
    final contacts = ref.read(contactsProvider).value ?? [];
    final newPresence = <String, PeerPresence>{};

    for (final contact in contacts) {
      final normalizedId = contact.identity.toLowerCase();
      newPresence[normalizedId] = PeerPresence(
        peerId: normalizedId,
        status: PresenceStatus.unknown,
        isContact: true,
      );
    }

    state = state.copyWith(
      peerPresence: {...state.peerPresence, ...newPresence},
    );
  }

  /// Sets up listener for presence events from Korium.
  void _setupEventListener() {
    ref.listen(koriumEventStreamProvider, (previous, next) {
      next.whenData(_handleKoriumEvent);
    });

    // Watch the node to get our identity
    ref.listen(koriumNodeProvider, (previous, next) {
      next.whenData((node) {
        _myIdentity = node.identity.toLowerCase();
      });
    });

    // Watch contacts to update presence subscriptions
    ref.listen(contactsProvider, (previous, next) {
      next.whenData((contacts) {
        _onContactsChanged(contacts);
      });
    });
  }

  /// Handles contact list changes.
  void _onContactsChanged(List<dynamic> contacts) {
    final currentPeers = state.peerPresence.keys.toSet();
    final contactIds =
        contacts.map((c) => (c.identity as String).toLowerCase()).toSet();

    // Add new contacts to presence tracking
    for (final contactId in contactIds) {
      if (!currentPeers.contains(contactId)) {
        state = state.copyWith(
          peerPresence: {
            ...state.peerPresence,
            contactId: PeerPresence(
              peerId: contactId,
              status: PresenceStatus.unknown,
              isContact: true,
            ),
          },
        );
      }
    }

    // Mark removed contacts as non-contact (keep for ad-hoc but clear contact flag)
    for (final peerId in currentPeers) {
      if (!contactIds.contains(peerId)) {
        final existing = state.peerPresence[peerId];
        if (existing != null && existing.isContact) {
          state = state.copyWith(
            peerPresence: {
              ...state.peerPresence,
              peerId: existing.copyWith(isContact: false),
            },
          );
        }
      }
    }
  }

  /// Handles incoming Korium events.
  void _handleKoriumEvent(korium.KoriumEvent event) {
    switch (event) {
      case korium.KoriumEvent_PubSubMessage(:final topic, :final fromIdentity):
        // Check if this is our presence inbox
        final expectedTopic =
            '${PresenceConstants.inboxTopicPrefix}$_myIdentity';
        if (topic == expectedTopic) {
          _handlePresenceHeartbeat(fromIdentity);
        }

      case korium.KoriumEvent_PeerPresenceChanged(
          :final peerIdentity,
          :final isOnline
        ):
        // Handle presence change from bridge (legacy support)
        _updatePeerPresence(
          peerIdentity,
          isOnline ? PresenceStatus.online : PresenceStatus.offline,
        );

      default:
        break;
    }
  }

  /// Handles a presence heartbeat from a contact.
  void _handlePresenceHeartbeat(String fromIdentity) {
    final normalizedId = fromIdentity.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Check if this is from a known contact
    final contacts = ref.read(contactsProvider).value ?? [];
    final isContact =
        contacts.any((c) => c.identity.toLowerCase() == normalizedId);

    debugPrint(
        '[Presence] Heartbeat from ${normalizedId.substring(0, 8)}... (contact: $isContact)');

    final currentPresence = state.peerPresence[normalizedId];
    final newPresence = PeerPresence(
      peerId: normalizedId,
      status: PresenceStatus.online,
      lastSeenMs: now,
      isContact: isContact,
    );

    // Update state (only trigger rebuild if status changed)
    if (currentPresence?.status != PresenceStatus.online) {
      state = state.copyWith(
        peerPresence: {...state.peerPresence, normalizedId: newPresence},
      );
    } else {
      // Just update timestamp in place
      state.peerPresence[normalizedId] = newPresence;
    }
  }

  /// Updates a peer's presence status.
  void _updatePeerPresence(String peerId, PresenceStatus status) {
    final normalizedId = peerId.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    final currentPresence = state.peerPresence[normalizedId];
    final newPresence = PeerPresence(
      peerId: normalizedId,
      status: status,
      lastSeenMs:
          status == PresenceStatus.online ? now : currentPresence?.lastSeenMs,
      isContact: currentPresence?.isContact ?? false,
    );

    state = state.copyWith(
      peerPresence: {...state.peerPresence, normalizedId: newPresence},
    );
  }

  /// Updates presence from ad-hoc DHT check.
  void _updateAdhocPresence(String peerId, bool isReachable) {
    final normalizedId = peerId.toLowerCase();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Update cache
    _adhocCache[normalizedId] = _CachedPresence(
      isReachable: isReachable,
      checkedAtMs: now,
    );

    // Only update state if not already a contact with real presence
    final existing = state.peerPresence[normalizedId];
    if (existing == null || !existing.isContact) {
      state = state.copyWith(
        peerPresence: {
          ...state.peerPresence,
          normalizedId: PeerPresence(
            peerId: normalizedId,
            status: isReachable ? PresenceStatus.online : PresenceStatus.offline,
            lastSeenMs: now,
            isContact: false,
          ),
        },
      );
    }
  }

  /// Subscribes to our presence inbox topic.
  Future<void> _subscribeToInbox() async {
    if (state.isSubscribed) return;

    final nodeAsync = ref.read(koriumNodeProvider);
    final node = nodeAsync.value;
    if (node == null) return;

    _myIdentity ??= node.identity.toLowerCase();
    final topic = '${PresenceConstants.inboxTopicPrefix}$_myIdentity';

    try {
      await node.subscribe(topic: topic);
      state = state.copyWith(isSubscribed: true);
      debugPrint('[Presence] Subscribed to inbox: $topic');
    } catch (e) {
      debugPrint('[Presence] Failed to subscribe to inbox: $e');
    }
  }

  /// Starts publishing heartbeats to contacts' inboxes.
  Future<void> startPublishing() async {
    if (state.isPublishing) return;

    state = state.copyWith(isPublishing: true);
    debugPrint('[Presence] Starting heartbeat publishing');

    // Send first heartbeat immediately
    await _publishHeartbeats();

    // Then periodically
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: PresenceConstants.heartbeatIntervalSec),
      (_) => _publishHeartbeats(),
    );
  }

  /// Stops publishing heartbeats.
  void stopPublishing() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    state = state.copyWith(isPublishing: false);
    debugPrint('[Presence] Stopped heartbeat publishing');
  }

  /// Publishes heartbeats to each contact's inbox.
  Future<void> _publishHeartbeats() async {
    final nodeAsync = ref.read(koriumNodeProvider);
    final node = nodeAsync.value;
    if (node == null) return;

    _myIdentity ??= node.identity.toLowerCase();

    // Get contacts and blocked list
    final contacts = ref.read(contactsProvider).value ?? [];
    final settings = ref.read(accountSettingsProvider);
    final blockedSet = settings.blockedContacts.map((e) => e.toLowerCase()).toSet();

    // Check last seen privacy setting
    if (settings.lastSeen == PrivacyVisibility.nobody) {
      debugPrint('[Presence] Last seen set to nobody, not publishing');
      return;
    }

    var publishCount = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final heartbeatData = '$_myIdentity:$now'.codeUnits;

    for (final contact in contacts.take(PresenceConstants.maxHeartbeatRecipients)) {
      final contactId = contact.identity.toLowerCase();

      // Skip blocked contacts
      if (blockedSet.contains(contactId)) {
        continue;
      }

      // Skip self
      if (contactId == _myIdentity) {
        continue;
      }

      final topic = '${PresenceConstants.inboxTopicPrefix}$contactId';

      try {
        await node.publish(topic: topic, data: heartbeatData);
        publishCount++;
      } catch (e) {
        // Best effort - don't fail on individual publish errors
        debugPrint('[Presence] Failed to publish to $contactId: $e');
      }
    }

    debugPrint('[Presence] Published heartbeat to $publishCount contacts');
  }

  /// Starts the cleanup timer that marks stale peers as offline.
  void _startCleanupTimer() {
    _cleanupTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _cleanupStalePresence(),
    );
  }

  /// Marks peers as offline if we haven't received a heartbeat recently.
  void _cleanupStalePresence() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final threshold = now - (PresenceConstants.offlineThresholdSec * 1000);

    var hasChanges = false;
    final updatedPresence = <String, PeerPresence>{};

    for (final entry in state.peerPresence.entries) {
      final presence = entry.value;

      // Skip if already offline or unknown
      if (presence.status == PresenceStatus.offline ||
          presence.status == PresenceStatus.unknown) {
        updatedPresence[entry.key] = presence;
        continue;
      }

      // Check if stale (only for contacts with real presence)
      if (presence.isContact &&
          presence.lastSeenMs != null &&
          presence.lastSeenMs! < threshold) {
        updatedPresence[entry.key] = presence.copyWith(
          status: PresenceStatus.offline,
        );
        hasChanges = true;
        debugPrint('[Presence] ${entry.key.substring(0, 8)}... went offline');
      } else {
        updatedPresence[entry.key] = presence;
      }
    }

    if (hasChanges) {
      state = state.copyWith(peerPresence: updatedPresence);
    }

    // Also clean up expired ad-hoc cache entries
    _adhocCache.removeWhere((_, v) => v.isExpired);
  }

  /// Checks presence for a non-contact (ad-hoc, with cache).
  Future<bool> checkAdhocPresence(String peerId) async {
    final normalizedId = peerId.toLowerCase();

    // Check cache first
    final cached = _adhocCache[normalizedId];
    if (cached != null && !cached.isExpired) {
      return cached.isReachable;
    }

    // Perform DHT lookup
    final nodeAsync = ref.read(koriumNodeProvider);
    final node = nodeAsync.value;
    if (node == null) return false;

    try {
      final addresses = await node.resolvePeer(peerId: peerId);
      final isReachable = addresses.isNotEmpty;

      _updateAdhocPresence(peerId, isReachable);
      return isReachable;
    } catch (_) {
      return false;
    }
  }
}
