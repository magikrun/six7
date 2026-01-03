import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/home/domain/models/chat_preview.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/presence_provider.dart';
import 'package:six7_chat/src/core/constants/app_constants.dart';
import 'package:timeago/timeago.dart' as timeago;

/// A tile widget for displaying a chat preview in a list.
/// Supports swipe-to-delete and swipe-to-pin actions.
/// Shows online status indicator on avatar.
class ChatListTile extends ConsumerWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.onTap,
    this.onDelete,
    this.onTogglePin,
  });

  final ChatPreview chat;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    // Watch peer online status using real-time presence
    final isOnline = ref.watch(isPeerOnlineProvider(chat.peerId));

    Widget tile = ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: AppConstants.avatarSizeSmall.toDouble() / 2,
            backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
            backgroundImage:
                chat.avatarUrl != null ? FileImage(File(chat.avatarUrl!)) : null,
            child: chat.avatarUrl == null
                ? Text(
                    _getInitials(chat.peerName),
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          // Online status indicator - green dot on avatar
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: isOnline ? Colors.green : Colors.grey.shade400,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
            ),
          ),
          if (chat.isPinned)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.push_pin,
                  size: 12,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.peerName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _formatTimestamp(chat.lastMessageTime),
            style: theme.textTheme.bodySmall?.copyWith(
              color: chat.unreadCount > 0
                  ? colorScheme.primary
                  : theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          if (chat.isFromMe) ...[
            Icon(
              chat.isDelivered
                  ? (chat.isRead ? Icons.done_all : Icons.done_all)
                  : Icons.done,
              size: 18,
              color: chat.isRead ? colorScheme.primary : Colors.grey,
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              chat.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
            ),
          ),
          if (chat.unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );

    // Wrap with swipe actions if callbacks are provided
    if (onDelete != null || onTogglePin != null) {
      tile = Dismissible(
        key: Key('chat_${chat.peerId}'),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.endToStart && onDelete != null) {
            // Delete action - show confirmation
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete Chat'),
                content: Text('Delete chat with ${chat.peerName}? This will also delete all messages.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              onDelete!();
            }
            return false; // We handle the action manually
          } else if (direction == DismissDirection.startToEnd && onTogglePin != null) {
            // Pin/unpin action
            onTogglePin!();
            return false; // Don't dismiss, just toggle
          }
          return false;
        },
        background: Container(
          color: colorScheme.primary,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Icon(
            chat.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            color: Colors.white,
          ),
        ),
        secondaryBackground: Container(
          color: Colors.red,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        child: tile,
      );
    }

    return tile;
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _formatTimestamp(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return timeago.format(time, locale: 'en_short');
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }
}
