import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:six7_chat/src/core/constants/app_constants.dart';
import 'package:six7_chat/src/core/storage/models/group_hive.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/models/vibe_hive.dart';
import 'package:path_provider/path_provider.dart';

/// Box names for Hive storage.
abstract class BoxNames {
  static const String messages = 'messages';
  static const String contacts = 'contacts';
  static const String chatPreviews = 'chat_previews';
  static const String settings = 'settings';
  static const String groups = 'groups';
  static const String outbox = 'outbox';
  static const String vibes = 'vibes';
}

/// Provider for the storage service.
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// Service for managing local storage using Hive.
class StorageService {
  bool _isInitialized = false;

  /// Initializes Hive and registers all adapters.
  /// MUST be called before using any storage methods.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Initialize Hive
    if (!kIsWeb) {
      final appDir = await getApplicationDocumentsDirectory();
      Hive.init('${appDir.path}/six7_chat');
    } else {
      await Hive.initFlutter();
    }

    // Register adapters
    _registerAdapters();

    // Open boxes
    await Future.wait([
      Hive.openBox<ChatMessageHive>(BoxNames.messages),
      Hive.openBox<ContactHive>(BoxNames.contacts),
      Hive.openBox<ChatPreviewHive>(BoxNames.chatPreviews),
      Hive.openBox<GroupHive>(BoxNames.groups),
      Hive.openBox<OutboxMessageHive>(BoxNames.outbox),
      Hive.openBox<VibeHive>(BoxNames.vibes),
      Hive.openBox<dynamic>(BoxNames.settings),
    ]);

