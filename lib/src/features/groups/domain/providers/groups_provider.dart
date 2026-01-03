import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/group_hive.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/groups/domain/models/group.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;
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

    // Subscribe to group topic so we receive messages
    // NOTE: Do this before updating state so messages don't arrive before we're ready
    final nodeAsync = ref.read(koriumNodeProvider);
    await nodeAsync.when(
      loading: () async {},
      error: (_, _) async {},
      data: (node) async {
        try {
          await node.subscribeToGroup(groupId: newGroup.id);
          debugPrint('[Groups] Subscribed to new group topic: ${newGroup.name}');
        } catch (e) {
          debugPrint('[Groups] Failed to subscribe to new group: $e');
        }
      },
    );

    // Update state
    state = AsyncData([newGroup, ...state.value ?? []]);

    // Send group invites to all other members via 1:1 channel
    // This allows them to auto-join the group
    await _sendGroupInvites(newGroup, myIdentity);

    return newGroup;
  }

  /// Sends group invite messages to all members (except ourselves).
  /// The invite contains all group info so recipients can auto-join.
  Future<void> _sendGroupInvites(Group group, String myIdentity) async {
    final nodeAsync = ref.read(koriumNodeProvider);
    
    await nodeAsync.when(
      loading: () async {},
      error: (_, _) async {},
      data: (node) async {
        // Build invite payload with all group info
        final invitePayload = jsonEncode({
          'groupId': group.id,
          'groupName': group.name,
          'description': group.description,
          'memberIds': group.memberIds,
          'memberNames': group.memberNames,
          'creatorId': group.creatorId,
          'createdAtMs': group.createdAt.millisecondsSinceEpoch,
        });

        // Send invite to each member (except ourselves)
        for (final memberId in group.memberIds) {
          if (memberId == myIdentity) continue;

          try {
            final inviteMessage = korium.ChatMessage(
              id: _uuid.v4(),
              senderId: myIdentity,
              recipientId: memberId,
              text: invitePayload,
              messageType: korium.MessageType.groupInvite,
              timestampMs: DateTime.now().millisecondsSinceEpoch,
              status: korium.MessageStatus.pending,
              isFromMe: true,
              groupId: group.id, // Include groupId for reference
            );

            await node.sendMessage(
              peerId: memberId,
              message: inviteMessage,
            );
            debugPrint('[Groups] Sent invite to $memberId for group: ${group.name}');
          } catch (e) {
            debugPrint('[Groups] Failed to send invite to $memberId: $e');
            // Continue with other members - don't fail the whole operation
          }
        }
      },
    );
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
    // Unsubscribe from group topic first
    final nodeAsync = ref.read(koriumNodeProvider);
    await nodeAsync.when(
      loading: () async {},
      error: (_, _) async {},
      data: (node) async {
        try {
          await node.unsubscribeFromGroup(groupId: groupId);
          debugPrint('[Groups] Unsubscribed from deleted group: $groupId');
        } catch (e) {
          debugPrint('[Groups] Failed to unsubscribe from group $groupId: $e');
        }
      },
    );

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

  /// Updates the name of a group.
  Future<void> updateGroupName(String groupId, String newName) async {
    final groups = state.value ?? [];
    final groupIndex = groups.indexWhere((g) => g.id == groupId);
    if (groupIndex == -1) return;

    final group = groups[groupIndex];
    await updateGroup(group.copyWith(name: newName.trim()));
  }

  /// Leaves a group (removes self from the group).
  Future<void> leaveGroup(String groupId) async {
    // Get our identity
    final nodeState = ref.read(koriumNodeStateProvider);
    String? myIdentity;
    if (nodeState is KoriumNodeConnected) {
      myIdentity = nodeState.identity;
    }

    if (myIdentity == null) {
      debugPrint('[Groups] Cannot leave group: not connected');
      return;
    }

    // Unsubscribe from group topic
    final nodeAsync = ref.read(koriumNodeProvider);
    await nodeAsync.when(
      loading: () async {},
      error: (_, _) async {},
      data: (node) async {
        try {
          await node.unsubscribeFromGroup(groupId: groupId);
          debugPrint('[Groups] Unsubscribed from left group: $groupId');
        } catch (e) {
          debugPrint('[Groups] Failed to unsubscribe from group $groupId: $e');
        }
      },
    );

    // Delete the group locally (we're leaving, not deleting for everyone)
    await _storage.deleteGroup(groupId);

    state = AsyncData(
      (state.value ?? []).where((g) => g.id != groupId).toList(),
    );
  }

  /// Subscribes to all group PubSub topics.
  /// Should be called once the Korium node is ready.
  Future<void> subscribeToAllGroupTopics() async {
    final groups = state.value ?? [];
    final nodeAsync = ref.read(koriumNodeProvider);
    
    await nodeAsync.when(
      data: (node) async {
        for (final group in groups) {
          try {
            await node.subscribeToGroup(groupId: group.id);
            debugPrint('[Groups] Subscribed to group topic: ${group.name}');
          } catch (e) {
            debugPrint('[Groups] Failed to subscribe to group ${group.name}: $e');
          }
        }
        debugPrint('[Groups] Subscribed to ${groups.length} group topics');
      },
      loading: () {},
      error: (e, st) {
        debugPrint('[Groups] Failed to subscribe to groups: $e');
      },
    );
  }
}

