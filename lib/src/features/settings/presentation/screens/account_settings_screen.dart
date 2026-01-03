import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Account settings screen for privacy, security, and blocked contacts.
class AccountSettingsScreen extends ConsumerWidget {
  const AccountSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(accountSettingsProvider);
    final notifier = ref.read(accountSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
      ),
      body: ListView(
        children: [
          // Privacy section
          _buildSectionHeader(context, 'Privacy'),
          ListTile(
            title: const Text('Last seen'),
            subtitle: Text(settings.lastSeen.label),
            onTap: () => _showVisibilityPicker(
              context,
              'Last seen',
              settings.lastSeen,
              notifier.setLastSeen,
            ),
          ),
          ListTile(
            title: const Text('Profile photo'),
            subtitle: Text(settings.profilePhoto.label),
            onTap: () => _showVisibilityPicker(
              context,
              'Profile photo',
              settings.profilePhoto,
              notifier.setProfilePhoto,
            ),
          ),
          ListTile(
            title: const Text('About'),
            subtitle: Text(settings.about.label),
            onTap: () => _showVisibilityPicker(
              context,
              'About',
              settings.about,
              notifier.setAbout,
            ),
          ),
          ListTile(
            title: const Text('Groups'),
            subtitle: Text(settings.groups.label),
            onTap: () => _showVisibilityPicker(
              context,
              'Groups',
              settings.groups,
              notifier.setGroups,
            ),
          ),
          SwitchListTile(
            title: const Text('Read receipts'),
            subtitle: const Text(
              'If turned off, you won\'t send or receive read receipts',
            ),
            value: settings.readReceipts,
            onChanged: notifier.setReadReceipts,
          ),

          const Divider(),

          // Security section
          _buildSectionHeader(context, 'Security'),
          SwitchListTile(
            title: const Text('Two-step verification'),
            subtitle: const Text('Add an extra layer of security'),
            value: settings.twoFactorEnabled,
            onChanged: notifier.setTwoFactorEnabled,
          ),
          SwitchListTile(
            title: const Text('Fingerprint lock'),
            subtitle: const Text('Require fingerprint to open Six7'),
            value: settings.fingerprintLock,
            onChanged: notifier.setFingerprintLock,
          ),
          SwitchListTile(
            title: const Text('Screen lock'),
            subtitle: const Text('Lock app after inactivity'),
            value: settings.screenLock,
            onChanged: notifier.setScreenLock,
          ),

          const Divider(),

          // Blocked contacts section
          _buildSectionHeader(context, 'Blocked contacts'),
          ListTile(
            title: const Text('Blocked contacts'),
            subtitle: Text(
              settings.blockedContacts.isEmpty
                  ? 'None'
                  : '${settings.blockedContacts.length} blocked',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showBlockedContacts(context, settings.blockedContacts),
          ),

          const Divider(),

          // Danger zone
          _buildSectionHeader(context, 'Account'),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red.shade700),
            title: Text(
              'Delete my account',
              style: TextStyle(color: Colors.red.shade700),
            ),
            onTap: () => _showDeleteAccountDialog(context),
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

  Future<void> _showVisibilityPicker(
    BuildContext context,
    String title,
    PrivacyVisibility currentValue,
    Future<void> Function(PrivacyVisibility) onChanged,
  ) async {
    final result = await showDialog<PrivacyVisibility>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: RadioGroup<PrivacyVisibility>(
          groupValue: currentValue,
          onChanged: (value) => Navigator.pop(context, value),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: PrivacyVisibility.values.map((visibility) {
              return RadioListTile<PrivacyVisibility>(
                title: Text(visibility.label),
                value: visibility,
              );
            }).toList(),
          ),
        ),
      ),
    );

    if (result != null) {
      await onChanged(result);
    }
  }

  void _showBlockedContacts(BuildContext context, List<String> blocked) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Blocked Contacts',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            if (blocked.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('No blocked contacts'),
                ),
              )
            else
              ...blocked.map(
                (contact) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(contact),
                  trailing: TextButton(
                    onPressed: () {
                      // Unblock logic would go here
                      Navigator.pop(context);
                    },
                    child: const Text('Unblock'),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all associated data. '
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
                  content: Text('Account deletion is not implemented yet'),
                ),
              );
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
