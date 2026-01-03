// Korium Platform Channel Bridge
//
// This module provides a Dart interface to native Korium functionality
// via Flutter platform channels. It replaces the previous flutter_rust_bridge
// integration with native UniFFI bindings on iOS (Swift) and Android (Kotlin).
//
// ARCHITECTURE:
// - Platform channels communicate with native KoriumBridge implementations
// - Async operations use Flutter's async/await pattern
// - Events are polled from a native-side bounded buffer
//
// SECURITY (per AGENTS.md):
// - All inputs validated on the native side
// - Identity data handled securely (not logged)
// - Bounded collections for event storage

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'korium_bridge.freezed.dart';
part 'korium_bridge.g.dart';

// =============================================================================
// Constants
// =============================================================================

/// Constants for resource bounds.
class KoriumConstants {
  KoriumConstants._();

  /// Maximum events to poll per request.
  static const int maxPollEvents = 100;

  /// Peer identity hex length (Ed25519 public key).
  static const int peerIdentityHexLen = 64;

  /// Private key hex length (Ed25519 secret key).
  static const int privateKeyHexLen = 64;

  /// Maximum message size in bytes (64 KB - matches Korium MAX_MESSAGE_SIZE).
  /// SECURITY: Enforced at Dart layer to prevent memory exhaustion.
  static const int maxMessageSizeBytes = 64 * 1024;

  /// Maximum topic length in characters.
  /// SECURITY: Prevents resource consumption via excessively long topic names.
  static const int maxTopicLength = 256;
}

/// Private constant for message size validation.
const int _maxMessageSizeBytes = KoriumConstants.maxMessageSizeBytes;

// =============================================================================
// Platform Channel
// =============================================================================

/// Platform channel for Korium native bridge.
const _channel = MethodChannel('chat.six7/korium');

// =============================================================================
// Enums (matching rust/message.dart)
// =============================================================================

/// Status of a chat message.
enum MessageStatus {
  /// Message is pending to be sent.
  pending,

  /// Message has been sent to the network.
  sent,

  /// Message has been delivered to the recipient.
  delivered,

  /// Message has been read by the recipient.
  read,

  /// Message failed to send.
  failed,
}

/// Type of chat message.
enum MessageType {
  /// Plain text message.
  text,

  /// Image message.
  image,

  /// Video message.
  video,

  /// Audio message.
  audio,

  /// Document/file message.
  document,

  /// Location message.
  location,

  /// Contact card message.
  contact,

  /// Group invitation message.
  groupInvite,
  
  /// Contact request (sent when adding someone via QR).
  contactRequest,
  
  /// Contact request accepted.
  contactAccepted,
  
  /// Vibe message (for anonymous matching).
  vibe,
  
  /// Read receipt (sender confirms they read messages).
  readReceipt,
  
  /// Profile update (contains avatar and profile info).
  profileUpdate,
}

// =============================================================================
// Data Classes (using freezed for immutability)
// =============================================================================

/// A chat message.
@freezed
sealed class ChatMessage with _$ChatMessage {
  const factory ChatMessage({
    required String id,
    required String senderId,
    required String recipientId,
    required String text,
    required MessageType messageType,
    required int timestampMs,
    required MessageStatus status,
    required bool isFromMe,
    /// Group ID if this is a group message (null for 1:1 chats)
    String? groupId,
    String? replyToId,
    String? mediaUrl,
    String? thumbnailUrl,
    int? mediaSizeBytes,
    int? mediaDurationMs,
  }) = _ChatMessage;

  factory ChatMessage.fromJson(Map<String, dynamic> json) =>
      _$ChatMessageFromJson(json);
}

/// Telemetry snapshot from the DHT.
class Telemetry {
  const Telemetry({
    required this.storedKeys,
    required this.replicationFactor,
    required this.concurrency,
  });

  /// Number of keys stored in the DHT.
  final int storedKeys;

  /// Replication factor for DHT records.
  final int replicationFactor;

  /// Concurrency level for DHT operations.
  final int concurrency;
}

/// Identity restoration data for saving to secure storage.
///
/// # Security
/// This data is HIGHLY SENSITIVE. The `secretKeyHex` is the node's private key.
/// It MUST be stored in secure storage (e.g., iOS Keychain, Android Keystore).
/// Leaking this data allows identity theft.
@freezed
sealed class IdentityRestoreData with _$IdentityRestoreData {
  const factory IdentityRestoreData({
    required String secretKeyHex,
    required BigInt powNonce,
  }) = _IdentityRestoreData;

