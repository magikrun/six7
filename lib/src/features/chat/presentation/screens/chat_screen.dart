import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/core/notifications/notification_listener.dart'
    as app_notifications;
import 'package:six7_chat/src/features/chat/presentation/widgets/message_bubble.dart';
import 'package:six7_chat/src/features/chat/presentation/widgets/chat_input.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/message_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/outbox_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/presence_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.peerId,
    this.peerName,
    this.autofocus = false,
  });

  final String peerId;
  final String? peerName;
  final bool autofocus;

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
      
      // Mark chat as read when opened
      ref.read(chatListProvider.notifier).markAsRead(widget.peerId);
      
      // Trigger ad-hoc presence check if this peer's status is unknown
      // (contacts get presence via inbox subscription automatically)
      final presence = ref.read(peerPresenceProvider(widget.peerId));
      if (presence.status == PresenceStatus.unknown) {
        ref.read(presenceProvider.notifier).checkAdhocPresence(widget.peerId);
      }
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
    // Use real-time presence provider for online status
    final peerPresence = ref.watch(peerPresenceProvider(widget.peerId));
    
    // Get contact avatar if available
    final contacts = ref.watch(contactsProvider).value ?? [];
    final contact = contacts.where(
      (c) => c.identity.toLowerCase() == widget.peerId.toLowerCase(),
    ).firstOrNull;
    final avatarPath = contact?.avatarUrl;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
              backgroundImage: avatarPath != null
                  ? FileImage(File(avatarPath))
                  : null,
              child: avatarPath == null
                  ? Text(
                      _getInitials(displayName),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
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
                  _buildPresenceStatus(context, peerPresence),
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
                value: 'add_contact',
                child: Text('Add to contacts'),
              ),
              const PopupMenuItem(
                value: 'block',
                child: Text('Block contact'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete chat'),
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
            autofocus: widget.autofocus,
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

  Future<void> _handleMenuAction(BuildContext context, String action) async {
    final displayName = widget.peerName ?? _truncateId(widget.peerId);
    
    switch (action) {
      case 'add_contact':
        await _addToContacts(context, displayName);
      case 'block':
        await _blockContact(context, displayName);
      case 'clear':
        await _clearChat(context);
      case 'delete':
        await _deleteChat(context);
    }
  }

  Future<void> _addToContacts(BuildContext context, String displayName) async {
    // Check if already a contact
    final contacts = ref.read(contactsProvider).value ?? [];
    final isContact = contacts.any((c) => c.identity == widget.peerId);
    
    if (isContact) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Already in contacts')),
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to Contacts'),
        content: Text('Add $displayName to your contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(contactsProvider.notifier).addContact(
        identity: widget.peerId,
        displayName: displayName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName added to contacts')),
        );
      }
    }
  }

  Future<void> _blockContact(BuildContext context, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block Contact'),
        content: Text('Block $displayName? You will no longer receive messages from them.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(contactsProvider.notifier).toggleBlock(widget.peerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$displayName has been blocked')),
        );
        context.pop(); // Leave the chat
      }
    }
  }

  Future<void> _clearChat(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Delete all messages in this chat? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(messageProvider(widget.peerId).notifier).clearMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat cleared')),
        );
      }
    }
  }

  Future<void> _deleteChat(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Chat'),
        content: const Text('Delete this chat and all messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(chatListProvider.notifier).deleteChat(widget.peerId);
      if (mounted) {
        context.pop(); // Leave the chat and return to home
      }
    }
  }

  /// Builds the presence status indicator using real-time presence data.
  Widget _buildPresenceStatus(BuildContext context, PeerPresence presence) {
    final Color dotColor;
    final Color textColor;
    final String statusText;
    final bool showGlow;

    switch (presence.status) {
      case PresenceStatus.online:
        dotColor = Colors.green;
        textColor = Colors.green.shade700;
        statusText = 'Online';
        showGlow = true;
      case PresenceStatus.away:
        dotColor = Colors.orange.shade400;
        textColor = Colors.orange.shade600;
        statusText = 'Away';
        showGlow = false;
      case PresenceStatus.offline:
        dotColor = Colors.grey.shade400;
        textColor = Colors.grey.shade600;
        statusText = presence.lastSeenText;
        showGlow = false;
      case PresenceStatus.unknown:
        dotColor = Colors.grey.shade300;
        textColor = Colors.grey.shade500;
        statusText = 'tap to check';
        showGlow = false;
    }

    return GestureDetector(
      onTap: presence.status == PresenceStatus.unknown
          ? () => ref.read(presenceProvider.notifier).checkAdhocPresence(widget.peerId)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
              boxShadow: showGlow
                  ? [
                      BoxShadow(
                        color: Colors.green.withValues(alpha: 0.4),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: presence.status == PresenceStatus.online 
                  ? FontWeight.w500 
                  : FontWeight.w400,
              color: textColor,
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
