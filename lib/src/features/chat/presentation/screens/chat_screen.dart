import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/notifications/notification_listener.dart'
    as app_notifications;
import 'package:six7_chat/src/features/chat/presentation/widgets/message_bubble.dart';
import 'package:six7_chat/src/features/chat/presentation/widgets/chat_input.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/message_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/outbox_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.peerId,
    this.peerName,
  });

  final String peerId;
  final String? peerName;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  // Save notification listener reference for safe dispose
  app_notifications.NotificationListener? _notificationListener;

  @override
  void initState() {
    super.initState();
    // Suppress notifications for this chat while it's open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notificationListener = ref.read(app_notifications.notificationListenerProvider);
      _notificationListener?.setActiveChatPeer(widget.peerId);
    });
  }

  @override
  void dispose() {
    // Clear active chat so notifications resume (use saved reference)
    _notificationListener?.setActiveChatPeer(null);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messageProvider(widget.peerId));
    final displayName = widget.peerName ?? _truncateId(widget.peerId);
    final peerStatusAsync = ref.watch(peerOnlineStatusProvider(widget.peerId));

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              child: Text(
                _getInitials(displayName),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  _buildPeerStatus(context, peerStatusAsync),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(context, value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'view_contact',
                child: Text('View contact'),
              ),
              const PopupMenuItem(
                value: 'media',
                child: Text('Media, links, and docs'),
              ),
              const PopupMenuItem(
                value: 'search',
                child: Text('Search'),
              ),
              const PopupMenuItem(
                value: 'mute',
                child: Text('Mute notifications'),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Outbox indicator - shows pending messages for this peer
          _buildOutboxBanner(context),
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error loading messages: $error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          ref.invalidate(messageProvider(widget.peerId)),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (messages) => _buildMessageList(context, messages),
            ),
          ),
          ChatInput(
            onSend: (text) => _sendMessage(text),
            onAttachment: () => _showComingSoon(context, 'Attachments'),
            onVoice: () => _showComingSoon(context, 'Voice message'),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(BuildContext context, List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Messages are end-to-end encrypted.\n'
                'No one outside of this chat can read them.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final previousMessage =
            index < messages.length - 1 ? messages[index + 1] : null;
        final showTimestamp = previousMessage == null ||
            message.timestamp.difference(previousMessage.timestamp).inMinutes >
                5;

        return Column(
          children: [
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _buildTimestampBadge(context, message.timestamp),
              ),
            MessageBubble(message: message),
          ],
        );
      },
    );
  }

  Widget _buildTimestampBadge(BuildContext context, DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    String text;

    if (difference.inDays == 0) {
      text = 'Today';
    } else if (difference.inDays == 1) {
      text = 'Yesterday';
    } else {
      text =
          '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final error = await ref
        .read(messageProvider(widget.peerId).notifier)
        .sendMessage(text.trim());

    // Show error if message failed
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _sendMessage(text),
          ),
        ),
      );
    }

    // Scroll to bottom after sending
    if (_scrollController.hasClients) {
      unawaited(_scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),);
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature - Coming soon')),
    );
  }

  void _handleMenuAction(BuildContext context, String action) {
    _showComingSoon(context, action);
  }

  Widget _buildPeerStatus(BuildContext context, AsyncValue<bool> statusAsync) {
    return statusAsync.when(
      loading: () => const Text(
        'Checking...',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.grey),
      ),
      error: (_, stackTrace) => const Text(
        'Status unknown',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: Colors.grey),
      ),
      data: (isOnline) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isOnline ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: isOnline ? Colors.green : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds a banner showing pending outbox messages for this peer.
  Widget _buildOutboxBanner(BuildContext context) {
    final outboxCount = ref.watch(outboxCountForPeerProvider(widget.peerId));
    final outboxState = ref.watch(outboxProvider);
    
    if (outboxCount == 0) {
      return const SizedBox.shrink();
    }

    final isRetrying = outboxState.isProcessing;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer,
      child: Row(
        children: [
          if (isRetrying)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(
              Icons.schedule,
              size: 16,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isRetrying
                  ? 'Sending $outboxCount pending message${outboxCount > 1 ? 's' : ''}...'
                  : '$outboxCount message${outboxCount > 1 ? 's' : ''} waiting to send',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (!isRetrying)
            TextButton(
              onPressed: () => ref.read(outboxProvider.notifier).processNow(),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: const Text('Retry Now'),
            ),
        ],
      ),
    );
  }

  String _truncateId(String id) {
    if (id.length <= 8) return id;
    return '${id.substring(0, 4)}...${id.substring(id.length - 4)}';
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}
