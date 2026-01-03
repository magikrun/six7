import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/home/domain/models/chat_preview.dart';
import 'package:six7_chat/src/features/home/domain/providers/chat_list_provider.dart';

/// Search query notifier for Riverpod 3.
class SearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';
  
  void setQuery(String query) {
    state = query;
  }
}

/// Search query state provider.
final searchQueryProvider = NotifierProvider<SearchQueryNotifier, String>(
  SearchQueryNotifier.new,
);

/// Combined search results containing both chats and contacts.
class SearchResults {
  const SearchResults({
    required this.chats,
    required this.contacts,
    required this.query,
  });

  final List<ChatPreview> chats;
  final List<Contact> contacts;
  final String query;

  bool get isEmpty => chats.isEmpty && contacts.isEmpty;
  bool get hasResults => !isEmpty;
  int get totalCount => chats.length + contacts.length;
}

/// Provider for search results.
/// Filters chats and contacts based on the current search query.
final searchResultsProvider = Provider<AsyncValue<SearchResults>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();

  // If query is empty, return empty results
  if (query.isEmpty) {
    return const AsyncData(SearchResults(
      chats: [],
      contacts: [],
      query: '',
    ),);
  }

  final chatsAsync = ref.watch(chatListProvider);
  final contactsAsync = ref.watch(contactsProvider);

  // Combine loading states
  if (chatsAsync.isLoading || contactsAsync.isLoading) {
    return const AsyncLoading();
  }

  // Handle errors
  if (chatsAsync.hasError) {
    return AsyncError(chatsAsync.error!, chatsAsync.stackTrace!);
  }
  if (contactsAsync.hasError) {
    return AsyncError(contactsAsync.error!, contactsAsync.stackTrace!);
  }

  final chats = chatsAsync.value ?? [];
  final contacts = contactsAsync.value ?? [];

  // Filter chats by peer name or last message content
  final filteredChats = chats.where((chat) {
    return chat.peerName.toLowerCase().contains(query) ||
        chat.lastMessage.toLowerCase().contains(query);
  }).toList();

  // Filter contacts by display name, identity, or status
  final filteredContacts = contacts.where((contact) {
    return contact.displayName.toLowerCase().contains(query) ||
        contact.identity.toLowerCase().contains(query) ||
        (contact.status?.toLowerCase().contains(query) ?? false);
  }).toList();

  // Remove contacts that already appear in filtered chats to avoid duplicates
  final chatPeerIds = filteredChats.map((c) => c.peerId.toLowerCase()).toSet();
  final uniqueContacts = filteredContacts
      .where((c) => !chatPeerIds.contains(c.identity.toLowerCase()))
      .toList();

  return AsyncData(SearchResults(
    chats: filteredChats,
    contacts: uniqueContacts,
    query: query,
  ),);
});

/// Provider for recent searches.
/// Stores up to 10 recent search queries, persisted to local storage.
final recentSearchesProvider =
    NotifierProvider<RecentSearchesNotifier, List<String>>(
  RecentSearchesNotifier.new,
);

class RecentSearchesNotifier extends Notifier<List<String>> {
  /// Storage key for recent searches.
  static const String _storageKey = 'recent_searches';

  /// Maximum number of recent searches to keep.
  static const int _maxRecent = 10;

  late final StorageService _storage;

  @override
  List<String> build() {
    _storage = ref.read(storageServiceProvider);
    // Load persisted searches on initialization
    return _loadFromStorage();
  }

  List<String> _loadFromStorage() {
    final stored = _storage.getSetting<List<dynamic>>(_storageKey);
    if (stored == null) return [];
    // SAFETY: Cast each element individually to handle Hive type conversion
    return stored.map((e) => e.toString()).take(_maxRecent).toList();
  }

  Future<void> _saveToStorage() async {
    await _storage.setSetting<List<String>>(_storageKey, state);
  }

  void addSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    // Remove if already exists (will be re-added at top)
    final updated = state.where((s) => s != trimmed).toList();

    // Add to beginning and limit size
    state = [trimmed, ...updated].take(_maxRecent).toList();
    _saveToStorage();
  }

  void removeSearch(String query) {
    state = state.where((s) => s != query).toList();
    _saveToStorage();
  }

  void clearAll() {
    state = [];
    _saveToStorage();
  }
}
