import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/home/domain/models/chat_preview.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart';

/// Provider for the list of chat previews.
/// Listens to Korium node for real-time updates.
final chatListProvider =
    AsyncNotifierProvider<ChatListNotifier, List<ChatPreview>>(
  ChatListNotifier.new,
);

class ChatListNotifier extends AsyncNotifier<List<ChatPreview>> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<List<ChatPreview>> build() async {
    // Listen to Korium events for incoming messages (non-blocking)
    // The event listener will start working once the node is ready
    _setupEventListener();

    // Load chats immediately from storage - don't wait for network
    return _loadChats();
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
  void _handleKoriumEvent(KoriumEvent event) {
    switch (event) {
      case KoriumEvent_ChatMessageReceived(:final message):
        // Update chat preview when a message is received
        _handleIncomingMessage(
          senderId: message.senderId,
          text: message.text,
          timestampMs: message.timestampMs,
          isFromMe: message.isFromMe,
        );

      case KoriumEvent_MessageStatusUpdate():
      case KoriumEvent_PubSubMessage():
      case KoriumEvent_IncomingRequest():
      case KoriumEvent_ConnectionStateChanged():
      case KoriumEvent_PeerPresenceChanged():
      case KoriumEvent_Error():
      case KoriumEvent_BootstrapComplete():
        // Not handled at chat list level
        break;
    }
  }

  /// Handles an incoming message by updating the chat preview.
  Future<void> _handleIncomingMessage({
    required String senderId,
    required String text,
    required int timestampMs,
    required bool isFromMe,
  }) async {
    // Get peer name from contacts if available
    final contacts = ref.read(contactsProvider).value ?? [];
    final contact = contacts.where((c) => c.identity == senderId).firstOrNull;
    final peerName = contact?.displayName ?? _truncateId(senderId);

    await updateChatPreviewFromMessage(
      peerId: senderId,
      peerName: peerName,
      lastMessage: text,
      lastMessageTime: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      isFromMe: isFromMe,
      incrementUnread: !isFromMe, // Only increment for incoming messages
    );
  }

  String _truncateId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  Future<List<ChatPreview>> _loadChats() async {
    final hivePreviews = _storage.getAllChatPreviews();
    return hivePreviews.map(_hiveToModel).toList();
  }

  ChatPreview _hiveToModel(ChatPreviewHive hive) {
    return ChatPreview(
      peerId: hive.peerId,
      peerName: hive.peerName,
      avatarUrl: hive.peerAvatarUrl,
      lastMessage: hive.lastMessage,
      lastMessageTime: DateTime.fromMillisecondsSinceEpoch(hive.lastMessageTimeMs),
      unreadCount: hive.unreadCount,
      isPinned: hive.isPinned,
      isMuted: hive.isMuted,
      isFromMe: hive.isFromMe,
      isDelivered: hive.isDelivered,
      isRead: hive.isRead,
    );
  }

  ChatPreviewHive _modelToHive(ChatPreview preview) {
    return ChatPreviewHive(
      peerId: preview.peerId,
      peerName: preview.peerName,
      peerAvatarUrl: preview.avatarUrl,
      lastMessage: preview.lastMessage,
      lastMessageTimeMs: preview.lastMessageTime.millisecondsSinceEpoch,
      unreadCount: preview.unreadCount,
      isPinned: preview.isPinned,
      isMuted: preview.isMuted,
      isFromMe: preview.isFromMe,
      isDelivered: preview.isDelivered,
      isRead: preview.isRead,
    );
  }

