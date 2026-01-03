// Local Notification Service
//
// Handles displaying local notifications when messages arrive while
// the app is running or in the background.
//
// ARCHITECTURE:
// - Uses flutter_local_notifications for cross-platform support
// - Respects user notification preferences from settings
// - Does NOT handle push notifications (no server for P2P)
//
// SECURITY (per AGENTS.md):
// - No sensitive data in notification content (truncated preview only)
// - Notification IDs are bounded to prevent overflow

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/features/settings/domain/providers/settings_provider.dart';

/// Maximum length for notification body text.
/// SECURITY: Prevents large message content in notification shade.
const int _maxNotificationBodyLength = 100;

/// Channel ID for message notifications on Android.
const String _messageChannelId = 'six7_messages';

/// Channel name displayed in Android settings.
const String _messageChannelName = 'Messages';

/// Channel description for Android settings.
const String _messageChannelDescription = 'Notifications for new messages';

/// Provider for the notification service.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(ref);
});

/// Stream provider for notification tap navigation events.
/// Emits the peer/group ID when user taps a notification.
final notificationTapStreamProvider = StreamProvider<NotificationTapEvent>((ref) {
  final service = ref.watch(notificationServiceProvider);
  return service.notificationTapStream;
});

/// Event emitted when a notification is tapped.
class NotificationTapEvent {
  const NotificationTapEvent({
    required this.targetId,
    required this.isGroupChat,
    this.targetName,
  });

  /// The peer ID or group ID to navigate to.
  final String targetId;

  /// Whether this is a group chat notification.
  final bool isGroupChat;

  /// Optional display name for the target.
  final String? targetName;
}

/// Service for managing local notifications.
class NotificationService {
  NotificationService(this._ref);

  final Ref _ref;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  /// The peer ID currently being viewed (to suppress notifications).
  String? _activeChatPeerId;

  /// The group ID currently being viewed (to suppress notifications).
  String? _activeGroupChatId;

  /// Notification ID counter (bounded to prevent overflow).
  int _notificationIdCounter = 0;

  /// Maximum notification ID before wrapping.
  static const int _maxNotificationId = 100000;

  /// Stream controller for notification tap events.
  /// RESOURCE: Broadcast stream allows multiple listeners.
  final _notificationTapController = StreamController<NotificationTapEvent>.broadcast();

  /// Stream of notification tap events for navigation.
  Stream<NotificationTapEvent> get notificationTapStream => _notificationTapController.stream;

  /// Initializes the notification plugin.
  /// Must be called before showing any notifications.
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS settings
    const darwinSettings = DarwinInitializationSettings();

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channel
    if (Platform.isAndroid) {
      await _createAndroidChannel();
    }

