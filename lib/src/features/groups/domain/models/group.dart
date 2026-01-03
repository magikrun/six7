import 'package:freezed_annotation/freezed_annotation.dart';

part 'group.freezed.dart';
part 'group.g.dart';

/// Represents a group chat.
@freezed
abstract class Group with _$Group {
  const factory Group({
    /// Unique group identifier (UUID)
    required String id,

    /// Group display name
    required String name,

    /// Optional group description
    String? description,

    /// Optional avatar URL
    String? avatarUrl,

    /// List of member identities (Ed25519 public key hex)
    required List<String> memberIds,

    /// Map of member IDs to display names for quick lookup
    required Map<String, String> memberNames,

    /// The identity of the group creator/admin
    required String creatorId,

    /// When the group was created
    required DateTime createdAt,

    /// When the group was last updated
    DateTime? updatedAt,

    /// Whether the current user is an admin
    @Default(false) bool isAdmin,

    /// Whether the group is muted
    @Default(false) bool isMuted,
  }) = _Group;

  factory Group.fromJson(Map<String, dynamic> json) => _$GroupFromJson(json);
}

/// Represents a group member with display info.
@freezed
abstract class GroupMember with _$GroupMember {
  const factory GroupMember({
    /// The Korium identity (Ed25519 public key hex)
    required String identity,

    /// Display name
    required String displayName,

    /// Optional avatar URL
    String? avatarUrl,

    /// Whether the member is an admin
    @Default(false) bool isAdmin,

    /// When the member joined
    required DateTime joinedAt,
  }) = _GroupMember;

  factory GroupMember.fromJson(Map<String, dynamic> json) =>
      _$GroupMemberFromJson(json);
}
