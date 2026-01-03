import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';

/// Storage keys for app settings.
abstract class SettingsKeys {
  // Account settings
  static const String twoFactorEnabled = 'two_factor_enabled';
  static const String readReceipts = 'read_receipts';
  static const String lastSeen = 'last_seen';
  static const String profilePhoto = 'profile_photo_visibility';
  static const String about = 'about_visibility';
  static const String groups = 'groups_visibility';
  static const String blockedContacts = 'blocked_contacts';
  static const String fingerprintLock = 'fingerprint_lock';
  static const String screenLock = 'screen_lock';

  // Chat settings
  static const String theme = 'theme';
  static const String fontSize = 'font_size';
  static const String enterToSend = 'enter_to_send';
  static const String mediaVisibility = 'media_visibility';
  static const String wallpaper = 'wallpaper';

  // Notification settings
  static const String messageNotifications = 'message_notifications';
  static const String groupNotifications = 'group_notifications';
  static const String callNotifications = 'call_notifications';
  static const String notificationTone = 'notification_tone';
  static const String vibrate = 'vibrate';
  static const String popupNotification = 'popup_notification';

  // Storage settings
  static const String autoDownloadWifi = 'auto_download_wifi';
  static const String autoDownloadMobile = 'auto_download_mobile';
  static const String autoDownloadRoaming = 'auto_download_roaming';
  static const String mediaQuality = 'media_quality';

  // Language settings
  static const String appLanguage = 'app_language';
}

/// Visibility options for privacy settings.
enum PrivacyVisibility {
  everyone('Everyone'),
  myContacts('My contacts'),
  nobody('Nobody');

  const PrivacyVisibility(this.label);

  final String label;
}

/// Theme options for the app.
enum AppTheme {
  system('System default'),
  light('Light'),
  dark('Dark');

  const AppTheme(this.label);

  final String label;
}

/// Font size options.
enum FontSize {
  small('Small'),
  medium('Medium'),
  large('Large');

  const FontSize(this.label);

  final String label;
}

/// Media quality options.
enum MediaQuality {
  auto('Auto (recommended)'),
  best('Best quality'),
  dataEfficient('Data efficient');

  const MediaQuality(this.label);

  final String label;
}

/// Provider for account settings.
final accountSettingsProvider =
    NotifierProvider<AccountSettingsNotifier, AccountSettings>(
  AccountSettingsNotifier.new,
);

class AccountSettings {
  const AccountSettings({
    this.twoFactorEnabled = false,
    this.readReceipts = true,
    this.lastSeen = PrivacyVisibility.everyone,
    this.profilePhoto = PrivacyVisibility.everyone,
    this.about = PrivacyVisibility.everyone,
    this.groups = PrivacyVisibility.everyone,
    this.blockedContacts = const [],
    this.fingerprintLock = false,
    this.screenLock = false,
  });

  final bool twoFactorEnabled;
  final bool readReceipts;
  final PrivacyVisibility lastSeen;
  final PrivacyVisibility profilePhoto;
  final PrivacyVisibility about;
  final PrivacyVisibility groups;
  final List<String> blockedContacts;
  final bool fingerprintLock;
  final bool screenLock;

  AccountSettings copyWith({
    bool? twoFactorEnabled,
    bool? readReceipts,
    PrivacyVisibility? lastSeen,
    PrivacyVisibility? profilePhoto,
    PrivacyVisibility? about,
    PrivacyVisibility? groups,
    List<String>? blockedContacts,
    bool? fingerprintLock,
    bool? screenLock,
  }) {
    return AccountSettings(
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      readReceipts: readReceipts ?? this.readReceipts,
      lastSeen: lastSeen ?? this.lastSeen,
      profilePhoto: profilePhoto ?? this.profilePhoto,
      about: about ?? this.about,
      groups: groups ?? this.groups,
      blockedContacts: blockedContacts ?? this.blockedContacts,
      fingerprintLock: fingerprintLock ?? this.fingerprintLock,
      screenLock: screenLock ?? this.screenLock,
    );
  }
}

