//! Flutter Rust Bridge API for Korium Chat
//!
//! This module defines the public API exposed to Flutter via flutter_rust_bridge.
//! All types and functions here are FFI-safe and can be called from Dart.
//!
//! # Architecture
//! Uses the actor pattern: a single `NodeActor` owns all node state and processes
//! commands sequentially via message passing. This eliminates lock contention.

use crate::actor::NodeHandle;
use crate::error::KoriumError;
use crate::node::NodeWrapper;
use crate::streams::KoriumEvent;
use flutter_rust_bridge::frb;

/// Configuration for creating a new Korium node.
#[frb(dart_metadata = ("freezed"))]
pub struct NodeConfig {
    /// Address to bind to (e.g., "0.0.0.0:0" for random port)
    pub bind_addr: String,

    /// Optional namespace secret for isolated networks (32 bytes hex)
    pub namespace_secret: Option<String>,

    /// Optional private key hex for identity restoration (64 hex chars = 32 bytes).
    /// If provided along with identity_proof_nonce, the node will restore
    /// the existing identity instead of generating a new one with PoW.
    pub private_key_hex: Option<String>,

    /// Optional PoW nonce for identity restoration.
    /// Must be provided together with private_key_hex to skip PoW generation.
    pub identity_proof_nonce: Option<u64>,
}

impl Default for NodeConfig {
    fn default() -> Self {
        Self {
            bind_addr: "0.0.0.0:0".to_string(),
            namespace_secret: None,
            private_key_hex: None,
            identity_proof_nonce: None,
        }
    }
}

/// Identity restoration data for saving to secure storage.
/// 
/// This contains the private key and PoW nonce needed to restore the node's
/// identity on subsequent launches without re-computing PoW.
///
/// # Security
/// This data is HIGHLY SENSITIVE. The `secret_key_hex` is the node's private key.
/// It MUST be stored in secure storage (e.g., iOS Keychain, Android Keystore).
/// Leaking this data allows identity theft.
#[frb(dart_metadata = ("freezed"))]
pub struct IdentityRestoreData {
    /// The secret key as hex (64 hex chars = 32 bytes).
    /// SECURITY: Store encrypted in secure storage only.
    pub secret_key_hex: String,
    /// The PoW nonce for identity restoration.
    pub pow_nonce: u64,
}

/// A peer discovered in the DHT (Distributed Hash Table).
#[derive(Debug, Clone)]
#[frb(dart_metadata = ("freezed"))]
pub struct DhtPeer {
    /// The peer's identity (64 hex chars)
    pub identity: String,
    /// List of addresses where the peer can be reached
    pub addresses: Vec<String>,
}

/// Provides a high-level API for P2P messaging.
///
/// # Architecture
/// Uses the actor pattern internally. The `NodeHandle` sends commands to a
/// background `NodeActor` which owns the actual node state. This eliminates
/// lock contention and provides natural backpressure.
#[frb(opaque)]
pub struct KoriumNode {
    /// Handle to send commands to the NodeActor
    handle: NodeHandle,
    /// Cached identity for fast sync access
    identity: String,
    /// Cached local address for fast sync access
    local_addr: String,
    /// Whether bootstrap succeeded
    is_bootstrapped: std::sync::atomic::AtomicBool,
    /// Bootstrap error message if bootstrap failed
    bootstrap_error: std::sync::Mutex<Option<String>>,
    /// Cached identity data for secure storage (only set at creation).
    /// SECURITY: This is cleared after `get_identity_restore_data()` is called
    /// to minimize exposure window of private key in memory.
    identity_restore_data: std::sync::Mutex<Option<IdentityRestoreData>>,
}

impl KoriumNode {
    /// Creates a new Korium node with default configuration.
    ///
    /// # Arguments
    /// * `bind_addr` - Address to bind to (e.g., "0.0.0.0:0")
    ///
    /// # Returns
    /// A new `KoriumNode` instance.
    ///
    /// # Errors
    /// Returns `KoriumError` if node creation fails.
    pub async fn create(bind_addr: String) -> Result<KoriumNode, KoriumError> {
        let config = NodeConfig {
            bind_addr,
            ..Default::default()
        };
        Self::create_with_config(config).await
    }

