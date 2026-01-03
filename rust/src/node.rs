//! Korium Node wrapper for the Flutter app.
//!
//! This module provides a safe, async wrapper around the Korium `Node` type,
//! handling all the complexity of P2P networking.

use crate::api::NodeConfig;
use crate::error::KoriumError;
use crate::message::{ChatMessage, MessageStatus};
use korium::Node;
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tracing::{debug, error, info, warn};

/// Constants for resource bounds (per AGENTS.md requirements).
#[allow(dead_code)]
mod constants {
    /// Maximum message size in bytes (matches Korium's limit).
    pub const MAX_MESSAGE_SIZE_BYTES: usize = 64 * 1024;

    /// Connection timeout in seconds.
    pub const CONNECTION_TIMEOUT_SECS: u64 = 30;

    /// Request timeout in seconds.
    pub const REQUEST_TIMEOUT_SECS: u64 = 30;

    /// Maximum retry attempts for operations.
    pub const MAX_RETRY_ATTEMPTS: u32 = 3;

    /// Base backoff delay in milliseconds.
    pub const RETRY_BACKOFF_BASE_MS: u64 = 100;

    /// Maximum backoff delay in milliseconds.
    pub const MAX_RETRY_BACKOFF_MS: u64 = 10_000;

    /// Topic prefix for direct messages.
    pub const DM_TOPIC_PREFIX: &str = "dm/";

    /// Topic for presence announcements.
    pub const PRESENCE_TOPIC: &str = "presence";

    /// Expected length of a Korium peer identity (Ed25519 public key hex).
    pub const PEER_IDENTITY_HEX_LEN: usize = 64;

    /// Maximum number of addresses accepted for bootstrap attempts.
    pub const MAX_BOOTSTRAP_ADDRS: usize = 32;

    /// Maximum length for a single address string (defensive bound).
    pub const MAX_ADDR_STR_LEN: usize = 128;
}

/// Wrapper around the Korium `Node` type.
pub struct NodeWrapper {
    /// The underlying Korium node.
    node: Node,
    /// Whether the node has been shut down.
    is_shutdown: Arc<AtomicBool>,
}

impl NodeWrapper {
    fn validate_peer_identity(peer_identity: &str) -> Result<(), KoriumError> {
        if peer_identity.len() != constants::PEER_IDENTITY_HEX_LEN {
            return Err(KoriumError::InvalidIdentity(format!(
                "Invalid peer identity length: expected {} hex chars, got {}",
                constants::PEER_IDENTITY_HEX_LEN,
                peer_identity.len()
            )));
        }

        if !peer_identity.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(KoriumError::InvalidIdentity(
                "Peer identity must be lowercase/uppercase hex".to_string(),
            ));
        }

