import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/features/profile/domain/providers/profile_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;
import 'package:uuid/uuid.dart';

/// Maximum avatar size in bytes (100KB compressed)
const int kMaxAvatarBytes = 100 * 1024;

/// Provider for profile picture exchange between contacts.
final profileExchangeProvider = Provider<ProfileExchangeService>((ref) {
  return ProfileExchangeService(ref);
});

/// Service to handle profile picture exchange via P2P messaging.
class ProfileExchangeService {
  ProfileExchangeService(this._ref);

  final Ref _ref;

  /// Sends our profile (including avatar) to a contact.
  /// Call this after a contact request is accepted.
  Future<void> sendProfileToContact(String contactIdentity) async {
    final nodeAsync = _ref.read(koriumNodeProvider);
    final profile = _ref.read(userProfileProvider).value;
    
    if (profile == null) return;

    await nodeAsync.when(
      loading: () async {},
      error: (e, _) async {},
      data: (node) async {
        try {
          // Read avatar bytes if available
          String? avatarBase64;
          if (profile.avatarPath != null) {
            final file = File(profile.avatarPath!);
            if (await file.exists()) {
              final bytes = await file.readAsBytes();
              // SECURITY: Limit avatar size
              if (bytes.length <= kMaxAvatarBytes) {
                avatarBase64 = base64Encode(bytes);
              } else {
                debugPrint('[ProfileExchange] Avatar too large (${bytes.length} bytes), skipping');
              }
            }
          }

          // Create profile update payload
          final payload = jsonEncode({
            'displayName': profile.displayName,
            'status': profile.status,
            'avatar': avatarBase64,
          });

          final messageId = const Uuid().v4();
          final now = DateTime.now().millisecondsSinceEpoch;

          final profileMessage = korium.ChatMessage(
            id: messageId,
            senderId: node.identity,
            recipientId: contactIdentity.toLowerCase(),
            text: payload,
            messageType: korium.MessageType.profileUpdate,
            timestampMs: now,
            status: korium.MessageStatus.pending,
            isFromMe: true,
          );

          await node.sendMessage(
            peerId: contactIdentity.toLowerCase(),
            message: profileMessage,
          );

          debugPrint('[ProfileExchange] Sent profile to ${contactIdentity.substring(0, 16)}...');
        } catch (e) {
          debugPrint('[ProfileExchange] Failed to send profile: $e');
        }
      },
    );
  }

  /// Handles an incoming profile update message.
  /// Saves the avatar locally and updates the contact.
  Future<void> handleProfileUpdate({
    required String fromIdentity,
    required String payload,
  }) async {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final displayName = data['displayName'] as String?;
      final status = data['status'] as String?;
      final avatarBase64 = data['avatar'] as String?;

      String? savedAvatarPath;

      // Save avatar if provided
      if (avatarBase64 != null && avatarBase64.isNotEmpty) {
        final bytes = base64Decode(avatarBase64);
        
        // SECURITY: Validate size
        if (bytes.length > kMaxAvatarBytes) {
          debugPrint('[ProfileExchange] Received avatar too large, ignoring');
        } else {
          // Save to contact avatars directory
          final appDir = await getApplicationDocumentsDirectory();
          final avatarDir = Directory('${appDir.path}/contact_avatars');
          if (!await avatarDir.exists()) {
            await avatarDir.create(recursive: true);
          }

          // Use identity as filename for easy lookup/replacement
          final normalizedId = fromIdentity.toLowerCase();
          final fileName = '${normalizedId.substring(0, 16)}.jpg';
          final avatarPath = '${avatarDir.path}/$fileName';

          // Delete old avatar if exists
          final oldFile = File(avatarPath);
          if (await oldFile.exists()) {
            await oldFile.delete();
          }

          // Write new avatar
          await File(avatarPath).writeAsBytes(bytes);
          savedAvatarPath = avatarPath;

          debugPrint('[ProfileExchange] Saved avatar for ${normalizedId.substring(0, 16)}...');
        }
      }

      // Update contact with new info
      final contacts = _ref.read(contactsProvider).value ?? [];
      final existingContact = contacts.firstWhere(
        (c) => c.identity.toLowerCase() == fromIdentity.toLowerCase(),
        orElse: () => throw Exception('Contact not found'),
      );

      // Update contact with avatar path and optionally status
      final updatedContact = existingContact.copyWith(
        avatarUrl: savedAvatarPath ?? existingContact.avatarUrl,
        status: status ?? existingContact.status,
        // Note: We don't override displayName - user chose their own name for this contact
      );

      await _ref.read(contactsProvider.notifier).updateContact(updatedContact);

      debugPrint('[ProfileExchange] Updated contact ${fromIdentity.substring(0, 16)}...');
    } catch (e) {
      debugPrint('[ProfileExchange] Failed to handle profile update: $e');
    }
  }
}
