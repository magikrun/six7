import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/groups/domain/models/group.dart';
import 'package:six7_chat/src/features/groups/domain/providers/groups_provider.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;
import 'package:uuid/uuid.dart';

/// Provider for messages in a specific group chat.
/// Uses family to create separate instances per group.
final groupMessageProvider = AsyncNotifierProvider.family<GroupMessageNotifier,
    List<ChatMessage>, String>(
  GroupMessageNotifier.new,
);

/// GroupMessageNotifier for a specific group.
/// Uses constructor injection for family arg as required by Riverpod 3.
class GroupMessageNotifier extends AsyncNotifier<List<ChatMessage>> {
  /// Constructor takes the groupId from family provider.
  GroupMessageNotifier(this.groupId);

  /// The groupId for this family instance.
  final String groupId;

  static const _uuid = Uuid();

  /// Maximum message text length
  /// SECURITY: Bounded to prevent oversized messages
  static const int maxMessageTextLength = 4096;

  StorageService get _storage => ref.read(storageServiceProvider);

  String? _myIdentity;

  @override
  Future<List<ChatMessage>> build() async {
    // Get our identity from the node
    ref.listen(koriumNodeProvider, (previous, next) {
      next.whenData((node) {
        _myIdentity = node.identity;
      });
    });

    // Also try to get identity immediately if node is already ready
    final nodeAsync = ref.read(koriumNodeProvider);
    nodeAsync.whenData((node) {
      _myIdentity = node.identity;
    });

    // Listen to Korium events for incoming group messages
    _setupEventListener();

    // Load persisted messages for this group from storage
    return _loadMessages();
  }

  /// Sets up listener for incoming Korium events.
  void _setupEventListener() {
    ref.listen(
      koriumEventStreamProvider,
      (previous, next) {
        next.whenData(_handleKoriumEvent);
      },
    );
  }

  /// Handles incoming Korium events.
  void _handleKoriumEvent(korium.KoriumEvent event) {
    switch (event) {
      case korium.KoriumEvent_ChatMessageReceived(:final message):
        // Only process messages for this group
        // SECURITY: Filter out our own messages to prevent echo
        // (we already added them locally when sending)
        if (message.groupId == groupId && message.senderId != _myIdentity) {
          _addIncomingMessage(message);
        }

      case korium.KoriumEvent_MessageStatusUpdate(:final messageId, :final status):
        // Update status of our sent messages
        final dartStatus = _koriumStatusToModel(status);
        _updateMessageStatus(messageId, dartStatus);

      case korium.KoriumEvent_PubSubMessage():
      case korium.KoriumEvent_IncomingRequest():
      case korium.KoriumEvent_ConnectionStateChanged():
      case korium.KoriumEvent_PeerPresenceChanged():
      case korium.KoriumEvent_Error():
      case korium.KoriumEvent_BootstrapComplete():
        // Not handled at message level
        break;
    }
  }

  /// Adds an incoming message from the network.
  Future<void> _addIncomingMessage(korium.ChatMessage koriumMsg) async {
    final timestampMs = koriumMsg.timestampMs;
    
    final incomingMessage = ChatMessage(
      id: koriumMsg.id,
      senderId: koriumMsg.senderId,
      recipientId: koriumMsg.recipientId,
      text: koriumMsg.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      isFromMe: false,
      status: MessageStatus.delivered,
      groupId: groupId,
    );

    // Check for duplicates
    final existing = (state.value ?? [])
        .any((m) => m.id == incomingMessage.id);
    if (existing) return;

    // Persist
    await _storage.saveMessage(ChatMessageHive(
      id: koriumMsg.id,
      senderId: koriumMsg.senderId,
      recipientId: koriumMsg.recipientId,
      text: koriumMsg.text,
      type: MessageTypeHive.text,
      timestampMs: timestampMs,
      status: MessageStatusHive.delivered,
      isFromMe: false,
      groupId: groupId,
    ));

    // Evict old messages if needed
    await _storage.evictOldGroupMessagesIfNeeded(groupId);

    // Update chat list preview for this incoming message
    await _updateIncomingGroupChatListPreview(
      senderName: koriumMsg.senderId,
      lastMessage: koriumMsg.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );

    // Add to state (newest first)
    state = AsyncData([incomingMessage, ...state.value ?? []]);
  }