    /// Creates a new Korium node with full configuration.
    /// 
    /// Automatically bootstraps to the public Korium network via DNS resolution
    /// of bootstrap.korium.io.
    pub async fn create_with_config(config: NodeConfig) -> Result<KoriumNode, KoriumError> {
        let start_time = std::time::Instant::now();
        
        // STEP 1: Create node
        let wrapper = NodeWrapper::new_with_config(config).await?;
        let identity = wrapper.identity().to_string();
        let local_addr = wrapper.local_addr()?;
        
        // Cache identity restoration data before moving wrapper to actor
        let identity_restore_data = IdentityRestoreData {
            secret_key_hex: wrapper.secret_key_hex(),
            pow_nonce: wrapper.pow_nonce(),
        };

        // Spawn the actor and get a handle
        let handle = NodeHandle::spawn(wrapper);

        // STEP 2: Bootstrap to the public Korium mesh via DNS
        tracing::info!("Bootstrapping via public DNS (bootstrap.korium.io)...");
        let (did_bootstrap, bootstrap_error) = match handle.bootstrap_public().await {
            Ok(external) => {
                tracing::info!("Public bootstrap successful, external addr: {:?}", external);
                (true, None)
            }
            Err(e) => {
                let error_msg = format!("{:?}", e);
                tracing::warn!("Bootstrap failed: {}", error_msg);
                (false, Some(error_msg))
            }
        };

        let node = KoriumNode {
            handle,
            identity,
            local_addr,
            is_bootstrapped: std::sync::atomic::AtomicBool::new(did_bootstrap),
            bootstrap_error: std::sync::Mutex::new(bootstrap_error),
            identity_restore_data: std::sync::Mutex::new(Some(identity_restore_data)),
        };
        
        let total_elapsed = start_time.elapsed();
        tracing::info!("Node creation complete in {:?}", total_elapsed);

        Ok(node)
    }

    /// Returns the node's identity (Ed25519 public key as hex string).
    #[frb(getter, sync)]
    pub fn identity(&self) -> String {
        self.identity.clone()
    }

    /// Returns whether the node has successfully bootstrapped to the Korium network.
    #[frb(getter, sync)]
    pub fn is_bootstrapped(&self) -> bool {
        self.is_bootstrapped.load(std::sync::atomic::Ordering::SeqCst)
    }

    /// Returns the bootstrap error message if bootstrap failed.
    /// Returns None if bootstrap succeeded or hasn't been attempted.
    #[frb(getter, sync)]
    pub fn bootstrap_error(&self) -> Option<String> {
        self.bootstrap_error.lock().unwrap().clone()
    }

    /// Returns the local address the node is listening on.
    #[frb(getter, sync)]
    pub fn local_addr(&self) -> String {
        self.local_addr.clone()
    }

    /// Returns routable addresses for this node.
    ///
    /// When bound to `0.0.0.0`, this enumerates all local network interfaces
    /// and returns their addresses with the bound port. This is suitable for
    /// peer discovery.
    ///
    /// Loopback addresses (127.0.0.1) are excluded.
    pub async fn routable_addresses(&self) -> Vec<String> {
        self.handle.routable_addresses().await.unwrap_or_default()
    }

