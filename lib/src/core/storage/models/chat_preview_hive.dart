import 'package:hive/hive.dart';
import 'package:six7_chat/src/core/storage/models/chat_message_hive.dart';

/// Hive-compatible chat preview model.
@HiveType(typeId: HiveTypeIds.chatPreview)
class ChatPreviewHive extends HiveObject {
  ChatPreviewHive({
    required this.peerId,
    required this.peerName,
    required this.lastMessage,
    required this.lastMessageTimeMs,
    this.peerAvatarUrl,
    this.unreadCount = 0,
    this.isFromMe = false,
    this.isDelivered = false,
    this.isRead = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isGroupChat = false,
  });

  /// The Korium identity (Ed25519 public key hex) of the peer
  @HiveField(0)
  String peerId;

  /// Display name of the peer
  @HiveField(1)
  String peerName;

  /// Optional avatar URL
  @HiveField(2)
  String? peerAvatarUrl;

  /// Preview of the last message
  @HiveField(3)
  String lastMessage;

  /// Timestamp of the last message (ms since epoch)
  @HiveField(4)
  int lastMessageTimeMs;

  /// Number of unread messages
  @HiveField(5)
  int unreadCount;

  /// Whether the last message was sent by the current user
  @HiveField(6)
  bool isFromMe;

  /// Whether the message has been delivered
  @HiveField(7)
  bool isDelivered;

  /// Whether the message has been read
  @HiveField(8)
  bool isRead;

  /// Whether the chat is pinned
  @HiveField(9)
  bool isPinned;

  /// Whether the chat is muted
  @HiveField(10)
  bool isMuted;

  /// Whether this is a group chat (vs 1:1 direct message)
  @HiveField(11)
  bool isGroupChat;
}

/// Manual Hive adapter for ChatPreviewHive.
/// (hive_generator incompatible with freezed 3.x)
class ChatPreviewHiveAdapter extends TypeAdapter<ChatPreviewHive> {
  @override
  final int typeId = HiveTypeIds.chatPreview;

  @override
  ChatPreviewHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatPreviewHive(
      peerId: fields[0] as String,
      peerName: fields[1] as String,
      peerAvatarUrl: fields[2] as String?,
      lastMessage: fields[3] as String,
      lastMessageTimeMs: fields[4] as int,
      unreadCount: fields[5] as int? ?? 0,
      isFromMe: fields[6] as bool? ?? false,
      isDelivered: fields[7] as bool? ?? false,
      isRead: fields[8] as bool? ?? false,
      isPinned: fields[9] as bool? ?? false,
      isMuted: fields[10] as bool? ?? false,
      isGroupChat: fields[11] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ChatPreviewHive obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.peerId)
      ..writeByte(1)
      ..write(obj.peerName)
      ..writeByte(2)
      ..write(obj.peerAvatarUrl)
      ..writeByte(3)
      ..write(obj.lastMessage)
      ..writeByte(4)
      ..write(obj.lastMessageTimeMs)
      ..writeByte(5)
      ..write(obj.unreadCount)
      ..writeByte(6)
      ..write(obj.isFromMe)
      ..writeByte(7)
      ..write(obj.isDelivered)
      ..writeByte(8)
      ..write(obj.isRead)
      ..writeByte(9)
      ..write(obj.isPinned)
      ..writeByte(10)
      ..write(obj.isMuted)
      ..writeByte(11)
      ..write(obj.isGroupChat);
  }
}
