import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/notifications/notification_service.dart';
import 'package:six7_chat/src/core/storage/models/vibe_hive.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/message_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe_profile.dart';
import 'package:six7_chat/src/features/vibes/domain/providers/discovery_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/utils/vibe_crypto.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;
import 'package:uuid/uuid.dart';

/// Provider for vibes (matching feature).
final vibesProvider = AsyncNotifierProvider<VibesNotifier, List<Vibe>>(
  VibesNotifier.new,
);

/// Provider for contacts available to vibe (not yet vibed or matched).
final availableToVibeProvider = Provider<List<Contact>>((ref) {
  final contactsAsync = ref.watch(contactsProvider);
  final vibesAsync = ref.watch(vibesProvider);

  final contacts = contactsAsync.value ?? [];
  final vibes = vibesAsync.value ?? [];

  // Get IDs of contacts we've already vibed or matched
  final vibedIds = vibes
      .where((v) => v.status != VibeStatus.skipped)
      .map((v) => v.contactId)
      .toSet();

  // Filter to contacts not yet vibed and not blocked
  return contacts
      .where((c) => !vibedIds.contains(c.identity) && !c.isBlocked)
      .toList();
});

/// Provider for matched vibes only.
final matchedVibesProvider = Provider<List<Vibe>>((ref) {
  final vibesAsync = ref.watch(vibesProvider);
  final vibes = vibesAsync.value ?? [];
  return vibes.where((v) => v.status == VibeStatus.matched).toList();
});

/// Provider for pending vibes (we sent, awaiting response).
final pendingVibesProvider = Provider<List<Vibe>>((ref) {
  final vibesAsync = ref.watch(vibesProvider);
  final vibes = vibesAsync.value ?? [];
  return vibes.where((v) => v.status == VibeStatus.pending).toList();
});

/// Provider for received vibes (they vibed us, we haven't responded).
final receivedVibesProvider = Provider<List<Vibe>>((ref) {
  final vibesAsync = ref.watch(vibesProvider);
  final vibes = vibesAsync.value ?? [];
  return vibes.where((v) => v.status == VibeStatus.received).toList();
});

/// Notifier for managing vibes.
class VibesNotifier extends AsyncNotifier<List<Vibe>> {
  static const _uuid = Uuid();

  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<List<Vibe>> build() async {
    // Listen for incoming vibe messages
    _setupEventListener();

    return _loadVibes();
  }

  Future<List<Vibe>> _loadVibes() async {
    final hiveVibes = _storage.getAllVibes();
    return hiveVibes.map(_hiveToModel).toList();
  }

  Vibe _hiveToModel(VibeHive hive) {
    return Vibe(
      id: hive.id,
      contactId: hive.contactId,
      contactName: hive.contactName,
      contactAvatarPath: hive.contactAvatarPath,
      ourCommitment: hive.ourCommitment,
      ourSecret: hive.ourSecret,
      theirCommitment: hive.theirCommitment,
      status: _hiveStatusToModel(hive.status),
      createdAt: DateTime.fromMillisecondsSinceEpoch(hive.createdAtMs),
      matchedAt: hive.matchedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(hive.matchedAtMs!)
          : null,
    );
  }

  VibeHive _modelToHive(Vibe vibe) {
    return VibeHive(
      id: vibe.id,
      contactId: vibe.contactId,
      contactName: vibe.contactName,
      contactAvatarPath: vibe.contactAvatarPath,
      ourCommitment: vibe.ourCommitment,
      ourSecret: vibe.ourSecret,
      theirCommitment: vibe.theirCommitment,
      status: _modelStatusToHive(vibe.status),
      createdAtMs: vibe.createdAt.millisecondsSinceEpoch,
      matchedAtMs: vibe.matchedAt?.millisecondsSinceEpoch,
    );
  }

  VibeStatus _hiveStatusToModel(VibeStatusHive status) {
    return switch (status) {
      VibeStatusHive.pending => VibeStatus.pending,
      VibeStatusHive.matched => VibeStatus.matched,
      VibeStatusHive.received => VibeStatus.received,
      VibeStatusHive.skipped => VibeStatus.skipped,
    };
  }

