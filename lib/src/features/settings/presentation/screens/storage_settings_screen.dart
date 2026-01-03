import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Storage and data settings screen for managing network usage and downloads.
class StorageSettingsScreen extends ConsumerWidget {
  const StorageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(storageSettingsProvider);
    final notifier = ref.read(storageSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage and data'),
      ),
      body: ListView(
        children: [
          // Storage usage section
          _buildSectionHeader(context, 'Storage usage'),
          _buildStorageUsageCard(context),

          const Divider(),

          // Media quality section
          _buildSectionHeader(context, 'Media upload quality'),
          ListTile(
            leading: const Icon(Icons.high_quality),
            title: const Text('Media quality'),
            subtitle: Text(settings.mediaQuality.label),
            onTap: () => _showQualityPicker(
              context,
              settings.mediaQuality,
              notifier,
            ),
          ),

          const Divider(),

          // Network usage section
          _buildSectionHeader(context, 'Network usage'),
          ListTile(
            leading: const Icon(Icons.analytics),
            title: const Text('Network usage'),
            subtitle: const Text('View data usage statistics'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showNetworkUsage(context),
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

  Widget _buildStorageUsageCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Six7 Data',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '12.4 MB',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: 0.15,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStorageItem('Messages', '2.1 MB', Colors.blue),
                _buildStorageItem('Media', '8.3 MB', Colors.green),
                _buildStorageItem('Cache', '2.0 MB', Colors.orange),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageItem(String label, String size, Color color) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Text(
          size,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Future<void> _showQualityPicker(
    BuildContext context,
    MediaQuality currentQuality,
    StorageSettingsNotifier notifier,
  ) async {
    final result = await showDialog<MediaQuality>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media upload quality'),
        content: RadioGroup<MediaQuality>(
          groupValue: currentQuality,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: MediaQuality.values.map((quality) {
              return RadioListTile<MediaQuality>(
                title: Text(quality.label),
                subtitle: Text(
                  switch (quality) {
                    MediaQuality.auto =>
                      'Automatically adjusts quality based on connection',
                    MediaQuality.best => 'Uploads at full resolution',
                    MediaQuality.dataEfficient =>
                      'Reduces file size to save data',
                  },
                ),
                value: quality,
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      await notifier.setMediaQuality(result);
    }
  }

  void _showNetworkUsage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Network Usage',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _buildUsageRow('Messages sent', '1.2 MB'),
            _buildUsageRow('Messages received', '3.4 MB'),
            _buildUsageRow('Media sent', '5.6 MB'),
            _buildUsageRow('Media received', '12.8 MB'),
            _buildUsageRow('Voice calls', '0.5 MB'),
            _buildUsageRow('Video calls', '0.0 MB'),
            const Divider(),
            _buildUsageRow('Total', '23.5 MB', bold: true),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Statistics reset')),
                  );
                },
                child: const Text('Reset Statistics'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildUsageRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
