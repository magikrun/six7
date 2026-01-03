import 'dart:convert';
import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'vibe_profile.freezed.dart';
part 'vibe_profile.g.dart';

/// Discovery topic for vibe profiles.
const String vibeDiscoveryTopic = 'six7-vibes-v1';

/// Maximum bio length in characters.
const int maxBioLength = 140;

/// Maximum profile payload size in bytes.
const int maxProfilePayloadBytes = 1024;

/// Profile TTL in milliseconds (24 hours).
const int profileTtlMs = 24 * 60 * 60 * 1000;

/// Republish interval in milliseconds (1 hour).
const int profileRepublishIntervalMs = 60 * 60 * 1000;

/// A discoverable vibe profile published to the discovery topic.
///
/// Security model:
/// - The `fromIdentity` in PubSub events is verified by Korium network
/// - We only accept profiles where fromIdentity == profile.identity
/// - No separate signature needed - network provides authenticity
/// - TTL of 24h - must be republished to stay visible
/// - Location is coarse geohash (~100km precision) for privacy
@freezed
abstract class VibeProfile with _$VibeProfile {
  const VibeProfile._();

  const factory VibeProfile({
    /// Ed25519 public key hex (64 chars) - same as Korium identity
    required String identity,

    /// Display name (1-50 chars)
    required String name,

    /// Optional short bio (max 140 chars)
    String? bio,

    /// Geohash for location-based filtering (6 chars, ~1km precision stored,
    /// but only first 3 chars used for matching = ~100km)
    String? geohash,

    /// When the profile was published (Unix ms)
    required int publishedAtMs,

    /// When the profile expires (Unix ms) - typically publishedAt + 24h
    required int expiresAtMs,
  }) = _VibeProfile;

  factory VibeProfile.fromJson(Map<String, dynamic> json) =>
      _$VibeProfileFromJson(json);

  /// Whether this profile has expired.
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch > expiresAtMs;

  /// Remaining time until expiry.
  Duration get timeUntilExpiry {
    final remaining = expiresAtMs - DateTime.now().millisecondsSinceEpoch;
    return Duration(milliseconds: remaining > 0 ? remaining : 0);
  }

  /// Encodes the profile to bytes for PubSub transmission.
  Uint8List encode() {
    final json = toJson();
    return Uint8List.fromList(utf8.encode(jsonEncode(json)));
  }

  /// Decodes a profile from PubSub bytes.
  static VibeProfile? decode(Uint8List data) {
    try {
      final json = jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
      return VibeProfile.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Validates the profile constraints.
  /// Returns null if valid, or error message if invalid.
  String? validate() {
    if (identity.length != 64) {
      return 'Invalid identity length';
    }
    if (name.isEmpty || name.length > 50) {
      return 'Name must be 1-50 characters';
    }
    if (bio != null && bio!.length > maxBioLength) {
      return 'Bio must be max $maxBioLength characters';
    }
    if (isExpired) {
      return 'Profile has expired';
    }
    return null;
  }

  /// Creates a new profile with standard TTL.
  static VibeProfile create({
    required String identity,
    required String name,
    String? bio,
    String? geohash,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return VibeProfile(
      identity: identity,
      name: name,
      bio: bio,
      geohash: geohash,
      publishedAtMs: now,
      expiresAtMs: now + profileTtlMs,
    );
  }
}
