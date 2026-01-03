import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Notification settings screen for managing vibe and tea notifications.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsProvider);
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: ListView(
        children: [
          // Message notifications section
          _buildSectionHeader(context, 'Message notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.message),
            title: const Text('Message notifications'),
            subtitle: const Text('Show notifications for new messages'),
            value: settings.messageNotifications,
            onChanged: notifier.setMessageNotifications,
          ),

          const Divider(),

          // Group notifications section
          _buildSectionHeader(context, 'Group notifications'),
          SwitchListTile(
            secondary: const Icon(Icons.group),
            title: const Text('Group notifications'),
            subtitle: const Text('Show notifications for group messages'),
            value: settings.groupNotifications,
            onChanged: notifier.setGroupNotifications,
          ),

          const Divider(),

          // General notification settings
          _buildSectionHeader(context, 'General'),
          ListTile(
            leading: const Icon(Icons.music_note),
            title: const Text('Notification tone'),
            subtitle: Text(settings.notificationTone),
            onTap: () => _showTonePicker(context, settings, notifier),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: const Text('Vibrate'),
            subtitle: const Text('Vibrate on new notifications'),
            value: settings.vibrate,
            onChanged: notifier.setVibrate,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: const Text('Pop-up notification'),
            subtitle: const Text('Show pop-up for new messages'),
            value: settings.popupNotification,
            onChanged: notifier.setPopupNotification,
          ),

          const Divider(),

          // Reset section
          ListTile(
            leading: Icon(Icons.restore, color: Colors.orange.shade700),
            title: const Text('Reset notification settings'),
            subtitle: const Text('Restore to default settings'),
            onTap: () => _showResetDialog(context, notifier),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }

  void _showTonePicker(
    BuildContext context,
    NotificationSettings settings,
    NotificationSettingsNotifier notifier,
  ) {
    final tones = [
      'Default',
      'Silent',
      'Chime',
      'Ding',
      'Ping',
      'Pop',
      'Whoosh',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        shrinkWrap: true,
        itemCount: tones.length,
        itemBuilder: (context, index) {
          final tone = tones[index];
          final isSelected = tone == settings.notificationTone;

          return ListTile(
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: Text(tone),
            trailing: tone != 'Silent'
                ? IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Playing $tone...')),
                      );
                    },
                  )
                : null,
            onTap: () {
              notifier.setNotificationTone(tone);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }

  void _showResetDialog(
    BuildContext context,
    NotificationSettingsNotifier notifier,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Settings?'),
        content: const Text(
          'This will reset all notification settings to their default values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await notifier.setMessageNotifications(true);
              await notifier.setGroupNotifications(true);
              await notifier.setCallNotifications(true);
              await notifier.setNotificationTone('Default');
              await notifier.setVibrate(true);
              await notifier.setPopupNotification(false);

              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Notification settings reset to defaults'),
                  ),
                );
              }
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }
}
