import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Select contact'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement search
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // New contact / New group options
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.person_add, color: Colors.white),
            ),
            title: const Text('Add to vibes'),
            onTap: () => _showAddContactDialog(context, ref),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              child: const Icon(Icons.group_add, color: Colors.white),
            ),
            title: const Text('Spill the tea'),
            onTap: () => context.push('/new-group'),
          ),
          const Divider(),
          
          // Contacts list
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text('Error: $error'),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => ref.invalidate(contactsProvider),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (contacts) {
                if (contacts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.contacts_outlined,
                          size: 80,
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No contacts yet',
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Add a contact to start chatting',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final contact = contacts[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                        child: Text(
                          _getInitials(contact.displayName),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(contact.displayName),
                      subtitle: Text(
                        _truncateId(contact.identity),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      onTap: () => context.push(
                        '/chat/${contact.identity}?name=${Uri.encodeComponent(contact.displayName)}',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddContactDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<({String identity, String name})?>(
      context: context,
      builder: (context) => const _AddContactDialog(),
    );

    if (result != null && context.mounted) {
      final identity = result.identity.trim().toLowerCase();
      final name = result.name.trim();

      // SECURITY: Validate identity is exactly 64 hex characters
      final isValidHex = RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(identity);
      
      if (isValidHex && name.isNotEmpty) {
        try {
          await ref.read(contactsProvider.notifier).addContact(
                identity: identity,
                displayName: name,
              );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added $name to contacts')),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Failed to add contact: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                !isValidHex 
                    ? 'Invalid identity: must be 64 hex characters'
                    : 'Display name cannot be empty',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _getInitials(String name) {
    // Split on whitespace and filter empty parts
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    final initials = '$first$second'.toUpperCase();
    return initials.isNotEmpty ? initials : '?';
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Stateful dialog widget to properly manage TextEditingController lifecycle.
class _AddContactDialog extends StatefulWidget {
  const _AddContactDialog();

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  late final TextEditingController _identityController;
  late final TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _identityController = TextEditingController();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _identityController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Contact'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _identityController,
            decoration: const InputDecoration(
              labelText: 'Korium Identity',
              hintText: 'Paste 64-character hex identity',
            ),
            maxLength: 64,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Display Name',
              hintText: 'Enter a name for this contact',
            ),
            maxLength: 50,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            (identity: _identityController.text, name: _nameController.text),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

