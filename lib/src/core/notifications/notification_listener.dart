// Notification Listener Provider
//
// Initializes the notification service and listens to Korium events
// to show local notifications for incoming messages.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/notifications/notification_service.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/contacts_provider.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/pending_contact_requests_provider.dart';
import 'package:six7_chat/src/features/contacts/domain/providers/profile_exchange_provider.dart';
import 'package:six7_chat/src/features/groups/domain/providers/groups_provider.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;

/// Provider that manages notification initialization and event listening.
/// This should be watched at the app level to ensure notifications work.
final notificationListenerProvider = Provider<NotificationListener>((ref) {
  final listener = NotificationListener(ref);
  
  // Initialize on creation
  listener._initialize();
  
  // Clean up on dispose
  ref.onDispose(listener._dispose);
  
  return listener;
});

/// Manages notification lifecycle and event subscriptions.
class NotificationListener {
  NotificationListener(this._ref);

  final Ref _ref;
  StreamSubscription<korium.KoriumEvent>? _eventSubscription;
  bool _isInitialized = false;
  
  /// SECURITY: Debounce map to prevent contact request/acceptance spam.
  /// Key: peer identity (lowercase), Value: timestamp of last response sent.
  /// Prevents infinite loops where both parties keep sending acceptances.
  final Map<String, int> _contactResponseDebounce = {};
  
  /// Debounce window in milliseconds (30 seconds).
  /// Don't send another acceptance to the same peer within this window.
  static const int _debounceWindowMs = 30000;

  NotificationService get _notificationService =>
      _ref.read(notificationServiceProvider);

  Future<void> _initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Initialize the notification service
    await _notificationService.initialize();
    
    // Request permissions (non-blocking, fire-and-forget)
    unawaited(
      _notificationService.requestPermissions().then((granted) {
        debugPrint('[NotificationListener] Permissions granted: $granted');
      }),
    );

    // Listen to Korium events for incoming messages
    _ref.listen(koriumEventStreamProvider, (previous, next) {
      next.whenData(_handleEvent);
    });

