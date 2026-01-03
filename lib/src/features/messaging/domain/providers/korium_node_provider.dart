import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:six7_chat/src/core/storage/identity_storage.dart';
import 'package:six7_chat/src/features/messaging/domain/providers/presence_provider.dart';
import 'package:six7_chat/src/korium/korium_bridge.dart';

/// Polling configuration for the Korium node.
/// Bootstrap is now handled automatically by the korium Rust library.
class PollingConfig {
  const PollingConfig._();

  /// Event polling interval in milliseconds.
  static const int pollIntervalMs = 500;

  /// Maximum events to poll per interval.
  static const int maxEventsPerPoll = 50;
}

/// State representing the Korium node connection status.
sealed class KoriumNodeState {
  const KoriumNodeState();
}

class KoriumNodeDisconnected extends KoriumNodeState {
  const KoriumNodeDisconnected();
}

class KoriumNodeConnecting extends KoriumNodeState {
  const KoriumNodeConnecting();
}

class KoriumNodeConnected extends KoriumNodeState {
  const KoriumNodeConnected({
    required this.identity,
    required this.localAddr,
    this.isBootstrapped = false,
    this.bootstrapError,
  });

  final String identity;
  final String localAddr;
  final bool isBootstrapped;
  final String? bootstrapError;
}

class KoriumNodeError extends KoriumNodeState {
  const KoriumNodeError(this.message);
  final String message;
}

/// Provider for the Korium node wrapper.
final koriumNodeProvider =
    AsyncNotifierProvider<KoriumNodeNotifier, KoriumNode>(
  KoriumNodeNotifier.new,
);

/// Provider for the node connection state (for UI).
/// Shows identity immediately, STUN address updates in background.
final koriumNodeStateProvider = Provider<KoriumNodeState>((ref) {
  final nodeAsync = ref.watch(koriumNodeProvider);
  final isBootstrapped = ref.watch(bootstrapStateProvider);
  final bootstrapError = ref.watch(bootstrapErrorProvider);
  
  // Watch the bootstrap event listener to ensure it's active
  ref.watch(_bootstrapEventListenerProvider);

  return nodeAsync.when(
    loading: () => const KoriumNodeConnecting(),
    error: (e, _) => KoriumNodeError(e.toString()),
    data: (node) => KoriumNodeConnected(
      identity: node.identity,
      // Use local_addr - korium handles routable address discovery internally
      localAddr: node.localAddr,
      isBootstrapped: isBootstrapped,
      bootstrapError: bootstrapError,
    ),
  );
});

/// Provider for the local address.
/// Korium handles routable address discovery internally via bootstrap_public().
final localAddressProvider = Provider<String?>((ref) {
  final nodeAsync = ref.watch(koriumNodeProvider);
  return nodeAsync.whenOrNull(
    data: (node) => node.localAddr,
  );
});

/// State notifier for tracking bootstrap status.
class BootstrapStateNotifier extends Notifier<bool> {
  @override
  bool build() => false;
  
  void setBootstrapped(bool value) {
    debugPrint('[BootstrapStateNotifier] Setting bootstrapped: $value');
    state = value;
  }
}

/// Provider for tracking bootstrap status.
/// Exposed publicly so NotificationListener can update it when bootstrap completes.
final bootstrapStateProvider = NotifierProvider<BootstrapStateNotifier, bool>(
  BootstrapStateNotifier.new,
);

/// Provider that listens to bootstrap events and updates state.
/// This must be eagerly watched to ensure events are processed.
final _bootstrapEventListenerProvider = Provider<void>((ref) {
  debugPrint('[BootstrapEventListener] Starting...');
  
  ref.listen(koriumEventStreamProvider, (previous, next) {
    next.whenData((event) {
      debugPrint('[BootstrapEventListener] Got event: ${event.runtimeType}');
      if (event is KoriumEvent_BootstrapComplete && event.success) {
        debugPrint('[BootstrapEventListener] Bootstrap success! Updating state.');
        ref.read(bootstrapStateProvider.notifier).setBootstrapped(true);
      }
    });
  });
});

/// Provider for bootstrap error message.
final bootstrapErrorProvider = Provider<String?>((ref) {
  final nodeAsync = ref.watch(koriumNodeProvider);
  return nodeAsync.whenOrNull(
    data: (node) => node.bootstrapError,
  );
});

/// Stream of Korium events from polling.
/// Components can listen to this to receive incoming messages.
final koriumEventStreamProvider = StreamProvider<KoriumEvent>((ref) async* {
  debugPrint('[EventStream] Provider starting...');
  
  // Watch node provider - will restart stream when node changes
  final nodeAsync = ref.watch(koriumNodeProvider);
  
  // Get the node - if not ready, exit early (provider will restart when node is available)
  final node = nodeAsync.value;
  if (node == null) {
    debugPrint('[EventStream] Node not ready, waiting...');
    // Node not ready yet - the watch will cause a rebuild when it is
    return;
  }

  debugPrint('[EventStream] Node ready, starting poll loop');

  // SECURITY: Cancellation flag to ensure polling loop terminates on dispose.
  // This prevents zombie polling loops from continuing after provider disposal.
  var isCancelled = false;
  ref.onDispose(() {
    debugPrint('[EventStream] Disposing...');
    isCancelled = true;
  });

  // Poll for events at regular intervals
  while (!isCancelled) {
    await Future<void>.delayed(
      const Duration(milliseconds: PollingConfig.pollIntervalMs),
    );

    // Check cancellation after delay to exit quickly on dispose
    if (isCancelled) break;

    try {
      final events = await pollEvents(
        maxEvents: PollingConfig.maxEventsPerPoll,
      );

      for (final event in events) {
        debugPrint('[EventStream] Yielding event: ${event.runtimeType}');
        yield event;
      }
    } catch (e) {
      // Log but continue polling (only in debug mode)
      debugPrint('Event polling error: $e');
    }
  }
});

