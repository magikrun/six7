import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Abuse report data model.
/// 
/// Contains all the cryptographic proof needed to verify that a message
/// was authentically sent by the reported sender. Can be verified by
/// anyone with the six7-verify tool.
class AbuseReport {
  const AbuseReport({
    required this.version,
    required this.generatedAt,
    required this.senderIdentity,
    required this.senderDisplayName,
    required this.messageId,
    required this.timestampMs,
    required this.reportedContent,
    required this.frankingTag,
    required this.frankingKey,
    required this.keyCommitment,
    required this.reporterIdentity,
    this.groupId,
    this.groupName,
    this.contextMessageIds,
    this.statement,
  });

  /// Report format version.
  final String version;

  /// When the report was generated.
  final DateTime generatedAt;

  /// Ed25519 public key hex of the reported sender.
  final String senderIdentity;

  /// Display name of the sender (for human readability).
  final String senderDisplayName;

  /// Unique message identifier.
  final String messageId;

  /// Message timestamp (Unix milliseconds).
  final int timestampMs;

  /// The reported message content.
  final String reportedContent;

  /// HMAC(Kf, plaintext) - the franking tag.
  final Uint8List frankingTag;

  /// The revealed franking key (Kf).
  final Uint8List frankingKey;

  /// HMAC(Kf, ciphertext) - key commitment.
  final Uint8List keyCommitment;

  /// Ed25519 public key hex of the reporter.
  final String reporterIdentity;

  /// Group ID if this was a group message.
  final String? groupId;

  /// Group name if this was a group message.
  final String? groupName;

  /// Surrounding message IDs for context.
  final List<String>? contextMessageIds;

  /// Optional statement from the reporter.
  final String? statement;

  /// Encodes to JSON.
  Map<String, dynamic> toJson() => {
        'version': version,
        'type': 'six7-abuse-report',
        'generated_at': generatedAt.toIso8601String(),
        'sender': {
          'identity': senderIdentity,
          'display_name': senderDisplayName,
        },
        'message': {
          'id': messageId,
          'timestamp_ms': timestampMs,
          'content_type': 'text/plain',
          'reported_content': reportedContent,
        },
        'franking_proof': {
          'tag': base64Encode(frankingTag),
          'key': base64Encode(frankingKey),
          'key_commitment': base64Encode(keyCommitment),
        },
        'context': {
          'reporter_identity': reporterIdentity,
          if (groupId != null) 'group_id': groupId,
          if (groupName != null) 'group_name': groupName,
          if (contextMessageIds != null)
            'surrounding_message_ids': contextMessageIds,
        },
        if (statement != null) 'reporter_statement': statement,
      };

  /// Encodes to pretty-printed JSON string.
  String toJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  /// Creates a verification summary (for display).
  String get verificationSummary {
    final buffer = StringBuffer();
    buffer.writeln('Six7 Abuse Report');
    buffer.writeln('=' * 40);
    buffer.writeln();
    buffer.writeln('Sender:    $senderIdentity');
    buffer.writeln('           ($senderDisplayName)');
    buffer.writeln('Message:   $messageId');
    buffer.writeln(
        'Time:      ${DateTime.fromMillisecondsSinceEpoch(timestampMs)}');
    if (groupName != null) {
      buffer.writeln('Group:     $groupName');
    }
    buffer.writeln();
    buffer.writeln('This report contains cryptographic proof that');
    buffer.writeln('the content was authentically sent by the sender.');
    return buffer.toString();
  }

  /// Verifies the franking proof.
  /// Returns null if valid, error message if invalid.
  String? verify() {
    // Compute expected tag
    final plaintext = utf8.encode(reportedContent);
    final hmac = Hmac(sha256, frankingKey);
    final computed = hmac.convert(plaintext);

    // Compare tags
    if (!_constantTimeEquals(computed.bytes, frankingTag)) {
      return 'Franking tag does not match plaintext (possible fabrication)';
    }

    return null; // Valid
  }

  bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }
}

/// Verification result for an abuse report.
class VerificationResult {
  const VerificationResult({
    required this.isValid,
    this.error,
  });

  final bool isValid;
  final String? error;

  factory VerificationResult.valid() => const VerificationResult(isValid: true);

  factory VerificationResult.invalid(String error) =>
      VerificationResult(isValid: false, error: error);
}
