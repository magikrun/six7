import 'package:freezed_annotation/freezed_annotation.dart';

part 'vibe.freezed.dart';
part 'vibe.g.dart';

/// Status of a vibe.
enum VibeStatus {
  /// We sent a vibe, waiting for response
  pending,
  /// Mutual match - both users vibed each other
  matched,
  /// They vibed us but we haven't responded
  received,
  /// We skipped this contact
  skipped,
}

/// Represents a vibe (anonymous interest signal) between users.
/// 
/// Privacy model:
/// - When you vibe someone, you send an encrypted commitment token
/// - They can't read it unless they also vibed you
/// - Only mutual vibes reveal the match
@freezed
abstract class Vibe with _$Vibe {
  const factory Vibe({
    /// Unique ID for this vibe
    required String id,

    /// The contact's identity we vibed (or who vibed us)
    required String contactId,

    /// Display name of the contact (for UI)
    required String contactName,

    /// Contact's avatar path (if any)
    String? contactAvatarPath,

    /// Our commitment token (hex-encoded, sent to them)
    String? ourCommitment,

    /// Our secret (hex-encoded, used to create commitment - kept locally)
    String? ourSecret,

    /// Their commitment token (hex-encoded, received from them)
    String? theirCommitment,

    /// Current status
    required VibeStatus status,

    /// When we sent/received the initial vibe
    required DateTime createdAt,

    /// When the match was revealed (if matched)
    DateTime? matchedAt,
  }) = _Vibe;

  factory Vibe.fromJson(Map<String, dynamic> json) => _$VibeFromJson(json);
}