  factory IdentityRestoreData.fromJson(Map<String, dynamic> json) =>
      _$IdentityRestoreDataFromJson(json);
}

/// Configuration for creating a new Korium node.
@freezed
sealed class NodeConfig with _$NodeConfig {
  const factory NodeConfig({
    String? namespaceSecret,
    String? privateKeyHex,
    BigInt? identityProofNonce,
  }) = _NodeConfig;

  factory NodeConfig.fromJson(Map<String, dynamic> json) =>
      _$NodeConfigFromJson(json);
}

// =============================================================================
// Korium Events (matching rust/streams.dart)
// =============================================================================

@freezed
sealed class KoriumEvent with _$KoriumEvent {
  const KoriumEvent._();

  /// A PubSub message was received
  const factory KoriumEvent.pubSubMessage({
    required String topic,
    required String fromIdentity,
    required Uint8List data,
  }) = KoriumEvent_PubSubMessage;

  /// A direct request was received (needs response)
  const factory KoriumEvent.incomingRequest({
    required String fromIdentity,
    required String requestId,
    required Uint8List data,
  }) = KoriumEvent_IncomingRequest;

  /// A chat message was received
  const factory KoriumEvent.chatMessageReceived({
    required ChatMessage message,
  }) = KoriumEvent_ChatMessageReceived;

  /// A message status update was received (delivery/read receipt)
  const factory KoriumEvent.messageStatusUpdate({
    required String messageId,
    required MessageStatus status,
  }) = KoriumEvent_MessageStatusUpdate;

  /// Connection state changed
  const factory KoriumEvent.connectionStateChanged({
    required bool isConnected,
  }) = KoriumEvent_ConnectionStateChanged;

  /// A peer came online or went offline
  const factory KoriumEvent.peerPresenceChanged({
    required String peerIdentity,
    required bool isOnline,
  }) = KoriumEvent_PeerPresenceChanged;

  /// An error occurred
  const factory KoriumEvent.error({required String message}) =
      KoriumEvent_Error;

  /// Bootstrap completed (success or failure)
  const factory KoriumEvent.bootstrapComplete({
    required bool success,
    String? error,
  }) = KoriumEvent_BootstrapComplete;
}

// =============================================================================
// Helper Functions
// =============================================================================

KoriumEvent _parseEvent(Map<dynamic, dynamic> map) {
  final type = map['type'] as String;
  switch (type) {
    case 'pubSubMessage':
      return KoriumEvent.pubSubMessage(
        topic: map['topic'] as String,
        fromIdentity: map['fromIdentity'] as String,
        data: Uint8List.fromList((map['data'] as List).cast<int>()),
      );
    case 'incomingRequest':
      return KoriumEvent.incomingRequest(
        fromIdentity: map['fromIdentity'] as String,
        requestId: map['requestId'] as String,
        data: Uint8List.fromList((map['data'] as List).cast<int>()),
      );
    case 'chatMessageReceived':
      return KoriumEvent.chatMessageReceived(
        message: _parseChatMessage(
          Map<String, dynamic>.from(map['message'] as Map),
        ),
      );
    case 'messageStatusUpdate':
      return KoriumEvent.messageStatusUpdate(
        messageId: map['messageId'] as String,
        status: _parseMessageStatus(map['status'] as String),
      );
    case 'connectionStateChanged':
      return KoriumEvent.connectionStateChanged(
        isConnected: map['isConnected'] as bool,
      );
    case 'peerPresenceChanged':
      return KoriumEvent.peerPresenceChanged(
        peerIdentity: map['peerIdentity'] as String,
        isOnline: map['isOnline'] as bool,
      );
    case 'error':
      return KoriumEvent.error(message: map['message'] as String);
    case 'bootstrapComplete':
      return KoriumEvent.bootstrapComplete(
        success: map['success'] as bool,
        error: map['error'] as String?,
      );
    default:
      return KoriumEvent.error(message: 'Unknown event type: $type');
  }
}

