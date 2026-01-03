import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            subtitle: Text(settings.theme.label),
            onTap: () => _showThemePicker(context, settings.theme, notifier),
          ),
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Wallpaper'),
            subtitle: Text(settings.wallpaper ?? 'Default'),
            onTap: () => _showWallpaperPicker(context, notifier),
          ),

          const Divider(),

          // Chat settings section
          _buildSectionHeader(context, 'Chat settings'),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('Font size'),
            subtitle: Text(settings.fontSize.label),
            onTap: () => _showFontSizePicker(
              context,
              settings.fontSize,
              notifier,
            ),
          ),
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
            leading: const Icon(Icons.backup),
            title: const Text('Chat backup'),
            subtitle: const Text('Back up your chats'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBackupOptions(context),
          ),
          ListTile(
            leading: Icon(Icons.history, color: Colors.orange.shade700),
            title: const Text('Export chat history'),
            onTap: () => _showExportOptions(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_sweep, color: Colors.red.shade700),
            title: Text(
              'Clear all chats',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () => _showClearChatsDialog(context),
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

  Future<void> _showThemePicker(
    BuildContext context,
    AppTheme currentTheme,
    ChatSettingsNotifier notifier,
  ) async {
    final result = await showDialog<AppTheme>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme'),
        content: RadioGroup<AppTheme>(
          groupValue: currentTheme,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: AppTheme.values.map((theme) {
              return RadioListTile<AppTheme>(
                title: Text(theme.label),
                value: theme,
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      await notifier.setTheme(result);
    }
  }

  Future<void> _showFontSizePicker(
    BuildContext context,
    FontSize currentSize,
    ChatSettingsNotifier notifier,
  ) async {
    final result = await showDialog<FontSize>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Font size'),
        content: RadioGroup<FontSize>(
          groupValue: currentSize,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: FontSize.values.map((size) {
              return RadioListTile<FontSize>(
                title: Text(
                  size.label,
                  style: TextStyle(
                    fontSize: switch (size) {
                      FontSize.small => 14,
                      FontSize.medium => 16,
                      FontSize.large => 18,
                    },
                  ),
                ),
                value: size,
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      await notifier.setFontSize(result);
    }
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

  void _showBackupOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat Backup',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.cloud_upload),
              title: const Text('Back up now'),
              subtitle: const Text('Last backup: Never'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Backup not implemented yet')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_download),
              title: const Text('Restore from backup'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Restore not implemented yet')),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showExportOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Export Chat History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const Text(
              'Choose a chat to export. The chat history will be saved as a '
              'text file that you can share or save.',
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Export not implemented yet'),
                    ),
                  );
                },
                child: const Text('Select Chat'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearChatsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Chats?'),
        content: const Text(
          'This will delete all messages from all chats. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Clear chats not implemented yet'),
                ),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}
