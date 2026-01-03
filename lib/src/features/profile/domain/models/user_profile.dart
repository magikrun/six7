import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_profile.freezed.dart';
part 'user_profile.g.dart';

/// Represents the current user's profile.
@freezed
abstract class UserProfile with _$UserProfile {
  const factory UserProfile({
    /// The user's display name
    required String displayName,

    /// Optional status message ("About" in WhatsApp)
    String? status,

    /// Optional avatar image path (local file path)
    String? avatarPath,

    /// When the profile was last updated
    required DateTime updatedAt,
  }) = _UserProfile;

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      _$UserProfileFromJson(json);

  /// Default profile for new users
  factory UserProfile.defaultProfile() => UserProfile(
        displayName: 'Six7 User',
        status: 'Hey there! I am using Six7',
        updatedAt: DateTime.now(),
      );
}