ChatMessage _parseChatMessage(Map<String, dynamic> map) {
  return ChatMessage(
    id: map['id'] as String,
    senderId: map['senderId'] as String,
    recipientId: map['recipientId'] as String,
    text: map['text'] as String,
    messageType: _parseMessageType(map['messageType'] as String),
    timestampMs: map['timestampMs'] as int,
    status: _parseMessageStatus(map['status'] as String),
    isFromMe: map['isFromMe'] as bool,
    groupId: map['groupId'] as String?,
    replyToId: map['replyToId'] as String?,
    mediaUrl: map['mediaUrl'] as String?,
    thumbnailUrl: map['thumbnailUrl'] as String?,
    mediaSizeBytes: map['mediaSizeBytes'] as int?,
    mediaDurationMs: map['mediaDurationMs'] as int?,
  );
}

Map<String, dynamic> _serializeChatMessage(ChatMessage msg) {
  return {
    'id': msg.id,
    'senderId': msg.senderId,
    'recipientId': msg.recipientId,
    'text': msg.text,
    'messageType': msg.messageType.name,
    'timestampMs': msg.timestampMs,
    'status': msg.status.name,
    'isFromMe': msg.isFromMe,
    'groupId': msg.groupId,
    'replyToId': msg.replyToId,
    'mediaUrl': msg.mediaUrl,
    'thumbnailUrl': msg.thumbnailUrl,
    'mediaSizeBytes': msg.mediaSizeBytes,
    'mediaDurationMs': msg.mediaDurationMs,
  };
}

MessageStatus _parseMessageStatus(String value) {
  return MessageStatus.values.firstWhere(
    (e) => e.name == value,
    orElse: () => MessageStatus.pending,
  );
}

MessageType _parseMessageType(String value) {
  return MessageType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => MessageType.text,
  );
}

// =============================================================================
// Exceptions
// =============================================================================

/// Korium error from native layer.
class KoriumException implements Exception {
  const KoriumException(this.message);

  final String message;

  @override
  String toString() => 'KoriumException: $message';
}

// =============================================================================
// KoriumNode
// =============================================================================

/// Main Korium node interface.
///
/// This class provides a Dart-friendly API to the native Korium node
/// via platform channels. The native implementation uses korium's
/// UniFFI bindings.
class KoriumNode {
  KoriumNode._({
    required String identity,
    required String localAddr,
  })  : _identity = identity,
        _localAddr = localAddr;

  final String _identity;
  final String _localAddr;
  bool _isBootstrapped = false;
  String? _bootstrapError;
  IdentityRestoreData? _identityRestoreData;
  bool _identityRestoreDataExtracted = false;

  /// The node's identity (Ed25519 public key as hex string).
  String get identity => _identity;

  /// Returns the local address the node is listening on.
  String get localAddr => _localAddr;

  /// Returns whether the node has successfully bootstrapped.
  bool get isBootstrapped => _isBootstrapped;

  /// Returns the bootstrap error message if bootstrap failed.
  String? get bootstrapError => _bootstrapError;

  /// Creates a new Korium node with default configuration.
  ///
  /// Korium automatically binds to an available address.
  ///
  /// # Returns
  /// A new `KoriumNode` instance.
  static Future<KoriumNode> create() async {
    return createWithConfig(config: const NodeConfig());
  }