  VibeStatusHive _modelStatusToHive(VibeStatus status) {
    return switch (status) {
      VibeStatus.pending => VibeStatusHive.pending,
      VibeStatus.matched => VibeStatusHive.matched,
      VibeStatus.received => VibeStatusHive.received,
      VibeStatus.skipped => VibeStatusHive.skipped,
    };
  }

  /// Sets up listener for incoming Korium events.
  void _setupEventListener() {
    ref.listen(
      koriumEventStreamProvider,
      (previous, next) {
        next.whenData(_handleKoriumEvent);
      },
    );
  }

  /// Handles incoming Korium events.
  void _handleKoriumEvent(korium.KoriumEvent event) {
    switch (event) {
      case korium.KoriumEvent_ChatMessageReceived(:final message):
        // Check if this is a vibe message
        if (message.messageType == korium.MessageType.vibe) {
          _handleIncomingVibe(message);
        }

      default:
        // Not handled here
        break;
    }
  }

  /// Sends a vibe to a contact.
  Future<void> sendVibe(Contact contact) async {
    // Check if we already have a vibe with this contact
    final existing = (state.value ?? [])
        .where((v) => v.contactId.toLowerCase() == contact.identity.toLowerCase())
        .firstOrNull;

    if (existing != null) {
      if (existing.status == VibeStatus.received) {
        // They already vibed us - this creates a match!
        await _completeMatch(existing, contact);
        return;
      } else if (existing.status != VibeStatus.skipped) {
        // Already pending or matched
        debugPrint('[Vibes] Already vibed this contact');
        return;
      }
    }

    // Generate secret and commitment
    final vibeId = _uuid.v4();
    final secret = VibeCrypto.generateSecret();
    final commitment = VibeCrypto.createCommitment(secret);

    // Create vibe record (secret stored in model, persisted via Hive)
    final vibe = Vibe(
      id: vibeId,
      contactId: contact.identity,
      contactName: contact.displayName,
      contactAvatarPath: contact.avatarUrl,
      ourCommitment: commitment,
      ourSecret: secret,
      status: VibeStatus.pending,
      createdAt: DateTime.now(),
    );

    // Save to storage
    await _storage.saveVibe(_modelToHive(vibe));

    // Update state
    final currentVibes = state.value ?? [];
    // Remove any existing skipped vibe for this contact
    final filtered = currentVibes
        .where((v) => v.contactId.toLowerCase() != contact.identity.toLowerCase())
        .toList();
    state = AsyncData([vibe, ...filtered]);

    // Send vibe message to contact
    await _sendVibeMessage(
      recipientId: contact.identity,
      payload: VibePayload(
        type: VibeMessageType.commitment,
        vibeId: vibeId,
        commitment: commitment,
      ),
    );

    debugPrint('[Vibes] Sent vibe to ${contact.displayName}');
  }

  /// Skips a contact by identity (won't show in available list).
  Future<void> skipContact(String contactId) async {
    // Look up contact info if available
    final contacts = ref.read(contactsProvider).value ?? [];
    final contact = contacts.where((c) => c.identity == contactId).firstOrNull;
    
    final vibeId = _uuid.v4();

    final vibe = Vibe(
      id: vibeId,
      contactId: contactId,
      contactName: contact?.displayName ?? _truncateId(contactId),
      contactAvatarPath: contact?.avatarUrl,
      status: VibeStatus.skipped,
      createdAt: DateTime.now(),
    );

    await _storage.saveVibe(_modelToHive(vibe));

    final currentVibes = state.value ?? [];
    state = AsyncData([vibe, ...currentVibes]);

    debugPrint('[Vibes] Skipped ${vibe.contactName}');
  }

