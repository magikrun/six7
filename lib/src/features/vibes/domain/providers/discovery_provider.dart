import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe.dart';
import 'package:six7_chat/src/features/vibes/domain/models/vibe_profile.dart';
import 'package:six7_chat/src/features/vibes/domain/providers/vibes_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;

/// Maximum number of discovered profiles to cache.
const int maxDiscoveredProfiles = 100;

/// Storage keys for discovery settings.
abstract class DiscoverySettingsKeys {
  static const String enabled = 'discovery_enabled';
}

/// Provider for discovery enabled state (persisted).
final discoveryEnabledProvider =
    NotifierProvider<DiscoveryEnabledNotifier, bool>(
  DiscoveryEnabledNotifier.new,
);

class DiscoveryEnabledNotifier extends Notifier<bool> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  bool build() {
    return _storage.getSetting<bool>(DiscoverySettingsKeys.enabled) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    await _storage.setSetting(DiscoverySettingsKeys.enabled, value);
    state = value;
  }
}

/// State for the discovery feature.
class DiscoveryState {
  const DiscoveryState({
    this.profiles = const [],
    this.isSubscribed = false,
    this.lastPublishTime,
    this.error,
  });

  /// Discovered profiles (LRU-bounded).
  final List<VibeProfile> profiles;

  /// Whether we're subscribed to the discovery topic.
  final bool isSubscribed;

  /// When we last published our profile.
  final DateTime? lastPublishTime;

  /// Last error, if any.
  final String? error;

  DiscoveryState copyWith({
    List<VibeProfile>? profiles,
    bool? isSubscribed,
    DateTime? lastPublishTime,
    String? error,
  }) {
    return DiscoveryState(
      profiles: profiles ?? this.profiles,
      isSubscribed: isSubscribed ?? this.isSubscribed,
      lastPublishTime: lastPublishTime ?? this.lastPublishTime,
      error: error,
    );
  }
}

/// Provider for discovery feature.
final discoveryProvider =
    AsyncNotifierProvider<DiscoveryNotifier, DiscoveryState>(
  DiscoveryNotifier.new,
);

/// Provider for profiles available to discover (excludes contacts, already vibed).
final discoverableProfilesProvider = Provider<List<VibeProfile>>((ref) {
  final discoveryState = ref.watch(discoveryProvider);
  final contacts = ref.watch(contactsProvider);
  final vibes = ref.watch(vibesProvider);
  final nodeAsync = ref.watch(koriumNodeProvider);

  final profiles = discoveryState.value?.profiles ?? [];
  final contactIds =
      (contacts.value ?? []).map((c) => c.identity.toLowerCase()).toSet();
  final vibedIds = (vibes.value ?? [])
      .where((v) => v.status != VibeStatus.skipped)
      .map((v) => v.contactId.toLowerCase())
      .toSet();

  // Get our own identity to exclude
  final myIdentity = nodeAsync.value?.identity.toLowerCase();

  return profiles.where((p) {
    final id = p.identity.toLowerCase();
    // Exclude: ourselves, existing contacts, already vibed, expired
    if (id == myIdentity ||
        contactIds.contains(id) ||
        vibedIds.contains(id) ||
        p.isExpired) {
      return false;
    }
    
    return true;
  }).toList();
});

/// Notifier for discovery feature.
class DiscoveryNotifier extends AsyncNotifier<DiscoveryState> {
  Timer? _republishTimer;

  @override
  Future<DiscoveryState> build() async {
    // Clean up on dispose
    ref.onDispose(_cleanup);

    // Listen for discovery enabled changes
    ref.listen(discoveryEnabledProvider, (prev, next) {
      if (prev != next) {
        if (next) {
          _enableDiscovery();
        } else {
          _disableDiscovery();
        }
      }
    });

    // Listen for profile changes to republish
    ref.listen(userProfileProvider, (prev, next) {
      final isEnabled = ref.read(discoveryEnabledProvider);
      if (isEnabled && prev?.value != next.value) {
        // Profile changed while discovery enabled - republish
        publishProfile();
      }
    });

    // Listen for incoming PubSub messages
    ref.listen(koriumEventStreamProvider, (prev, next) {
      next.whenData(_handleEvent);
    });

    // Check if discovery should be enabled on startup
    final enabled = ref.read(discoveryEnabledProvider);
    if (enabled) {
      // Delay to ensure node is ready
      Future.delayed(const Duration(seconds: 2), _enableDiscovery);
    }

    return const DiscoveryState();
  }

  void _cleanup() {
    _republishTimer?.cancel();
  }