  /// Creates a new Korium node with full configuration.
  ///
  /// Automatically bootstraps to the public Korium network via DNS resolution
  /// of bootstrap.korium.io.
  static Future<KoriumNode> createWithConfig({required NodeConfig config}) async {
    try {
      // SECURITY: Convert BigInt to hex string for native (native expects 16-char hex)
      // BigInt.toRadixString(16) produces lowercase hex without padding
      // Pad to 16 chars (64 bits / 4 bits per hex digit = 16 hex digits)
      String? nonceHex;
      if (config.identityProofNonce != null) {
        nonceHex = config.identityProofNonce!.toRadixString(16).padLeft(16, '0');
      }

      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createNodeWithConfig',
        {
          'namespaceSecret': config.namespaceSecret,
          'privateKeyHex': config.privateKeyHex,
          'identityProofNonce': nonceHex,
        },
      );

      if (result == null) {
        throw const KoriumException('Failed to create node: null result');
      }

      final node = KoriumNode._(
        identity: result['identity'] as String,
        localAddr: result['localAddr'] as String,
      );

      node._isBootstrapped = result['isBootstrapped'] as bool? ?? false;
      node._bootstrapError = result['bootstrapError'] as String?;

      // Parse identity restore data if provided
      if (result['secretKeyHex'] != null && result['powNonce'] != null) {
        // SECURITY: powNonce comes from native as hex string (16 chars)
        // Must parse with radix 16, not decimal
        node._identityRestoreData = IdentityRestoreData(
          secretKeyHex: result['secretKeyHex'] as String,
          powNonce: BigInt.parse(result['powNonce'].toString(), radix: 16),
        );
      }

      return node;
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to create node');
    }
  }

  /// Returns identity restoration data for saving to secure storage.
  ///
  /// This method returns the private key and PoW nonce needed to restore
  /// the node's identity on subsequent app launches without re-computing PoW.
  ///
  /// # Security
  /// - MUST be stored in secure storage (iOS Keychain / Android Keystore)
  /// - This method can only be called ONCE per node instance
  /// - Subsequent calls return None (one-shot extraction to minimize exposure)
  /// - The secret key allows full identity impersonation - treat as password
  IdentityRestoreData? getIdentityRestoreData() {
    if (_identityRestoreDataExtracted) {
      return null;
    }
    _identityRestoreDataExtracted = true;
    return _identityRestoreData;
  }

  /// Starts listening for incoming messages and requests.
  Future<void> startListeners() async {
    try {
      await _channel.invokeMethod<void>('startListeners');
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to start listeners');
    }
  }

  /// Gracefully shuts down the node.
  Future<void> shutdown() async {
    try {
      await _channel.invokeMethod<void>('shutdown');
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to shutdown');
    }
  }

  /// Bootstraps the node by connecting to an existing peer.
  Future<void> bootstrap({
    required String peerIdentity,
    required List<String> peerAddrs,
  }) async {
    _validateIdentity(peerIdentity);
    try {
      await _channel.invokeMethod<void>('bootstrap', {
        'peerIdentity': peerIdentity,
        'peerAddrs': peerAddrs,
      });
      _isBootstrapped = true;
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to bootstrap');
    }
  }

  /// Adds a peer to the routing table.
  ///
  /// Use this after scanning a QR code to add the peer before resolving.
  /// If addresses are provided, they will be used for direct connection.
  /// Otherwise, the DHT will be used to resolve addresses.
  Future<void> addPeer({
    required String peerId,
    List<String> addresses = const [],
  }) async {
    _validateIdentity(peerId);
    try {
      await _channel.invokeMethod<void>('addPeer', {
        'peerId': peerId,
        'addresses': addresses,
      });
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to add peer');
    }
  }

  /// Subscribes to a PubSub topic.
  /// 
  /// SECURITY: Topic length is validated to prevent resource consumption.
  Future<void> subscribe({required String topic}) async {
    if (topic.isEmpty) {
      throw const KoriumException('Topic cannot be empty');
    }
    if (topic.length > KoriumConstants.maxTopicLength) {
      throw KoriumException(
        'Topic length ${topic.length} exceeds maximum ${KoriumConstants.maxTopicLength}',
      );
    }
    try {
      await _channel.invokeMethod<void>('subscribe', {'topic': topic});
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to subscribe');
    }
  }

  /// Unsubscribes from a PubSub topic.
  /// 
  /// SECURITY: Topic length is validated to prevent resource consumption.
  Future<void> unsubscribe({required String topic}) async {
    if (topic.isEmpty) {
      throw const KoriumException('Topic cannot be empty');
    }
    if (topic.length > KoriumConstants.maxTopicLength) {
      throw KoriumException(
        'Topic length ${topic.length} exceeds maximum ${KoriumConstants.maxTopicLength}',
      );
    }
    try {
      await _channel.invokeMethod<void>('unsubscribe', {'topic': topic});
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to unsubscribe');
    }
  }

  /// Publishes a message to a PubSub topic.
  /// 
  /// SECURITY: Message size and topic length are validated to prevent
  /// memory exhaustion attacks at the Dart layer.
  Future<void> publish({required String topic, required List<int> data}) async {
    // SECURITY: Validate topic
    if (topic.isEmpty) {
      throw const KoriumException('Topic cannot be empty');
    }
    if (topic.length > KoriumConstants.maxTopicLength) {
      throw KoriumException(
        'Topic length ${topic.length} exceeds maximum ${KoriumConstants.maxTopicLength}',
      );
    }
    // SECURITY: Validate message size before sending to native
    if (data.length > _maxMessageSizeBytes) {
      throw KoriumException(
        'Message size ${data.length} exceeds maximum $_maxMessageSizeBytes bytes',
      );
    }
    try {
      await _channel.invokeMethod<void>('publish', {
        'topic': topic,
        'data': Uint8List.fromList(data),
      });
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to publish');
    }
  }

  /// Publishes the node's address for peer discovery.
  Future<void> publishAddress({required List<String> addresses}) async {
    try {
      await _channel.invokeMethod<void>('publishAddress', {
        'addresses': addresses,
      });
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to publish address');
    }
  }

  /// Resolves a peer's contact information.
  Future<List<String>> resolvePeer({required String peerId}) async {
    _validateIdentity(peerId);
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'resolvePeer',
        {'peerId': peerId},
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to resolve peer');
    }
  }

  /// Checks if a peer is reachable by resolving their address.
  Future<bool> isPeerOnline({required String peerId}) async {
    _validateIdentity(peerId);
    try {
      final addresses = await resolvePeer(peerId: peerId);
      return addresses.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Sends a request to a peer and waits for a response.
  Future<Uint8List> sendRequest({
    required String peerId,
    required List<int> data,
  }) async {
    _validateIdentity(peerId);
    try {
      final result = await _channel.invokeMethod<Uint8List>('sendRequest', {
        'peerId': peerId,
        'data': Uint8List.fromList(data),
      });
      return result ?? Uint8List(0);
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to send request');
    }
  }

  /// Sends a chat message to a peer.
  Future<ChatMessage> sendMessage({
    required String peerId,
    required ChatMessage message,
  }) async {
    _validateIdentity(peerId);
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'sendMessage',
        {
          'peerId': peerId,
          'message': _serializeChatMessage(message),
        },
      );
      if (result == null) {
        throw const KoriumException('Failed to send message: null result');
      }
      return _parseChatMessage(Map<String, dynamic>.from(result));
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to send message');
    }
  }

  /// Sends a group chat message to all members of a group.
  /// The message is published to the group's PubSub topic.
  Future<void> sendGroupMessage({
    required String groupId,
    required ChatMessage message,
  }) async {
    // SECURITY: Validate group ID format (UUID)
    if (groupId.isEmpty || groupId.length > 36) {
      throw const KoriumException('Invalid group ID');
    }
    try {
      await _channel.invokeMethod<void>(
        'sendGroupMessage',
        {
          'groupId': groupId,
          'message': _serializeChatMessage(message),
        },
      );
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to send group message');
    }
  }

  /// Subscribes to a group's PubSub topic for receiving messages.
  Future<void> subscribeToGroup({required String groupId}) async {
    // SECURITY: Validate group ID format
    if (groupId.isEmpty || groupId.length > 36) {
      throw const KoriumException('Invalid group ID');
    }
    // Group topic uses prefix "six7-group:" followed by groupId
    await subscribe(topic: 'six7-group:$groupId');
  }

  /// Unsubscribes from a group's PubSub topic.
  Future<void> unsubscribeFromGroup({required String groupId}) async {
    if (groupId.isEmpty) return;
    await unsubscribe(topic: 'six7-group:$groupId');
  }

  /// Returns routable addresses for this node.
  Future<List<String>> routableAddresses() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'routableAddresses',
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to get routable addresses');
    }
  }

  /// Returns the primary routable address for DHT publishing.
  Future<String> primaryRoutableAddress() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'primaryRoutableAddress',
      );
      return result ?? _localAddr;
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to get primary address');
    }
  }

  /// Finds peers near a target identity in the DHT.
  Future<List<String>> findPeers({required String targetId}) async {
    _validateIdentity(targetId);
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'findPeers',
        {'targetId': targetId},
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to find peers');
    }
  }

  /// Gets list of subscribed PubSub topics.
  Future<List<String>> getSubscriptions() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getSubscriptions',
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to get subscriptions');
    }
  }

  /// Gets telemetry snapshot from the DHT.
  Future<Telemetry> getTelemetry() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getTelemetry',
      );
      if (result == null) {
        return const Telemetry(storedKeys: 0, replicationFactor: 0, concurrency: 0);
      }
      final map = Map<String, dynamic>.from(result);
      return Telemetry(
        storedKeys: map['storedKeys'] as int? ?? 0,
        replicationFactor: map['replicationFactor'] as int? ?? 0,
        concurrency: map['concurrency'] as int? ?? 0,
      );
    } on PlatformException catch (e) {
      throw KoriumException(e.message ?? 'Failed to get telemetry');
    }
  }

  void _validateIdentity(String identityHex) {
    if (identityHex.length != KoriumConstants.peerIdentityHexLen) {
      throw KoriumException(
        'Invalid identity length: expected ${KoriumConstants.peerIdentityHexLen}, '
        'got ${identityHex.length}',
      );
    }
    if (!_isHexString(identityHex)) {
      throw const KoriumException('Identity must be hex string');
    }
  }

  static bool _isHexString(String s) {
    return s.split('').every(
          (c) =>
              (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || // 0-9
              (c.codeUnitAt(0) >= 65 && c.codeUnitAt(0) <= 70) || // A-F
              (c.codeUnitAt(0) >= 97 && c.codeUnitAt(0) <= 102), // a-f
        );
  }
}