        Ok(())
    }

    fn validate_peer_addrs(peer_addrs: &[String]) -> Result<(), KoriumError> {
        if peer_addrs.is_empty() {
            return Err(KoriumError::BootstrapError(
                "No peer addresses provided for bootstrap".to_string(),
            ));
        }

        if peer_addrs.len() > constants::MAX_BOOTSTRAP_ADDRS {
            return Err(KoriumError::BootstrapError(format!(
                "Too many bootstrap addresses: max {}, got {}",
                constants::MAX_BOOTSTRAP_ADDRS,
                peer_addrs.len()
            )));
        }

        for addr in peer_addrs {
            if addr.len() > constants::MAX_ADDR_STR_LEN {
                return Err(KoriumError::BootstrapError(format!(
                    "Bootstrap address too long (max {} chars)",
                    constants::MAX_ADDR_STR_LEN
                )));
            }

            // SECURITY: Validate address format early to avoid passing attacker-controlled
            // junk into lower layers (also prevents surprising allocations / parsing work).
            addr.parse::<SocketAddr>().map_err(|e| {
                KoriumError::BootstrapError(format!("Invalid bootstrap address '{addr}': {e}"))
            })?;
        }

        Ok(())
    }

    /// Creates a new node wrapper with the specified bind address.
    ///
    /// # Arguments
    /// * `bind_addr` - Address to bind to (e.g., "0.0.0.0:0")
    ///
    /// # Errors
    /// Returns `KoriumError::BindError` if binding fails.
    #[allow(dead_code)]
    pub async fn new(bind_addr: &str) -> Result<Self, KoriumError> {
        info!("Creating Korium node on {}", bind_addr);

        let node = Node::bind(bind_addr)
            .await
            .map_err(|e| KoriumError::BindError(e.to_string()))?;

        info!("Node created with identity: {}", node.identity());

        Ok(Self {
            node,
            is_shutdown: Arc::new(AtomicBool::new(false)),
        })
    }

    /// Creates a new node wrapper with full configuration.
    ///
    /// If `private_key_hex` and `identity_proof_nonce` are provided, the node
    /// will restore the existing identity without re-computing PoW (instant startup).
    /// Otherwise, generates a new identity with PoW (~1-4 seconds).
    ///
    /// # Errors
    /// Returns `KoriumError` if node creation fails.
    pub async fn new_with_config(config: NodeConfig) -> Result<Self, KoriumError> {
        info!("Creating Korium node with config on {}", config.bind_addr);

        // SECURITY: Namespace isolation is not yet implemented.
        // Return an error instead of silently ignoring to prevent false sense of security.
        // Users might believe they have network isolation when they don't.
        if config.namespace_secret.is_some() {
            return Err(KoriumError::Internal(
                "Namespace isolation is not yet supported. Remove namespace_secret from config or wait for future release.".to_string()
            ));
        }

        // Check if we have identity restoration data
        let node = match (&config.private_key_hex, config.identity_proof_nonce) {
            (Some(private_key_hex), Some(pow_nonce)) => {
                // Restore existing identity (instant - no PoW computation)
                info!("Restoring existing identity from saved keypair (skipping PoW)");

                // SECURITY: Validate private key format before parsing
                // Secret key is 32 bytes = 64 hex characters
                const SECRET_KEY_HEX_LEN: usize = 64;
                if private_key_hex.len() != SECRET_KEY_HEX_LEN {
                    return Err(KoriumError::Internal(format!(
                        "Invalid private key length: expected {} hex chars, got {}",
                        SECRET_KEY_HEX_LEN,
                        private_key_hex.len()
                    )));
                }

                let secret_bytes: [u8; 32] = hex::decode(private_key_hex)
                    .map_err(|e| KoriumError::Internal(format!("Invalid private key hex: {e}")))?
                    .try_into()
                    .map_err(|_| KoriumError::Internal("Private key must be 32 bytes".to_string()))?;

                // Reconstruct keypair and PoW proof
                let keypair = korium::Keypair::from_secret_key_bytes(&secret_bytes);
                let pow_proof = korium::IdentityProof::new(pow_nonce);

                // SECURITY: Verify the PoW is valid for this keypair
                // This prevents accepting corrupted/invalid saved state
                if !keypair.identity().verify_pow(&pow_proof) {
                    return Err(KoriumError::Internal(
                        "Invalid identity proof: PoW verification failed. The saved keypair or nonce may be corrupted.".to_string()
                    ));
                }

                info!("Identity restored: {}", keypair.identity());

                Node::bind_with_keypair_and_pow(&config.bind_addr, keypair, pow_proof)
                    .await
                    .map_err(|e| KoriumError::BindError(e.to_string()))?
            }
            (Some(_), None) | (None, Some(_)) => {
                // Partial identity data - reject to prevent confusion
                return Err(KoriumError::Internal(
                    "Both private_key_hex and identity_proof_nonce must be provided for identity restoration".to_string()
                ));
            }
            (None, None) => {
                // Fresh identity with PoW (slow: 1-4 seconds)
                info!("Generating new identity with PoW...");
                Node::bind(&config.bind_addr)
                    .await
                    .map_err(|e| KoriumError::BindError(e.to_string()))?
            }
        };

        info!("Node created with identity: {}", node.identity());

        let wrapper = Self {
            node,
            is_shutdown: Arc::new(AtomicBool::new(false)),
        };

        Ok(wrapper)
    }

    /// Returns the node's identity as a hex string.
    #[must_use]
    pub fn identity(&self) -> String {
        self.node.identity()
    }

    /// Returns the node's secret key as a hex string (32 bytes = 64 hex chars).
    /// 
    /// # Security
    /// This method is used for identity persistence (secure storage) and
    /// Pkarr DHT signing. The secret key must be stored encrypted.
    #[must_use]
    pub fn secret_key_hex(&self) -> String {
        hex::encode(self.node.keypair().secret_key_bytes())
    }

    /// Returns the PoW nonce for identity restoration.
    ///
    /// This nonce, combined with the secret key, allows restoring the node's
    /// identity without re-computing Proof-of-Work (instant startup).
    ///
    /// # Returns
    /// The PoW nonce from the node's contact record.
    #[must_use]
    pub fn pow_nonce(&self) -> u64 {
        self.node.peer_endpoint().pow_proof.nonce
    }

    /// Returns the local address the node is listening on.
    ///
    /// **WARNING:** This returns the raw socket bind address (e.g., `0.0.0.0:PORT`).
    /// For addresses suitable for peer discovery, use `routable_addresses()` instead.
    ///
    /// # Errors
    /// Returns `KoriumError` if the address cannot be determined.
    pub fn local_addr(&self) -> Result<String, KoriumError> {
        self.node
            .local_addr()
            .map(|addr| addr.to_string())
            .map_err(|e| KoriumError::Internal(e.to_string()))
    }

    /// Returns routable addresses for this node.
    ///
    /// When bound to `0.0.0.0` or `::`, this enumerates all local network interfaces
    /// and returns their addresses with the bound port. This is suitable for
    /// peer discovery and DHT publishing (Pkarr, etc.).
    ///
    /// # Returns
    /// A vector of routable addresses (e.g., `["192.168.1.10:8000", "10.0.0.5:8000"]`).
    /// Loopback addresses (127.0.0.1) are excluded for external discovery.
    #[must_use]
    pub fn routable_addresses(&self) -> Vec<String> {
        self.node
            .routable_addresses()
            .into_iter()
            // Filter out loopback addresses for external discovery
            .filter(|addr| !addr.starts_with("127.") && !addr.starts_with("[::1]"))
            .collect()
    }

    /// Returns the first routable address, or falls back to local_addr.
    ///
    /// This is a convenience method for when you need a single address
    /// for DHT publishing. Prefers non-loopback addresses.
    pub fn primary_routable_address(&self) -> String {
        let addrs = self.routable_addresses();
        addrs.into_iter().next().unwrap_or_else(|| {
            // Fallback to local_addr if no routable addresses found
            self.local_addr().unwrap_or_else(|_| "0.0.0.0:0".to_string())
        })
    }

    /// Checks if the node has been shut down.
    fn check_shutdown(&self) -> Result<(), KoriumError> {
        if self.is_shutdown.load(Ordering::Acquire) {
            Err(KoriumError::ShutDown)
        } else {
            Ok(())
        }
    }

    /// Bootstraps the node by connecting to an existing peer.
    ///
    /// # Arguments
    /// * `peer_identity` - The peer's 64-character hex identity
    /// * `peer_addrs` - List of addresses to try for this peer
    ///
    /// # Errors
    /// Returns `KoriumError::BootstrapError` if bootstrapping fails.
    pub async fn bootstrap(
        &self,
        peer_identity: &str,
        peer_addrs: Vec<String>,
    ) -> Result<(), KoriumError> {
        self.check_shutdown()?;

        Self::validate_peer_identity(peer_identity)?;
        Self::validate_peer_addrs(&peer_addrs)?;

        info!(
            "Bootstrapping with peer {} at {:?}",
            peer_identity, peer_addrs
        );

        self.node
            .bootstrap(peer_identity, &peer_addrs)
            .await
            .map_err(|e| KoriumError::BootstrapError(e.to_string()))?;

        info!("Bootstrap successful");
        Ok(())
    }

    /// Bootstraps the node using the public Korium mesh via DNS resolution.
    ///
    /// This resolves `bootstrap.korium.io` to get the bootstrap peer identity
    /// and address, then connects to join the public mesh.
    ///
    /// # Returns
    /// The observed external address of this node as seen by the bootstrap peer.
    ///
    /// # Errors
    /// Returns `KoriumError::BootstrapError` if DNS resolution or connection fails.
    pub async fn bootstrap_public(&self) -> Result<Option<String>, KoriumError> {
        self.check_shutdown()?;

        info!("Bootstrapping via public DNS (bootstrap.korium.io)...");

        let external_addr = self
            .node
            .bootstrap_public()
            .await
            .map_err(|e| KoriumError::BootstrapError(e.to_string()))?;

        info!("Public bootstrap successful, external addr: {:?}", external_addr);
        Ok(external_addr)
    }

    /// Publishes the node's address for peer discovery.
    ///
    /// # Errors
    /// Returns `KoriumError` if publishing fails.
    pub async fn publish_address(&self, addresses: Vec<String>) -> Result<(), KoriumError> {
        self.check_shutdown()?;

        debug!("Publishing addresses: {:?}", addresses);

        self.node
            .publish_address(addresses)
            .await
            .map_err(|e| KoriumError::Internal(e.to_string()))?;

        Ok(())
    }

    /// Subscribes to a PubSub topic.
    ///
    /// # Errors
    /// Returns `KoriumError` if subscription fails.
    pub async fn subscribe(&self, topic: &str) -> Result<(), KoriumError> {
        self.check_shutdown()?;

        debug!("Subscribing to topic: {}", topic);

        self.node
            .subscribe(topic)
            .await
            .map_err(|e| KoriumError::Internal(e.to_string()))?;

        Ok(())
    }

    /// Publishes a message to a PubSub topic.
    ///
    /// # Errors
    /// Returns `KoriumError` if publishing fails.
    pub async fn publish(&self, topic: &str, data: Vec<u8>) -> Result<(), KoriumError> {
        self.check_shutdown()?;

        // Validate message size
        if data.len() > constants::MAX_MESSAGE_SIZE_BYTES {
            return Err(KoriumError::SendError(format!(
                "Message size {} exceeds maximum {}",
                data.len(),
                constants::MAX_MESSAGE_SIZE_BYTES
            )));
        }

        debug!("Publishing {} bytes to topic: {}", data.len(), topic);

        self.node
            .publish(topic, data)
            .await
            .map_err(|e| KoriumError::SendError(e.to_string()))?;

        Ok(())
    }

    /// Sends a request to a peer and waits for a response.
    ///
    /// # Errors
    /// Returns `KoriumError` if the request fails.
    pub async fn send_request(&self, peer_id: &str, data: Vec<u8>) -> Result<Vec<u8>, KoriumError> {
        self.check_shutdown()?;

        // Validate message size
        if data.len() > constants::MAX_MESSAGE_SIZE_BYTES {
            return Err(KoriumError::SendError(format!(
                "Request size {} exceeds maximum {}",
                data.len(),
                constants::MAX_MESSAGE_SIZE_BYTES
            )));
        }

        debug!("Sending {} bytes request to peer: {}", data.len(), peer_id);

        // Apply timeout to the request
        let timeout = tokio::time::Duration::from_secs(constants::REQUEST_TIMEOUT_SECS);

        let result = tokio::time::timeout(timeout, self.node.send(peer_id, data)).await;

        match result {
            Ok(Ok(response)) => {
                // SECURITY: Validate response size to prevent memory exhaustion from malicious peers
                if response.len() > constants::MAX_MESSAGE_SIZE_BYTES {
                    return Err(KoriumError::ReceiveError(format!(
                        "Response size {} exceeds maximum {}",
                        response.len(),
                        constants::MAX_MESSAGE_SIZE_BYTES
                    )));
                }
                debug!("Received {} bytes response", response.len());
                Ok(response)
            }
            Ok(Err(e)) => Err(KoriumError::SendError(e.to_string())),
            Err(_) => Err(KoriumError::Timeout(format!(
                "Request to {} timed out after {}s",
                peer_id,
                constants::REQUEST_TIMEOUT_SECS
            ))),
        }
    }

    /// Sends a chat message to a peer.
    ///
    /// # Errors
    /// Returns `KoriumError` if sending fails.
    pub async fn send_chat_message(
        &self,
        peer_id: &str,
        mut message: ChatMessage,
    ) -> Result<ChatMessage, KoriumError> {
        self.check_shutdown()?;

        let data = message.to_bytes()?;

        // Validate message size
        if data.len() > constants::MAX_MESSAGE_SIZE_BYTES {
            return Err(KoriumError::SendError(format!(
                "Message size {} exceeds maximum {}",
                data.len(),
                constants::MAX_MESSAGE_SIZE_BYTES
            )));
        }

        debug!(
            "Sending chat message {} ({} bytes) to peer: {}",
            message.id,
            data.len(),
            peer_id
        );

        // Apply timeout
        let timeout = tokio::time::Duration::from_secs(constants::REQUEST_TIMEOUT_SECS);

        match tokio::time::timeout(timeout, self.node.send(peer_id, data)).await {
            Ok(Ok(_)) => {
                message.status = MessageStatus::Sent;
                debug!("Message {} sent successfully", message.id);
                Ok(message)
            }
            Ok(Err(e)) => {
                message.status = MessageStatus::Failed;
                error!("Failed to send message {}: {}", message.id, e);
                Err(KoriumError::SendError(e.to_string()))
            }
            Err(_) => {
                message.status = MessageStatus::Failed;
                warn!("Message {} timed out", message.id);
                Err(KoriumError::Timeout(format!(
                    "Message to {} timed out",
                    peer_id
                )))
            }
        }
    }

    /// Resolves a peer's contact information.
    /// Note: This method is a placeholder - actual resolution depends on Korium API.
    ///
    /// # Errors
    /// Returns `KoriumError` if resolution fails.
    pub async fn resolve_peer(&self, peer_id: &str) -> Result<Vec<String>, KoriumError> {
        self.check_shutdown()?;

        debug!("Resolving peer: {}", peer_id);

        // Parse the peer_id as an Identity from hex string
        let identity = korium::Identity::from_hex(peer_id)
            .map_err(|e| KoriumError::InvalidIdentity(format!("{}", e)))?;

        let contact = self
            .node
            .resolve(&identity)
            .await
            .map_err(|e| KoriumError::PeerNotFound(e.to_string()))?;

        match contact {
            Some(c) => Ok(c.addrs.iter().map(|a| a.to_string()).collect()),
            None => Ok(Vec::new()),
        }
    }

    /// Finds peers near a target identity in the DHT.
    ///
    /// # Errors
    /// Returns `KoriumError` if the search fails.
    pub async fn find_peers(&self, target_id: &str) -> Result<Vec<String>, KoriumError> {
        self.check_shutdown()?;

        debug!("Finding peers near: {}", target_id);

        // Parse the target_id as an Identity from hex string
        let identity = korium::Identity::from_hex(target_id)
            .map_err(|e| KoriumError::InvalidIdentity(format!("{}", e)))?;

        let peers = self
            .node
            .find_peers(identity)
            .await
            .map_err(|e| KoriumError::Internal(e.to_string()))?;

        Ok(peers.into_iter().map(|c| c.identity.to_string()).collect())
    }

    /// Gets DHT peers with full contact information (identity + addresses).
    ///
    /// # Errors
    /// Returns `KoriumError` if the search fails.
    pub async fn get_dht_peers(
        &self,
        target_id: &str,
    ) -> Result<Vec<crate::api::DhtPeer>, KoriumError> {
        self.check_shutdown()?;

        debug!("Getting DHT peers near: {}", target_id);

        // Parse the target_id as an Identity from hex string
        let identity = korium::Identity::from_hex(target_id)
            .map_err(|e| KoriumError::InvalidIdentity(format!("{}", e)))?;

        let peers = self
            .node
            .find_peers(identity)
            .await
            .map_err(|e| KoriumError::Internal(e.to_string()))?;

        Ok(peers
            .into_iter()
            .map(|c| crate::api::DhtPeer {
                identity: c.identity.to_string(),
                addresses: c.addrs.iter().map(|a| a.to_string()).collect(),
            })
            .collect())
    }

    /// Starts listening for incoming messages and requests.
    /// This spawns background tasks that forward events to the event broadcaster.
    ///
    /// # Errors
    /// Returns `KoriumError` if listener setup fails.
    pub async fn start_listeners(&self) -> Result<(), KoriumError> {
        self.check_shutdown()?;

        // Get the global event broadcaster
        use crate::streams::{KoriumEvent, GLOBAL_BROADCASTER};
        let broadcaster = &*GLOBAL_BROADCASTER;

        // Spawn PubSub message listener
        let pubsub_broadcaster = broadcaster.clone();
        if let Ok(mut rx) = self.node.messages().await {
            let is_shutdown = self.is_shutdown.clone();
            tokio::spawn(async move {
                while let Some(msg) = rx.recv().await {
                    if is_shutdown.load(Ordering::Acquire) {
                        break;
                    }

                    // SECURITY: Validate message size before deserialization to prevent
                    // memory exhaustion from malicious peers sending oversized messages.
                    if msg.data.len() > constants::MAX_MESSAGE_SIZE_BYTES {
                        warn!(
                            "Rejecting oversized PubSub message: {} bytes from {}",
                            msg.data.len(),
                            msg.from
                        );
                        continue;
                    }

                    // Try to parse as ChatMessage, otherwise send raw
                    if let Ok(chat_msg) = crate::message::ChatMessage::from_bytes(&msg.data) {
                        pubsub_broadcaster.broadcast(KoriumEvent::ChatMessageReceived {
                            message: chat_msg,
                        });
                    } else {
                        // SECURITY: Send full identity, not truncated - let UI truncate for display
                        pubsub_broadcaster.broadcast(KoriumEvent::PubSubMessage {
                            topic: msg.topic.clone(),
                            from_identity: msg.from.to_string(),
                            data: msg.data.clone(),
                        });
                    }
                }
            });
        }

        // Spawn incoming request listener
        let request_broadcaster = broadcaster.clone();
        if let Ok(mut rx) = self.node.incoming_requests().await {
            let is_shutdown = self.is_shutdown.clone();
            let my_identity = self.node.identity();
            tokio::spawn(async move {
                while let Some((from, request, response_tx)) = rx.recv().await {
                    if is_shutdown.load(Ordering::Acquire) {
                        break;
                    }

                    // SECURITY: Validate request size before deserialization to prevent
                    // memory exhaustion from malicious peers sending oversized requests.
                    if request.len() > constants::MAX_MESSAGE_SIZE_BYTES {
                        warn!(
                            "Rejecting oversized request: {} bytes from {}",
                            request.len(),
                            from
                        );
                        let _ = response_tx.send(b"ERR:OVERSIZED".to_vec());
                        continue;
                    }

                    // Try to parse as ChatMessage
                    if let Ok(mut chat_msg) = crate::message::ChatMessage::from_bytes(&request) {
                        // Update recipient to our identity
                        chat_msg.recipient_id = my_identity.clone();
                        chat_msg.is_from_me = false;

                        // Capture message ID before moving
                        let message_id = chat_msg.id.clone();

                        request_broadcaster.broadcast(KoriumEvent::ChatMessageReceived {
                            message: chat_msg,
                        });

                        // Send delivery receipt
                        let receipt = serde_json::json!({
                            "type": "delivery_receipt",
                            "message_id": message_id,
                        });
                        let _ = response_tx.send(receipt.to_string().into_bytes());
                    } else {
                        // Raw request - send full identity for proper identification
                        // SECURITY: ThreadRng is CSPRNG-seeded via OsRng, safe for request IDs.
                        // Using 256 bits (2x u128) to avoid collisions.
                        let request_id = format!("{:032x}{:032x}", rand::random::<u128>(), rand::random::<u128>());
                        request_broadcaster.broadcast(KoriumEvent::IncomingRequest {
                            from_identity: from.to_string(),
                            request_id: request_id.clone(),
                            data: request.clone(),
                        });

                        // Echo back as acknowledgment
                        let _ = response_tx.send(b"ACK".to_vec());
                    }
                }
            });
        }

        info!("Message listeners started");
        Ok(())
    }

    /// Shuts down the node gracefully.
    ///
    /// # Errors
    /// Returns `KoriumError` if shutdown fails.
    pub async fn shutdown(&self) -> Result<(), KoriumError> {
        if self
            .is_shutdown
            .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
            .is_ok()
        {
            info!("Shutting down Korium node");
            // The node will be dropped when the wrapper is dropped
            Ok(())
        } else {
            Err(KoriumError::ShutDown)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_node_creation_invalid_address() {
        // This test requires a network, so we just verify the error handling
        let result = NodeWrapper::new("invalid:addr").await;
        assert!(result.is_err());
    }

    #[test]
    fn test_constants_message_size() {
        // MAX_MESSAGE_SIZE_BYTES should be reasonable
        assert!(constants::MAX_MESSAGE_SIZE_BYTES >= 1024); // At least 1KB
        assert!(constants::MAX_MESSAGE_SIZE_BYTES <= 10 * 1024 * 1024); // At most 10MB
    }

    #[test]
    fn test_constants_timeouts() {
        // Timeouts should be reasonable
        assert!(constants::CONNECTION_TIMEOUT_SECS >= 5);
        assert!(constants::CONNECTION_TIMEOUT_SECS <= 120);
        assert!(constants::REQUEST_TIMEOUT_SECS >= 5);
        assert!(constants::REQUEST_TIMEOUT_SECS <= 120);
    }

    #[test]
    fn test_constants_retry() {
        // Retry parameters should be reasonable
        assert!(constants::MAX_RETRY_ATTEMPTS >= 1);
        assert!(constants::MAX_RETRY_ATTEMPTS <= 10);
        assert!(constants::RETRY_BACKOFF_BASE_MS >= 50);
        assert!(constants::MAX_RETRY_BACKOFF_MS >= constants::RETRY_BACKOFF_BASE_MS);
    }

    #[test]
    fn test_constants_topics() {
        // Topic strings should be non-empty
        assert!(!constants::DM_TOPIC_PREFIX.is_empty());
        assert!(!constants::PRESENCE_TOPIC.is_empty());
    }
}
