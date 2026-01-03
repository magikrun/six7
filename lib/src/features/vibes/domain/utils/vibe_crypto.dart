import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Cryptographic utilities for the vibes matching system.
/// 
/// Privacy Model:
/// 1. When A vibes B, A generates a random secret and creates commitment = SHA256(secret)
/// 2. A sends the commitment to B (B can't derive secret from it - preimage resistance)
/// 3. If B also vibes A, B generates secretB and sends commitment = SHA256(secretB) to A
/// 4. Both send their secrets: A sends secretA to B, B sends secretB to A
/// 5. Both can verify: SHA256(receivedSecret) == receivedCommitment
/// 6. Only if both steps complete → match revealed
/// 
/// SECURITY: Uses SHA-256 for commitments. Secrets are 32 bytes of random data.
class VibeCrypto {
  VibeCrypto._();

  /// Size of the random secret in bytes.
  static const int _secretLength = 32;

  /// Generates a random secret for a vibe commitment.
  /// Returns hex-encoded 32 bytes from secure random source.
  static String generateSecret() {
    final random = Random.secure();
    final bytes = Uint8List(_secretLength);
    for (var i = 0; i < _secretLength; i++) {
      bytes[i] = random.nextInt(256);
    }
    return _bytesToHex(bytes);
  }

  /// Creates a commitment hash from a secret using SHA-256.
  /// 
  /// SECURITY: SHA-256 provides:
  /// - Preimage resistance: Can't derive secret from commitment
  /// - Collision resistance: Can't find two secrets with same commitment
  static String createCommitment(String secretHex) {
    final secretBytes = _hexToBytes(secretHex);
    final digest = sha256.convert(secretBytes);
    return digest.toString();
  }

  /// Verifies that a secret matches a commitment.
  /// Uses constant-time comparison to prevent timing attacks.
  static bool verifyCommitment(String secretHex, String commitmentHex) {
    final computed = createCommitment(secretHex);
    // Constant-time comparison
    if (computed.length != commitmentHex.length) return false;
    var result = 0;
    for (var i = 0; i < computed.length; i++) {
      result |= computed.codeUnitAt(i) ^ commitmentHex.codeUnitAt(i);
    }
    return result == 0;
  }

  /// Creates a match token that both parties can compute independently.
  /// This proves both parties know each other's secrets.
  /// 
  /// matchToken = SHA256(sort([secretA, secretB]).join())
  static String createMatchToken(String secret1Hex, String secret2Hex) {
    // Sort to ensure same result regardless of order
    final sorted = [secret1Hex, secret2Hex]..sort();
    final combined = sorted.join('');
    return createCommitment(combined);
  }

  /// Converts bytes to hex string.
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Converts hex string to bytes.
  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

/// Payload structure for vibe messages.
/// Serialized as JSON for transmission.
class VibePayload {
  const VibePayload({
    required this.type,
    required this.vibeId,
    this.commitment,
    this.secret,
  });

  /// Type of vibe message.
  final VibeMessageType type;

  /// Unique ID for this vibe exchange.
  final String vibeId;

  /// Commitment hash (for initial vibe).
  final String? commitment;

  /// Secret reveal (for match confirmation).
  final String? secret;

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'vibeId': vibeId,
    if (commitment != null) 'commitment': commitment,
    if (secret != null) 'secret': secret,
  };

  factory VibePayload.fromJson(Map<String, dynamic> json) {
    return VibePayload(
      type: VibeMessageType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => VibeMessageType.commitment,
      ),
      vibeId: json['vibeId'] as String,
      commitment: json['commitment'] as String?,
      secret: json['secret'] as String?,
    );
  }

  String encode() => jsonEncode(toJson());

  static VibePayload? decode(String text) {
    try {
      return VibePayload.fromJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[VibeCrypto] Failed to decode payload: $e');
      return null;
    }
  }
}

/// Types of vibe messages.
enum VibeMessageType {
  /// Initial vibe with commitment hash.
  commitment,
  /// Secret reveal for match confirmation.
  reveal,
}