  /// Enables discovery mode.
  Future<void> _enableDiscovery() async {
    final nodeAsync = ref.read(koriumNodeProvider);

    await nodeAsync.when(
      loading: () async {},
      error: (_, __) async {},
      data: (node) async {
        try {
          // Subscribe to discovery topic
          await node.subscribe(topic: vibeDiscoveryTopic);

          state = AsyncData(
            (state.value ?? const DiscoveryState()).copyWith(
              isSubscribed: true,
              error: null,
            ),
          );

          // Publish our profile
          await publishProfile();

          // Set up republish timer (every hour)
          _republishTimer?.cancel();
          _republishTimer = Timer.periodic(
            const Duration(milliseconds: profileRepublishIntervalMs),
            (_) => publishProfile(),
          );

          debugPrint('[Discovery] Enabled and subscribed to $vibeDiscoveryTopic');
        } catch (e) {
          state = AsyncData(
            (state.value ?? const DiscoveryState()).copyWith(
              error: 'Failed to enable discovery: $e',
            ),
          );
        }
      },
    );
  }

  /// Disables discovery mode.
  Future<void> _disableDiscovery() async {
    _republishTimer?.cancel();
    _republishTimer = null;

    // Note: We don't unsubscribe - just stop publishing
    // This way we still receive profiles in case user re-enables

    state = AsyncData(
      (state.value ?? const DiscoveryState()).copyWith(
        isSubscribed: false,
        lastPublishTime: null,
      ),
    );

    debugPrint('[Discovery] Disabled');
  }

  /// Publishes our profile to the discovery topic.
  Future<void> publishProfile() async {
    final nodeAsync = ref.read(koriumNodeProvider);
    final userProfileAsync = ref.read(userProfileProvider);

    final userProfile = userProfileAsync.value;
    if (userProfile == null || userProfile.displayName.isEmpty) {
      debugPrint('[Discovery] Cannot publish - no profile name set');
      return;
    }

    await nodeAsync.when(
      loading: () async {},
      error: (_, __) async {},
      data: (node) async {
        try {
          final profile = VibeProfile.create(
            identity: node.identity,
            name: userProfile.displayName,
            bio: userProfile.status,
            geohash: null, // Geolocation disabled
          );

          final validationError = profile.validate();
          if (validationError != null) {
            debugPrint('[Discovery] Profile validation failed: $validationError');
            return;
          }

          final data = profile.encode();
          if (data.length > maxProfilePayloadBytes) {
            debugPrint('[Discovery] Profile too large: ${data.length} bytes');
            return;
          }

          await node.publish(topic: vibeDiscoveryTopic, data: data.toList());

          state = AsyncData(
            (state.value ?? const DiscoveryState()).copyWith(
              lastPublishTime: DateTime.now(),
              error: null,
            ),
          );

          debugPrint('[Discovery] Published profile: ${profile.name}');
        } catch (e) {
          debugPrint('[Discovery] Failed to publish profile: $e');
        }
      },
    );
  }

  /// Handles incoming Korium events.
  void _handleEvent(korium.KoriumEvent event) {
    switch (event) {
      case korium.KoriumEvent_PubSubMessage(
        :final topic,
        :final fromIdentity,
        :final data
      ):
        if (topic == vibeDiscoveryTopic) {
          _handleDiscoveryMessage(fromIdentity, data);
        }
      default:
        break;
    }
  }

  /// Handles an incoming discovery profile.
  void _handleDiscoveryMessage(String fromIdentity, Uint8List data) {
    final profile = VibeProfile.decode(data);
    if (profile == null) {
      debugPrint('[Discovery] Failed to decode profile from $fromIdentity');
      return;
    }

    // SECURITY: Verify the sender matches the profile identity
    if (profile.identity.toLowerCase() != fromIdentity.toLowerCase()) {
      debugPrint('[Discovery] Identity mismatch: profile=${profile.identity}, sender=$fromIdentity');
      return;
    }

    // Validate the profile
    final error = profile.validate();
    if (error != null) {
      debugPrint('[Discovery] Invalid profile from $fromIdentity: $error');
      return;
    }

    // Check if expired
    if (profile.isExpired) {
      debugPrint('[Discovery] Expired profile from $fromIdentity');
      return;
    }

    // Add or update in our cache
    final currentState = state.value ?? const DiscoveryState();
    final currentProfiles = List<VibeProfile>.from(currentState.profiles);

    // Remove existing profile from same identity (update case)
    currentProfiles.removeWhere(
      (p) => p.identity.toLowerCase() == profile.identity.toLowerCase(),
    );

    // Add new profile at front
    currentProfiles.insert(0, profile);

    // Enforce LRU bound
    while (currentProfiles.length > maxDiscoveredProfiles) {
      currentProfiles.removeLast();
    }

    state = AsyncData(currentState.copyWith(profiles: currentProfiles));

    debugPrint('[Discovery] Received profile: ${profile.name} (${currentProfiles.length} cached)');
  }

  /// Clears all discovered profiles.
  void clearProfiles() {
    state = AsyncData(
      (state.value ?? const DiscoveryState()).copyWith(profiles: []),
    );
  }
}
