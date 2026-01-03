import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/groups/domain/providers/groups_provider.dart';

/// Screen for creating a new group.
/// Step 1: Select contacts to add to the group.
class NewGroupScreen extends ConsumerStatefulWidget {
  const NewGroupScreen({super.key});

  @override
  ConsumerState<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends ConsumerState<NewGroupScreen> {
  final Set<String> _selectedContactIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('New group'),
            Text(
              _selectedContactIds.isEmpty
                  ? 'Add participants'
                  : '${_selectedContactIds.length} selected',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Selected contacts chips
          if (_selectedContactIds.isNotEmpty)
            _buildSelectedChips(context, contactsAsync),

          // Search field
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
            ),
          ),

          // Contacts list
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
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
                  ],
                ),
              ),
              data: (contacts) => _buildContactsList(context, contacts, theme),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedContactIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _proceedToGroupDetails(context),
              child: const Icon(Icons.arrow_forward),
            )
          : null,
    );
  }

  Widget _buildSelectedChips(
    BuildContext context,
    AsyncValue<List<Contact>> contactsAsync,
  ) {
    final contacts = contactsAsync.value ?? [];

    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedContactIds.length,
        itemBuilder: (context, index) {
          final id = _selectedContactIds.elementAt(index);
          final contact = contacts.where((c) => c.identity == id).firstOrNull;
          if (contact == null) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.2),
                      child: Text(
                        _getInitials(contact.displayName),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      top: -2,
                      child: GestureDetector(
                        onTap: () => _toggleContact(id),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.grey,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 60,
                  child: Text(
                    contact.displayName,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildContactsList(
    BuildContext context,
    List<Contact> contacts,
    ThemeData theme,
  ) {
    // Filter contacts by search query
    final filteredContacts = _searchQuery.isEmpty
        ? contacts
        : contacts.where((c) {
            final query = _searchQuery.toLowerCase();
            return c.displayName.toLowerCase().contains(query) ||
                c.identity.toLowerCase().contains(query);
          }).toList();

    if (filteredContacts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.contacts_outlined,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              contacts.isEmpty ? 'No contacts yet' : 'No matching contacts',
              style: theme.textTheme.titleMedium,
            ),
            if (contacts.isEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.push('/contacts'),
                child: const Text('Add contacts first'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: filteredContacts.length,
      itemBuilder: (context, index) {
        final contact = filteredContacts[index];
        final isSelected = _selectedContactIds.contains(contact.identity);

        return ListTile(
          leading: Stack(
            children: [
              CircleAvatar(
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
              if (isSelected)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          title: Text(contact.displayName),
          subtitle: contact.status != null
              ? Text(
                  contact.status!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text(
                  _truncateId(contact.identity),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
          onTap: () => _toggleContact(contact.identity),
        );
      },
    );
  }

  void _toggleContact(String contactId) {
    if (!mounted) return;
    setState(() {
      if (_selectedContactIds.contains(contactId)) {
        _selectedContactIds.remove(contactId);
      } else {
        _selectedContactIds.add(contactId);
      }
    });
  }

  void _proceedToGroupDetails(BuildContext context) {
    // Navigate to group details screen with selected contacts
    context.push(
      '/new-group/details',
      extra: _selectedContactIds.toList(),
    );
  }

  String _getInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }

  String _truncateId(String id) {
    if (id.length <= 16) return id;
    return '${id.substring(0, 8)}...${id.substring(id.length - 8)}';
  }
}

/// Screen for setting group name and creating the group.
/// Step 2: Configure group details.
class GroupDetailsScreen extends ConsumerStatefulWidget {
  const GroupDetailsScreen({
    super.key,
    required this.selectedContactIds,
  });

  final List<String> selectedContactIds;

  @override
  ConsumerState<GroupDetailsScreen> createState() => _GroupDetailsScreenState();
}

class _GroupDetailsScreenState extends ConsumerState<GroupDetailsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _nameFocusNode = FocusNode();
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _nameFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New group'),
      ),
      body: Column(
        children: [
          // Group name and icon
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _selectGroupIcon,
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.2),
                    child: Icon(
                      Icons.camera_alt,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      TextField(
                        controller: _nameController,
                        focusNode: _nameFocusNode,
                        decoration: const InputDecoration(
                          hintText: 'Group name',
                          border: UnderlineInputBorder(),
                        ),
                        textCapitalization: TextCapitalization.words,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          hintText: 'Group description (optional)',
                          border: InputBorder.none,
                        ),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // Participants header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Participants: ${widget.selectedContactIds.length}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          // Selected participants list
          Expanded(
            child: contactsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Error: $error')),
              data: (contacts) {
                final selectedContacts = contacts
                    .where(
                      (c) => widget.selectedContactIds.contains(c.identity),
                    )
                    .toList();

                return ListView.builder(
                  itemCount: selectedContacts.length,
                  itemBuilder: (context, index) {
                    final contact = selectedContacts[index];
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
                      subtitle: contact.status != null
                          ? Text(contact.status!)
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _nameController.text.trim().isNotEmpty && !_isCreating
            ? _createGroup
            : null,
        backgroundColor: _nameController.text.trim().isNotEmpty && !_isCreating
            ? theme.colorScheme.primary
            : Colors.grey,
        child: _isCreating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.check),
      ),
    );
  }

  void _selectGroupIcon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Group icon selection - Coming soon')),
    );
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a group name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Build members map from contacts
      final contacts = ref.read(contactsProvider).value ?? [];
      final members = <String, String>{};
      for (final id in widget.selectedContactIds) {
        final contact = contacts.where((c) => c.identity == id).firstOrNull;
        if (contact != null) {
          members[id] = contact.displayName;
        }
      }

      // ignore: unused_local_variable - Will be used for group chat navigation
      final group = await ref.read(groupsProvider.notifier).createGroup(
            name: name,
            members: members,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "$name" created')),
        );

        // Navigate to the group chat
        context.go('/group-chat/${group.id}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create group: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  String _getInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : '?';
    }
    final first = parts[0].isNotEmpty ? parts[0][0] : '';
    final second = parts[1].isNotEmpty ? parts[1][0] : '';
    return '$first$second'.toUpperCase();
  }
}
