import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:six7_chat/src/core/auth/lock_service.dart';
import 'package:six7_chat/src/core/location/location_provider.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';
import 'package:six7_chat/src/features/vibes/domain/providers/discovery_provider.dart';

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
          _FingerprintLockTile(
            settings: settings,
            notifier: notifier,
          ),
          SwitchListTile(
            title: const Text('Screen lock'),
            subtitle: const Text('Lock app after 30 seconds in background'),
            value: settings.screenLock,
            onChanged: notifier.setScreenLock,
          ),

          const Divider(),

          // Discovery section
          _buildSectionHeader(context, 'Discovery'),
          _DiscoverySection(),

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
            onTap: () => _showBlockedContacts(context, ref, settings.blockedContacts),
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

  void _showBlockedContacts(BuildContext context, WidgetRef ref, List<String> blocked) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => Consumer(
        builder: (sheetContext, sheetRef, child) {
          // Watch contacts provider to get updated blocked list
          final contacts = sheetRef.watch(contactsProvider).value ?? [];
          final currentBlocked = contacts
              .where((c) => c.isBlocked)
              .map((c) => c.identity)
              .toList();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocked Contacts',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (currentBlocked.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: Text('No blocked contacts'),
                    ),
                  )
                else
                  ...currentBlocked.map(
                    (contactId) {
                      final contact = contacts.firstWhere(
                        (c) => c.identity == contactId,
                      );
                      return ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(contact.displayName.isNotEmpty ? contact.displayName : _truncateId(contactId)),
                        subtitle: Text(_truncateId(contactId)),
                        trailing: TextButton(
                          onPressed: () async {
                            await sheetRef.read(contactsProvider.notifier).toggleBlock(contactId);
                            if (sheetContext.mounted) {
                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(content: Text('${contact.displayName.isNotEmpty ? contact.displayName : "Contact"} unblocked')),
                              );
                            }
                          },
                          child: const Text('Unblock'),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}

/// Discovery settings section.
class _DiscoverySection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnabled = ref.watch(discoveryEnabledProvider);
    final userProfileAsync = ref.watch(userProfileProvider);
    final location = ref.watch(locationProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        SwitchListTile(
          title: const Text('Enable discovery'),
          subtitle: const Text(
            'Let nearby people find you and swipe on your profile',
          ),
          value: isEnabled,
          onChanged: (value) async {
            if (value) {
              // Request location permission when enabling
              final granted = await ref.read(locationProvider.notifier).requestPermission();
              if (!granted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Location permission is required for discovery'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              // Update location
              await ref.read(locationProvider.notifier).updateLocation();
            }
            await ref.read(discoveryEnabledProvider.notifier).setEnabled(value);
          },
        ),

        // Location status
        if (isEnabled) ...[
          ListTile(
            leading: Icon(
              location.hasPermission ? Icons.location_on : Icons.location_off,
              color: location.hasPermission 
                  ? theme.colorScheme.primary 
                  : theme.colorScheme.error,
            ),
            title: const Text('Location'),
            subtitle: Text(
              location.hasPermission
                  ? (location.geohash != null 
                      ? 'Active • Will show to users within ~100km' 
                      : 'Waiting for location...')
                  : 'Permission required',
            ),
            trailing: location.hasPermission
                ? null
                : TextButton(
                    onPressed: () async {
                      await ref.read(locationProvider.notifier).requestPermission();
                    },
                    child: const Text('Enable'),
                  ),
          ),

          // Profile preview
          const Divider(indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Your Discovery Profile',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          userProfileAsync.when(
            loading: () => const ListTile(
              leading: CircleAvatar(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('Loading profile...'),
            ),
            error: (_, __) => ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.errorContainer,
                child: Icon(Icons.error, color: theme.colorScheme.error),
              ),
              title: const Text('Error loading profile'),
            ),
            data: (profile) => Column(
              children: [
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      profile.displayName.isNotEmpty 
                          ? profile.displayName[0].toUpperCase() 
                          : '?',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    profile.displayName.isNotEmpty 
                        ? profile.displayName 
                        : 'No name set',
                    style: TextStyle(
                      fontStyle: profile.displayName.isEmpty ? FontStyle.italic : null,
                      color: profile.displayName.isEmpty 
                          ? theme.colorScheme.onSurfaceVariant 
                          : null,
                    ),
                  ),
                  subtitle: profile.status?.isNotEmpty == true
                      ? Text(profile.status!)
                      : Text(
                          'No status',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to profile settings
                    Navigator.of(context).pushNamed('/settings/profile');
                  },
                ),

                // Warning if profile incomplete
                if (profile.displayName.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Set a display name in your profile to be discoverable',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Fingerprint lock tile that checks biometrics availability.
class _FingerprintLockTile extends ConsumerWidget {
  const _FingerprintLockTile({
    required this.settings,
    required this.notifier,
  });

  final AccountSettings settings;
  final AccountSettingsNotifier notifier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final biometricsAvailable = ref.watch(biometricsAvailableProvider);
    final availableBiometrics = ref.watch(availableBiometricsProvider);

    return biometricsAvailable.when(
      data: (available) {
        if (!available) {
          // Biometrics not available on this device
          return const ListTile(
            title: Text('Biometric lock'),
            subtitle: Text('Not available on this device'),
            leading: Icon(Icons.fingerprint, color: Colors.grey),
            enabled: false,
          );
        }

        // Determine biometric type for display
        final biometricLabel = availableBiometrics.maybeWhen(
          data: (types) {
            if (types.contains(BiometricType.face)) {
              return 'Face ID';
            } else if (types.contains(BiometricType.fingerprint)) {
              return 'fingerprint';
            }
            return 'biometrics';
          },
          orElse: () => 'biometrics',
        );

        return SwitchListTile(
          title: const Text('Biometric lock'),
          subtitle: Text('Require $biometricLabel to open Six7'),
          secondary: Icon(
            availableBiometrics.maybeWhen(
              data: (types) =>
                  types.contains(BiometricType.face) ? Icons.face : Icons.fingerprint,
              orElse: () => Icons.fingerprint,
            ),
          ),
          value: settings.fingerprintLock,
          onChanged: (value) async {
            if (value) {
              // Test biometric auth before enabling
              final lockService = ref.read(lockServiceProvider);
              final success = await lockService.authenticateWithBiometrics();
              if (success) {
                await notifier.setFingerprintLock(true);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Authentication failed. Biometric lock not enabled.'),
                    ),
                  );
                }
              }
            } else {
              await notifier.setFingerprintLock(false);
            }
          },
        );
      },
      loading: () => const ListTile(
        title: Text('Biometric lock'),
        subtitle: Text('Checking availability...'),
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => const ListTile(
        title: Text('Biometric lock'),
        subtitle: Text('Error checking availability'),
        leading: Icon(Icons.error_outline, color: Colors.red),
        enabled: false,
      ),
    );
  }
}