/// Provider that subscribes to all group topics when the node is ready.
/// Watch this provider from a widget that's always mounted (e.g., HomeScreen)
/// to ensure group subscriptions are maintained.
final groupTopicSubscriptionProvider = FutureProvider<void>((ref) async {
  // Wait for node to be ready
  final node = await ref.watch(koriumNodeProvider.future);
  
  // Wait for groups to be loaded
  final groups = await ref.watch(groupsProvider.future);
  
  // Subscribe to each group's topic
  for (final group in groups) {
    try {
      await node.subscribeToGroup(groupId: group.id);
      debugPrint('[Groups] Subscribed to group topic: ${group.name} (${group.id})');
    } catch (e) {
      debugPrint('[Groups] Failed to subscribe to group ${group.name}: $e');
    }
  }
  
  debugPrint('[Groups] Subscribed to ${groups.length} group topics total');
});
/// Provider that listens for incoming group invite messages and auto-joins.
/// Watch this provider from a widget that's always mounted (e.g., HomeScreen)
/// to ensure group invites are processed.
final groupInviteListenerProvider = Provider<void>((ref) {
  ref.listen(koriumEventStreamProvider, (previous, next) {
    next.whenData((event) {
      switch (event) {
        case korium.KoriumEvent_ChatMessageReceived(:final message):
          // Check if this is a group invite
          if (message.messageType == korium.MessageType.groupInvite) {
            _handleGroupInvite(ref, message);
          }
        default:
          break;
      }
    });
  });
});

/// Handles an incoming group invite message.
/// Creates the group locally and subscribes to the topic.
void _handleGroupInvite(Ref ref, korium.ChatMessage message) {
  try {
    // Parse the invite payload
    final payload = jsonDecode(message.text) as Map<String, dynamic>;
    
    final groupId = payload['groupId'] as String?;
    final groupName = payload['groupName'] as String?;
    final description = payload['description'] as String?;
    final memberIds = (payload['memberIds'] as List?)?.cast<String>() ?? [];
    final memberNames = (payload['memberNames'] as Map?)?.cast<String, String>() ?? {};
    final creatorId = payload['creatorId'] as String?;
    final createdAtMs = payload['createdAtMs'] as int?;
    
    if (groupId == null || groupName == null || creatorId == null) {
      debugPrint('[Groups] Invalid group invite: missing required fields');
      return;
    }
    
    // Check if we already have this group
    final existingGroups = ref.read(groupsProvider).value ?? [];
    if (existingGroups.any((g) => g.id == groupId)) {
      debugPrint('[Groups] Already have group $groupName, ignoring invite');
      return;
    }
    
    // Create the group locally
    final storage = ref.read(storageServiceProvider);
    final newGroup = GroupHive(
      id: groupId,
      name: groupName,
      description: description,
      memberIds: memberIds,
      memberNamesJson: jsonEncode(memberNames),
      creatorId: creatorId,
      createdAtMs: createdAtMs ?? DateTime.now().millisecondsSinceEpoch,
      isAdmin: false, // We're not the admin since we received the invite
      isMuted: false,
    );
    
    storage.saveGroup(newGroup);
    debugPrint('[Groups] Auto-created group from invite: $groupName');
    
    // Invalidate the groups provider to refresh the list
    ref.invalidate(groupsProvider);
    
    // Subscribe to the group topic
    final nodeAsync = ref.read(koriumNodeProvider);
    nodeAsync.whenData((node) async {
      try {
        await node.subscribeToGroup(groupId: groupId);
        debugPrint('[Groups] Subscribed to invited group topic: $groupName');
      } catch (e) {
        debugPrint('[Groups] Failed to subscribe to invited group: $e');
      }
    });
    
    debugPrint('[Groups] Accepted group invite from ${message.senderId}: $groupName');
  } catch (e) {
    debugPrint('[Groups] Failed to process group invite: $e');
  }
}