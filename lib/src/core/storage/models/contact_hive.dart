import 'package:hive/hive.dart';
import 'package:six7_chat/src/core/storage/models/chat_message_hive.dart';

/// Hive-compatible contact model.
@HiveType(typeId: HiveTypeIds.contact)
class ContactHive extends HiveObject {
  ContactHive({
    required this.identity,
    required this.displayName,
    required this.addedAtMs,
    this.avatarUrl,
    this.status,
    this.isBlocked = false,
    this.isFavorite = false,
  });

  /// The Korium identity (Ed25519 public key hex)
  @HiveField(0)
  String identity;

  /// User-defined display name
  @HiveField(1)
  String displayName;

  /// Optional avatar URL
  @HiveField(2)
  String? avatarUrl;

  /// Optional status message
  @HiveField(3)
  String? status;

  /// When the contact was added (ms since epoch)
  @HiveField(4)
  int addedAtMs;

  /// Whether the contact is blocked
  @HiveField(5)
  bool isBlocked;

  /// Whether the contact is a favorite
  @HiveField(6)
  bool isFavorite;
}

/// Manual Hive adapter for ContactHive.
/// (hive_generator incompatible with freezed 3.x)
class ContactHiveAdapter extends TypeAdapter<ContactHive> {
  @override
  final int typeId = HiveTypeIds.contact;

  @override
  ContactHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContactHive(
      identity: fields[0] as String,
      displayName: fields[1] as String,
      avatarUrl: fields[2] as String?,
      status: fields[3] as String?,
      addedAtMs: fields[4] as int,
      isBlocked: fields[5] as bool? ?? false,
      isFavorite: fields[6] as bool? ?? false,
    );
  }

  @override
  void write(BinaryWriter writer, ContactHive obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.identity)
      ..writeByte(1)
      ..write(obj.displayName)
      ..writeByte(2)
      ..write(obj.avatarUrl)
      ..writeByte(3)
      ..write(obj.status)
      ..writeByte(4)
      ..write(obj.addedAtMs)
      ..writeByte(5)
      ..write(obj.isBlocked)
      ..writeByte(6)
      ..write(obj.isFavorite);
  }
}
