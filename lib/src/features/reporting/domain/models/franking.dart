import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Franking tag size in bytes (HMAC-SHA256 output).
const int frankingTagBytes = 32;

/// Franking key size in bytes.
const int frankingKeyBytes = 32;

/// Domain separator for franking operations.
const String frankingDomain = 'six7-franking-v1';

/// Message franking data attached to each outgoing message.
/// 
/// Franking provides cryptographic proof that:
/// 1. The sender authentically sent this content (non-repudiation)
/// 2. The recipient cannot fabricate messages (non-fabrication)
/// 
/// Security model:
/// - Sender generates random Kf (franking key) per message
/// - tag = HMAC(Kf, plaintext) - proves content authenticity
/// - keyCommitment = HMAC(Kf, ciphertext) - binds key to specific message
/// - encryptedKey = Encrypt(Kf, recipient) - only recipient can reveal
class MessageFranking {
  const MessageFranking({
    required this.tag,
    required this.keyCommitment,
    required this.encryptedKey,
  });

  /// HMAC(Kf, plaintext) - proves content authenticity.
  /// When revealed, proves sender sent this exact content.
  final Uint8List tag;

  /// HMAC(Kf, ciphertext) - binds key to this specific message.
  /// Prevents key substitution attacks.
  final Uint8List keyCommitment;

  /// Encrypt(Kf, recipient_pubkey) - only recipient can reveal.
  /// In practice, we use a simplified approach: Kf XOR'd with shared secret.
  final Uint8List encryptedKey;

  /// Total overhead: 32 + 32 + 32 = 96 bytes per message.
  static const int overheadBytes = frankingTagBytes * 3;

  /// Encodes to JSON-compatible map.
  Map<String, String> toJson() => {
        'tag': base64Encode(tag),
        'key_commitment': base64Encode(keyCommitment),
        'encrypted_key': base64Encode(encryptedKey),
      };

  /// Decodes from JSON map.
  factory MessageFranking.fromJson(Map<String, dynamic> json) {
    return MessageFranking(
      tag: base64Decode(json['tag'] as String),
      keyCommitment: base64Decode(json['key_commitment'] as String),
      encryptedKey: base64Decode(json['encrypted_key'] as String),
    );
  }
}

/// Result of franking a message (includes the key for local storage).
class FrankingResult {
  const FrankingResult({
    required this.franking,
    required this.plaintextKey,
  });

  /// The franking data to attach to the message.
  final MessageFranking franking;

  /// The plaintext franking key (store locally, never transmit).
  final Uint8List plaintextKey;
}

/// Service for creating and verifying message franking.
class FrankingService {
  final _random = Random.secure();

  /// Generates random bytes for the franking key.
  Uint8List _generateRandomKey() {
    final key = Uint8List(frankingKeyBytes);
    for (var i = 0; i < frankingKeyBytes; i++) {
      key[i] = _random.nextInt(256);
    }
    return key;
  }

  /// Computes HMAC-SHA256.
  Uint8List _hmac(Uint8List key, Uint8List data) {
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(data);
    return Uint8List.fromList(digest.bytes);
  }

  /// XOR two byte arrays (for simple key encryption).
  Uint8List _xor(Uint8List a, Uint8List b) {
    assert(a.length == b.length);
    final result = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }

  /// Creates franking data for an outgoing message.
  /// 
  /// [plaintext] - The message content as bytes.
  /// [ciphertext] - The encrypted message (for key commitment).
  /// [sharedSecret] - Shared secret with recipient (from key agreement).
  /// 
  /// Returns franking data and the plaintext key (for local storage).
  FrankingResult frank({
    required Uint8List plaintext,
    required Uint8List ciphertext,
    required Uint8List sharedSecret,
  }) {
    // Generate random franking key
    final frankingKey = _generateRandomKey();

    // Compute franking tag: HMAC(Kf, plaintext)
    final tag = _hmac(frankingKey, plaintext);

    // Compute key commitment: HMAC(Kf, ciphertext)
    final keyCommitment = _hmac(frankingKey, ciphertext);

    // Encrypt franking key with shared secret
    // Simple XOR with hash of shared secret (in production, use proper KDF)
    final keyEncryptionKey = _hmac(
      utf8.encode('$frankingDomain:key-encryption') as Uint8List,
      sharedSecret,
    );
    final encryptedKey = _xor(frankingKey, keyEncryptionKey);

    return FrankingResult(
      franking: MessageFranking(
        tag: tag,
        keyCommitment: keyCommitment,
        encryptedKey: encryptedKey,
      ),
      plaintextKey: frankingKey,
    );
  }

  /// Decrypts the franking key using the shared secret.
  Uint8List decryptFrankingKey({
    required Uint8List encryptedKey,
    required Uint8List sharedSecret,
  }) {
    final keyEncryptionKey = _hmac(
      utf8.encode('$frankingDomain:key-encryption') as Uint8List,
      sharedSecret,
    );
    return _xor(encryptedKey, keyEncryptionKey);
  }

  /// Verifies franking on a received message.
  /// 
  /// Returns true if the franking tag matches the plaintext.
  bool verify({
    required Uint8List plaintext,
    required Uint8List frankingTag,
    required Uint8List frankingKey,
  }) {
    final computed = _hmac(frankingKey, plaintext);
    return _constantTimeEquals(computed, frankingTag);
  }

  /// Verifies the key commitment (requires original ciphertext).
  bool verifyKeyCommitment({
    required Uint8List ciphertext,
    required Uint8List keyCommitment,
    required Uint8List frankingKey,
  }) {
    final computed = _hmac(frankingKey, ciphertext);
    return _constantTimeEquals(computed, keyCommitment);
  }

  /// Constant-time comparison to prevent timing attacks.
  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}
