import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';

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
            onPressed: () => _showContactSearch(context, ref),
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
                        backgroundImage: contact.avatarUrl != null
                            ? FileImage(File(contact.avatarUrl!))
                            : null,
                        child: contact.avatarUrl == null
                            ? Text(
                                _getInitials(contact.displayName),
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(contact.displayName),
                      subtitle: Text(
                        _truncateId(contact.identity),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                      trailing: contact.isBlocked
                          ? Icon(Icons.block, color: Colors.red.shade300, size: 20)
                          : null,
                      onTap: () => context.push(
                        '/chat/${contact.identity}?name=${Uri.encodeComponent(contact.displayName)}',
                      ),
                      onLongPress: () => _showContactOptions(context, ref, contact),
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
    final result = await showDialog<({String identity, String name, bool startChat})?>(
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
          // Add contact locally
          await ref.read(contactsProvider.notifier).addContact(
                identity: identity,
                displayName: name,
              );
          
          // Send contact request to notify the peer with our display name
          try {
            final profile = ref.read(userProfileProvider).value;
            final myName = profile?.displayName ?? 'Unknown';
            await ref.read(contactsProvider.notifier).sendContactRequest(
                  identity: identity,
                  myDisplayName: myName,
                );
          } catch (e) {
            // Contact request failed but contact was added locally - that's OK
            debugPrint('[Contacts] Contact request send failed: $e');
          }
          
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added $name to contacts')),
            );
            
            // Navigate to chat if requested
            if (result.startChat) {
              context.push('/chat/$identity?name=${Uri.encodeComponent(name)}');
            }
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
  bool _startChat = true;

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
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _startChat,
            onChanged: (value) => setState(() => _startChat = value ?? true),
            title: const Text('Start chat'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
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
            (
              identity: _identityController.text,
              name: _nameController.text,
              startChat: _startChat,
            ),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// Shows options for a contact (edit, block, delete).
void _showContactOptions(BuildContext context, WidgetRef ref, Contact contact) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('Send message'),
            onTap: () {
              Navigator.pop(sheetContext);
              context.push(
                '/chat/${contact.identity}?name=${Uri.encodeComponent(contact.displayName)}',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('Edit name'),
            onTap: () {
              Navigator.pop(sheetContext);
              _showEditNameDialog(context, ref, contact);
            },
          ),
          ListTile(
            leading: Icon(
              contact.isBlocked ? Icons.check_circle : Icons.block,
              color: contact.isBlocked ? Colors.green : Colors.orange,
            ),
            title: Text(contact.isBlocked ? 'Unblock' : 'Block'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await ref.read(contactsProvider.notifier).toggleBlock(contact.identity);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(contact.isBlocked 
                      ? '${contact.displayName} unblocked'
                      : '${contact.displayName} blocked'),
                  ),
                );
              }
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('Delete contact', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(sheetContext);
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Delete Contact'),
                  content: Text('Delete ${contact.displayName} from your contacts?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              
              if (confirmed == true && context.mounted) {
                await ref.read(contactsProvider.notifier).deleteContact(contact.identity);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${contact.displayName} deleted')),
                  );
                }
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// Shows dialog to edit contact name.
void _showEditNameDialog(BuildContext context, WidgetRef ref, Contact contact) {
  final controller = TextEditingController(text: contact.displayName);
  
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit Name'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Display Name',
          border: OutlineInputBorder(),
        ),
        autofocus: true,
        maxLength: 50,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            final newName = controller.text.trim();
            if (newName.isNotEmpty && newName != contact.displayName) {
              await ref.read(contactsProvider.notifier).updateContactName(
                contact.identity,
                newName,
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact name updated')),
                );
              }
            } else {
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Shows a search dialog to filter contacts.
void _showContactSearch(BuildContext context, WidgetRef ref) {
  showSearch(
    context: context,
    delegate: _ContactSearchDelegate(ref),
  );
}

/// Search delegate for filtering contacts.
class _ContactSearchDelegate extends SearchDelegate<Contact?> {
  _ContactSearchDelegate(this.ref);

  final WidgetRef ref;

  @override
  String get searchFieldLabel => 'Search contacts';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final contacts = ref.read(contactsProvider).value ?? [];
    final theme = Theme.of(context);
    
    final filteredContacts = query.isEmpty
        ? contacts
        : contacts.where((contact) {
            final queryLower = query.toLowerCase();
            return contact.displayName.toLowerCase().contains(queryLower) ||
                   contact.identity.toLowerCase().contains(queryLower);
          }).toList();

    if (filteredContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              query.isEmpty ? 'No contacts yet' : 'No contacts found',
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = filteredContacts[index];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
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
          onTap: () {
            close(context, contact);
            context.push(
              '/chat/${contact.identity}?name=${Uri.encodeComponent(contact.displayName)}',
            );
          },
        );
      },
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  String _truncateId(String id) {
    if (id.length <= 12) return id;
    return '${id.substring(0, 6)}...${id.substring(id.length - 4)}';
  }
}