// =============================================================================
// Global Functions (matching rust/api.dart)
// =============================================================================

/// Validates and normalizes a hex-encoded identity string.
///
/// This function validates that the input is a valid Ed25519 public key
/// by checking its format through the native FFI. Use this to validate
/// identities scanned from QR codes before adding them as peers.
///
/// Returns the validated identity hex string (normalized to lowercase).
/// Throws [KoriumException] if the identity is invalid.
Future<String> identityFromHex(String hexStr) async {
  try {
    final result = await _channel.invokeMethod<String>(
      'identityFromHex',
      {'hexStr': hexStr},
    );
    if (result == null) {
      throw const KoriumException('Invalid identity: null result');
    }
    return result;
  } on PlatformException catch (e) {
    throw KoriumException(e.message ?? 'Failed to validate identity');
  }
}

/// Signature result containing the signature.
class SignatureResult {
  const SignatureResult({
    required this.signatureHex,
  });

  /// The 64-byte signature as 128 hex characters.
  final String signatureHex;
}

/// Signs a message using an Ed25519 secret key.
///
/// # Arguments
/// * [secretKeyHex] - The 32-byte secret key as 64 hex characters
/// * [message] - The message bytes to sign
///
/// # Returns
/// A [SignatureResult] containing the signature and derived public key.
///
/// # Security
/// The secret key should be stored securely and never logged.
Future<SignatureResult> sign({
  required String secretKeyHex,
  required Uint8List message,
}) async {
  // SECURITY: Validate secret key length
  if (secretKeyHex.length != KoriumConstants.privateKeyHexLen) {
    throw const KoriumException('Invalid secret key length');
  }
  try {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'sign',
      {
        'secretKeyHex': secretKeyHex,
        'message': message,
      },
    );
    if (result == null) {
      throw const KoriumException('Failed to sign: null result');
    }
    return SignatureResult(
      signatureHex: result['signatureHex'] as String,
    );
  } on PlatformException catch (e) {
    throw KoriumException(e.message ?? 'Failed to sign message');
  }
}

