import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/models/models.dart';
import 'package:six7_chat/src/core/storage/storage_service.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/korium_node_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart' as korium;

/// Minimum interval between outbox processing cycles.
/// SECURITY: Prevents busy-loop CPU exhaustion.
const Duration _minProcessInterval = Duration(seconds: 5);

/// Maximum concurrent retry attempts.
/// SECURITY: Limits parallel network requests.
const int _maxConcurrentRetries = 3;

/// Provider for the outbox processor.
final outboxProvider = NotifierProvider<OutboxNotifier, OutboxState>(() {
  return OutboxNotifier();
});

/// Provider for outbox count (for UI badge).
final outboxCountProvider = Provider<int>((ref) {
  final state = ref.watch(outboxProvider);
  return state.totalPending;
});

/// Provider for outbox count for a specific peer.
final outboxCountForPeerProvider = Provider.family<int, String>((ref, peerId) {
  // Watch outbox state to trigger rebuilds
  final outboxState = ref.watch(outboxProvider);
  // If outbox isn't ready yet, return 0
  if (outboxState.totalPending == 0) return 0;
  
  try {
    final storage = ref.read(storageServiceProvider);
    return storage.getOutboxCountForPeer(peerId);
  } catch (_) {
    // Storage not ready yet
    return 0;
  }
});

/// State of the outbox processor.
class OutboxState {
  const OutboxState({
    this.totalPending = 0,
    this.isProcessing = false,
    this.lastProcessedAt,
    this.currentlyRetrying = const {},
  });

  /// Total messages waiting to be sent.
  final int totalPending;

  /// Whether the processor is currently running.
  final bool isProcessing;

  /// When the outbox was last processed.
  final DateTime? lastProcessedAt;

  /// Message IDs currently being retried.
  final Set<String> currentlyRetrying;

  OutboxState copyWith({
    int? totalPending,
    bool? isProcessing,
    DateTime? lastProcessedAt,
    Set<String>? currentlyRetrying,
  }) {
    return OutboxState(
      totalPending: totalPending ?? this.totalPending,
      isProcessing: isProcessing ?? this.isProcessing,
      lastProcessedAt: lastProcessedAt ?? this.lastProcessedAt,
      currentlyRetrying: currentlyRetrying ?? this.currentlyRetrying,
    );
  }
}

/// Manages the outbox queue and retry logic.
class OutboxNotifier extends Notifier<OutboxState> {
  Timer? _processTimer;
  bool _isDisposed = false;

  StorageService get _storage => ref.read(storageServiceProvider);

  @override
  OutboxState build() {
    // Clean up on dispose
    ref.onDispose(() {
      _isDisposed = true;
      _processTimer?.cancel();
    });

    // Return initial state with current count
    final initialState = OutboxState(
      totalPending: _storage.getOutboxCount(),
    );

    // Start the background processor after a microtask delay
    // to avoid reading state before build() completes
    Future.microtask(() {
      if (!_isDisposed) {
        _startProcessor();
      }
    });

    return initialState;
  }

  /// Starts the background outbox processor.
  void _startProcessor() {
    // Process immediately on startup
    _processOutbox();

    // Then periodically check for messages ready to retry
    _processTimer = Timer.periodic(_minProcessInterval, (_) {
      if (!_isDisposed) {
        _processOutbox();
      }
    });
  }