  /// Updates or creates a chat preview when a message is sent/received.
  Future<void> updateChatPreviewFromMessage({
    required String peerId,
    required String peerName,
    required String lastMessage,
    required DateTime lastMessageTime,
    required bool isFromMe,
    bool incrementUnread = false,
  }) async {
    final currentChats = state.value ?? [];
    final existingIndex = currentChats.indexWhere((c) => c.peerId == peerId);

    ChatPreview updatedPreview;
    List<ChatPreview> updatedChats;

    if (existingIndex >= 0) {
      final existing = currentChats[existingIndex];
      updatedPreview = existing.copyWith(
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        isFromMe: isFromMe,
        unreadCount: incrementUnread
            ? existing.unreadCount + 1
            : existing.unreadCount,
      );
      updatedChats = [...currentChats];
      updatedChats[existingIndex] = updatedPreview;
    } else {
      updatedPreview = ChatPreview(
        peerId: peerId,
        peerName: peerName,
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        isFromMe: isFromMe,
        unreadCount: incrementUnread ? 1 : 0,
      );
      updatedChats = [updatedPreview, ...currentChats];
    }

    // Sort: pinned first, then by time
    updatedChats.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });

    // Persist
    await _storage.saveChatPreview(_modelToHive(updatedPreview));

    state = AsyncData(updatedChats);
  }

  /// Marks a chat as read and optionally sends read receipts.
  /// 
  /// This method:
  /// 1. Updates the local unread count to 0
  /// 2. Marks messages as read in storage
  /// 3. Sends read receipts over the network (if enabled in settings)
  Future<void> markAsRead(String peerId) async {
    // Update UI immediately
    state = await AsyncValue.guard(() async {
      final chats = state.value ?? [];
      final updated = chats.map((chat) {
        if (chat.peerId == peerId) {
          return chat.copyWith(unreadCount: 0);
        }
        return chat;
      }).toList();
      return updated;
    });

    // Get unread message IDs before marking as read
    final unreadMessageIds = _storage.getUnreadMessageIdsFromPeer(peerId);

    // Mark as read in local storage
    await _storage.markChatAsRead(peerId);
    await _storage.markMessagesAsReadFromPeer(peerId);

    // Send read receipts if enabled and there are unread messages
    if (unreadMessageIds.isNotEmpty) {
      await _sendReadReceipts(peerId, unreadMessageIds);
    }
  }

  /// Sends read receipts to the peer for the given message IDs.
  /// Respects user's read receipt privacy setting.
  Future<void> _sendReadReceipts(String peerId, List<String> messageIds) async {
    // Check if read receipts are enabled in settings
    final settings = ref.read(accountSettingsProvider);
    if (!settings.readReceipts) {
      debugPrint('Read receipts disabled in settings, not sending');
      return;
    }

    // Get the node
    final nodeAsync = ref.read(koriumNodeProvider);
    final node = nodeAsync.value;
    if (node == null) {
      debugPrint('Node not ready, cannot send read receipts');
      return;
    }

    try {
      // Create read receipt message
      // Format: messageType=readReceipt, content=comma-separated message IDs
      final readReceiptMessage = ChatMessage(
        id: 'rr-${DateTime.now().millisecondsSinceEpoch}',
        senderId: node.identity,
        recipientId: peerId,
        text: messageIds.join(','),
        messageType: MessageType.readReceipt,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        status: MessageStatus.pending,
        isFromMe: true,
      );

      await node.sendMessage(peerId: peerId, message: readReceiptMessage);
      debugPrint('Sent read receipts for ${messageIds.length} messages to ${peerId.substring(0, 8)}...');
    } catch (e) {
      // Read receipt sending is best-effort, don't fail the operation
      debugPrint('Failed to send read receipts: $e');
    }
  }

  Future<void> deleteChat(String peerId) async {
    state = await AsyncValue.guard(() async {
      final chats = state.value ?? [];
      return chats.where((chat) => chat.peerId != peerId).toList();
    });

    await _storage.deleteChatPreview(peerId);
    await _storage.deleteMessagesForPeer(peerId);
  }

  Future<void> togglePin(String peerId) async {
    ChatPreview? updatedPreview;
    state = await AsyncValue.guard(() async {
      final chats = state.value ?? [];
      final updated = chats.map((chat) {
        if (chat.peerId == peerId) {
          updatedPreview = chat.copyWith(isPinned: !chat.isPinned);
          return updatedPreview!;
        }
        return chat;
      }).toList();

      // Sort: pinned first, then by time
      updated.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.lastMessageTime.compareTo(a.lastMessageTime);
      });

      return updated;
    });

    if (updatedPreview != null) {
      await _storage.saveChatPreview(_modelToHive(updatedPreview!));
    }
  }
}
