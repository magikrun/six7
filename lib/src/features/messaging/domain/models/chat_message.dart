import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

/// Converter for Uint8List to/from JSON (base64 encoded).
class Uint8ListConverter implements JsonConverter<Uint8List?, String?> {
  const Uint8ListConverter();

  @override
  Uint8List? fromJson(String? json) {
    if (json == null) return null;
    // Decode base64
    return Uint8List.fromList(
      List<int>.from(json.codeUnits.map((c) => c)),
    );
  }

  @override
  String? toJson(Uint8List? object) {
    if (object == null) return null;
    return String.fromCharCodes(object);
  }
}

enum MessageStatus {
  pending,
  sent,
  delivered,
  read,
  failed,
}

enum MessageType {
  text,
  image,
  video,
  audio,
  document,
  location,
  contact,
  groupInvite,
}

/// Represents a chat message.
/// All fields are immutable for thread-safety.
@freezed
abstract class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    /// Unique message ID (UUID)
    required String id,

    /// The Korium identity of the sender
    required String senderId,

    /// The Korium identity of the recipient (peer or self for group messages)
    required String recipientId,

    /// Message content (text or path/URL for media)
    required String text,

    /// Message type
    @Default(MessageType.text) MessageType type,

    /// Message timestamp
    required DateTime timestamp,

    /// Message status
    @Default(MessageStatus.pending) MessageStatus status,

    /// Whether the message is from the current user
    required bool isFromMe,

    /// Group ID if this is a group message (null for 1:1 chats)
    String? groupId,

    /// Optional reply-to message ID
    String? replyToId,

    /// Optional media URL
    String? mediaUrl,

    /// Optional media thumbnail URL
    String? thumbnailUrl,

    /// Optional media size in bytes
    int? mediaSizeBytes,

    /// Optional media duration for audio/video
    Duration? mediaDuration,

    // ============ Message Franking (Abuse Reporting) ============
    // These fields enable cryptographic proof that a message was
    // authentically sent by the sender, for abuse reporting.

    /// Franking tag: HMAC(Kf, plaintext)
    /// Proves the content authenticity when revealed with the key.
    @JsonKey(includeFromJson: false, includeToJson: false)
    Uint8List? frankingTag,

    /// Franking key commitment: HMAC(Kf, ciphertext)
    /// Binds the franking key to this specific message.
    @JsonKey(includeFromJson: false, includeToJson: false)
    Uint8List? frankingKeyCommitment,

    /// Franking key (decrypted, stored locally only).
    /// NEVER transmitted - only used for report generation.
    @JsonKey(includeFromJson: false, includeToJson: false)
    Uint8List? frankingKey,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