  /// Sends a vibe to a discovered profile (not yet a contact).
  Future<void> sendVibeToDiscovered(VibeProfile profile) async {
    // Check if we already have a vibe with this peer
    final existing = (state.value ?? [])
        .where((v) => v.contactId.toLowerCase() == profile.identity.toLowerCase())
        .firstOrNull;

    if (existing != null) {
      if (existing.status == VibeStatus.received) {
        // They already vibed us - this creates a match!
        await _completeMatchForPeer(
          vibe: existing,
          peerId: profile.identity,
          peerName: profile.name,
          peerAvatar: null,
        );
        return;
      } else if (existing.status != VibeStatus.skipped) {
        // Already pending or matched
        debugPrint('[Vibes] Already vibed this discovered profile');
        return;
      }
    }

    // Generate secret and commitment
    final vibeId = _uuid.v4();
    final secret = VibeCrypto.generateSecret();
    final commitment = VibeCrypto.createCommitment(secret);

    // Create vibe record
    final vibe = Vibe(
      id: vibeId,
      contactId: profile.identity,
      contactName: profile.name,
      contactAvatarPath: null,
      ourCommitment: commitment,
      ourSecret: secret,
      status: VibeStatus.pending,
      createdAt: DateTime.now(),
    );

    // Save to storage
    await _storage.saveVibe(_modelToHive(vibe));

    // Update state
    final currentVibes = state.value ?? [];
    // Remove any existing skipped vibe
    final filtered = currentVibes
        .where((v) => v.contactId.toLowerCase() != profile.identity.toLowerCase())
        .toList();
    state = AsyncData([vibe, ...filtered]);

    // Send vibe message
    await _sendVibeMessage(
      recipientId: profile.identity,
      payload: VibePayload(
        type: VibeMessageType.commitment,
        vibeId: vibeId,
        commitment: commitment,
      ),
    );

    debugPrint('[Vibes] Sent vibe to discovered profile: ${profile.name}');
  }

  /// Skips a discovered profile by identity.
  Future<void> skipDiscovered(String identity) async {
    // Look up profile info if available
    final discoveryState = ref.read(discoveryProvider).value;
    final profile = discoveryState?.profiles
        .where((p) => p.identity.toLowerCase() == identity.toLowerCase())
        .firstOrNull;

    final vibeId = _uuid.v4();

    final vibe = Vibe(
      id: vibeId,
      contactId: identity,
      contactName: profile?.name ?? _truncateId(identity),
      contactAvatarPath: null,
      status: VibeStatus.skipped,
      createdAt: DateTime.now(),
    );

    await _storage.saveVibe(_modelToHive(vibe));

    final currentVibes = state.value ?? [];
    state = AsyncData([vibe, ...currentVibes]);

    debugPrint('[Vibes] Skipped discovered: ${vibe.contactName}');
  }

  /// Handles an incoming vibe message.
  Future<void> _handleIncomingVibe(korium.ChatMessage message) async {
    final payload = VibePayload.decode(message.text);
    if (payload == null) {
      debugPrint('[Vibes] Invalid vibe payload');
      return;
    }

    final senderId = message.senderId;

    switch (payload.type) {
      case VibeMessageType.commitment:
        await _handleIncomingCommitment(senderId, payload);
      case VibeMessageType.reveal:
        await _handleIncomingReveal(senderId, payload);
    }
  }

  /// Handles an incoming commitment (someone vibed us).
  Future<void> _handleIncomingCommitment(String senderId, VibePayload payload) async {
    final currentVibes = state.value ?? [];
    final existing = currentVibes
        .where((v) => v.contactId.toLowerCase() == senderId.toLowerCase())
        .firstOrNull;

    if (existing != null) {
      if (existing.status == VibeStatus.pending) {
        // We already vibed them - this is a match!
        // Update the vibe with their commitment
        final updated = existing.copyWith(
          theirCommitment: payload.commitment,
        );
        
        // Get contact/discovered profile info for the match
        final (senderName, senderAvatar) = _lookupSenderInfo(senderId);
        
        // Create a pseudo-contact for the match flow
        await _completeMatchForPeer(
          vibe: updated,
          peerId: senderId,
          peerName: senderName,
          peerAvatar: senderAvatar,
        );
        return;
      } else if (existing.status == VibeStatus.matched) {
        // RACE CONDITION: Already matched, just store their commitment if missing
        if (existing.theirCommitment == null) {
          final updated = existing.copyWith(theirCommitment: payload.commitment);
          await _storage.saveVibe(_modelToHive(updated));
          state = AsyncData(
            currentVibes.map((v) => v.id == existing.id ? updated : v).toList(),
          );
        }
        debugPrint('[Vibes] Already matched with $senderId, ignoring duplicate commitment');
        return;
      } else if (existing.status == VibeStatus.received) {
        // They already vibed us before - update commitment if different
        if (existing.theirCommitment != payload.commitment) {
          final updated = existing.copyWith(theirCommitment: payload.commitment);
          await _storage.saveVibe(_modelToHive(updated));
          state = AsyncData(
            currentVibes.map((v) => v.id == existing.id ? updated : v).toList(),
          );
        }
        debugPrint('[Vibes] Already received vibe from $senderId, updated commitment');
        return;
      }
      // If skipped, fall through to create new received vibe
    }

    // They vibed us first - store as received
    // Get sender info from contacts OR discovered profiles
    final (senderName, senderAvatar) = _lookupSenderInfo(senderId);

    final vibe = Vibe(
      id: payload.vibeId,
      contactId: senderId,
      contactName: senderName,
      contactAvatarPath: senderAvatar,
      theirCommitment: payload.commitment,
      status: VibeStatus.received,
      createdAt: DateTime.now(),
    );

    // Save to storage
    await _storage.saveVibe(_modelToHive(vibe));

    // Update state - remove any existing skipped vibe for this contact
    final filtered = currentVibes
        .where((v) => v.contactId.toLowerCase() != senderId.toLowerCase())
        .toList();
    state = AsyncData([vibe, ...filtered]);

    // Show notification for received vibe
    await ref.read(notificationServiceProvider).showVibeReceivedNotification(
      contactId: senderId,
      contactName: senderName,
    );

    debugPrint('[Vibes] Received vibe from ${vibe.contactName}');
  }

