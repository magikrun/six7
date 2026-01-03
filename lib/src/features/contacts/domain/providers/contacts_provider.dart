import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/contacts/domain/models/contact.dart';

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

    final newContact = Contact(
      identity: identity,
      displayName: displayName,
      avatarUrl: avatarUrl,
      addedAt: DateTime.now(),
    );

    // Persist to storage
    await _storage.saveContact(_modelToHive(newContact));

    state = AsyncData([newContact, ...state.value ?? []]);

    // Note: Contact discovery is handled by Korium DHT, not Pkarr.
    // Pkarr is only used for bootstrap node discovery.
    // ignore: avoid_print
    print('[Contacts] Added contact: ${identity.substring(0, 16)}...');
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