  MessageStatus _koriumStatusToModel(korium.MessageStatus status) {
    return switch (status) {
      korium.MessageStatus.pending => MessageStatus.pending,
      korium.MessageStatus.sent => MessageStatus.sent,
      korium.MessageStatus.delivered => MessageStatus.delivered,
      korium.MessageStatus.read => MessageStatus.read,
      korium.MessageStatus.failed => MessageStatus.failed,
    };
  }

  Future<List<ChatMessage>> _loadMessages() async {
    final hiveMessages = _storage.getMessagesForGroup(groupId);
    return hiveMessages.map(_hiveToModel).toList();
  }

  ChatMessage _hiveToModel(ChatMessageHive hive) {
    return ChatMessage(
      id: hive.id,
      senderId: hive.senderId,
      recipientId: hive.recipientId,
      text: hive.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(hive.timestampMs),
      isFromMe: hive.isFromMe,
      status: _hiveStatusToModel(hive.status),
      groupId: hive.groupId,
    );
  }

  MessageStatus _hiveStatusToModel(MessageStatusHive hiveStatus) {
    return switch (hiveStatus) {
      MessageStatusHive.pending => MessageStatus.pending,
      MessageStatusHive.sent => MessageStatus.sent,
      MessageStatusHive.delivered => MessageStatus.delivered,
      MessageStatusHive.read => MessageStatus.read,
      MessageStatusHive.failed => MessageStatus.failed,
    };
  }

  MessageStatusHive _modelStatusToHive(MessageStatus status) {
    return switch (status) {
      MessageStatus.pending => MessageStatusHive.pending,
      MessageStatus.sent => MessageStatusHive.sent,
      MessageStatus.delivered => MessageStatusHive.delivered,
      MessageStatus.read => MessageStatusHive.read,
      MessageStatus.failed => MessageStatusHive.failed,
    };
  }

  /// Sends a message to all group members.
  /// Returns a reason if the message couldn't be sent.
  Future<String?> sendMessage(String text) async {
    // SECURITY: Validate text length
    if (text.isEmpty) {
      return 'Message cannot be empty';
    }
    if (text.length > maxMessageTextLength) {
      return 'Message is too long (max $maxMessageTextLength characters)';
    }

    final myId = _myIdentity;
    if (myId == null) {
      return 'Not connected to network';
    }

    // Get group details for member list
    final groups = ref.read(groupsProvider).value ?? [];
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    if (group == null) {
      return 'Group not found';
    }

    final messageId = _uuid.v4();
    final now = DateTime.now();

    // Optimistically add the message
    final newMessage = ChatMessage(
      id: messageId,
      senderId: myId,
      recipientId: groupId, // Group ID as recipient for group messages
      text: text,
      timestamp: now,
      isFromMe: true,
      status: MessageStatus.pending,
      groupId: groupId,
    );

    // Persist immediately
    await _storage.saveMessage(ChatMessageHive(
      id: messageId,
      senderId: myId,
      recipientId: groupId,
      text: text,
      type: MessageTypeHive.text,
      timestampMs: now.millisecondsSinceEpoch,
      status: MessageStatusHive.pending,
      isFromMe: true,
      groupId: groupId,
    ));

    state = AsyncData([newMessage, ...state.value ?? []]);

    // Send via Korium to all group members (except ourselves)
    try {
      final nodeAsync = ref.read(koriumNodeProvider);
      String? errorReason;

      await nodeAsync.when(
        loading: () async {
          errorReason = 'Network not ready';
        },
        error: (e, stackTrace) async {
          errorReason = 'Network error: $e';
        },
        data: (node) async {
          // Create Korium ChatMessage with groupId
          final koriumMessage = korium.ChatMessage(
            id: messageId,
            senderId: myId,
            recipientId: groupId,
            text: text,
            messageType: korium.MessageType.text,
            timestampMs: now.millisecondsSinceEpoch,
            status: korium.MessageStatus.pending,
            isFromMe: true,
            groupId: groupId,
          );

          // Send to group topic - all members are subscribed
          try {
            await node.sendGroupMessage(
              groupId: groupId,
              message: koriumMessage,
            );

            // Mark as sent
            await _updateMessageStatus(messageId, MessageStatus.sent);
            
            // Update chat list preview
            await _updateGroupChatListPreview(group, text, now);
          } catch (e) {
            errorReason = 'Failed to send: $e';
            await _updateMessageStatus(messageId, MessageStatus.failed);
          }
        },
      );

      if (errorReason != null) {
        await _updateMessageStatus(messageId, MessageStatus.failed);
      }

      return errorReason;
    } catch (e) {
      debugPrint('Error sending group message: $e');
      await _updateMessageStatus(messageId, MessageStatus.failed);
      return 'Failed to send: $e';
    }
  }

