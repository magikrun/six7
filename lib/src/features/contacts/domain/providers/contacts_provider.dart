import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;
import 'package:uuid/uuid.dart';

final contactsProvider =
    AsyncNotifierProvider<ContactsNotifier, List<Contact>>(
  ContactsNotifier.new,
);

class ContactsNotifier extends AsyncNotifier<List<Contact>> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  Future<List<Contact>> build() async {
    return _loadContacts();
  }

  Future<List<Contact>> _loadContacts() async {
    final hiveContacts = _storage.getAllContacts();
    return hiveContacts.map(_hiveToModel).toList();
  }

  Contact _hiveToModel(ContactHive hive) {
    return Contact(
      identity: hive.identity,
      displayName: hive.displayName,
      avatarUrl: hive.avatarUrl,
      status: hive.status,
      addedAt: DateTime.fromMillisecondsSinceEpoch(hive.addedAtMs),
      isFavorite: hive.isFavorite,
      isBlocked: hive.isBlocked,
    );
  }

  ContactHive _modelToHive(Contact contact) {
    return ContactHive(
      identity: contact.identity,
      displayName: contact.displayName,
      avatarUrl: contact.avatarUrl,
      status: contact.status,
      addedAtMs: contact.addedAt.millisecondsSinceEpoch,
      isFavorite: contact.isFavorite,
      isBlocked: contact.isBlocked,
    );
  }

  Future<void> addContact({
    required String identity,
    required String displayName,
    String? avatarUrl,
  }) async {
    // SECURITY: Validate identity format before storing
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(identity)) {
      throw ArgumentError(
        'Invalid identity format: must be 64 hexadecimal characters',
      );
    }

    // SECURITY: Normalize identity to lowercase for consistent comparison
    final normalizedIdentity = identity.toLowerCase();

    // Check if contact already exists in current state
    final currentContacts = state.value ?? [];
    final existingIndex = currentContacts.indexWhere(
      (c) => c.identity.toLowerCase() == normalizedIdentity,
    );

    if (existingIndex >= 0) {
      // Contact already exists - update the display name instead
      final existing = currentContacts[existingIndex];
      final updated = existing.copyWith(displayName: displayName);
      await _storage.saveContact(_modelToHive(updated));

      final updatedList = [...currentContacts];
      updatedList[existingIndex] = updated;
      state = AsyncData(updatedList);

      // ignore: avoid_print
      print('[Contacts] Updated existing contact: ${normalizedIdentity.substring(0, 16)}...');
      return;
    }

    final newContact = Contact(
      identity: normalizedIdentity,
      displayName: displayName,
      avatarUrl: avatarUrl,
      addedAt: DateTime.now(),
    );

    // Persist to storage
    await _storage.saveContact(_modelToHive(newContact));

    state = AsyncData([newContact, ...currentContacts]);

    // ignore: avoid_print
    print('[Contacts] Added contact: ${normalizedIdentity.substring(0, 16)}...');
  }

  /// Sends a contact request to a peer.
  /// This notifies them that we want to add them as a contact.
  Future<void> sendContactRequest({
    required String identity,
    required String myDisplayName,
  }) async {
    // SECURITY: Validate identity format
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(identity)) {
      throw ArgumentError('Invalid identity format');
    }

    final nodeAsync = ref.read(koriumNodeProvider);
    await nodeAsync.when(
      loading: () async {
        throw const korium.KoriumException('Network not ready');
      },
      error: (e, _) async {
        throw korium.KoriumException('Network error: $e');
      },
      data: (node) async {
        final messageId = const Uuid().v4();
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // Send contact request message
        final requestMessage = korium.ChatMessage(
          id: messageId,
          senderId: node.identity,
          recipientId: identity.toLowerCase(),
          text: myDisplayName, // Include our display name in the request
          messageType: korium.MessageType.contactRequest,
          timestampMs: now,
          status: korium.MessageStatus.pending,
          isFromMe: true,
        );
        
        await node.sendMessage(
          peerId: identity.toLowerCase(),
          message: requestMessage,
        );
        
        // ignore: avoid_print
        print('[Contacts] Sent contact request to ${identity.substring(0, 16)}...');
      },
    );
  }

  /// Accepts a contact request and notifies the requester.
  Future<void> acceptContactRequest({
    required String identity,
    required String displayName,
    required String myDisplayName,
  }) async {
    // Add them as contact first
    await addContact(identity: identity, displayName: displayName);
    
    // Send acceptance message back
    final nodeAsync = ref.read(koriumNodeProvider);
    await nodeAsync.when(
      loading: () async {},
      error: (e, s) async {},
      data: (node) async {
        final messageId = const Uuid().v4();
        final now = DateTime.now().millisecondsSinceEpoch;
        
        final acceptMessage = korium.ChatMessage(
          id: messageId,
          senderId: node.identity,
          recipientId: identity.toLowerCase(),
          text: myDisplayName, // Include our display name
          messageType: korium.MessageType.contactAccepted,
          timestampMs: now,
          status: korium.MessageStatus.pending,
          isFromMe: true,
        );
        
        await node.sendMessage(
          peerId: identity.toLowerCase(),
          message: acceptMessage,
        );
        
        // ignore: avoid_print
        print('[Contacts] Accepted contact request from ${identity.substring(0, 16)}...');
      },
    );
  }

  Future<void> updateContact(Contact contact) async {
    state = AsyncData(
      (state.value ?? []).map((c) {
        if (c.identity == contact.identity) {
          return contact;
        }
        return c;
      }).toList(),
    );

    await _storage.saveContact(_modelToHive(contact));
  }

  /// Updates the display name for a contact.
  Future<void> updateContactName(String identity, String newName) async {
    Contact? updated;
    state = AsyncData(
      (state.value ?? []).map((c) {
        if (c.identity == identity) {
          updated = c.copyWith(displayName: newName);
          return updated!;
        }
        return c;
      }).toList(),
    );

    if (updated != null) {
      await _storage.saveContact(_modelToHive(updated!));
    }
  }

  Future<void> deleteContact(String identity) async {
    state = AsyncData(
      (state.value ?? []).where((c) => c.identity != identity).toList(),
    );

    await _storage.deleteContact(identity);
  }

  Future<void> toggleFavorite(String identity) async {
    Contact? updated;
    state = AsyncData(
      (state.value ?? []).map((c) {
        if (c.identity == identity) {
          updated = c.copyWith(isFavorite: !c.isFavorite);
          return updated!;
        }
        return c;
      }).toList(),
    );

    if (updated != null) {
      await _storage.saveContact(_modelToHive(updated!));
    }
  }

  Future<void> toggleBlock(String identity) async {
    Contact? updated;
    state = AsyncData(
      (state.value ?? []).map((c) {
        if (c.identity == identity) {
          updated = c.copyWith(isBlocked: !c.isBlocked);
          return updated!;
        }
        return c;
      }).toList(),
    );

    if (updated != null) {
      await _storage.saveContact(_modelToHive(updated!));
    }
  }
}
