import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';

/// Screen for editing the user's profile.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final nodeState = ref.watch(koriumNodeStateProvider);

    String identity = 'Not connected';
    if (nodeState is KoriumNodeConnected) {
      identity = nodeState.identity;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(userProfileProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (profile) => ListView(
          children: [
            // Avatar section
            _buildAvatarSection(context, profile.avatarPath, theme),

            const Divider(),

            // Name section
            ListTile(
              leading: Icon(Icons.person, color: theme.colorScheme.primary),
              title: const Text('Name'),
              subtitle: Text(profile.displayName),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _editName(context, profile.displayName),
            ),

            const Divider(indent: 72),

            // Status section
            ListTile(
              leading: Icon(Icons.info_outline, color: theme.colorScheme.primary),
              title: const Text('About'),
              subtitle: Text(profile.status ?? 'Add a status...'),
              trailing: const Icon(Icons.edit, size: 20),
              onTap: () => _editStatus(context, profile.status),
            ),

            const Divider(indent: 72),

            // Identity section (read-only)
            ListTile(
              leading: Icon(Icons.fingerprint, color: theme.colorScheme.primary),
              title: const Text('Identity'),
              subtitle: Text(
                _formatIdentity(identity),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.qr_code),
                onPressed: () => context.push('/qr-display'),
                tooltip: 'Show QR Code',
              ),
            ),

            const Divider(),

            // Info section
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Your name and status are shared with contacts. '
                        'Your identity is your cryptographic key.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection(
    BuildContext context,
    String? avatarPath,
    ThemeData theme,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Stack(
          children: [
            GestureDetector(
              onTap: _showAvatarOptions,
              child: CircleAvatar(
                radius: 64,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                backgroundImage:
                    avatarPath != null ? FileImage(File(avatarPath)) : null,
                child: avatarPath == null
                    ? Icon(
                        Icons.person,
                        size: 64,
                        color: theme.colorScheme.primary,
                      )
                    : null,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _showAvatarOptions,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAvatarOptions() {
    final profile = ref.read(userProfileProvider).value;
    final hasAvatar = profile?.avatarPath != null;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Remove photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _removeAvatar();
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );

      if (pickedFile == null) return;

      // Copy to app documents directory for persistence
      final appDir = await getApplicationDocumentsDirectory();
      final avatarDir = Directory('${appDir.path}/avatars');
      if (!await avatarDir.exists()) {
        await avatarDir.create(recursive: true);
      }

      final fileName = 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final newPath = '${avatarDir.path}/$fileName';
      await File(pickedFile.path).copy(newPath);

      // Delete old avatar if exists
      final oldAvatarPath =
          ref.read(userProfileProvider).value?.avatarPath;
      if (oldAvatarPath != null) {
        final oldFile = File(oldAvatarPath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      }

      await ref.read(userProfileProvider.notifier).updateAvatar(newPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeAvatar() async {
    try {
      final avatarPath =
          ref.read(userProfileProvider).value?.avatarPath;
      if (avatarPath != null) {
        final file = File(avatarPath);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await ref.read(userProfileProvider.notifier).clearAvatar();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile photo removed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove photo: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editName(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          maxLength: 50,
          decoration: const InputDecoration(
            hintText: 'Your name',
            counterText: '',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty && context.mounted) {
      try {
        await ref.read(userProfileProvider.notifier).updateDisplayName(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Name updated')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update name: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editStatus(BuildContext context, String? currentStatus) async {
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _StatusEditSheet(currentStatus: currentStatus),
    );

    if (result != null && context.mounted) {
      try {
        await ref.read(userProfileProvider.notifier).updateStatus(result);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Status updated')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update status: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatIdentity(String identity) {
    if (identity.length <= 20) return identity;
    return '${identity.substring(0, 16)}...${identity.substring(identity.length - 16)}';
  }
}

/// Bottom sheet for editing status with predefined options.
class _StatusEditSheet extends StatefulWidget {
  const _StatusEditSheet({this.currentStatus});

  final String? currentStatus;

  @override
  State<_StatusEditSheet> createState() => _StatusEditSheetState();
}

class _StatusEditSheetState extends State<_StatusEditSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentStatus);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Title and custom input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'About',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 140,
                    decoration: InputDecoration(
                      hintText: 'Enter your status...',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check),
                        onPressed: () => Navigator.pop(context, _controller.text),
                      ),
                    ),
                    onSubmitted: (value) => Navigator.pop(context, value),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Predefined statuses
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quick select',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: predefinedStatuses.length,
                itemBuilder: (context, index) {
                  final status = predefinedStatuses[index];
                  final isSelected = status == widget.currentStatus;

                  return ListTile(
                    title: Text(status),
                    trailing: isSelected
                        ? Icon(Icons.check, color: theme.colorScheme.primary)
                        : null,
                    onTap: () => Navigator.pop(context, status),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
