import 'package:hive/hive.dart';
import 'package:six7_chat/src/core/storage/models/chat_message_hive.dart';

/// Hive type ID for Group - uses centralized HiveTypeIds to prevent collisions.
/// @deprecated Use HiveTypeIds.group instead. Kept for adapter registration compatibility.
const int hiveTypeIdGroup = HiveTypeIds.group;

/// Hive-compatible group model.
@HiveType(typeId: HiveTypeIds.group)
class GroupHive extends HiveObject {
  GroupHive({
    required this.id,
    required this.name,
    required this.memberIds,
    required this.memberNamesJson,
    required this.creatorId,
    required this.createdAtMs,
    this.description,
    this.avatarUrl,
    this.updatedAtMs,
    this.isAdmin = false,
    this.isMuted = false,
  });

  /// Unique group identifier (UUID)
  @HiveField(0)
  String id;

  /// Group display name
  @HiveField(1)
  String name;

  /// Optional group description
  @HiveField(2)
  String? description;

  /// Optional avatar URL
  @HiveField(3)
  String? avatarUrl;

  /// List of member identities (Ed25519 public key hex)
  @HiveField(4)
  List<String> memberIds;

  /// JSON-encoded map of member IDs to display names
  @HiveField(5)
  String memberNamesJson;

  /// The identity of the group creator/admin
  @HiveField(6)
  String creatorId;

  /// When the group was created (ms since epoch)
  @HiveField(7)
  int createdAtMs;

  /// When the group was last updated (ms since epoch)
  @HiveField(8)
  int? updatedAtMs;

  /// Whether the current user is an admin
  @HiveField(9)
  bool isAdmin;

  /// Whether the group is muted
  @HiveField(10)
  bool isMuted;
}

/// Manual Hive adapter for GroupHive.
/// (hive_generator incompatible with freezed 3.x)
class GroupHiveAdapter extends TypeAdapter<GroupHive> {
  @override
  final int typeId = hiveTypeIdGroup;

  @override
  GroupHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return GroupHive(
      id: fields[0] as String,
      name: fields[1] as String,
      description: fields[2] as String?,
      avatarUrl: fields[3] as String?,
      memberIds: (fields[4] as List).cast<String>(),
      memberNamesJson: fields[5] as String,
      creatorId: fields[6] as String,
      createdAtMs: fields[7] as int,
      updatedAtMs: fields[8] as int?,
      isAdmin: fields[9] as bool? ?? false,
      isMuted: fields[10] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, GroupHive obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.description)
      ..writeByte(3)
      ..write(obj.avatarUrl)
      ..writeByte(4)
      ..write(obj.memberIds)
      ..writeByte(5)
      ..write(obj.memberNamesJson)
      ..writeByte(6)
      ..write(obj.creatorId)
      ..writeByte(7)
      ..write(obj.createdAtMs)
      ..writeByte(8)
      ..write(obj.updatedAtMs)
      ..writeByte(9)
      ..write(obj.isAdmin)
      ..writeByte(10)
      ..write(obj.isMuted);
  }
}