    debugPrint('[NotificationListener] Initialized');
  }

  void _dispose() {
    _eventSubscription?.cancel();
    debugPrint('[NotificationListener] Disposed');
  }

  /// Handles incoming Korium events and shows notifications as needed.
  Future<void> _handleEvent(korium.KoriumEvent event) async {
    switch (event) {
      case korium.KoriumEvent_ChatMessageReceived(:final message):
        // Don't notify for our own messages
        if (message.isFromMe) return;
        
        // Handle contact request/accepted messages specially
        if (message.messageType == korium.MessageType.contactRequest) {
          await _handleContactRequest(message);
          return;
        }
        if (message.messageType == korium.MessageType.contactAccepted) {
          await _handleContactAccepted(message);
          return;
        }
        
        // Handle profile update messages (avatar exchange)
        if (message.messageType == korium.MessageType.profileUpdate) {
          await _handleProfileUpdate(message);
          return;
        }
        
        // Check if this is a group message
        if (message.groupId != null) {
          // Group message - get group name and sender name
          final groupName = await _getGroupName(message.groupId!);
          final senderName = await _getSenderName(message.senderId);
          
          await _notificationService.showGroupMessageNotification(
            groupId: message.groupId!,
            groupName: groupName,
            senderName: senderName,
            messageText: message.text,
          );
        } else {
          // Direct message - get sender display name from contacts
          final senderName = await _getSenderName(message.senderId);
          
          await _notificationService.showMessageNotification(
            senderId: message.senderId,
            senderName: senderName,
            messageText: message.text,
          );
        }

      case korium.KoriumEvent_PubSubMessage(:final fromIdentity, :final data):
        // For raw PubSub messages, try to parse as chat message
        // This handles messages that come through before being converted
        try {
          final text = String.fromCharCodes(data);
          final senderName = await _getSenderName(fromIdentity);
          
          await _notificationService.showMessageNotification(
            senderId: fromIdentity,
            senderName: senderName,
            messageText: text,
          );
        } catch (_) {
          // Not a text message, ignore
        }

      case korium.KoriumEvent_IncomingRequest():
      case korium.KoriumEvent_MessageStatusUpdate():
      case korium.KoriumEvent_ConnectionStateChanged():
      case korium.KoriumEvent_PeerPresenceChanged():
      case korium.KoriumEvent_Error():
        // No notification needed for these events
        break;
        
      case korium.KoriumEvent_BootstrapComplete(:final success):
        // Update bootstrap state in the node provider
        debugPrint('[NotificationListener] Bootstrap complete: success=$success');
        if (success) {
          _ref.read(bootstrapStateProvider.notifier).setBootstrapped(true);
        }
    }
  }

  /// Handles an incoming contact request - auto-accepts and adds contact.
  /// SECURITY: Implements debounce to prevent acceptance message spam.
  Future<void> _handleContactRequest(korium.ChatMessage message) async {
    final normalizedSenderId = message.senderId.toLowerCase();
    final senderName = message.text.isNotEmpty 
        ? message.text  // The text contains their display name
        : '${message.senderId.substring(0, 8)}...';
    
    // SECURITY: Check debounce to prevent infinite acceptance loops
    final now = DateTime.now().millisecondsSinceEpoch;
    final lastResponse = _contactResponseDebounce[normalizedSenderId];
    if (lastResponse != null && (now - lastResponse) < _debounceWindowMs) {
      debugPrint('[NotificationListener] Contact request from $senderName - DEBOUNCED (sent response ${(now - lastResponse) / 1000}s ago)');
      return;
    }
    
    debugPrint('[NotificationListener] Contact request from $senderName - auto-accepting');
    
    // Check if already a contact
    final contacts = await _ref.read(contactsProvider.future);
    final alreadyContact = contacts.any(
      (c) => c.identity.toLowerCase() == normalizedSenderId,
    );
    
    // Update debounce timestamp BEFORE sending response
    _contactResponseDebounce[normalizedSenderId] = now;
    
    // SECURITY: Clean up old debounce entries to prevent unbounded growth
    _cleanupDebounceMap(now);
    
    if (!alreadyContact) {
      // Get our display name for the acceptance message
      final nodeAsync = _ref.read(koriumNodeProvider);
      final myName = await nodeAsync.when(
        loading: () async => 'Unknown',
        error: (e, s) async => 'Unknown',
        data: (node) async => node.identity.substring(0, 8),
      );
      
      // Auto-accept: add them and send acceptance back
      await _ref.read(contactsProvider.notifier).acceptContactRequest(
        identity: message.senderId,
        displayName: senderName,
        myDisplayName: myName,
      );
      
      // Send our profile to the new contact (avatar exchange)
      await _ref.read(profileExchangeProvider).sendProfileToContact(message.senderId);
      
      // Show notification that contact was added
      await _notificationService.showMessageNotification(
        senderId: message.senderId,
        senderName: senderName,
        messageText: '$senderName was added to your contacts',
      );
    } else {
      debugPrint('[NotificationListener] Already a contact, sending acceptance only');
      // Already a contact, just send acceptance back
      final nodeAsync = _ref.read(koriumNodeProvider);
      await nodeAsync.whenData((node) async {
        final acceptMessage = korium.ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          senderId: node.identity,
          recipientId: message.senderId,
          text: node.identity.substring(0, 8),
          messageType: korium.MessageType.contactAccepted,
          timestampMs: DateTime.now().millisecondsSinceEpoch,
          status: korium.MessageStatus.pending,
          isFromMe: true,
        );
        await node.sendMessage(peerId: message.senderId, message: acceptMessage);
      });
    }
  }
  
  /// Cleans up old entries from the debounce map to prevent unbounded growth.
  /// SECURITY: Per AGENTS.md - bounded collections requirement.
  void _cleanupDebounceMap(int now) {
    _contactResponseDebounce.removeWhere((_, timestamp) {
      return (now - timestamp) > _debounceWindowMs * 2;
    });
  }

  /// Handles a contact accepted response.
  Future<void> _handleContactAccepted(korium.ChatMessage message) async {
    final senderName = message.text.isNotEmpty 
        ? message.text  // The text contains their display name
        : '${message.senderId.substring(0, 8)}...';
    
    debugPrint('[NotificationListener] Contact accepted by $senderName');
    
    // Auto-add them as a contact if not already
    final contacts = await _ref.read(contactsProvider.future);
    final alreadyContact = contacts.any(
      (c) => c.identity.toLowerCase() == message.senderId.toLowerCase(),
    );
    
    if (!alreadyContact) {
      await _ref.read(contactsProvider.notifier).addContact(
        identity: message.senderId,
        displayName: senderName,
      );
    }
    
    // Send our profile to the new contact (avatar exchange)
    await _ref.read(profileExchangeProvider).sendProfileToContact(message.senderId);
    
    // Show notification
    await _notificationService.showMessageNotification(
      senderId: message.senderId,
      senderName: senderName,
      messageText: '$senderName accepted your contact request',
    );
  }

  /// Handles an incoming profile update message (avatar exchange).
  Future<void> _handleProfileUpdate(korium.ChatMessage message) async {
    debugPrint('[NotificationListener] Profile update from ${message.senderId.substring(0, 16)}...');
    
    await _ref.read(profileExchangeProvider).handleProfileUpdate(
      fromIdentity: message.senderId,
      payload: message.text,
    );
  }

  /// Gets the display name for a group by ID.
  Future<String> _getGroupName(String groupId) async {
    try {
      final groups = await _ref.read(groupsProvider.future);
      final group = groups.firstWhere(
        (g) => g.id == groupId,
        orElse: () => throw StateError('Not found'),
      );
      return group.name;
    } catch (_) {
      // Group not found, use truncated ID
      return 'Group ${groupId.substring(0, 8)}...';
    }
  }

  /// Gets the display name for a sender from contacts, or truncated ID.
  Future<String> _getSenderName(String senderId) async {
    try {
      final contacts = await _ref.read(contactsProvider.future);
      final contact = contacts.firstWhere(
        (c) => c.identity.toLowerCase() == senderId.toLowerCase(),
        orElse: () => throw StateError('Not found'),
      );
      return contact.displayName;
    } catch (_) {
      // Not in contacts, use truncated ID
      return '${senderId.substring(0, 8)}...';
    }
  }

  /// Sets the currently active chat to suppress notifications for it.
  void setActiveChatPeer(String? peerId) {
    _notificationService.setActiveChatPeer(peerId);
  }

  /// Sets the currently active group chat to suppress notifications for it.
  void setActiveGroupChat(String? groupId) {
    _notificationService.setActiveGroupChat(groupId);
  }
}
