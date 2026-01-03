import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/outbox_provider.dart';
import 'package:six7_chat/src/rust/message.dart' as rust_msg;
import 'package:six7_chat/src/rust/streams.dart';
import 'package:uuid/uuid.dart';

/// Represents the result of checking peer reachability.
sealed class PeerReachability {
  const PeerReachability();
}

class PeerOnline extends PeerReachability {
  const PeerOnline(this.addresses);
  final List<String> addresses;
}

class PeerOffline extends PeerReachability {
  const PeerOffline();
}

class PeerCheckFailed extends PeerReachability {
  const PeerCheckFailed(this.error);
  final String error;
}

/// Provider for messages in a specific chat.
/// Uses family to create separate instances per peer.
final messageProvider = AsyncNotifierProvider.family<MessageNotifier,
    List<ChatMessage>, String>(
  MessageNotifier.new,
);

/// Provider to check if a peer is reachable before sending.
final peerReachabilityProvider =
    FutureProvider.family<PeerReachability, String>((ref, peerId) async {
  final nodeAsync = ref.watch(koriumNodeProvider);

  return nodeAsync.when(
    loading: () => const PeerOffline(),
    error: (e, _) => PeerCheckFailed(e.toString()),
    data: (node) async {
      try {
        final addresses = await node.resolvePeer(peerId: peerId);
        if (addresses.isEmpty) {
          return const PeerOffline();
        }
        return PeerOnline(addresses);
      } catch (e) {
        return PeerCheckFailed(e.toString());
      }
    },
  );
});

/// MessageNotifier for a specific peer.
/// Uses constructor injection for family arg as required by Riverpod 3.
class MessageNotifier extends AsyncNotifier<List<ChatMessage>> {
  /// Constructor takes the peerId from family provider.
  MessageNotifier(this.peerId);

  /// The peerId for this family instance.
  final String peerId;

  static const _uuid = Uuid();

  StorageService get _storage => ref.read(storageServiceProvider);

  String? _myIdentity;
  StreamSubscription<KoriumEvent>? _eventSubscription;

  @override
  Future<List<ChatMessage>> build() async {
    // Get our identity from the node (non-blocking - uses listen instead of watch)
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

    // Listen to Korium events for incoming messages
    _setupEventListener(peerId);

    // Clean up subscription on dispose
    ref.onDispose(() {
      _eventSubscription?.cancel();
    });

    // Load persisted messages for this peer from storage
    return _loadMessages(peerId);
  }

  /// Sets up listener for incoming Korium events.
  void _setupEventListener(String peerId) {
    final eventStream = ref.listen(
      koriumEventStreamProvider,
      (previous, next) {
        next.whenData((event) => _handleKoriumEvent(event, peerId));
      },
    );

    // Store for cleanup
    ref.onDispose(eventStream.close);
  }

  /// Handles incoming Korium events.
  void _handleKoriumEvent(KoriumEvent event, String peerId) {
    switch (event) {
      case KoriumEvent_ChatMessageReceived(:final message):
        // Only process messages from/to this peer
        if (message.senderId == peerId || message.recipientId == peerId) {
          _addIncomingMessage(message);
        }

      case KoriumEvent_MessageStatusUpdate(:final messageId, :final status):
        // Update status of our sent messages
        final dartStatus = _rustStatusToModel(status);
        _updateMessageStatus(messageId, dartStatus);

      case KoriumEvent_PubSubMessage():
      case KoriumEvent_IncomingRequest():
      case KoriumEvent_ConnectionStateChanged():
      case KoriumEvent_PeerPresenceChanged():
      case KoriumEvent_Error():
        // Not handled at message level
        break;
    }
  }

  /// Adds an incoming message from the network.
  Future<void> _addIncomingMessage(rust_msg.ChatMessage rustMsg) async {
    final incomingMessage = ChatMessage(
      id: rustMsg.id,
      senderId: rustMsg.senderId,
      recipientId: rustMsg.recipientId,
      text: rustMsg.text,
      timestamp: DateTime.fromMillisecondsSinceEpoch(rustMsg.timestampMs),
      isFromMe: false,
      status: MessageStatus.delivered,
    );

    // Check for duplicates
    final existing = (state.value ?? [])
        .any((m) => m.id == incomingMessage.id,);
    if (existing) return;

    // Persist
    await _storage.saveMessage(ChatMessageHive(
      id: rustMsg.id,
      senderId: rustMsg.senderId,
      recipientId: rustMsg.recipientId,
      text: rustMsg.text,
      type: MessageTypeHive.text,
      timestampMs: rustMsg.timestampMs,
      status: MessageStatusHive.delivered,
      isFromMe: false,
    ));

    // Add to state (newest first)
    state = AsyncData([incomingMessage, ...state.value ?? []]);
  }

  MessageStatus _rustStatusToModel(rust_msg.MessageStatus status) {
    return switch (status) {
      rust_msg.MessageStatus.pending => MessageStatus.pending,
      rust_msg.MessageStatus.sent => MessageStatus.sent,
      rust_msg.MessageStatus.delivered => MessageStatus.delivered,
      rust_msg.MessageStatus.read => MessageStatus.read,
      rust_msg.MessageStatus.failed => MessageStatus.failed,
    };
  }