    /// Returns the primary routable address for DHT publishing.
    ///
    /// This returns the first non-loopback routable address, suitable for
    /// peer discovery.
    pub async fn primary_routable_address(&self) -> String {
        self.handle.primary_routable_address().await.unwrap_or_default()
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
    ///
    /// # Returns
    /// - `Some(IdentityRestoreData)` on first call after node creation
    /// - `None` on subsequent calls (data already extracted)
    #[frb(sync)]
    pub fn get_identity_restore_data(&self) -> Option<IdentityRestoreData> {
        // SECURITY: One-shot extraction - take() clears the data after first retrieval
        self.identity_restore_data
            .lock()
            .ok()
            .and_then(|mut guard| guard.take())
    }

    /// Bootstraps the node by connecting to an existing peer.
    ///
    /// # Arguments
    /// * `peer_identity` - The identity (hex) of the bootstrap peer
    /// * `peer_addrs` - List of addresses to try for this peer
    pub async fn bootstrap(
        &self,
        peer_identity: String,
        peer_addrs: Vec<String>,
    ) -> Result<(), KoriumError> {
        self.handle.bootstrap(peer_identity, peer_addrs).await
    }

    /// Publishes the node's address for peer discovery.
    ///
    /// # Arguments
    /// * `addresses` - List of addresses where this node can be reached
    pub async fn publish_address(&self, addresses: Vec<String>) -> Result<(), KoriumError> {
        self.handle.publish_address(addresses).await
    }

    /// Subscribes to a PubSub topic.
    ///
    /// # Arguments
    /// * `topic` - The topic name to subscribe to
    pub async fn subscribe(&self, topic: String) -> Result<(), KoriumError> {
        self.handle.subscribe(topic).await
    }

    /// Publishes a message to a PubSub topic.
    ///
    /// # Arguments
    /// * `topic` - The topic to publish to
    /// * `data` - The message data
    pub async fn publish(&self, topic: String, data: Vec<u8>) -> Result<(), KoriumError> {
        self.handle.publish(topic, data).await
    }

    /// Sends a request to a peer and waits for a response.
    ///
    /// # Arguments
    /// * `peer_id` - The identity of the target peer
    /// * `data` - The request data
    ///
    /// # Returns
    /// The response data from the peer.
    pub async fn send_request(
        &self,
        peer_id: String,
        data: Vec<u8>,
    ) -> Result<Vec<u8>, KoriumError> {
        self.handle.send_request(peer_id, data).await
    }

    /// Sends a chat message to a peer.
    ///
    /// # Arguments
    /// * `peer_id` - The identity of the recipient
    /// * `message` - The chat message to send
    ///
    /// # Returns
    /// The sent message with updated status.
    pub async fn send_message(
        &self,
        peer_id: String,
        message: ChatMessage,
    ) -> Result<ChatMessage, KoriumError> {
        self.handle.send_message(peer_id, message).await
    }

    /// Resolves a peer's contact information.
    ///
    /// # Arguments
    /// * `peer_id` - The identity to resolve
    ///
    /// # Returns
    /// List of addresses where the peer can be reached.
    pub async fn resolve_peer(&self, peer_id: String) -> Result<Vec<String>, KoriumError> {
        self.handle.resolve_peer(peer_id).await
    }

    /// Finds peers near a target identity in the DHT.
    ///
    /// # Arguments
    /// * `target_id` - The target identity to search near
    ///
    /// # Returns
    /// List of peer identities found.
    pub async fn find_peers(&self, target_id: String) -> Result<Vec<String>, KoriumError> {
        self.handle.find_peers(target_id).await
    }

    /// Gets peers from the DHT routing table.
    ///
    /// Searches for peers near this node's identity in the DHT.
    /// Returns a list of peers with their identities and addresses.
    pub async fn get_dht_peers(&self) -> Result<Vec<DhtPeer>, KoriumError> {
        self.handle.get_dht_peers(self.identity.clone()).await
    }

    /// Gracefully shuts down the node.
    pub async fn shutdown(&self) -> Result<(), KoriumError> {
        self.handle.shutdown().await
    }

    /// Starts listening for incoming messages and requests.
    /// This spawns background tasks that forward events to the event broadcaster.
    /// Call this after node creation to receive incoming messages.
    pub async fn start_listeners(&self) -> Result<(), KoriumError> {
        self.handle.start_listeners().await
    }

    /// Checks if a peer is reachable by resolving their address.
    /// Returns true if the peer has published addresses, false otherwise.
    pub async fn is_peer_online(&self, peer_id: String) -> Result<bool, KoriumError> {
        let addrs = self.resolve_peer(peer_id).await?;
        Ok(!addrs.is_empty())
    }
}

/// Polls for pending events from the global broadcaster.
/// Returns a list of events that have been received since the last poll.
/// This is a polling fallback for when streaming isn't available.
///
/// # Arguments
/// * `max_events` - Maximum number of events to return (bounded to prevent memory issues)
///
/// # Returns
/// List of pending events (may be empty if none available).
#[frb]
pub fn poll_events(max_events: i32) -> Vec<KoriumEvent> {
    use std::sync::Mutex;
    use std::sync::LazyLock;

    // SECURITY: Bound max_events to prevent memory exhaustion
    const MAX_ALLOWED_EVENTS: usize = 100;
    let max = (max_events as usize).min(MAX_ALLOWED_EVENTS);

    static POLL_RECEIVER: LazyLock<Mutex<Option<tokio::sync::broadcast::Receiver<KoriumEvent>>>> =
        LazyLock::new(|| Mutex::new(None));

    let mut guard = POLL_RECEIVER.lock().unwrap_or_else(|poisoned| {
        tracing::warn!("POLL_RECEIVER mutex was poisoned, recovering");
        poisoned.into_inner()
    });

    if guard.is_none() {
        *guard = Some(crate::streams::GLOBAL_BROADCASTER.subscribe());
    }

    let rx = guard.as_mut().unwrap();
    let mut events = Vec::with_capacity(max);

    for _ in 0..max {
        match rx.try_recv() {
            Ok(event) => events.push(event),
            Err(tokio::sync::broadcast::error::TryRecvError::Empty) => break,
            Err(tokio::sync::broadcast::error::TryRecvError::Lagged(skipped)) => {
                tracing::warn!("Event polling lagged, skipped {} events", skipped);
            }
            Err(tokio::sync::broadcast::error::TryRecvError::Closed) => {
                *guard = None;
                break;
            }
        }
    }

    events
}

/// A received PubSub message.
#[frb(dart_metadata = ("freezed"))]
pub struct PubSubMessage {
    /// Topic the message was published to
    pub topic: String,
    /// Identity of the sender
    pub from: String,
    /// Message data
    pub data: Vec<u8>,
}

/// An incoming request from a peer.
#[frb(dart_metadata = ("freezed"))]
pub struct IncomingRequest {
    /// Identity of the requester
    pub from: String,
    /// Request data
    pub data: Vec<u8>,
    /// Request ID for response correlation
    pub request_id: String,
}

// Re-export types for Dart
pub use crate::message::ChatMessage;
pub use crate::message::MessageStatus;
pub use crate::message::MessageType;

/// Creates an event stream for receiving Korium events.
/// This is a Flutter Rust Bridge stream that pushes events to Dart.
pub fn create_event_stream() -> impl futures::Stream<Item = KoriumEvent> {
    use crate::streams::GLOBAL_BROADCASTER;
    use futures::stream::StreamExt;

    let rx = GLOBAL_BROADCASTER.subscribe();

    tokio_stream::wrappers::BroadcastStream::new(rx)
        .filter_map(|result| async move { result.ok() })
}