class AccountSettingsNotifier extends Notifier<AccountSettings> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  AccountSettings build() {
    return AccountSettings(
      twoFactorEnabled:
          _storage.getSetting<bool>(SettingsKeys.twoFactorEnabled) ?? false,
      readReceipts:
          _storage.getSetting<bool>(SettingsKeys.readReceipts) ?? true,
      lastSeen: _parseVisibility(
        _storage.getSetting<String>(SettingsKeys.lastSeen),
      ),
      profilePhoto: _parseVisibility(
        _storage.getSetting<String>(SettingsKeys.profilePhoto),
      ),
      about: _parseVisibility(
        _storage.getSetting<String>(SettingsKeys.about),
      ),
      groups: _parseVisibility(
        _storage.getSetting<String>(SettingsKeys.groups),
      ),
      fingerprintLock:
          _storage.getSetting<bool>(SettingsKeys.fingerprintLock) ?? false,
      screenLock: _storage.getSetting<bool>(SettingsKeys.screenLock) ?? false,
    );
  }

  PrivacyVisibility _parseVisibility(String? value) {
    if (value == null) return PrivacyVisibility.everyone;
    return PrivacyVisibility.values.firstWhere(
      (v) => v.name == value,
      orElse: () => PrivacyVisibility.everyone,
    );
  }

  Future<void> setTwoFactorEnabled(bool value) async {
    await _storage.setSetting(SettingsKeys.twoFactorEnabled, value);
    state = state.copyWith(twoFactorEnabled: value);
  }

  Future<void> setReadReceipts(bool value) async {
    await _storage.setSetting(SettingsKeys.readReceipts, value);
    state = state.copyWith(readReceipts: value);
  }

  Future<void> setLastSeen(PrivacyVisibility value) async {
    await _storage.setSetting(SettingsKeys.lastSeen, value.name);
    state = state.copyWith(lastSeen: value);
  }

  Future<void> setProfilePhoto(PrivacyVisibility value) async {
    await _storage.setSetting(SettingsKeys.profilePhoto, value.name);
    state = state.copyWith(profilePhoto: value);
  }

  Future<void> setAbout(PrivacyVisibility value) async {
    await _storage.setSetting(SettingsKeys.about, value.name);
    state = state.copyWith(about: value);
  }

  Future<void> setGroups(PrivacyVisibility value) async {
    await _storage.setSetting(SettingsKeys.groups, value.name);
    state = state.copyWith(groups: value);
  }

  Future<void> setFingerprintLock(bool value) async {
    await _storage.setSetting(SettingsKeys.fingerprintLock, value);
    state = state.copyWith(fingerprintLock: value);
  }

  Future<void> setScreenLock(bool value) async {
    await _storage.setSetting(SettingsKeys.screenLock, value);
    state = state.copyWith(screenLock: value);
  }
}

/// Provider for chat settings.
final chatSettingsProvider =
    NotifierProvider<ChatSettingsNotifier, ChatSettings>(
  ChatSettingsNotifier.new,
);

class ChatSettings {
  const ChatSettings({
    this.theme = AppTheme.system,
    this.fontSize = FontSize.medium,
    this.enterToSend = false,
    this.mediaVisibility = true,
    this.wallpaper,
  });

  final AppTheme theme;
  final FontSize fontSize;
  final bool enterToSend;
  final bool mediaVisibility;
  final String? wallpaper;

  ChatSettings copyWith({
    AppTheme? theme,
    FontSize? fontSize,
    bool? enterToSend,
    bool? mediaVisibility,
    String? wallpaper,
  }) {
    return ChatSettings(
      theme: theme ?? this.theme,
      fontSize: fontSize ?? this.fontSize,
      enterToSend: enterToSend ?? this.enterToSend,
      mediaVisibility: mediaVisibility ?? this.mediaVisibility,
      wallpaper: wallpaper ?? this.wallpaper,
    );
  }
}