  /// Adds a message to the outbox for retry.
  Future<void> addToOutbox({
    required String messageId,
    required String recipientId,
    required String text,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final outboxMessage = OutboxMessageHive(
      messageId: messageId,
      recipientId: recipientId,
      text: text,
      createdAtMs: now,
      nextRetryAtMs: now + outboxBaseDelayMs, // First retry after base delay
    );

    await _storage.addToOutbox(outboxMessage);
    
    state = state.copyWith(
      totalPending: _storage.getOutboxCount(),
    );

    debugPrint('📤 Added message $messageId to outbox for $recipientId');
  }

  /// Removes a message from the outbox (after successful delivery).
  Future<void> removeFromOutbox(String messageId) async {
    await _storage.removeFromOutbox(messageId);
    
    state = state.copyWith(
      totalPending: _storage.getOutboxCount(),
      currentlyRetrying: {...state.currentlyRetrying}..remove(messageId),
    );

    debugPrint('✅ Removed message $messageId from outbox');
  }

  /// Manually triggers outbox processing.
  Future<void> processNow() async {
    await _processOutbox();
  }

  /// Processes all messages ready for retry.
  Future<void> _processOutbox() async {
    if (state.isProcessing || _isDisposed) return;

    final readyMessages = _storage.getOutboxMessagesReadyForRetry();
    if (readyMessages.isEmpty) return;

    state = state.copyWith(isProcessing: true);

    try {
      // Process in batches to limit concurrency
      for (var i = 0; i < readyMessages.length; i += _maxConcurrentRetries) {
        if (_isDisposed) break;

        final batch = readyMessages.skip(i).take(_maxConcurrentRetries);
        await Future.wait(
          batch.map((msg) => _retryMessage(msg)),
          eagerError: false, // Continue even if one fails
        );
      }
    } finally {
      if (!_isDisposed) {
        state = state.copyWith(
          isProcessing: false,
          lastProcessedAt: DateTime.now(),
          totalPending: _storage.getOutboxCount(),
        );
      }
    }
  }

  /// Retries sending a single message.
  Future<void> _retryMessage(OutboxMessageHive outboxMsg) async {
    if (_isDisposed) return;
    if (state.currentlyRetrying.contains(outboxMsg.messageId)) return;

    state = state.copyWith(
      currentlyRetrying: {...state.currentlyRetrying, outboxMsg.messageId},
    );

    try {
      final nodeAsync = ref.read(koriumNodeProvider);
      
      await nodeAsync.when(
        loading: () async {
          // Node not ready, record failure and retry later
          outboxMsg.recordFailedAttempt('Node not ready');
          await _storage.updateOutboxMessage(outboxMsg);
        },
        error: (e, _) async {
          outboxMsg.recordFailedAttempt('Node error: $e');
          await _storage.updateOutboxMessage(outboxMsg);
        },
        data: (node) async {
          try {
            // Get our identity for the message
            final myId = node.identity;
            
            // Create Korium message for sending
            final koriumMessage = korium.ChatMessage(
              id: outboxMsg.messageId,
              senderId: myId,
              recipientId: outboxMsg.recipientId,
              text: outboxMsg.text,
              messageType: korium.MessageType.text,
              timestampMs: outboxMsg.createdAtMs,
              status: korium.MessageStatus.pending,
              isFromMe: true,
            );

            // Attempt to send
            await node.sendMessage(
              peerId: outboxMsg.recipientId,
              message: koriumMessage,
            );

            // Success! Remove from outbox
            await _storage.removeFromOutbox(outboxMsg.messageId);
            debugPrint('✅ Outbox retry successful: ${outboxMsg.messageId}');

            // Update the message status in main storage
            await _storage.updateMessageStatus(
              outboxMsg.messageId,
              MessageStatusHive.sent,
            );
          } catch (e) {
            // Send failed, record and schedule next retry
            outboxMsg.recordFailedAttempt('Send failed: $e');
            await _storage.updateOutboxMessage(outboxMsg);
            
            if (outboxMsg.isPermanentlyFailed) {
              debugPrint('❌ Message ${outboxMsg.messageId} permanently failed after ${outboxMsg.attemptCount} attempts');
              // Update message status to failed
              await _storage.updateMessageStatus(
                outboxMsg.messageId,
                MessageStatusHive.failed,
              );
            } else {
              final nextRetryIn = Duration(
                milliseconds: outboxMsg.nextRetryAtMs - DateTime.now().millisecondsSinceEpoch,
              );
              debugPrint('🔄 Retry ${outboxMsg.attemptCount}/$maxOutboxRetryAttempts failed for ${outboxMsg.messageId}, next retry in ${nextRetryIn.inSeconds}s');
            }
          }
        },
      );
    } finally {
      if (!_isDisposed) {
        state = state.copyWith(
          currentlyRetrying: {...state.currentlyRetrying}..remove(outboxMsg.messageId),
        );
      }
    }
  }

  /// Clears all permanently failed messages.
  Future<void> clearPermanentlyFailed() async {
    await _storage.clearPermanentlyFailedOutbox();
    state = state.copyWith(
      totalPending: _storage.getOutboxCount(),
    );
  }

  /// Clears outbox for a specific peer.
  Future<void> clearForPeer(String peerId) async {
    await _storage.clearOutboxForPeer(peerId);
    state = state.copyWith(
      totalPending: _storage.getOutboxCount(),
    );
  }
}