/// Verifies an Ed25519 signature.
///
/// # Arguments
/// * [publicKeyHex] - The 32-byte public key (identity) as 64 hex characters
/// * [message] - The original message bytes
/// * [signatureHex] - The 64-byte signature as 128 hex characters
///
/// # Returns
/// `true` if the signature is valid, `false` otherwise.
Future<bool> verify({
  required String publicKeyHex,
  required Uint8List message,
  required String signatureHex,
}) async {
  // SECURITY: Validate public key length
  if (publicKeyHex.length != KoriumConstants.peerIdentityHexLen) {
    throw const KoriumException('Invalid public key length');
  }
  try {
    final result = await _channel.invokeMethod<bool>(
      'verify',
      {
        'publicKeyHex': publicKeyHex,
        'message': message,
        'signatureHex': signatureHex,
      },
    );
    return result ?? false;
  } on PlatformException catch (e) {
    throw KoriumException(e.message ?? 'Failed to verify signature');
  }
}

/// Polls for pending events from the global broadcaster.
/// Returns a list of events that have been received since the last poll.
Future<List<KoriumEvent>> pollEvents({required int maxEvents}) async {
  try {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'pollEvents',
      {'maxEvents': maxEvents},
    );
    if (result == null) return [];
    return result
        .map((e) => _parseEvent(e as Map<dynamic, dynamic>))
        .toList();
  } on PlatformException catch (e) {
    debugPrint('pollEvents error: ${e.message}');
    return [];
  }
}
