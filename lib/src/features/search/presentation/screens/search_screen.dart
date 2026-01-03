import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/home/domain/models/chat_preview.dart';
import 'package:six7_chat/src/features/search/domain/providers/search_provider.dart';

/// Search screen for finding chats and contacts.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  /// Debounce duration for search input.
  static const _debounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      ref.read(searchQueryProvider.notifier).setQuery(value);
    });
  }

  void _onSearchSubmitted(String value) {
    _debounceTimer?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery(value);
    if (value.trim().isNotEmpty) {
      ref.read(recentSearchesProvider.notifier).addSearch(value);
    }
  }

  void _clearSearch() {
    _searchController.clear();
    ref.read(searchQueryProvider.notifier).setQuery('');
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchResults = ref.watch(searchResultsProvider);
    final recentSearches = ref.watch(recentSearchesProvider);
    final query = ref.watch(searchQueryProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          onSubmitted: _onSearchSubmitted,
          decoration: InputDecoration(
            hintText: 'Search chats and contacts...',
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: _clearSearch,
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
        ),
      ),
      body: query.isEmpty
          ? _buildRecentSearches(context, recentSearches, theme)
          : searchResults.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text('Error: $error'),
                  ],
                ),
              ),
              data: (results) => _buildSearchResults(context, results, theme),
            ),
    );
  }

  Widget _buildRecentSearches(
    BuildContext context,
    List<String> recentSearches,
    ThemeData theme,
  ) {
    if (recentSearches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for chats and contacts',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent searches',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: Colors.grey,
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(recentSearchesProvider.notifier).clearAll();
                },
                child: const Text('Clear all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: recentSearches.length,
            itemBuilder: (context, index) {
              final search = recentSearches[index];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(search),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () {
                    ref.read(recentSearchesProvider.notifier).removeSearch(search);
                  },
                ),
                onTap: () {
                  _searchController.text = search;
                  ref.read(searchQueryProvider.notifier).setQuery(search);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults(
    BuildContext context,
    SearchResults results,
    ThemeData theme,
  ) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a different search term',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        // Chats section
        if (results.chats.isNotEmpty) ...[
          _buildSectionHeader(context, 'Chats', results.chats.length, theme),
          ...results.chats.map((chat) => _buildChatTile(context, chat, theme)),
        ],

        // Contacts section
        if (results.contacts.isNotEmpty) ...[
          _buildSectionHeader(
            context,
            'Contacts',
            results.contacts.length,
            theme,
          ),
          ...results.contacts
              .map((contact) => _buildContactTile(context, contact, theme)),
        ],
      ],
    );
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    int count,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        '$title ($count)',
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildChatTile(
    BuildContext context,
    ChatPreview chat,
    ThemeData theme,
  ) {
    final query = ref.read(searchQueryProvider).toLowerCase();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
        child: Text(
          _getInitials(chat.peerName),
          style: TextStyle(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: _highlightText(chat.peerName, query, theme),
      subtitle: _highlightText(chat.lastMessage, query, theme, isSubtitle: true),
      trailing: Text(
        _formatTime(chat.lastMessageTime),
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
      ),
      onTap: () {
        ref.read(recentSearchesProvider.notifier).addSearch(query);
        context.push(
          '/chat/${chat.peerId}?name=${Uri.encodeComponent(chat.peerName)}',
        );
      },
    );
  }

  Widget _buildContactTile(
    BuildContext context,
    Contact contact,
    ThemeData theme,
  ) {
    final query = ref.read(searchQueryProvider).toLowerCase();

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.2),
        child: Text(
          _getInitials(contact.displayName),
          style: TextStyle(
            color: theme.colorScheme.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: _highlightText(contact.displayName, query, theme),
      subtitle: contact.status != null
          ? _highlightText(contact.status!, query, theme, isSubtitle: true)
          : Text(
              _truncateId(contact.identity),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
      onTap: () {
        ref.read(recentSearchesProvider.notifier).addSearch(query);
        context.push(
          '/chat/${contact.identity}?name=${Uri.encodeComponent(contact.displayName)}',
        );
      },
    );
  }

  /// Highlights matching text portions in the search results.
  Widget _highlightText(
    String text,
    String query,
    ThemeData theme, {
    bool isSubtitle = false,
  }) {
    if (query.isEmpty) {
      return Text(
        text,
        style: isSubtitle ? const TextStyle(color: Colors.grey) : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex == -1) {
      return Text(
        text,
        style: isSubtitle ? const TextStyle(color: Colors.grey) : null,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    final before = text.substring(0, matchIndex);
    final match = text.substring(matchIndex, matchIndex + query.length);
    final after = text.substring(matchIndex + query.length);

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: DefaultTextStyle.of(context).style.copyWith(
              color: isSubtitle ? Colors.grey : null,
            ),
        children: [
          TextSpan(text: before),
          TextSpan(
            text: match,
            style: TextStyle(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(text: after),
        ],
      ),
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

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);

    if (difference.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[time.weekday - 1];
    } else {
      return '${time.day}/${time.month}/${time.year}';
    }
  }
}
