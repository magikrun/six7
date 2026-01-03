import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_message.freezed.dart';
part 'chat_message.g.dart';

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
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}
