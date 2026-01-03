import 'dart:typed_data';

import 'package:hive/hive.dart';

/// Hive type IDs - MUST be unique across all Hive adapters.
/// Range 0-99 reserved for core types.
/// SECURITY: All TypeIds MUST be defined here to prevent collisions.
abstract class HiveTypeIds {
  static const int chatMessage = 0;
  static const int messageStatus = 1;
  static const int messageType = 2;
  static const int contact = 3;
  static const int chatPreview = 4;
  // Extended types (leaving room for future core types)
  static const int group = 10;
  static const int outboxMessage = 11;
}

/// Status of a chat message.
@HiveType(typeId: HiveTypeIds.messageStatus)
enum MessageStatusHive {
  @HiveField(0)
  pending,
  @HiveField(1)
  sent,
  @HiveField(2)
  delivered,
  @HiveField(3)
  read,
  @HiveField(4)
  failed,
}

/// Type of chat message.
@HiveType(typeId: HiveTypeIds.messageType)
enum MessageTypeHive {
  @HiveField(0)
  text,
  @HiveField(1)
  image,
  @HiveField(2)
  video,
  @HiveField(3)
  audio,
  @HiveField(4)
  document,
  @HiveField(5)
  location,
  @HiveField(6)
  contact,
  @HiveField(7)
  groupInvite,
}

/// Hive-compatible chat message model.
@HiveType(typeId: HiveTypeIds.chatMessage)
class ChatMessageHive extends HiveObject {
  ChatMessageHive({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.type,
    required this.timestampMs,
    required this.status,
    required this.isFromMe,
    this.groupId,
    this.replyToId,
    this.mediaUrl,
    this.thumbnailUrl,
    this.mediaSizeBytes,
    this.mediaDurationMs,
    this.frankingTag,
    this.frankingKeyCommitment,
    this.frankingKey,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String senderId;

  @HiveField(2)
  String recipientId;

  @HiveField(3)
  String text;

  @HiveField(4)
  MessageTypeHive type;

  @HiveField(5)
  int timestampMs;

  @HiveField(6)
  MessageStatusHive status;

  @HiveField(7)
  bool isFromMe;

  /// Group ID if this is a group message (null for 1:1 chats)
  @HiveField(13)
  String? groupId;

  @HiveField(8)
  String? replyToId;

  @HiveField(9)
  String? mediaUrl;

  @HiveField(10)
  String? thumbnailUrl;

  @HiveField(11)
  int? mediaSizeBytes;

  @HiveField(12)
  int? mediaDurationMs;

  // ============ Message Franking (Abuse Reporting) ============
  // These fields enable cryptographic proof of message authenticity.

  /// Franking tag: HMAC(Kf, plaintext)
  @HiveField(14)
  Uint8List? frankingTag;

  /// Franking key commitment: HMAC(Kf, ciphertext)
  @HiveField(15)
  Uint8List? frankingKeyCommitment;

  /// Franking key (decrypted, stored locally only)
  @HiveField(16)
  Uint8List? frankingKey;
}

/// Manual Hive adapter for MessageStatusHive.
/// (hive_generator incompatible with freezed 3.x)
class MessageStatusHiveAdapter extends TypeAdapter<MessageStatusHive> {
  @override
  final int typeId = HiveTypeIds.messageStatus;

  @override
  MessageStatusHive read(BinaryReader reader) {
    return MessageStatusHive.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, MessageStatusHive obj) {
    writer.writeByte(obj.index);
  }
}

/// Manual Hive adapter for MessageTypeHive.
/// (hive_generator incompatible with freezed 3.x)
class MessageTypeHiveAdapter extends TypeAdapter<MessageTypeHive> {
  @override
  final int typeId = HiveTypeIds.messageType;

  @override
  MessageTypeHive read(BinaryReader reader) {
    return MessageTypeHive.values[reader.readByte()];
  }

  @override
  void write(BinaryWriter writer, MessageTypeHive obj) {
    writer.writeByte(obj.index);
  }
}

/// Manual Hive adapter for ChatMessageHive.
/// (hive_generator incompatible with freezed 3.x)
class ChatMessageHiveAdapter extends TypeAdapter<ChatMessageHive> {
  @override
  final int typeId = HiveTypeIds.chatMessage;

  @override
  ChatMessageHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessageHive(
      id: fields[0] as String,
      senderId: fields[1] as String,
      recipientId: fields[2] as String,
      text: fields[3] as String,
      type: fields[4] as MessageTypeHive,
      timestampMs: fields[5] as int,
      status: fields[6] as MessageStatusHive,
      isFromMe: fields[7] as bool,
      replyToId: fields[8] as String?,
      mediaUrl: fields[9] as String?,
      thumbnailUrl: fields[10] as String?,
      mediaSizeBytes: fields[11] as int?,
      mediaDurationMs: fields[12] as int?,
      groupId: fields[13] as String?,
      frankingTag: fields[14] as Uint8List?,
      frankingKeyCommitment: fields[15] as Uint8List?,
      frankingKey: fields[16] as Uint8List?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessageHive obj) {
    writer
      ..writeByte(17) // Number of fields
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.senderId)
      ..writeByte(2)
      ..write(obj.recipientId)
      ..writeByte(3)
      ..write(obj.text)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.timestampMs)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.isFromMe)
      ..writeByte(8)
      ..write(obj.replyToId)
      ..writeByte(9)
      ..write(obj.mediaUrl)
      ..writeByte(10)
      ..write(obj.thumbnailUrl)
      ..writeByte(11)
      ..write(obj.mediaSizeBytes)
      ..writeByte(12)
      ..write(obj.mediaDurationMs)
      ..writeByte(13)
      ..write(obj.groupId)
      ..writeByte(14)
      ..write(obj.frankingTag)
      ..writeByte(15)
      ..write(obj.frankingKeyCommitment)
      ..writeByte(16)
      ..write(obj.frankingKey);
  }
}
