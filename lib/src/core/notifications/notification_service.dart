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

    await _plugin.show(
      notificationId,
      senderName,
      truncatedBody,
      details,
      payload: senderId, // Pass sender ID for tap handling
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

    await _plugin.show(
      notificationId,
      groupName,
      '$senderName: $truncatedBody',
      details,
      payload: groupId,
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
    
    // The payload contains the sender ID
    // Navigation is handled by the app's router listening to this
    // For now, we just log it - navigation integration can be added later
    
    // TODO: Navigate to chat with payload (sender ID)
    // This requires access to GoRouter or a navigation service
  }
}
