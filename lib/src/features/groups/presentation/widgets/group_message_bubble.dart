import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/groups/domain/providers/group_message_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/core/theme/app_theme.dart';
import 'package:six7_chat/src/features/reporting/presentation/widgets/report_message_dialog.dart';

/// Message bubble for group chats that shows sender name for received messages.
class GroupMessageBubble extends ConsumerWidget {
  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.groupId,
    this.groupName,
    this.showSenderName = true,
    this.onReply,
    this.onDelete,
  });

  final ChatMessage message;
  final String groupId;
  final String? groupName;
  final bool showSenderName;
  
  /// Callback when user wants to reply to this message.
  final VoidCallback? onReply;
  
  /// Callback when user wants to delete this message.
  final VoidCallback? onDelete;

  void _showContextMenu(BuildContext context, TapDownDetails details, String? senderName) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        details.globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        const PopupMenuItem(
          value: 'copy',
          child: ListTile(
            leading: Icon(Icons.copy, size: 20),
            title: Text('Copy'),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (onReply != null)
          const PopupMenuItem(
            value: 'reply',
            child: ListTile(
              leading: Icon(Icons.reply, size: 20),
              title: Text('Reply'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (onDelete != null)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, size: 20),
              title: Text('Delete'),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        // Only show report for received messages
        if (!message.isFromMe) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'report',
            child: ListTile(
              leading: Icon(
                Icons.flag_outlined,
                size: 20,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Report',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    ).then((value) {
      if (value == null) return;
      
      switch (value) {
        case 'copy':
          Clipboard.setData(ClipboardData(text: message.text));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message copied'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        case 'reply':
          onReply?.call();
        case 'delete':
          onDelete?.call();
        case 'report':
          _showReportDialog(context, senderName);
      }
    });
  }

  void _showReportDialog(BuildContext context, String? senderName) {
    ReportMessageDialog.show(
      context,
      message: message,
      senderDisplayName: senderName ?? _truncateId(message.senderId),
      groupId: groupId,
      groupName: groupName,
    );
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMe = message.isFromMe;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Get sender display name for group messages
    final senderName = !isMe && showSenderName
        ? ref.watch(groupMemberNameProvider(
            (groupId: groupId, senderId: message.senderId),
          ))
        : null;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (details) => _showContextMenu(context, details, senderName),
        onLongPressStart: (details) => _showContextMenu(
          context,
          TapDownDetails(globalPosition: details.globalPosition),
          senderName,
        ),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show sender name for received messages in groups
              if (senderName != null) ...[
                Text(
                  senderName,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _getSenderColor(message.senderId, isDark),
                  ),
                ),
                const SizedBox(height: 2),
              ],
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
                          ? (isDark ? Colors.white70 : Colors.black54)
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
      ),
    );
  }

  /// Generates a consistent color for a sender based on their identity.
  Color _getSenderColor(String senderId, bool isDark) {
    // Hash the senderId to get a consistent color
    final hash = senderId.hashCode.abs();
    final colors = isDark
        ? [
            Colors.tealAccent.shade200,
            Colors.amberAccent.shade200,
            Colors.lightBlueAccent.shade200,
            Colors.pinkAccent.shade100,
            Colors.lightGreenAccent.shade200,
            Colors.orangeAccent.shade200,
            Colors.purpleAccent.shade100,
            Colors.cyanAccent.shade200,
          ]
        : [
            Colors.teal.shade700,
            Colors.amber.shade700,
            Colors.blue.shade700,
            Colors.pink.shade700,
            Colors.green.shade700,
            Colors.orange.shade700,
            Colors.purple.shade700,
            Colors.cyan.shade700,
          ];
    return colors[hash % colors.length];
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