  /// Handles an incoming reveal (match confirmation).
  Future<void> _handleIncomingReveal(String senderId, VibePayload payload) async {
    final currentVibes = state.value ?? [];
    final vibe = currentVibes
        .where((v) => v.contactId.toLowerCase() == senderId.toLowerCase())
        .firstOrNull;

    if (vibe == null) {
      debugPrint('[Vibes] Unexpected reveal from unknown $senderId');
      return;
    }

    // Handle reveal for pending vibes (we vibed first, they're confirming)
    if (vibe.status == VibeStatus.pending) {
      // Verify the secret matches their commitment
      if (vibe.theirCommitment != null && payload.secret != null) {
        if (VibeCrypto.verifyCommitment(payload.secret!, vibe.theirCommitment!)) {
          // Valid reveal - mark as matched
          final updated = vibe.copyWith(
            status: VibeStatus.matched,
            matchedAt: DateTime.now(),
          );

          await _storage.saveVibe(_modelToHive(updated));

          state = AsyncData(
            currentVibes.map((v) => v.id == vibe.id ? updated : v).toList(),
          );

          // Show notification for the match (we vibed second, so we also need notif)
          await ref.read(notificationServiceProvider).showVibeMatchNotification(
            contactId: vibe.contactId,
            contactName: vibe.contactName,
          );

          debugPrint('[Vibes] Match confirmed with ${vibe.contactName}!');
        } else {
          debugPrint('[Vibes] Invalid reveal secret from $senderId');
        }
      }
    } else if (vibe.status == VibeStatus.matched) {
      // Already matched - ignore duplicate reveal
      debugPrint('[Vibes] Ignoring duplicate reveal from $senderId');
    } else {
      debugPrint('[Vibes] Unexpected reveal for vibe status ${vibe.status}');
    }
  }

  /// Completes a match when both users have vibed (for contacts).
  Future<void> _completeMatch(Vibe vibe, Contact contact) async {
    await _completeMatchForPeer(
      vibe: vibe,
      peerId: contact.identity,
      peerName: contact.displayName,
      peerAvatar: contact.avatarUrl,
    );
  }

  /// Sends a vibe message via Korium.
  Future<void> _sendVibeMessage({
    required String recipientId,
    required VibePayload payload,
  }) async {
    final nodeAsync = ref.read(koriumNodeProvider);

    await nodeAsync.when(
      loading: () async {},
      error: (_, __) async {},
      data: (node) async {
        final messageId = _uuid.v4();
        final now = DateTime.now().millisecondsSinceEpoch;

        final message = korium.ChatMessage(
          id: messageId,
          senderId: node.identity,
          recipientId: recipientId,
          text: payload.encode(),
          messageType: korium.MessageType.vibe,
          timestampMs: now,
          status: korium.MessageStatus.pending,
          isFromMe: true,
        );

        try {
          await node.sendMessage(peerId: recipientId, message: message);
        } catch (e) {
          debugPrint('[Vibes] Failed to send vibe message: $e');
        }
      },
    );
  }

