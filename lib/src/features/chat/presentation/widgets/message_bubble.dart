import 'package:flutter/material.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/core/theme/app_theme.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
  });

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isFromMe;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: EdgeInsets.only(
          left: isMe ? 48 : 0,
          right: isMe ? 0 : 48,
          bottom: 4,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isMe
              ? (isDark ? AppColors.darkViolet : AppColors.lightViolet)
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isMe ? 12 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isMe
                    ? (isDark ? Colors.white : Colors.black87)
                    : theme.textTheme.bodyMedium?.color,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: isMe
                        ? (isDark
                            ? Colors.white70
                            : Colors.black54)
                        : Colors.grey,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    message.status == MessageStatus.read
                        ? Icons.done_all
                        : message.status == MessageStatus.delivered
                            ? Icons.done_all
                            : message.status == MessageStatus.sent
                                ? Icons.done
                                : Icons.access_time,
                    size: 16,
                    color: message.status == MessageStatus.read
                        ? AppColors.lightViolet
                        : (isDark ? Colors.white60 : Colors.black45),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