/// Provider for checking if a specific peer is online.
/// 
/// This provider first checks the real-time presence system (heartbeats).
/// If presence is unknown, it falls back to DHT resolution.
/// 
/// For UI components, prefer using `isPeerOnlineProvider` from presence_provider.dart
/// for real-time updates. This provider is useful for one-time checks.
final peerOnlineStatusProvider =
    FutureProvider.family<bool, String>((ref, peerId) async {
  // First check presence system for real-time status
  // Import presence provider dynamically to avoid circular dependency
  final presenceState = ref.watch(presenceProvider);
  final presence = presenceState.peerPresence[peerId.toLowerCase()];
  
  if (presence != null && presence.status == PresenceStatus.online) {
    return true;
  }
  
  // Fall back to DHT resolution if presence unknown
  final nodeAsync = ref.watch(koriumNodeProvider);

  return nodeAsync.when(
    data: (node) async {
      try {
        return await node.isPeerOnline(peerId: peerId);
      } catch (_) {
        return false;
      }
    },
    loading: () async => false,
    error: (_, stackTrace) async => false,
  );
});

class KoriumNodeNotifier extends AsyncNotifier<KoriumNode> {
  Timer? _pollTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  Future<KoriumNode> build() async {
    // Load identity from secure storage (if exists)
    final storage = ref.read(identityStorageProvider);
    final savedIdentity = await storage.loadIdentity();
    
    KoriumNode node;
    
    if (savedIdentity != null && savedIdentity.hasRestoreData) {
      // FAST PATH: Restore existing identity (skips PoW - instant)
      debugPrint('Restoring saved identity: ${savedIdentity.identity}');
      final config = NodeConfig(
        privateKeyHex: savedIdentity.privateKeyHex,
        identityProofNonce: savedIdentity.powNonce,
      );
      node = await KoriumNode.createWithConfig(config: config);
    } else {
      // SLOW PATH: Generate new identity with PoW (~1-4 seconds)
      debugPrint('Generating new identity with PoW (this may take a few seconds)...');
      node = await KoriumNode.create();
      
      // Save the new identity for next launch
      final restoreData = node.getIdentityRestoreData();
      if (restoreData != null) {
        debugPrint('Saving new identity for future restores: ${node.identity}');
        await storage.saveIdentity(
          StoredIdentity(
            privateKeyHex: restoreData.secretKeyHex,
            publicKeyHex: node.identity,
            powNonce: restoreData.powNonce,
          ),
        );
      }
    }

    // Start message listeners for incoming messages
    await node.startListeners();

    // Log bootstrap status
    debugPrint('Node created - identity: ${node.identity}');
    debugPrint('Node created - localAddr: ${node.localAddr}');
    debugPrint('Node created - isBootstrapped: ${node.isBootstrapped}');
    if (node.bootstrapError != null) {
      debugPrint('Node created - bootstrapError: ${node.bootstrapError}');
    }

    // Update bootstrap state from Rust (bootstrap happens during create())
    if (node.isBootstrapped) {
      ref.read(bootstrapStateProvider.notifier).setBootstrapped(true);
    }

    // Start network connectivity listener for logging
    _startConnectivityListener(node);

    // Clean up on dispose
    ref.onDispose(() {
      _pollTimer?.cancel();
      _connectivitySubscription?.cancel();
      node.shutdown();
    });

    return node;
  }

  /// Starts listening for network connectivity changes.
  /// Logs connectivity changes for debugging (korium handles reconnection internally).
  void _startConnectivityListener(KoriumNode node) {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        // Skip if no connectivity
        if (results.isEmpty || results.contains(ConnectivityResult.none)) {
          debugPrint('Connectivity: offline');
          return;
        }

        debugPrint('Connectivity changed: $results');
        // Korium handles reconnection and address discovery internally via bootstrap_public()
      },
      onError: (error) {
        debugPrint('Connectivity listener error: $error');
      },
    );
  }

  /// Bootstraps to a specific peer (for manual connection).
  Future<void> bootstrap(String peerIdentity, List<String> peerAddrs) async {
    final node = await future;
    await node.bootstrap(peerIdentity: peerIdentity, peerAddrs: peerAddrs);
    ref.read(bootstrapStateProvider.notifier).setBootstrapped(true);
  }

  /// Publishes custom addresses (e.g., external IP).
  Future<void> publishAddress(List<String> addresses) async {
    final node = await future;
    await node.publishAddress(addresses: addresses);
  }

  /// Checks if a peer is online/reachable.
  Future<bool> isPeerOnline(String peerId) async {
    final node = await future;
    return node.isPeerOnline(peerId: peerId);
  }

  /// Resolves a peer's addresses.
  Future<List<String>> resolvePeer(String peerId) async {
    final node = await future;
    return node.resolvePeer(peerId: peerId);
  }

  Future<void> subscribe(String topic) async {
    final node = await future;
    await node.subscribe(topic: topic);
  }

  Future<void> publish(String topic, List<int> data) async {
    final node = await future;
    await node.publish(topic: topic, data: data);
  }

  Future<List<int>> sendRequest(String peerId, List<int> data) async {
    final node = await future;
    return node.sendRequest(peerId: peerId, data: data);
  }
}

