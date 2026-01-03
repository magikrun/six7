import 'package:hive/hive.dart';
import 'package:six7_chat/src/core/storage/models/chat_message_hive.dart';

/// Hive type ID for Vibe - extends HiveTypeIds
/// Adding to extended types range (10+)
const int vibeHiveTypeId = 12;
const int vibeStatusHiveTypeId = 13;

/// Hive-compatible vibe status enum.
@HiveType(typeId: vibeStatusHiveTypeId)
enum VibeStatusHive {
  @HiveField(0)
  pending,
  @HiveField(1)
  matched,
  @HiveField(2)
  received,
  @HiveField(3)
  skipped,
}

/// Hive-compatible vibe model for persistence.
@HiveType(typeId: vibeHiveTypeId)
class VibeHive extends HiveObject {
  VibeHive({
    required this.id,
    required this.contactId,
    required this.contactName,
    this.contactAvatarPath,
    this.ourCommitment,
    this.ourSecret,
    this.theirCommitment,
    required this.status,
    required this.createdAtMs,
    this.matchedAtMs,
  });

  @HiveField(0)
  String id;

  @HiveField(1)
  String contactId;

  @HiveField(2)
  String contactName;

  @HiveField(3)
  String? contactAvatarPath;

  @HiveField(4)
  String? ourCommitment;

  @HiveField(9)
  String? ourSecret;

  @HiveField(5)
  String? theirCommitment;

  @HiveField(6)
  VibeStatusHive status;

  @HiveField(7)
  int createdAtMs;

  @HiveField(8)
  int? matchedAtMs;
}

/// Manual Hive adapter for VibeStatusHive.
class VibeStatusHiveAdapter extends TypeAdapter<VibeStatusHive> {
  @override
  final int typeId = vibeStatusHiveTypeId;

  @override
  VibeStatusHive read(BinaryReader reader) {
    final index = reader.readByte();
    return VibeStatusHive.values[index];
  }

  @override
  void write(BinaryWriter writer, VibeStatusHive obj) {
    writer.writeByte(obj.index);
  }
}

/// Manual Hive adapter for VibeHive.
class VibeHiveAdapter extends TypeAdapter<VibeHive> {
  @override
  final int typeId = vibeHiveTypeId;

  @override
  VibeHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return VibeHive(
      id: fields[0] as String,
      contactId: fields[1] as String,
      contactName: fields[2] as String,
      contactAvatarPath: fields[3] as String?,
      ourCommitment: fields[4] as String?,
      ourSecret: fields[9] as String?,
      theirCommitment: fields[5] as String?,
      status: fields[6] as VibeStatusHive,
      createdAtMs: fields[7] as int,
      matchedAtMs: fields[8] as int?,
    );
  }

  @override
  void write(BinaryWriter writer, VibeHive obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.contactId)
      ..writeByte(2)
      ..write(obj.contactName)
      ..writeByte(3)
      ..write(obj.contactAvatarPath)
      ..writeByte(4)
      ..write(obj.ourCommitment)
      ..writeByte(9)
      ..write(obj.ourSecret)
      ..writeByte(5)
      ..write(obj.theirCommitment)
      ..writeByte(6)
      ..write(obj.status)
      ..writeByte(7)
      ..write(obj.createdAtMs)
      ..writeByte(8)
      ..write(obj.matchedAtMs);
  }
}
