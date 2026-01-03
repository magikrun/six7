import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_preview.freezed.dart';
part 'chat_preview.g.dart';

/// Represents a chat conversation preview shown in the chat list.
/// All fields are immutable for thread-safety.
@freezed
abstract class ChatPreview with _$ChatPreview {
  const factory ChatPreview({
    /// The Korium identity (Ed25519 public key hex) of the peer
    required String peerId,

    /// Display name of the peer
    required String peerName,

    /// Optional avatar URL
    String? avatarUrl,

    /// Preview of the last message
    required String lastMessage,

    /// Timestamp of the last message
    required DateTime lastMessageTime,

    /// Number of unread messages
    @Default(0) int unreadCount,

    /// Whether the last message was sent by the current user
    @Default(false) bool isFromMe,

    /// Whether the message has been delivered
    @Default(false) bool isDelivered,

    /// Whether the message has been read
    @Default(false) bool isRead,

    /// Whether the chat is pinned
    @Default(false) bool isPinned,

    /// Whether the chat is muted
    @Default(false) bool isMuted,
  }) = _ChatPreview;

  factory ChatPreview.fromJson(Map<String, dynamic> json) =>
      _$ChatPreviewFromJson(json);
}