class ChatSettingsNotifier extends Notifier<ChatSettings> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  ChatSettings build() {
    return ChatSettings(
      theme: _parseTheme(_storage.getSetting<String>(SettingsKeys.theme)),
      fontSize:
          _parseFontSize(_storage.getSetting<String>(SettingsKeys.fontSize)),
      enterToSend:
          _storage.getSetting<bool>(SettingsKeys.enterToSend) ?? false,
      mediaVisibility:
          _storage.getSetting<bool>(SettingsKeys.mediaVisibility) ?? true,
      wallpaper: _storage.getSetting<String>(SettingsKeys.wallpaper),
    );
  }

  AppTheme _parseTheme(String? value) {
    if (value == null) return AppTheme.system;
    return AppTheme.values.firstWhere(
      (t) => t.name == value,
      orElse: () => AppTheme.system,
    );
  }

  FontSize _parseFontSize(String? value) {
    if (value == null) return FontSize.medium;
    return FontSize.values.firstWhere(
      (f) => f.name == value,
      orElse: () => FontSize.medium,
    );
  }

  Future<void> setTheme(AppTheme value) async {
    await _storage.setSetting(SettingsKeys.theme, value.name);
    state = state.copyWith(theme: value);
  }

  Future<void> setFontSize(FontSize value) async {
    await _storage.setSetting(SettingsKeys.fontSize, value.name);
    state = state.copyWith(fontSize: value);
  }

  Future<void> setEnterToSend(bool value) async {
    await _storage.setSetting(SettingsKeys.enterToSend, value);
    state = state.copyWith(enterToSend: value);
  }

  Future<void> setMediaVisibility(bool value) async {
    await _storage.setSetting(SettingsKeys.mediaVisibility, value);
    state = state.copyWith(mediaVisibility: value);
  }

  Future<void> setWallpaper(String? value) async {
    if (value != null) {
      await _storage.setSetting(SettingsKeys.wallpaper, value);
    }
    state = state.copyWith(wallpaper: value);
  }
}

/// Provider for notification settings.
final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
  NotificationSettingsNotifier.new,
);

class NotificationSettings {
  const NotificationSettings({
    this.messageNotifications = true,
    this.groupNotifications = true,
    this.callNotifications = true,
    this.notificationTone = 'Default',
    this.vibrate = true,
    this.popupNotification = false,
  });

  final bool messageNotifications;
  final bool groupNotifications;
  final bool callNotifications;
  final String notificationTone;
  final bool vibrate;
  final bool popupNotification;

  NotificationSettings copyWith({
    bool? messageNotifications,
    bool? groupNotifications,
    bool? callNotifications,
    String? notificationTone,
    bool? vibrate,
    bool? popupNotification,
  }) {
    return NotificationSettings(
      messageNotifications: messageNotifications ?? this.messageNotifications,
      groupNotifications: groupNotifications ?? this.groupNotifications,
      callNotifications: callNotifications ?? this.callNotifications,
      notificationTone: notificationTone ?? this.notificationTone,
      vibrate: vibrate ?? this.vibrate,
      popupNotification: popupNotification ?? this.popupNotification,
    );
  }
}

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  NotificationSettings build() {
    return NotificationSettings(
      messageNotifications:
          _storage.getSetting<bool>(SettingsKeys.messageNotifications) ?? true,
      groupNotifications:
          _storage.getSetting<bool>(SettingsKeys.groupNotifications) ?? true,
      callNotifications:
          _storage.getSetting<bool>(SettingsKeys.callNotifications) ?? true,
      notificationTone:
          _storage.getSetting<String>(SettingsKeys.notificationTone) ??
              'Default',
      vibrate: _storage.getSetting<bool>(SettingsKeys.vibrate) ?? true,
      popupNotification:
          _storage.getSetting<bool>(SettingsKeys.popupNotification) ?? false,
    );
  }

  Future<void> setMessageNotifications(bool value) async {
    await _storage.setSetting(SettingsKeys.messageNotifications, value);
    state = state.copyWith(messageNotifications: value);
  }

  Future<void> setGroupNotifications(bool value) async {
    await _storage.setSetting(SettingsKeys.groupNotifications, value);
    state = state.copyWith(groupNotifications: value);
  }

  Future<void> setCallNotifications(bool value) async {
    await _storage.setSetting(SettingsKeys.callNotifications, value);
    state = state.copyWith(callNotifications: value);
  }

  Future<void> setNotificationTone(String value) async {
    await _storage.setSetting(SettingsKeys.notificationTone, value);
    state = state.copyWith(notificationTone: value);
  }

  Future<void> setVibrate(bool value) async {
    await _storage.setSetting(SettingsKeys.vibrate, value);
    state = state.copyWith(vibrate: value);
  }

  Future<void> setPopupNotification(bool value) async {
    await _storage.setSetting(SettingsKeys.popupNotification, value);
    state = state.copyWith(popupNotification: value);
  }
}