  Future<List<ChatMessage>> _loadMessages(String peerId) async {
    final hiveMessages = _storage.getMessagesForPeer(peerId);

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

  /// Sends a message to the peer, checking reachability first.
  /// Returns a reason if the message couldn't be sent.
  Future<String?> sendMessage(String text) async {
    final myId = _myIdentity ?? 'unknown';
    final messageId = _uuid.v4();
    final now = DateTime.now();

    // Check if this is a self-message ("Notes to Self")
    final isSelfMessage = peerId.toLowerCase() == myId.toLowerCase();

    // Optimistically add the message
    final newMessage = ChatMessage(
      id: messageId,
      senderId: myId,
      recipientId: peerId,
      text: text,
      timestamp: now,
      isFromMe: true,
      status: isSelfMessage ? MessageStatus.delivered : MessageStatus.pending,
    );

    // Persist immediately
    await _storage.saveMessage(ChatMessageHive(
      id: messageId,
      senderId: myId,
      recipientId: peerId,
      text: text,
      type: MessageTypeHive.text,
      timestampMs: now.millisecondsSinceEpoch,
      status: isSelfMessage ? MessageStatusHive.delivered : MessageStatusHive.pending,
      isFromMe: true,
    ),);

    state = AsyncData([newMessage, ...state.value ?? []]);

    // For self-messages, skip network and update chat list directly
    if (isSelfMessage) {
      await _updateChatListPreview(text, now, isFromMe: true);
      return null; // Success
    }

    // Send via Korium
    try {
      final nodeAsync = ref.read(koriumNodeProvider);
      String? errorReason;

      await nodeAsync.when(
        loading: () async {
          errorReason = 'Network not ready';
          // Queue in outbox for retry instead of marking failed
          await _addToOutbox(messageId, text);
        },
        error: (e, stackTrace) async {
          errorReason = 'Network error: $e';
          // Queue in outbox for retry instead of marking failed
          await _addToOutbox(messageId, text);
        },
        data: (node) async {
          // Create Rust ChatMessage and send via Korium
          final rustMessage = rust_msg.ChatMessage(
            id: messageId,
            senderId: myId,
            recipientId: peerId,
            text: text,
            messageType: rust_msg.MessageType.text,
            timestampMs: now.millisecondsSinceEpoch,
            status: rust_msg.MessageStatus.pending,
            isFromMe: true,
          );

          try {
            await node.sendMessage(
              peerId: peerId,
              message: rustMessage,
            );
            await _updateMessageStatusWithPersist(messageId, MessageStatus.sent);

            // Update chat list with the sent message
            await _updateChatListPreview(text, now, isFromMe: true);
          } catch (e) {
            debugPrint('📤 Send failed, queuing in outbox: $e');
            // Queue in outbox for automatic retry
            await _addToOutbox(messageId, text);
            // Keep status as pending (outbox will update to sent or failed)
            errorReason = null; // Don't show error to user, we'll retry
          }
        },
      );

      return errorReason;
    } catch (e) {
      // Queue in outbox for retry
      await _addToOutbox(messageId, text);
      return null; // Don't show error, we'll retry
    }
  }

  /// Adds a message to the outbox for automatic retry.
  Future<void> _addToOutbox(String messageId, String text) async {
    await ref.read(outboxProvider.notifier).addToOutbox(
      messageId: messageId,
      recipientId: peerId,
      text: text,
    );
  }

  /// Updates the chat list preview when a message is sent/received.
  Future<void> _updateChatListPreview(
    String text,
    DateTime timestamp, {
    required bool isFromMe,
  }) async {
    // Get peer name from contacts if available
    final contacts = ref.read(contactsProvider).value ?? [];
    final contact = contacts.where((c) => c.identity == peerId).firstOrNull;
    final peerName = contact?.displayName ?? _truncateId(peerId);

    await ref.read(chatListProvider.notifier).updateChatPreviewFromMessage(
      peerId: peerId,
      peerName: peerName,
      lastMessage: text,
      lastMessageTime: timestamp,
      isFromMe: isFromMe,
      incrementUnread: false, // Don't increment for sent messages
    );
  }

  String _truncateId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  void _updateMessageStatus(String messageId, MessageStatus status) {
    state = AsyncData(
      (state.value ?? []).map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(status: status);
        }
        return msg;
      }).toList(),
    );
  }

  Future<void> _updateMessageStatusWithPersist(
    String messageId,
    MessageStatus status,
  ) async {
    _updateMessageStatus(messageId, status);
    await _storage.updateMessageStatus(messageId, _modelStatusToHive(status));
  }

  Future<void> retryMessage(String messageId) async {
    final messages = state.value ?? [];
    final message = messages.firstWhere(
      (m) => m.id == messageId,
      orElse: () => throw StateError('Message not found'),
    );

    if (message.status == MessageStatus.failed) {
      await _updateMessageStatusWithPersist(messageId, MessageStatus.pending);
      // Retry sending
      await sendMessage(message.text);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    state = AsyncData(
      (state.value ?? []).where((m) => m.id != messageId).toList(),
    );
    await _storage.deleteMessage(messageId);
  }
}
