import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/group_hive.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/groups/domain/models/group.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:uuid/uuid.dart';

/// Provider for the list of groups.
final groupsProvider = AsyncNotifierProvider<GroupsNotifier, List<Group>>(
  GroupsNotifier.new,
);

class GroupsNotifier extends AsyncNotifier<List<Group>> {
  static const _uuid = Uuid();

  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<List<Group>> build() async {
    return _loadGroups();
  }

  Future<List<Group>> _loadGroups() async {
    final hiveGroups = _storage.getAllGroups();
    return hiveGroups.map(_hiveToModel).toList();
  }

  Group _hiveToModel(GroupHive hive) {
    Map<String, String> memberNames = {};
    try {
      final decoded = jsonDecode(hive.memberNamesJson);
      if (decoded is Map) {
        memberNames = Map<String, String>.from(decoded);
      }
    } catch (_) {
      // Fallback to empty map if JSON is invalid
    }

    return Group(
      id: hive.id,
      name: hive.name,
      description: hive.description,
      avatarUrl: hive.avatarUrl,
      memberIds: List<String>.from(hive.memberIds),
      memberNames: memberNames,
      creatorId: hive.creatorId,
      createdAt: DateTime.fromMillisecondsSinceEpoch(hive.createdAtMs),
      updatedAt: hive.updatedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(hive.updatedAtMs!)
          : null,
      isAdmin: hive.isAdmin,
      isMuted: hive.isMuted,
    );
  }

  GroupHive _modelToHive(Group group) {
    return GroupHive(
      id: group.id,
      name: group.name,
      description: group.description,
      avatarUrl: group.avatarUrl,
      memberIds: group.memberIds,
      memberNamesJson: jsonEncode(group.memberNames),
      creatorId: group.creatorId,
      createdAtMs: group.createdAt.millisecondsSinceEpoch,
      updatedAtMs: group.updatedAt?.millisecondsSinceEpoch,
      isAdmin: group.isAdmin,
      isMuted: group.isMuted,
    );
  }

  /// Creates a new group with the given name and members.
  ///
  /// Returns the newly created group.
  Future<Group> createGroup({
    required String name,
    required Map<String, String> members, // identity -> displayName
    String? description,
  }) async {
    // SECURITY: Validate group name
    if (name.trim().isEmpty) {
      throw ArgumentError('Group name cannot be empty');
    }

    // SECURITY: Validate at least one member
    if (members.isEmpty) {
      throw ArgumentError('Group must have at least one member');
    }

    // Get our identity to add as creator
    final nodeState = ref.read(koriumNodeStateProvider);
    String? myIdentity;
    if (nodeState is KoriumNodeConnected) {
      myIdentity = nodeState.identity;
    }

    if (myIdentity == null) {
      throw StateError('Cannot create group: not connected to network');
    }

    // Add ourselves to members if not already included
    final allMembers = Map<String, String>.from(members);
    if (!allMembers.containsKey(myIdentity)) {
      allMembers[myIdentity] = 'You';
    }

    final now = DateTime.now();
    final newGroup = Group(
      id: _uuid.v4(),
      name: name.trim(),
      description: description?.trim(),
      memberIds: allMembers.keys.toList(),
      memberNames: allMembers,
      creatorId: myIdentity,
      createdAt: now,
      isAdmin: true, // Creator is always admin
    );

    // Persist to storage
    await _storage.saveGroup(_modelToHive(newGroup));

    // Update state
    state = AsyncData([newGroup, ...state.value ?? []]);

    return newGroup;
  }

  /// Updates an existing group.
  Future<void> updateGroup(Group group) async {
    final hive = _modelToHive(group.copyWith(updatedAt: DateTime.now()));
    await _storage.saveGroup(hive);

    state = AsyncData(
      (state.value ?? []).map((g) {
        if (g.id == group.id) {
          return group;
        }
        return g;
      }).toList(),
    );
  }

  /// Deletes a group.
  Future<void> deleteGroup(String groupId) async {
    await _storage.deleteGroup(groupId);

    state = AsyncData(
      (state.value ?? []).where((g) => g.id != groupId).toList(),
    );
  }

  /// Adds a member to a group.
  Future<void> addMember({
    required String groupId,
    required String memberId,
    required String memberName,
  }) async {
    final groups = state.value ?? [];
    final groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = groups[groupIndex];
    if (group.memberIds.contains(memberId)) return;

    final updatedGroup = group.copyWith(
      memberIds: [...group.memberIds, memberId],
      memberNames: {...group.memberNames, memberId: memberName},
      updatedAt: DateTime.now(),
    );

    await updateGroup(updatedGroup);
  }

  /// Removes a member from a group.
  Future<void> removeMember({
    required String groupId,
    required String memberId,
  }) async {
    final groups = state.value ?? [];
    final groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = groups[groupIndex];
    final updatedMemberIds =
        group.memberIds.where((id) => id != memberId).toList();
    final updatedMemberNames = Map<String, String>.from(group.memberNames)
      ..remove(memberId);

    final updatedGroup = group.copyWith(
      memberIds: updatedMemberIds,
      memberNames: updatedMemberNames,
      updatedAt: DateTime.now(),
    );

    await updateGroup(updatedGroup);
  }

  /// Toggles mute status for a group.
  Future<void> toggleMute(String groupId) async {
    final groups = state.value ?? [];
    final groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = groups[groupIndex];
    await updateGroup(group.copyWith(isMuted: !group.isMuted));
  }
}