/// Provider for storage settings.
final storageSettingsProvider =
    NotifierProvider<StorageSettingsNotifier, StorageSettings>(
  StorageSettingsNotifier.new,
);

class StorageSettings {
  const StorageSettings({
    this.autoDownloadWifi = true,
    this.autoDownloadMobile = false,
    this.autoDownloadRoaming = false,
    this.mediaQuality = MediaQuality.auto,
  });

  final bool autoDownloadWifi;
  final bool autoDownloadMobile;
  final bool autoDownloadRoaming;
  final MediaQuality mediaQuality;

  StorageSettings copyWith({
    bool? autoDownloadWifi,
    bool? autoDownloadMobile,
    bool? autoDownloadRoaming,
    MediaQuality? mediaQuality,
  }) {
    return StorageSettings(
      autoDownloadWifi: autoDownloadWifi ?? this.autoDownloadWifi,
      autoDownloadMobile: autoDownloadMobile ?? this.autoDownloadMobile,
      autoDownloadRoaming: autoDownloadRoaming ?? this.autoDownloadRoaming,
      mediaQuality: mediaQuality ?? this.mediaQuality,
    );
  }
}

class StorageSettingsNotifier extends Notifier<StorageSettings> {
  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  StorageSettings build() {
    return StorageSettings(
      autoDownloadWifi:
          _storage.getSetting<bool>(SettingsKeys.autoDownloadWifi) ?? true,
      autoDownloadMobile:
          _storage.getSetting<bool>(SettingsKeys.autoDownloadMobile) ?? false,
      autoDownloadRoaming:
          _storage.getSetting<bool>(SettingsKeys.autoDownloadRoaming) ?? false,
      mediaQuality: _parseMediaQuality(
        _storage.getSetting<String>(SettingsKeys.mediaQuality),
      ),
    );
  }

  MediaQuality _parseMediaQuality(String? value) {
    if (value == null) return MediaQuality.auto;
    return MediaQuality.values.firstWhere(
      (q) => q.name == value,
      orElse: () => MediaQuality.auto,
    );
  }

  Future<void> setAutoDownloadWifi(bool value) async {
    await _storage.setSetting(SettingsKeys.autoDownloadWifi, value);
    state = state.copyWith(autoDownloadWifi: value);
  }

  Future<void> setAutoDownloadMobile(bool value) async {
    await _storage.setSetting(SettingsKeys.autoDownloadMobile, value);
    state = state.copyWith(autoDownloadMobile: value);
  }

  Future<void> setAutoDownloadRoaming(bool value) async {
    await _storage.setSetting(SettingsKeys.autoDownloadRoaming, value);
    state = state.copyWith(autoDownloadRoaming: value);
  }

  Future<void> setMediaQuality(MediaQuality value) async {
    await _storage.setSetting(SettingsKeys.mediaQuality, value.name);
    state = state.copyWith(mediaQuality: value);
  }
}

/// Provider for language settings.
final languageSettingsProvider =
    NotifierProvider<LanguageSettingsNotifier, String>(
  LanguageSettingsNotifier.new,
);

class LanguageSettingsNotifier extends Notifier<String> {
  StorageService get _storage => ref.read(storageServiceProvider);

  /// Supported languages with their display names.
  static const Map<String, String> supportedLanguages = {
    'system': "Device's language",
    'en': 'English',
    'de': 'Deutsch',
    'fr': 'Français',
    'es': 'Español',
    'it': 'Italiano',
    'pt': 'Português',
    'zh': '中文',
    'ja': '日本語',
    'ko': '한국어',
  };

  @override
  String build() {
    return _storage.getSetting<String>(SettingsKeys.appLanguage) ?? 'system';
  }

  Future<void> setLanguage(String languageCode) async {
    if (!supportedLanguages.containsKey(languageCode)) {
      throw ArgumentError('Unsupported language: $languageCode');
    }
    await _storage.setSetting(SettingsKeys.appLanguage, languageCode);
    state = languageCode;
  }
}
