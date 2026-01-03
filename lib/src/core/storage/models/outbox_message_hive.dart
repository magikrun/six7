import 'package:hive/hive.dart';
import 'package:six7_chat/src/core/storage/models/chat_message_hive.dart';

/// Hive type ID for outbox messages - uses centralized HiveTypeIds to prevent collisions.
/// @deprecated Use HiveTypeIds.outboxMessage instead. Kept for adapter registration compatibility.
const int hiveTypeIdOutboxMessage = HiveTypeIds.outboxMessage;

/// Maximum retry attempts before marking as permanently failed.
/// SECURITY: Bounded to prevent infinite retry loops.
const int maxOutboxRetryAttempts = 10;

/// Base delay for exponential backoff in milliseconds.
/// Retry schedule: 5s, 10s, 20s, 40s, 80s, 160s, 320s, 640s, 1280s, 2560s
const int outboxBaseDelayMs = 5000;

/// Maximum delay cap in milliseconds (30 minutes).
const int outboxMaxDelayMs = 30 * 60 * 1000;

/// Per-peer outbox limit to prevent unbounded growth.
/// SECURITY: Enforced to prevent memory exhaustion attacks.
const int maxOutboxMessagesPerPeer = 100;

/// Hive-compatible outbox message model for sender-side buffering.
/// 
/// Messages are queued here when:
/// - Recipient is offline
/// - Network is unavailable
/// - Send attempt failed
/// 
/// The outbox processor periodically retries delivery with exponential backoff.
@HiveType(typeId: hiveTypeIdOutboxMessage)
class OutboxMessageHive extends HiveObject {
  OutboxMessageHive({
    required this.messageId,
    required this.recipientId,
    required this.text,
    required this.createdAtMs,
    required this.nextRetryAtMs,
    this.attemptCount = 0,
    this.lastErrorMessage,
  });

  /// Reference to the ChatMessage ID in the messages box.
  @HiveField(0)
  String messageId;

  /// Target peer identity (Ed25519 public key hex).
  @HiveField(1)
  String recipientId;

  /// Message text (duplicated for quick access during retry).
  @HiveField(2)
  String text;

  /// When the message was first queued (ms since epoch).
  @HiveField(3)
  int createdAtMs;

  /// When to attempt the next retry (ms since epoch).
  @HiveField(4)
  int nextRetryAtMs;

  /// Number of delivery attempts made.
  @HiveField(5)
  int attemptCount;

  /// Last error message from failed delivery attempt.
  @HiveField(6)
  String? lastErrorMessage;

  /// Calculates the next retry delay using exponential backoff with jitter.
  /// 
  /// Formula: min(baseDelay * 2^attempts + jitter, maxDelay)
  static int calculateNextRetryDelay(int attemptCount) {
    // Exponential backoff: 5s, 10s, 20s, 40s, ...
    final exponentialDelay = outboxBaseDelayMs * (1 << attemptCount);
    
    // Cap at maximum delay
    final cappedDelay = exponentialDelay.clamp(outboxBaseDelayMs, outboxMaxDelayMs);
    
    // Add jitter (±20%) to prevent thundering herd
    final jitterRange = (cappedDelay * 0.2).toInt();
    final jitter = (DateTime.now().millisecondsSinceEpoch % (jitterRange * 2)) - jitterRange;
    
    return cappedDelay + jitter;
  }

  /// Whether this message has exceeded maximum retry attempts.
  bool get isPermanentlyFailed => attemptCount >= maxOutboxRetryAttempts;

  /// Whether this message is ready for retry.
  bool get isReadyForRetry => 
      !isPermanentlyFailed && 
      DateTime.now().millisecondsSinceEpoch >= nextRetryAtMs;

  /// Updates retry metadata after a failed attempt.
  void recordFailedAttempt(String errorMessage) {
    attemptCount++;
    lastErrorMessage = errorMessage;
    
    if (!isPermanentlyFailed) {
      final delay = calculateNextRetryDelay(attemptCount);
      nextRetryAtMs = DateTime.now().millisecondsSinceEpoch + delay;
    }
  }
}

/// Manual Hive adapter for OutboxMessageHive.
/// (hive_generator incompatible with freezed 3.x)
class OutboxMessageHiveAdapter extends TypeAdapter<OutboxMessageHive> {
  @override
  final int typeId = hiveTypeIdOutboxMessage;

  @override
  OutboxMessageHive read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OutboxMessageHive(
      messageId: fields[0] as String,
      recipientId: fields[1] as String,
      text: fields[2] as String,
      createdAtMs: fields[3] as int,
      nextRetryAtMs: fields[4] as int,
      attemptCount: fields[5] as int? ?? 0,
      lastErrorMessage: fields[6] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, OutboxMessageHive obj) {
    writer
      ..writeByte(7)
      ..writeByte(0)
      ..write(obj.messageId)
      ..writeByte(1)
      ..write(obj.recipientId)
      ..writeByte(2)
      ..write(obj.text)
      ..writeByte(3)
      ..write(obj.createdAtMs)
      ..writeByte(4)
      ..write(obj.nextRetryAtMs)
      ..writeByte(5)
      ..write(obj.attemptCount)
      ..writeByte(6)
      ..write(obj.lastErrorMessage);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboxMessageHiveAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