  /// Clears all messages for this group.
  Future<void> clearMessages() async {
    state = const AsyncData([]);
    await _storage.deleteMessagesForGroup(groupId);
  }

  /// Updates a message status in both state and storage.
  Future<void> _updateMessageStatus(
    String messageId,
    MessageStatus newStatus,
  ) async {
    // Update storage
    await _storage.updateMessageStatus(
      messageId,
      _modelStatusToHive(newStatus),
    );

    // Update state
    state = AsyncData(
      (state.value ?? []).map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(status: newStatus);
        }
        return msg;
      }).toList(),
    );
  }

  /// Updates the chat list preview for this group.
  Future<void> _updateGroupChatListPreview(
    Group group,
    String lastMessage,
    DateTime timestamp,
  ) async {
    // Update chat list preview
    // This uses the group ID as the peerId to identify the chat
    await _storage.saveChatPreview(ChatPreviewHive(
      peerId: groupId,
      peerName: group.name,
      lastMessage: lastMessage,
      lastMessageTimeMs: timestamp.millisecondsSinceEpoch,
      unreadCount: 0,
      isFromMe: true,
      isGroupChat: true,
    ));

    // Refresh chat list
    ref.invalidate(chatListProvider);
  }

  /// Updates the chat list preview for incoming group messages.
  Future<void> _updateIncomingGroupChatListPreview({
    required String senderName,
    required String lastMessage,
    required DateTime timestamp,
  }) async {
    // Get group name for the preview
    final groups = ref.read(groupsProvider).value ?? [];
    final group = groups.where((g) => g.id == groupId).firstOrNull;
    final groupName = group?.name ?? 'Group';
    
    // Get readable sender name from group member names
    final displaySender = group?.memberNames[senderName] ?? _truncateId(senderName);
    
    // Get existing preview to preserve and increment unread count
    final existingPreview = _storage.getChatPreview(groupId);
    final currentUnread = existingPreview?.unreadCount ?? 0;
    
    // Update chat list preview with sender prefix and incremented unread
    await _storage.saveChatPreview(ChatPreviewHive(
      peerId: groupId,
      peerName: groupName,
      lastMessage: '$displaySender: $lastMessage',
      lastMessageTimeMs: timestamp.millisecondsSinceEpoch,
      unreadCount: currentUnread + 1,
      isFromMe: false,
      isGroupChat: true,
    ));

    // Refresh chat list
    ref.invalidate(chatListProvider);
  }
}

/// Provider to get sender display name for group messages.
/// Uses the group's memberNames map for quick lookup.
final groupMemberNameProvider = Provider.family<String, ({String groupId, String senderId})>((ref, params) {
  final groups = ref.watch(groupsProvider).value ?? [];
  final group = groups.where((g) => g.id == params.groupId).firstOrNull;
  
  if (group == null) return _truncateId(params.senderId);
  
  return group.memberNames[params.senderId] ?? _truncateId(params.senderId);
});

/// Truncates a Korium identity for display.
String _truncateId(String id) {
  if (id.length <= 12) return id;
  return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
}
