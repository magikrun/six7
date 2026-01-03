import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A pending contact request from another user.
class PendingContactRequest {
  const PendingContactRequest({
    required this.senderId,
    required this.senderName,
    required this.timestamp,
  });

  final String senderId;
  final String senderName;
  final DateTime timestamp;
}

/// Provider for managing pending contact requests.
final pendingContactRequestsProvider =
    NotifierProvider<PendingContactRequestsNotifier, List<PendingContactRequest>>(
  PendingContactRequestsNotifier.new,
);

/// Notifier for pending contact requests.
class PendingContactRequestsNotifier extends Notifier<List<PendingContactRequest>> {
  @override
  List<PendingContactRequest> build() {
    return [];
  }

  /// Adds a new pending contact request.
  void addRequest({
    required String senderId,
    required String senderName,
    required DateTime timestamp,
  }) {
    // Don't add duplicates
    final exists = state.any(
      (r) => r.senderId.toLowerCase() == senderId.toLowerCase(),
    );
    if (exists) return;

    state = [
      PendingContactRequest(
        senderId: senderId,
        senderName: senderName,
        timestamp: timestamp,
      ),
      ...state,
    ];
  }

  /// Removes a pending request (after accept/reject).
  void removeRequest(String senderId) {
    state = state.where(
      (r) => r.senderId.toLowerCase() != senderId.toLowerCase(),
    ).toList();
  }

  /// Clears all pending requests.
  void clearAll() {
    state = [];
  }
}
