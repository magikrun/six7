import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Chat settings screen for theme, font size, and chat customization.
class ChatSettingsScreen extends ConsumerWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(chatSettingsProvider);
    final notifier = ref.read(chatSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
      ),
      body: ListView(
        children: [
          // Display section
          _buildSectionHeader(context, 'Display'),
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Wallpaper'),
            subtitle: Text(settings.wallpaper ?? 'Default'),
            onTap: () => _showWallpaperPicker(context, notifier),
          ),

          const Divider(),

          // Chat settings section
          _buildSectionHeader(context, 'Chat settings'),
          SwitchListTile(
            secondary: const Icon(Icons.keyboard_return),
            title: const Text('Enter is send'),
            subtitle: const Text('Press Enter to send messages'),
            value: settings.enterToSend,
            onChanged: notifier.setEnterToSend,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.photo_library),
            title: const Text('Media visibility'),
            subtitle: const Text('Show media in device gallery'),
            value: settings.mediaVisibility,
            onChanged: notifier.setMediaVisibility,
          ),

          const Divider(),

          // Chat history section
          _buildSectionHeader(context, 'Chat history'),
          ListTile(
            leading: Icon(Icons.delete_sweep, color: Colors.red.shade700),
            title: Text(
              'Clear all chats',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () => _showClearChatsDialog(context, ref),
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

  void _showWallpaperPicker(
    BuildContext context,
    ChatSettingsNotifier notifier,
  ) {
    final wallpapers = [
      ('Default', null, Colors.grey.shade200),
      ('Dark', 'dark', Colors.grey.shade800),
      ('Blue', 'blue', Colors.blue.shade200),
      ('Green', 'green', Colors.green.shade200),
      ('Purple', 'purple', Colors.purple.shade200),
      ('Orange', 'orange', Colors.orange.shade200),
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose Wallpaper',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: wallpapers.length,
                separatorBuilder: (_, index) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final (name, value, color) = wallpapers[index];
                  return GestureDetector(
                    onTap: () {
                      notifier.setWallpaper(value);
                      Navigator.pop(context);
                    },
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(name, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showClearChatsDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear All Chats?'),
        content: const Text(
          'This will delete all messages from all chats. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              // Clear all chat messages and previews
              final storage = ref.read(storageServiceProvider);
              await storage.clearAllMessages();
              
              // Refresh chat list
              ref.invalidate(chatListProvider);
              
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All chats cleared')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