  /// Clears a match (removes from matches list).
  Future<void> clearMatch(String vibeId) async {
    await _storage.deleteVibe(vibeId);
    final currentVibes = state.value ?? [];
    state = AsyncData(currentVibes.where((v) => v.id != vibeId).toList());
  }

  /// Resets all vibes (for testing/debugging).
  Future<void> resetAllVibes() async {
    await _storage.clearAllVibes();
    state = const AsyncData([]);
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  /// Looks up sender info from contacts first, then discovered profiles.
  /// Returns (name, avatarPath) tuple.
  (String, String?) _lookupSenderInfo(String senderId) {
    // First, check contacts
    final contacts = ref.read(contactsProvider).value ?? [];
    final contact = contacts
        .where((c) => c.identity.toLowerCase() == senderId.toLowerCase())
        .firstOrNull;

    if (contact != null) {
      return (contact.displayName, contact.avatarUrl);
    }

    // Second, check discovered profiles (from Discovery feature)
    final discoveryState = ref.read(discoveryProvider).value;
    if (discoveryState != null) {
      final discoveredProfile = discoveryState.profiles
          .where((p) => p.identity.toLowerCase() == senderId.toLowerCase())
          .firstOrNull;

      if (discoveredProfile != null) {
        return (discoveredProfile.name, null);
      }
    }

    // Fallback: truncated ID
    return (_truncateId(senderId), null);
  }

  /// Completes a match for any peer (contact or discovered).
  Future<void> _completeMatchForPeer({
    required Vibe vibe,
    required String peerId,
    required String peerName,
    required String? peerAvatar,
  }) async {
    // Get our secret from the vibe model
    final ourSecret = vibe.ourSecret;

    // Update vibe to matched with peer info
    final matched = vibe.copyWith(
      contactName: peerName,
      contactAvatarPath: peerAvatar,
      status: VibeStatus.matched,
      matchedAt: DateTime.now(),
    );

    await _storage.saveVibe(_modelToHive(matched));

    // Update state
    final currentVibes = state.value ?? [];
    state = AsyncData(
      currentVibes.map((v) => v.contactId == peerId ? matched : v).toList(),
    );

    // Show match notification
    await ref.read(notificationServiceProvider).showVibeMatchNotification(
      contactId: peerId,
      contactName: peerName,
    );

    // Send our secret to confirm the match
    if (ourSecret != null) {
      await _sendVibeMessage(
        recipientId: peerId,
        payload: VibePayload(
          type: VibeMessageType.reveal,
          vibeId: vibe.id,
          secret: ourSecret,
        ),
      );
    } else {
      debugPrint('[Vibes] WARNING: No secret found for vibe ${vibe.id} - cannot send reveal');
    }

    // Send automatic match message to start the conversation
    // To avoid duplicates in race conditions, only the user with the 
    // lexicographically lower identity sends the message
    final nodeAsync = ref.read(koriumNodeProvider);
    final myIdentity = nodeAsync.value?.identity;
    
    if (myIdentity != null && myIdentity.toLowerCase().compareTo(peerId.toLowerCase()) < 0) {
      await _sendMatchMessage(peerId: peerId, peerName: peerName);
    } else {
      debugPrint('[Vibes] Peer will send match message (their ID is lower)');
    }

    debugPrint('[Vibes] MATCH with $peerName! 🎉');
  }

  /// Sends an automatic message when a match occurs.
  /// This creates a chat entry for both users immediately.
  Future<void> _sendMatchMessage({
    required String peerId,
    required String peerName,
  }) async {
    const matchMessage = '🎉 You matched! Say hi!';
    
    try {
      // Send the match message through the message provider
      // This will persist it locally and send it to the peer
      final error = await ref
          .read(messageProvider(peerId).notifier)
          .sendMessage(matchMessage);
      
      if (error != null) {
        debugPrint('[Vibes] Failed to send match message: $error');
      } else {
        debugPrint('[Vibes] Match message sent to $peerName');
      }
    } catch (e) {
      debugPrint('[Vibes] Error sending match message: $e');
    }
  }
}
