import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:six7_chat/src/core/constants/app_constants.dart';

/// Keys for secure storage.
abstract class SecureStorageKeys {
  static const String keypairPrivate = 'korium_keypair_private';
  static const String keypairPublic = 'korium_keypair_public';
  static const String powNonce = 'korium_pow_nonce';
  static const String displayName = 'korium_display_name';
  static const String namespaceSecret = 'korium_namespace_secret';
}

/// Provider for the identity storage service.
final identityStorageProvider = Provider<IdentityStorage>((ref) {
  return IdentityStorage();
});

/// Stored identity data.
class StoredIdentity {
  const StoredIdentity({
    required this.privateKeyHex,
    required this.publicKeyHex,
    this.powNonce,
    this.displayName,
    this.namespaceSecretHex,
  });

  factory StoredIdentity.fromJson(Map<String, dynamic> json) => StoredIdentity(
        privateKeyHex: json['privateKeyHex'] as String,
        publicKeyHex: json['publicKeyHex'] as String,
        // SECURITY: powNonce is stored as hex string (16 chars) to match native format.
        // Native (Kotlin/Swift) returns nonceHex as 16-char hex string.
        // Parse with radix 16 for consistency across all code paths.
        powNonce: json['powNonce'] != null
            ? BigInt.parse(json['powNonce'].toString(), radix: 16)
            : null,
        displayName: json['displayName'] as String?,
        namespaceSecretHex: json['namespaceSecretHex'] as String?,
      );

  /// Ed25519 secret key (32 bytes = 64 hex chars).
  /// NOTE: This is the 32-byte seed, not the 64-byte expanded key.
  final String privateKeyHex;

  /// Ed25519 public key / identity (32 bytes = 64 hex chars)
  final String publicKeyHex;

  /// PoW nonce for identity restoration (u64).
  /// Required to skip PoW on subsequent app launches.
  final BigInt? powNonce;

  /// Optional display name
  final String? displayName;

  /// Optional namespace secret for isolated networks
  final String? namespaceSecretHex;

  /// Expected length of secret key in hex (32 bytes = 64 hex chars)
  static const int privateKeyHexLength = 64;

  /// Returns the identity (public key) in standard format.
  String get identity => publicKeyHex;

  /// Validates the identity format.
  /// SECURITY: Validates both public and private key format and length.
  bool get isValid {
    final validPublicKey =
        publicKeyHex.length == AppConstants.identityHexLength &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(publicKeyHex);
    final validPrivateKey =
        privateKeyHex.length == privateKeyHexLength &&
        RegExp(r'^[0-9a-fA-F]+$').hasMatch(privateKeyHex);
    return validPublicKey && validPrivateKey;
  }

  /// Returns true if this identity has PoW data for restoration.
  bool get hasRestoreData => powNonce != null;

  Map<String, dynamic> toJson() => {
        'privateKeyHex': privateKeyHex,
        'publicKeyHex': publicKeyHex,
        // SECURITY: Store powNonce as hex string (padded to 16 chars) to match native format
        'powNonce': powNonce?.toRadixString(16).padLeft(16, '0'),
        'displayName': displayName,
        'namespaceSecretHex': namespaceSecretHex,
      };
}

/// Service for securely storing the user's Korium identity (keypair).
/// Uses flutter_secure_storage for encryption at rest.
class IdentityStorage {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  /// Checks if an identity has been stored.
  Future<bool> hasIdentity() async {
    final publicKey = await _storage.read(key: SecureStorageKeys.keypairPublic);
    return publicKey != null && publicKey.length == AppConstants.identityHexLength;
  }

