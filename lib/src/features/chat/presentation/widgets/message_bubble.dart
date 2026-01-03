import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:six7_chat/src/features/messaging/domain/models/chat_message.dart';
import 'package:six7_chat/src/core/theme/app_theme.dart';
import 'package:six7_chat/src/features/reporting/presentation/widgets/report_message_dialog.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.senderDisplayName,
    this.onReply,
    this.onDelete,
  });

  final ChatMessage message;
  
  /// Display name of the sender (for reporting).
  final String? senderDisplayName;
  
  /// Callback when user wants to reply to this message.
  final VoidCallback? onReply;
  
  /// Callback when user wants to delete this message.
  final VoidCallback? onDelete;

  void _showContextMenu(BuildContext context, TapDownDetails details) {
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
          _showReportDialog(context);
      }
    });
  }

  void _showReportDialog(BuildContext context) {
    ReportMessageDialog.show(
      context,
      message: message,
      senderDisplayName: senderDisplayName ?? _truncateId(message.senderId),
    );
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final isMe = message.isFromMe;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onSecondaryTapDown: (details) => _showContextMenu(context, details),
        onLongPressStart: (details) => _showContextMenu(
          context,
          TapDownDetails(globalPosition: details.globalPosition),
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
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}
