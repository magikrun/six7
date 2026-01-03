import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/core/notifications/notification_listener.dart';
import 'package:six7_chat/src/features/chat/presentation/widgets/chat_input.dart';
import 'package:six7_chat/src/features/groups/domain/models/group.dart';
import 'package:six7_chat/src/features/groups/domain/providers/group_message_provider.dart';
import 'package:six7_chat/src/features/groups/domain/providers/groups_provider.dart';
import 'package:six7_chat/src/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';

/// Screen for group chat conversations.
class GroupChatScreen extends ConsumerStatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
  });

  final String groupId;

  @override
  ConsumerState<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends ConsumerState<GroupChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Mark group chat as read when opening
    ref.read(chatListProvider.notifier).markAsRead(widget.groupId);
    // Suppress notifications for this group while it's open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationListenerProvider).setActiveGroupChat(widget.groupId);
    });
  }

  @override
  void dispose() {
    // Clear active group so notifications resume
    ref.read(notificationListenerProvider).setActiveGroupChat(null);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(groupMessageProvider(widget.groupId));
    final groups = ref.watch(groupsProvider).value ?? [];
    final group = groups.where((g) => g.id == widget.groupId).firstOrNull;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Group')),
        body: const Center(child: Text('Group not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _buildGroupAvatar(context, group),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: const TextStyle(fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${group.memberIds.length} members',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(context, value, group),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'group_info',
                child: Text('Group info'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'clear',
                child: Text('Clear chat'),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave group'),
              ),
              if (group.isAdmin) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'edit_group',
                  child: Text('Edit group name'),
                ),
                const PopupMenuItem(
                  value: 'delete_group',
                  child: Text('Delete group'),
                ),
              ],
            ],
          ),
        ],
      ),
      body: Column(
        children: [
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
                          ref.invalidate(groupMessageProvider(widget.groupId)),
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

  Widget _buildGroupAvatar(BuildContext context, Group group, {double? size}) {
    return CircleAvatar(
      radius: size != null ? size / 2 : 20,
      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
      backgroundImage: group.avatarUrl != null ? NetworkImage(group.avatarUrl!) : null,
      child: group.avatarUrl == null
          ? Icon(
              Icons.group,
              color: Theme.of(context).colorScheme.primary,
            )
          : null,
    );
  }

  Widget _buildMessageList(BuildContext context, List<ChatMessage> messages) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.group,
              size: 48,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'No messages yet.\n'
                'Send the first message to start the conversation!',
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
        final nextMessage = index > 0 ? messages[index - 1] : null;

        // Show timestamp if more than 5 minutes since previous message
        final showTimestamp = previousMessage == null ||
            message.timestamp.difference(previousMessage.timestamp).inMinutes > 5;

        // Show sender name if it's a different sender than the next message
        // (since list is reversed, we compare with next which is earlier in index)
        final showSenderName = !message.isFromMe &&
            (nextMessage == null ||
                nextMessage.senderId != message.senderId ||
                nextMessage.isFromMe);

        return Column(
          children: [
            if (showTimestamp)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: _buildTimestampBadge(context, message.timestamp),
              ),
            GroupMessageBubble(
              message: message,
              groupId: widget.groupId,
              showSenderName: showSenderName,
            ),
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
      text = '${timestamp.day}/${timestamp.month}/${timestamp.year}';
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
        .read(groupMessageProvider(widget.groupId).notifier)
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
      ));
    }
  }

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature - Coming soon')),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String action, Group group) async {
    switch (action) {
      case 'group_info':
        await _showGroupInfo(context, group);
      case 'edit_group':
        await _editGroupName(context, group);
      case 'clear':
        await _clearGroupChat(context);
      case 'leave':
        await _leaveGroup(context, group);
      case 'delete_group':
        await _deleteGroup(context, group);
    }
  }

  Future<void> _showGroupInfo(BuildContext context, Group group) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Center(child: _buildGroupAvatar(context, group, size: 80)),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    group.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Created ${_formatDate(group.createdAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Members (${group.memberIds.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...group.memberIds.map((memberId) {
                  final memberName = group.memberNames[memberId] ?? _truncateId(memberId);
                  final isAdmin = memberId == group.creatorId;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        memberName.isNotEmpty ? memberName[0].toUpperCase() : '?',
                        style: TextStyle(color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    title: Text(memberName),
                    trailing: isAdmin ? const Chip(label: Text('Admin')) : null,
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _editGroupName(BuildContext context, Group group) async {
    final controller = TextEditingController(text: group.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Group Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Group name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != group.name && mounted) {
      await ref.read(groupsProvider.notifier).updateGroupName(group.id, newName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group name updated')),
        );
      }
    }
  }

  Future<void> _clearGroupChat(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat'),
        content: const Text('Delete all messages in this group? This cannot be undone.'),
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
      await ref.read(groupMessageProvider(widget.groupId).notifier).clearMessages();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat cleared')),
        );
      }
    }
  }

  Future<void> _leaveGroup(BuildContext context, Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Group'),
        content: Text('Leave "${group.name}"? You will no longer receive messages from this group.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref.read(groupsProvider.notifier).leaveGroup(group.id);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _deleteGroup(BuildContext context, Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}"? This will remove the group for all members and cannot be undone.'),
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
      await ref.read(groupsProvider.notifier).deleteGroup(group.id);
      if (mounted) {
        context.pop();
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}
