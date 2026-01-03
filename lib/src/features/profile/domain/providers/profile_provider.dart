import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/profile/domain/models/user_profile.dart';

/// Storage keys for profile data.
abstract class ProfileStorageKeys {
  static const String profile = 'user_profile';
}

/// Provider for the current user's profile.
final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);

class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<UserProfile> build() async {
    return _loadProfile();
  }

  Future<UserProfile> _loadProfile() async {
    final json = _storage.getSetting<String>(ProfileStorageKeys.profile);
    if (json != null) {
      try {
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        return UserProfile.fromJson(decoded);
      } catch (_) {
        // Fallback to default if JSON is invalid
      }
    }
    return UserProfile.defaultProfile();
  }

  Future<void> _saveProfile(UserProfile profile) async {
    final json = jsonEncode(profile.toJson());
    await _storage.setSetting(ProfileStorageKeys.profile, json);
  }

  /// Updates the user's display name.
  Future<void> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Display name cannot be empty');
    }

    // SECURITY: Limit name length to prevent abuse
    if (trimmed.length > 50) {
      throw ArgumentError('Display name must be 50 characters or less');
    }

    final currentProfile = state.value ?? UserProfile.defaultProfile();
    final updatedProfile = currentProfile.copyWith(
      displayName: trimmed,
      updatedAt: DateTime.now(),
    );

    await _saveProfile(updatedProfile);
    state = AsyncData(updatedProfile);
  }

  /// Updates the user's status message.
  Future<void> updateStatus(String? status) async {
    final trimmed = status?.trim();

    // SECURITY: Limit status length to prevent abuse
    if (trimmed != null && trimmed.length > 140) {
      throw ArgumentError('Status must be 140 characters or less');
    }

    final currentProfile = state.value ?? UserProfile.defaultProfile();
    final updatedProfile = currentProfile.copyWith(
      status: trimmed?.isEmpty == true ? null : trimmed,
      updatedAt: DateTime.now(),
    );

    await _saveProfile(updatedProfile);
    state = AsyncData(updatedProfile);
  }

  /// Updates the user's avatar.
  Future<void> updateAvatar(String? avatarPath) async {
    final currentProfile = state.value ?? UserProfile.defaultProfile();
    final updatedProfile = currentProfile.copyWith(
      avatarPath: avatarPath,
      updatedAt: DateTime.now(),
    );

    await _saveProfile(updatedProfile);
    state = AsyncData(updatedProfile);
  }

  /// Updates the entire profile at once.
  Future<void> updateProfile({
    String? displayName,
    String? status,
    String? avatarPath,
  }) async {
    final currentProfile = state.value ?? UserProfile.defaultProfile();

    final newName = displayName?.trim() ?? currentProfile.displayName;
    final newStatus = status?.trim();

    // SECURITY: Validate inputs
    if (newName.isEmpty) {
      throw ArgumentError('Display name cannot be empty');
    }
    if (newName.length > 50) {
      throw ArgumentError('Display name must be 50 characters or less');
    }
    if (newStatus != null && newStatus.length > 140) {
      throw ArgumentError('Status must be 140 characters or less');
    }

    final updatedProfile = currentProfile.copyWith(
      displayName: newName,
      status: newStatus?.isEmpty == true ? null : newStatus,
      avatarPath: avatarPath ?? currentProfile.avatarPath,
      updatedAt: DateTime.now(),
    );

    await _saveProfile(updatedProfile);
    state = AsyncData(updatedProfile);
  }

  /// Clears the avatar.
  Future<void> clearAvatar() async {
    final currentProfile = state.value ?? UserProfile.defaultProfile();
    final updatedProfile = currentProfile.copyWith(
      avatarPath: null,
      updatedAt: DateTime.now(),
    );

    await _saveProfile(updatedProfile);
    state = AsyncData(updatedProfile);
  }
}

/// Predefined status options for quick selection.
const List<String> predefinedStatuses = [
  'Available',
  'Busy',
  'At school',
  'At the movies',
  'At work',
  'Battery about to die',
  "Can't talk, Six7 only",
  'In a meeting',
  'At the gym',
  'Sleeping',
  'Urgent calls only',
];