  /// Saves the identity (keypair) to secure storage.
  ///
  /// # Security
  /// - Private key is encrypted at rest using platform secure storage
  /// - On iOS: Keychain with first_unlock_this_device accessibility
  /// - On Android: EncryptedSharedPreferences backed by AndroidKeyStore
  Future<void> saveIdentity(StoredIdentity identity) async {
    // Validate before saving
    if (!identity.isValid) {
      throw ArgumentError('Invalid identity: public key must be ${AppConstants.identityHexLength} hex chars');
    }

    await Future.wait([
      _storage.write(
        key: SecureStorageKeys.keypairPrivate,
        value: identity.privateKeyHex,
      ),
      _storage.write(
        key: SecureStorageKeys.keypairPublic,
        value: identity.publicKeyHex,
      ),
      if (identity.powNonce != null)
        _storage.write(
          key: SecureStorageKeys.powNonce,
          value: identity.powNonce.toString(),
        ),
      if (identity.displayName != null)
        _storage.write(
          key: SecureStorageKeys.displayName,
          value: identity.displayName,
        ),
      if (identity.namespaceSecretHex != null)
        _storage.write(
          key: SecureStorageKeys.namespaceSecret,
          value: identity.namespaceSecretHex,
        ),
    ]);
  }

  /// Loads the identity from secure storage.
  /// Returns null if no identity is stored.
  Future<StoredIdentity?> loadIdentity() async {
    final results = await Future.wait([
      _storage.read(key: SecureStorageKeys.keypairPrivate),
      _storage.read(key: SecureStorageKeys.keypairPublic),
      _storage.read(key: SecureStorageKeys.powNonce),
      _storage.read(key: SecureStorageKeys.displayName),
      _storage.read(key: SecureStorageKeys.namespaceSecret),
    ]);

    final privateKey = results[0];
    final publicKey = results[1];
    final powNonceStr = results[2];

    if (privateKey == null || publicKey == null) {
      return null;
    }

    return StoredIdentity(
      privateKeyHex: privateKey,
      publicKeyHex: publicKey,
      powNonce: powNonceStr != null ? BigInt.parse(powNonceStr) : null,
      displayName: results[3],
      namespaceSecretHex: results[4],
    );
  }

  /// Updates the display name.
  Future<void> updateDisplayName(String displayName) async {
    await _storage.write(
      key: SecureStorageKeys.displayName,
      value: displayName,
    );
  }

  /// Deletes all stored identity data.
  /// WARNING: This will permanently delete the keypair!
  Future<void> deleteIdentity() async {
    await Future.wait([
      _storage.delete(key: SecureStorageKeys.keypairPrivate),
      _storage.delete(key: SecureStorageKeys.keypairPublic),
      _storage.delete(key: SecureStorageKeys.powNonce),
      _storage.delete(key: SecureStorageKeys.displayName),
      _storage.delete(key: SecureStorageKeys.namespaceSecret),
    ]);
  }

  /// Exports the identity as a JSON string for backup.
  /// WARNING: Handle with extreme care - contains private key!
  Future<String?> exportIdentity() async {
    final identity = await loadIdentity();
    if (identity == null) return null;
    return jsonEncode(identity.toJson());
  }

  /// Imports an identity from a JSON backup string.
  /// 
  /// Throws [FormatException] if the JSON is malformed.
  /// Throws [ArgumentError] if the identity data is invalid.
  Future<void> importIdentity(String jsonString) async {
    // SECURITY: Validate JSON format before processing
    final dynamic decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException catch (e) {
      throw FormatException('Invalid JSON format: ${e.message}');
    }
    
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup format: expected JSON object');
    }
    
    // Validate required fields exist
    if (!decoded.containsKey('privateKeyHex') || !decoded.containsKey('publicKeyHex')) {
      throw const FormatException('Missing required fields: privateKeyHex and publicKeyHex');
    }
    
    final identity = StoredIdentity.fromJson(decoded);
    
    // Validate the identity before saving
    if (!identity.isValid) {
      throw ArgumentError(
        'Invalid identity data: keys must be valid hexadecimal '
        '(public: ${AppConstants.identityHexLength} chars, '
        'private: ${StoredIdentity.privateKeyHexLength} chars)',
      );
    }
    
    await saveIdentity(identity);
  }
}
