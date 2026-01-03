/// Application-wide constants following RFC 2119 compliance.
/// All magic numbers MUST be defined here as named constants.
abstract final class AppConstants {
  // Network constants
  static const int maxMessageSizeBytes = 64 * 1024; // 64 KB - matches Korium MAX_MESSAGE_SIZE
  static const int maxPeersPerTopic = 1000;
  static const int connectionTimeoutSeconds = 30;
  static const int messageRetryAttempts = 3;
  static const int retryBackoffBaseMs = 100;
  static const int maxRetryBackoffMs = 10000;

  // UI constants
  static const int maxDisplayNameLength = 50;
  static const int maxStatusLength = 140;
  static const int chatPreviewLength = 50;
  static const int avatarSizeSmall = 40;
  static const int avatarSizeMedium = 56;
  static const int avatarSizeLarge = 120;

  // Storage constants
  static const int maxCachedMessages = 1000;
  static const int maxCachedContacts = 500;
  static const String messagesCacheKey = 'cached_messages';
  static const String contactsCacheKey = 'cached_contacts';
  static const String identityKey = 'user_identity';

  // PubSub topics
  static const String presenceTopic = 'presence';
  static const String directMessageTopicPrefix = 'dm/';

  // Korium identity length (Ed25519 public key = 64 hex chars)
  static const int identityHexLength = 64;
}