    _isInitialized = true;
  }

  void _registerAdapters() {
    // Register only if not already registered
    if (!Hive.isAdapterRegistered(HiveTypeIds.messageStatus)) {
      Hive.registerAdapter(MessageStatusHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.messageType)) {
      Hive.registerAdapter(MessageTypeHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.chatMessage)) {
      Hive.registerAdapter(ChatMessageHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.contact)) {
      Hive.registerAdapter(ContactHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(HiveTypeIds.chatPreview)) {
      Hive.registerAdapter(ChatPreviewHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(hiveTypeIdGroup)) {
      Hive.registerAdapter(GroupHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(hiveTypeIdOutboxMessage)) {
      Hive.registerAdapter(OutboxMessageHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(vibeStatusHiveTypeId)) {
      Hive.registerAdapter(VibeStatusHiveAdapter());
    }
    if (!Hive.isAdapterRegistered(vibeHiveTypeId)) {
      Hive.registerAdapter(VibeHiveAdapter());
    }
  }

  // ============ Messages ============

  Box<ChatMessageHive> get _messagesBox =>
      Hive.box<ChatMessageHive>(BoxNames.messages);

  /// Saves a message to storage with LRU eviction.
  /// SECURITY: Enforces maxCachedMessages bound to prevent unbounded growth.
  Future<void> saveMessage(ChatMessageHive message) async {
    await _messagesBox.put(message.id, message);
    
    // Determine peer ID for eviction
    final peerId = message.isFromMe ? message.recipientId : message.senderId;
    await _evictOldMessagesIfNeeded(peerId);
  }

  /// Evicts oldest messages for a peer if count exceeds maxCachedMessages.
  Future<void> _evictOldMessagesIfNeeded(String peerId) async {
    final messages = getMessagesForPeer(peerId);
    if (messages.length > AppConstants.maxCachedMessages) {
      // Messages are sorted newest first, so skip the ones to keep
      final toDelete = messages
          .skip(AppConstants.maxCachedMessages)
          .map((m) => m.id)
          .toList();
      await _messagesBox.deleteAll(toDelete);
    }
  }

  /// Gets all messages for a specific peer, sorted by timestamp descending.
  /// SECURITY: Normalizes identity to lowercase for consistent comparison.
  List<ChatMessageHive> getMessagesForPeer(String peerId) {
    final normalizedPeerId = peerId.toLowerCase();
    final messages = _messagesBox.values.where((msg) {
      return msg.senderId.toLowerCase() == normalizedPeerId || 
             msg.recipientId.toLowerCase() == normalizedPeerId;
    }).toList();

    // Sort by timestamp descending (newest first)
    messages.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return messages;
  }

  /// Gets IDs of unread messages from a specific peer (messages not sent by me).
  /// These are the messages we should send read receipts for.
  List<String> getUnreadMessageIdsFromPeer(String peerId) {
    final normalizedPeerId = peerId.toLowerCase();
    return _messagesBox.values
        .where((msg) =>
            msg.senderId.toLowerCase() == normalizedPeerId &&
            !msg.isFromMe &&
            msg.status != MessageStatusHive.read)
        .map((msg) => msg.id)
        .toList();
  }

  /// Marks all messages from a peer as read in storage.
  Future<void> markMessagesAsReadFromPeer(String peerId) async {
    final normalizedPeerId = peerId.toLowerCase();
    final messages = _messagesBox.values.where((msg) =>
        msg.senderId.toLowerCase() == normalizedPeerId &&
        !msg.isFromMe &&
        msg.status != MessageStatusHive.read);

    for (final msg in messages) {
      msg.status = MessageStatusHive.read;
      await msg.save();
    }
  }

  /// Gets a specific message by ID.
  ChatMessageHive? getMessage(String messageId) {
    return _messagesBox.get(messageId);
  }

  /// Updates a message's status.
  Future<void> updateMessageStatus(
    String messageId,
    MessageStatusHive status,
  ) async {
    final message = _messagesBox.get(messageId);
    if (message != null) {
      message.status = status;
      await message.save();
    }
  }

  /// Deletes a message by ID.
  Future<void> deleteMessage(String messageId) async {
    await _messagesBox.delete(messageId);
  }

  /// Deletes all messages for a specific peer.
  Future<void> deleteMessagesForPeer(String peerId) async {
    final keysToDelete = _messagesBox.values
        .where((msg) => msg.senderId == peerId || msg.recipientId == peerId)
        .map((msg) => msg.id)
        .toList();

    await _messagesBox.deleteAll(keysToDelete);
  }

  /// Gets all messages for a specific group, sorted by timestamp descending.
  List<ChatMessageHive> getMessagesForGroup(String groupId) {
    final messages = _messagesBox.values.where((msg) {
      return msg.groupId == groupId;
    }).toList();

    // Sort by timestamp descending (newest first)
    messages.sort((a, b) => b.timestampMs.compareTo(a.timestampMs));
    return messages;
  }

  /// Evicts oldest messages for a group if count exceeds maxCachedMessages.
  Future<void> evictOldGroupMessagesIfNeeded(String groupId) async {
    final messages = getMessagesForGroup(groupId);
    if (messages.length > AppConstants.maxCachedMessages) {
      // Messages are sorted newest first, so skip the ones to keep
      final toDelete = messages
          .skip(AppConstants.maxCachedMessages)
          .map((m) => m.id)
          .toList();
      await _messagesBox.deleteAll(toDelete);
    }
  }

  /// Deletes all messages for a specific group.
  Future<void> deleteMessagesForGroup(String groupId) async {
    final keysToDelete = _messagesBox.values
        .where((msg) => msg.groupId == groupId)
        .map((msg) => msg.id)
        .toList();

    await _messagesBox.deleteAll(keysToDelete);
  }

  /// Clears all messages and chat previews.
  Future<void> clearAllMessages() async {
    await _messagesBox.clear();
    await _chatPreviewsBox.clear();
  }

  // ============ Contacts ============

  Box<ContactHive> get _contactsBox =>
      Hive.box<ContactHive>(BoxNames.contacts);

  /// Saves a contact to storage with LRU eviction.
  /// SECURITY: Enforces maxCachedContacts bound to prevent unbounded growth.
  Future<void> saveContact(ContactHive contact) async {
    // Check if adding new contact (not updating existing)
    if (!_contactsBox.containsKey(contact.identity)) {
      // Evict oldest contact if at limit
      if (_contactsBox.length >= AppConstants.maxCachedContacts) {
        final contacts = _contactsBox.values.toList()
          ..sort((a, b) => a.addedAtMs.compareTo(b.addedAtMs));
        if (contacts.isNotEmpty) {
          await _contactsBox.delete(contacts.first.identity);
        }
      }
    }
    await _contactsBox.put(contact.identity, contact);
  }

  /// Gets all contacts, sorted by display name.
  List<ContactHive> getAllContacts() {
    final contacts = _contactsBox.values.toList();
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    return contacts;
  }

  /// Gets a specific contact by identity.
  ContactHive? getContact(String identity) {
    return _contactsBox.get(identity);
  }

  /// Deletes a contact by identity.
  Future<void> deleteContact(String identity) async {
    await _contactsBox.delete(identity);
  }

  // ============ Chat Previews ============

  Box<ChatPreviewHive> get _chatPreviewsBox =>
      Hive.box<ChatPreviewHive>(BoxNames.chatPreviews);

  /// Saves a chat preview to storage.
  Future<void> saveChatPreview(ChatPreviewHive preview) async {
    await _chatPreviewsBox.put(preview.peerId, preview);
  }

  /// Gets all chat previews, sorted by pinned first then by timestamp.
  List<ChatPreviewHive> getAllChatPreviews() {
    final previews = _chatPreviewsBox.values.toList();
    previews.sort((a, b) {
      // Pinned first
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      // Then by time descending
      return b.lastMessageTimeMs.compareTo(a.lastMessageTimeMs);
    });
    return previews;
  }

  /// Gets a specific chat preview by peer ID.
  ChatPreviewHive? getChatPreview(String peerId) {
    return _chatPreviewsBox.get(peerId);
  }

  /// Deletes a chat preview by peer ID.
  Future<void> deleteChatPreview(String peerId) async {
    await _chatPreviewsBox.delete(peerId);
  }

  /// Marks all messages from a peer as read.
  Future<void> markChatAsRead(String peerId) async {
    final preview = _chatPreviewsBox.get(peerId);
    if (preview != null && preview.unreadCount > 0) {
      preview.unreadCount = 0;
      await preview.save();
    }
  }

  // ============ Settings ============

  Box<dynamic> get _settingsBox => Hive.box<dynamic>(BoxNames.settings);

  /// Gets a setting value.
  T? getSetting<T>(String key) {
    return _settingsBox.get(key) as T?;
  }

  /// Sets a setting value.
  Future<void> setSetting<T>(String key, T value) async {
    await _settingsBox.put(key, value);
  }

  /// Deletes a setting.
  Future<void> deleteSetting(String key) async {
    await _settingsBox.delete(key);
  }

  // ============ Groups ============

  Box<GroupHive> get _groupsBox => Hive.box<GroupHive>(BoxNames.groups);

  /// Gets all groups, sorted by creation date descending.
  List<GroupHive> getAllGroups() {
    final groups = _groupsBox.values.toList();
    groups.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    return groups;
  }

  /// Gets a group by ID.
  GroupHive? getGroup(String id) {
    return _groupsBox.get(id);
  }

  /// Saves a group to storage.
  Future<void> saveGroup(GroupHive group) async {
    await _groupsBox.put(group.id, group);
  }

  /// Deletes a group from storage.
  Future<void> deleteGroup(String id) async {
    await _groupsBox.delete(id);
  }

  // ============ Outbox ============

  Box<OutboxMessageHive> get _outboxBox =>
      Hive.box<OutboxMessageHive>(BoxNames.outbox);

  /// Adds a message to the outbox for retry.
  /// SECURITY: Enforces per-peer limit to prevent unbounded growth.
  Future<void> addToOutbox(OutboxMessageHive message) async {
    // Check per-peer limit
    final peerMessages = getOutboxForPeer(message.recipientId);
    if (peerMessages.length >= maxOutboxMessagesPerPeer) {
      // Evict oldest message for this peer
      final oldest = peerMessages.last;
      await _outboxBox.delete(oldest.messageId);
    }
    
    await _outboxBox.put(message.messageId, message);
  }

  /// Gets all outbox messages for a specific peer.
  List<OutboxMessageHive> getOutboxForPeer(String recipientId) {
    return _outboxBox.values
        .where((msg) => msg.recipientId == recipientId)
        .toList()
      ..sort((a, b) => a.createdAtMs.compareTo(b.createdAtMs));
  }

  /// Gets all outbox messages ready for retry (across all peers).
  List<OutboxMessageHive> getOutboxMessagesReadyForRetry() {
    return _outboxBox.values
        .where((msg) => msg.isReadyForRetry)
        .toList()
      ..sort((a, b) => a.nextRetryAtMs.compareTo(b.nextRetryAtMs));
  }

  /// Gets all outbox messages (for UI display).
  List<OutboxMessageHive> getAllOutboxMessages() {
    return _outboxBox.values.toList()
      ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
  }

  /// Gets count of pending outbox messages.
  int getOutboxCount() {
    return _outboxBox.length;
  }

  /// Gets count of pending outbox messages for a specific peer.
  int getOutboxCountForPeer(String recipientId) {
    return _outboxBox.values
        .where((msg) => msg.recipientId == recipientId)
        .length;
  }

  /// Removes a message from the outbox (after successful delivery).
  Future<void> removeFromOutbox(String messageId) async {
    await _outboxBox.delete(messageId);
  }

  /// Updates an outbox message (after failed retry).
  Future<void> updateOutboxMessage(OutboxMessageHive message) async {
    await message.save();
  }

  /// Clears all permanently failed messages from outbox.
  Future<void> clearPermanentlyFailedOutbox() async {
    final toDelete = _outboxBox.values
        .where((msg) => msg.isPermanentlyFailed)
        .map((msg) => msg.messageId)
        .toList();
    await _outboxBox.deleteAll(toDelete);
  }

  /// Clears outbox for a specific peer.
  Future<void> clearOutboxForPeer(String recipientId) async {
    final toDelete = _outboxBox.values
        .where((msg) => msg.recipientId == recipientId)
        .map((msg) => msg.messageId)
        .toList();
    await _outboxBox.deleteAll(toDelete);
  }

  // ============ Vibes ============

  Box<VibeHive> get _vibesBox => Hive.box<VibeHive>(BoxNames.vibes);

  /// Gets all vibes.
  List<VibeHive> getAllVibes() {
    return _vibesBox.values.toList();
  }

  /// Gets a vibe by contact ID.
  VibeHive? getVibeByContactId(String contactId) {
    return _vibesBox.values
        .where((v) => v.contactId == contactId)
        .firstOrNull;
  }

  /// Gets all matched vibes.
  List<VibeHive> getMatchedVibes() {
    return _vibesBox.values
        .where((v) => v.status == VibeStatusHive.matched)
        .toList();
  }

  /// Gets all pending vibes (we sent, waiting for response).
  List<VibeHive> getPendingVibes() {
    return _vibesBox.values
        .where((v) => v.status == VibeStatusHive.pending)
        .toList();
  }

  /// Gets all received vibes (they sent, we haven't responded).
  List<VibeHive> getReceivedVibes() {
    return _vibesBox.values
        .where((v) => v.status == VibeStatusHive.received)
        .toList();
  }

  /// Saves a vibe.
  Future<void> saveVibe(VibeHive vibe) async {
    await _vibesBox.put(vibe.id, vibe);
  }

  /// Deletes a vibe by ID.
  Future<void> deleteVibe(String vibeId) async {
    await _vibesBox.delete(vibeId);
  }

  /// Clears all vibes.
  Future<void> clearAllVibes() async {
    await _vibesBox.clear();
  }

  // ============ Cleanup ============

  /// Clears all stored data.
  Future<void> clearAll() async {
    await Future.wait([
      _messagesBox.clear(),
      _contactsBox.clear(),
      _chatPreviewsBox.clear(),
      _groupsBox.clear(),
      _outboxBox.clear(),
      _vibesBox.clear(),
      _settingsBox.clear(),
    ]);
  }

  /// Closes all boxes. Call when app is closing.
  Future<void> close() async {
    await Hive.close();
    _isInitialized = false;
  }
}