    _isInitialized = true;
    debugPrint('[Notifications] Initialized');
  }

  /// Creates the Android notification channel.
  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      _messageChannelId,
      _messageChannelName,
      description: _messageChannelDescription,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// Requests notification permissions (iOS/macOS).
  Future<bool> requestPermissions() async {
    if (Platform.isIOS || Platform.isMacOS) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    }

    if (Platform.isAndroid) {
      final result = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return result ?? false;
    }

    return true;
  }

  /// Sets the currently active chat peer ID.
  /// When set, notifications for this peer are suppressed.
  void setActiveChatPeer(String? peerId) {
    _activeChatPeerId = peerId;
  }

  /// Sets the currently active group chat ID.
  /// When set, notifications for this group are suppressed.
  void setActiveGroupChat(String? groupId) {
    _activeGroupChatId = groupId;
  }

  /// Shows a notification for an incoming message.
  ///
  /// Respects user preferences and suppresses if:
  /// - Notifications are disabled in settings
  /// - The chat for this sender is currently open
  Future<void> showMessageNotification({
    required String senderId,
    required String senderName,
    required String messageText,
    String? conversationId,
  }) async {
    if (!_isInitialized) {
      debugPrint('[Notifications] Not initialized, skipping');
      return;
    }

    // Check if notifications are enabled in settings
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.messageNotifications) {
      debugPrint('[Notifications] Message notifications disabled');
      return;
    }

    // Suppress if this chat is currently open
    if (_activeChatPeerId == senderId) {
      debugPrint('[Notifications] Chat is active, suppressing');
      return;
    }

    // Truncate message for privacy/security
    final truncatedBody = messageText.length > _maxNotificationBodyLength
        ? '${messageText.substring(0, _maxNotificationBodyLength)}...'
        : messageText;

    // Get next notification ID (bounded)
    final notificationId = _getNextNotificationId();

    // Build notification details
    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.vibrate, // Use vibrate setting for sound too
      enableVibration: settings.vibrate,
      category: AndroidNotificationCategory.message,
      // Group notifications by sender
      groupKey: 'six7_chat_$senderId',
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: settings.popupNotification,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: senderId, // Group by sender on iOS
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // Payload format: "type:id:name" for navigation
    final payload = 'chat:$senderId:$senderName';

    await _plugin.show(
      notificationId,
      senderName,
      truncatedBody,
      details,
      payload: payload,
    );

    debugPrint('[Notifications] Showed notification for $senderName');
  }

  /// Shows a notification for a group message.
  Future<void> showGroupMessageNotification({
    required String groupId,
    required String groupName,
    required String senderName,
    required String messageText,
  }) async {
    if (!_isInitialized) return;

    // Check if group notifications are enabled
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.groupNotifications) {
      return;
    }

    // Suppress if this group chat is currently open
    if (_activeGroupChatId == groupId) {
      return;
    }

    final truncatedBody = messageText.length > _maxNotificationBodyLength
        ? '${messageText.substring(0, _maxNotificationBodyLength)}...'
        : messageText;

    final notificationId = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.vibrate,
      enableVibration: settings.vibrate,
      category: AndroidNotificationCategory.message,
      groupKey: 'six7_group_$groupId',
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: settings.popupNotification,
      presentBadge: true,
      presentSound: true,
      threadIdentifier: groupId,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    // Payload format: "type:id:name" for navigation
    final payload = 'group:$groupId:$groupName';

    await _plugin.show(
      notificationId,
      groupName,
      '$senderName: $truncatedBody',
      details,
      payload: payload,
    );
  }

  /// Shows a notification for a contact request.
  Future<void> showContactRequestNotification({
    required String senderId,
    required String senderName,
  }) async {
    if (!_isInitialized) return;

    // Check if notifications are enabled
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.messageNotifications) return;

    final notificationId = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.vibrate,
      enableVibration: settings.vibrate,
      category: AndroidNotificationCategory.social,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: settings.popupNotification,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      notificationId,
      'Contact Request',
      '$senderName wants to add you as a contact',
      details,
      payload: 'contact_request:$senderId',
    );

    debugPrint('[Notifications] Showed contact request from $senderName');
  }

  /// Shows a notification for a received vibe (someone vibed us).
  Future<void> showVibeReceivedNotification({
    required String contactId,
    required String contactName,
  }) async {
    if (!_isInitialized) return;

    // Check if notifications are enabled
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.messageNotifications) return;

    final notificationId = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.vibrate,
      enableVibration: settings.vibrate,
      category: AndroidNotificationCategory.social,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: settings.popupNotification,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      notificationId,
      '💜 Someone vibed you!',
      '$contactName sent you a vibe',
      details,
      payload: 'vibe_received:$contactId:$contactName',
    );

    debugPrint('[Notifications] Showed vibe received from $contactName');
  }

  /// Shows a notification for a vibe match.
  Future<void> showVibeMatchNotification({
    required String contactId,
    required String contactName,
  }) async {
    if (!_isInitialized) return;

    // Check if notifications are enabled
    final settings = _ref.read(notificationSettingsProvider);
    if (!settings.messageNotifications) return;

    final notificationId = _getNextNotificationId();

    final androidDetails = AndroidNotificationDetails(
      _messageChannelId,
      _messageChannelName,
      channelDescription: _messageChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      playSound: settings.vibrate,
      enableVibration: settings.vibrate,
      category: AndroidNotificationCategory.social,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: settings.popupNotification,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(
      notificationId,
      '💕 New Match!',
      'You and $contactName both vibed each other',
      details,
      payload: 'vibe_match:$contactId:$contactName',
    );

    debugPrint('[Notifications] Showed vibe match with $contactName');
  }

  /// Cancels all notifications for a specific sender/conversation.
  Future<void> cancelNotificationsForPeer(String peerId) async {
    // Note: flutter_local_notifications doesn't support canceling by group
    // We'd need to track notification IDs per peer for this
    // For now, this is a no-op placeholder
  }

  /// Cancels all notifications.
  Future<void> cancelAllNotifications() async {
    await _plugin.cancelAll();
  }

  /// Gets the next notification ID, wrapping at max.
  int _getNextNotificationId() {
    _notificationIdCounter = (_notificationIdCounter + 1) % _maxNotificationId;
    return _notificationIdCounter;
  }

  /// Callback when user taps a notification.
  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    debugPrint('[Notifications] Tapped, payload: $payload');

    if (payload == null || payload.isEmpty) {
      debugPrint('[Notifications] Empty payload, ignoring');
      return;
    }

    // Parse payload format: "type:id" or "type:id:name"
    // Examples: "chat:abc123", "group:xyz789", "contact_request:abc123:John"
    final parts = payload.split(':');
    if (parts.length < 2) {
      debugPrint('[Notifications] Invalid payload format: $payload');
      return;
    }

    final type = parts[0];
    final targetId = parts[1];
    final targetName = parts.length > 2 ? parts.sublist(2).join(':') : null;

    switch (type) {
      case 'chat':
        _notificationTapController.add(NotificationTapEvent(
          targetId: targetId,
          isGroupChat: false,
          targetName: targetName,
        ));
      case 'group':
        _notificationTapController.add(NotificationTapEvent(
          targetId: targetId,
          isGroupChat: true,
          targetName: targetName,
        ));
      case 'contact_request':
        // For contact requests, navigate to the 1:1 chat with that contact
        _notificationTapController.add(NotificationTapEvent(
          targetId: targetId,
          isGroupChat: false,
          targetName: targetName,
        ));
      case 'vibe_match':
        // For vibe matches, navigate to the 1:1 chat with the matched contact
        _notificationTapController.add(NotificationTapEvent(
          targetId: targetId,
          isGroupChat: false,
          targetName: targetName,
        ));
      case 'vibe_received':
        // For received vibes, navigate to the Vibes tab (home index 2)
        // Note: For now we send an event with targetId, the UI will handle navigation
        _notificationTapController.add(NotificationTapEvent(
          targetId: 'vibes_tab', // Special identifier for Vibes tab
          isGroupChat: false,
          targetName: targetName,
        ));
      default:
        debugPrint('[Notifications] Unknown notification type: $type');
    }
  }

  /// Disposes resources. Call when service is no longer needed.
  void dispose() {
    _notificationTapController.close();
  }
}
