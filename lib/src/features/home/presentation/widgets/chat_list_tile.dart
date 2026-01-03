import 'package:flutter/material.dart';
import 'package:six7_chat/src/features/home/domain/models/chat_preview.dart';
import 'package:six7_chat/src/core/constants/app_constants.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatListTile extends StatelessWidget {
  const ChatListTile({
    super.key,
    required this.chat,
    required this.onTap,
  });

  final ChatPreview chat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: AppConstants.avatarSizeSmall.toDouble() / 2,
        backgroundColor: colorScheme.primary.withValues(alpha: 0.2),
        backgroundImage:
            chat.avatarUrl != null ? NetworkImage(chat.avatarUrl!) : null,
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
