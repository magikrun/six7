//! Actor pattern implementation for KoriumNode.
//!
//! This module provides a message-passing architecture that eliminates lock
//! contention by having a single actor own all node state. Commands are sent
//! via bounded channels and processed sequentially.
//!
//! # Architecture (per AGENTS.md)
//! - Single owner of NodeWrapper (no Arc<Mutex<>>)
//! - Command channels with explicit capacity bounds
//! - Graceful shutdown via mailbox drain
//! - No deadlocks possible by design

use crate::error::KoriumError;
use crate::message::ChatMessage;
use crate::node::NodeWrapper;
use tokio::sync::{mpsc, oneshot};
use tracing::{info, warn};

/// Maximum commands to buffer in the actor's mailbox.
/// SECURITY: Bounded to prevent unbounded memory growth under load.
const MAX_COMMAND_BUFFER: usize = 256;

/// Commands that can be sent to the NodeActor.
/// Each command includes a oneshot channel for the response.
#[derive(Debug)]
#[allow(dead_code)] // All variants are part of the complete API
pub enum NodeCommand {
    /// Get the node's identity
    GetIdentity {
        reply: oneshot::Sender<String>,
    },

    /// Get the node's secret key (internal use only)
    GetSecretKeyHex {
        reply: oneshot::Sender<String>,
    },

    /// Get the node's PoW nonce for identity restoration
    GetPowNonce {
        reply: oneshot::Sender<u64>,
    },

    /// Get the local address
    GetLocalAddr {
        reply: oneshot::Sender<Result<String, KoriumError>>,
    },

    /// Get routable addresses
    GetRoutableAddresses {
        reply: oneshot::Sender<Vec<String>>,
    },

    /// Get primary routable address
    GetPrimaryRoutableAddress {
        reply: oneshot::Sender<String>,
    },

    /// Bootstrap to a peer with multiple addresses
    Bootstrap {
        peer_identity: String,
        peer_addrs: Vec<String>,
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },

    /// Bootstrap via public DNS (bootstrap.korium.io)
    BootstrapPublic {
        reply: oneshot::Sender<Result<Option<String>, KoriumError>>,
    },

    /// Publish address for peer discovery
    PublishAddress {
        addresses: Vec<String>,
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },

    /// Subscribe to a PubSub topic
    Subscribe {
        topic: String,
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },

    /// Publish to a PubSub topic
    Publish {
        topic: String,
        data: Vec<u8>,
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },

    /// Send a request to a peer
    SendRequest {
        peer_id: String,
        data: Vec<u8>,
        reply: oneshot::Sender<Result<Vec<u8>, KoriumError>>,
    },

    /// Send a chat message
    SendMessage {
        peer_id: String,
        message: ChatMessage,
        reply: oneshot::Sender<Result<ChatMessage, KoriumError>>,
    },

    /// Resolve a peer's addresses
    ResolvePeer {
        peer_id: String,
        reply: oneshot::Sender<Result<Vec<String>, KoriumError>>,
    },

    /// Find peers near a target ID
    FindPeers {
        target_id: String,
        reply: oneshot::Sender<Result<Vec<String>, KoriumError>>,
    },

    /// Get DHT peers with full contact info
    GetDhtPeers {
        target_id: String,
        reply: oneshot::Sender<Result<Vec<crate::api::DhtPeer>, KoriumError>>,
    },

    /// Start message listeners
    StartListeners {
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },

    /// Graceful shutdown
    Shutdown {
        reply: oneshot::Sender<Result<(), KoriumError>>,
    },
}

/// The NodeActor owns the NodeWrapper and processes commands sequentially.
/// This eliminates all lock contention - only one command runs at a time.
pub struct NodeActor {
    /// The owned node wrapper (no Arc, no Mutex)
    node: NodeWrapper,
    /// Command receiver
    rx: mpsc::Receiver<NodeCommand>,
    /// Shutdown flag
    is_shutdown: bool,
}

impl NodeActor {
    /// Creates a new NodeActor with the given node and receiver.
    fn new(node: NodeWrapper, rx: mpsc::Receiver<NodeCommand>) -> Self {
        Self {
            node,
            rx,
            is_shutdown: false,
        }
    }

    /// Runs the actor's event loop, processing commands until shutdown.
    /// This is spawned as a background task.
    pub async fn run(mut self) {
        info!("NodeActor: starting event loop");

        while let Some(cmd) = self.rx.recv().await {
            if self.is_shutdown {
                // After shutdown, reject all commands
                self.reject_command(cmd);
                continue;
            }

            match cmd {
                NodeCommand::GetIdentity { reply } => {
                    let _ = reply.send(self.node.identity());
                }

                NodeCommand::GetSecretKeyHex { reply } => {
                    let _ = reply.send(self.node.secret_key_hex());
                }

                NodeCommand::GetPowNonce { reply } => {
                    let _ = reply.send(self.node.pow_nonce());
                }

                NodeCommand::GetLocalAddr { reply } => {
                    let _ = reply.send(self.node.local_addr());
                }

                NodeCommand::GetRoutableAddresses { reply } => {
                    let _ = reply.send(self.node.routable_addresses());
                }

                NodeCommand::GetPrimaryRoutableAddress { reply } => {
                    let _ = reply.send(self.node.primary_routable_address());
                }

                NodeCommand::Bootstrap {
                    peer_identity,
                    peer_addrs,
                    reply,
                } => {
                    let result = self.node.bootstrap(&peer_identity, peer_addrs).await;
                    let _ = reply.send(result);
                }

                NodeCommand::BootstrapPublic { reply } => {
                    let result = self.node.bootstrap_public().await;
                    let _ = reply.send(result);
                }

                NodeCommand::PublishAddress { addresses, reply } => {
                    let result = self.node.publish_address(addresses).await;
                    let _ = reply.send(result);
                }

                NodeCommand::Subscribe { topic, reply } => {
                    let result = self.node.subscribe(&topic).await;
                    let _ = reply.send(result);
                }

                NodeCommand::Publish { topic, data, reply } => {
                    let result = self.node.publish(&topic, data).await;
                    let _ = reply.send(result);
                }

                NodeCommand::SendRequest {
                    peer_id,
                    data,
                    reply,
                } => {
                    let result = self.node.send_request(&peer_id, data).await;
                    let _ = reply.send(result);
                }

                NodeCommand::SendMessage {
                    peer_id,
                    message,
                    reply,
                } => {
                    let result = self.node.send_chat_message(&peer_id, message).await;
                    let _ = reply.send(result);
                }

                NodeCommand::ResolvePeer { peer_id, reply } => {
                    let result = self.node.resolve_peer(&peer_id).await;
                    let _ = reply.send(result);
                }

                NodeCommand::FindPeers { target_id, reply } => {
                    let result = self.node.find_peers(&target_id).await;
                    let _ = reply.send(result);
                }

                NodeCommand::GetDhtPeers { target_id, reply } => {
                    let result = self.node.get_dht_peers(&target_id).await;
                    let _ = reply.send(result);
                }

                NodeCommand::StartListeners { reply } => {
                    let result = self.node.start_listeners().await;
                    let _ = reply.send(result);
                }

                NodeCommand::Shutdown { reply } => {
                    info!("NodeActor: received shutdown command");
                    self.is_shutdown = true;
                    let result = self.node.shutdown().await;
                    let _ = reply.send(result);
                    // Continue draining mailbox to reject pending commands
                }
            }
        }

        info!("NodeActor: event loop terminated");
    }

    /// Rejects a command after shutdown.
    fn reject_command(&self, cmd: NodeCommand) {
        warn!("NodeActor: rejecting command after shutdown");
        match cmd {
            NodeCommand::GetIdentity { reply } => {
                let _ = reply.send(String::new());
            }
            NodeCommand::GetSecretKeyHex { reply } => {
                let _ = reply.send(String::new());
            }
            NodeCommand::GetPowNonce { reply } => {
                let _ = reply.send(0);
            }
            NodeCommand::GetLocalAddr { reply } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::GetRoutableAddresses { reply } => {
                let _ = reply.send(Vec::new());
            }
            NodeCommand::GetPrimaryRoutableAddress { reply } => {
                let _ = reply.send(String::new());
            }
            NodeCommand::Bootstrap { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::BootstrapPublic { reply } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::PublishAddress { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::Subscribe { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::Publish { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::SendRequest { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::SendMessage { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::ResolvePeer { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::FindPeers { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::GetDhtPeers { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::StartListeners { reply, .. } => {
                let _ = reply.send(Err(KoriumError::ShutDown));
            }
            NodeCommand::Shutdown { reply, .. } => {
                let _ = reply.send(Ok(()));
            }
        }
    }
}

/// Handle for sending commands to the NodeActor.
/// This is what gets stored in KoriumNode.
#[derive(Clone)]
pub struct NodeHandle {
    tx: mpsc::Sender<NodeCommand>,
}

impl NodeHandle {
    /// Spawns a new NodeActor and returns a handle for communicating with it.
    pub fn spawn(node: NodeWrapper) -> Self {
        let (tx, rx) = mpsc::channel(MAX_COMMAND_BUFFER);
        let actor = NodeActor::new(node, rx);

        // Spawn the actor as a background task
        tokio::spawn(actor.run());

        Self { tx }
    }

    /// Sends a command and waits for the response.
    /// Returns an error if the actor has terminated.
    async fn send<T, F>(&self, make_cmd: F) -> Result<T, KoriumError>
    where
        F: FnOnce(oneshot::Sender<T>) -> NodeCommand,
    {
        let (reply_tx, reply_rx) = oneshot::channel();
        let cmd = make_cmd(reply_tx);

        self.tx
            .send(cmd)
            .await
            .map_err(|_| KoriumError::ShutDown)?;

        reply_rx
            .await
            .map_err(|_| KoriumError::Internal("Actor terminated unexpectedly".to_string()))
    }

    /// Sends a command that returns Result<T, KoriumError>.
    async fn send_result<T, F>(&self, make_cmd: F) -> Result<T, KoriumError>
    where
        F: FnOnce(oneshot::Sender<Result<T, KoriumError>>) -> NodeCommand,
    {
        let (reply_tx, reply_rx) = oneshot::channel();
        let cmd = make_cmd(reply_tx);

        self.tx
            .send(cmd)
            .await
            .map_err(|_| KoriumError::ShutDown)?;

        reply_rx
            .await
            .map_err(|_| KoriumError::Internal("Actor terminated unexpectedly".to_string()))?
    }

    // =========================================================================
    // Public API - mirrors NodeWrapper methods
    // =========================================================================

    #[allow(dead_code)] // Part of complete API
    pub async fn identity(&self) -> Result<String, KoriumError> {
        self.send(|reply| NodeCommand::GetIdentity { reply }).await
    }

    #[allow(dead_code)] // Part of complete API - secret_key_hex read at creation, not via actor
    pub async fn secret_key_hex(&self) -> Result<String, KoriumError> {
        self.send(|reply| NodeCommand::GetSecretKeyHex { reply })
            .await
    }

    #[allow(dead_code)] // Part of complete API - pow_nonce read at creation, not via actor
    pub async fn pow_nonce(&self) -> Result<u64, KoriumError> {
        self.send(|reply| NodeCommand::GetPowNonce { reply })
            .await
    }

    #[allow(dead_code)] // Part of complete API
    pub async fn local_addr(&self) -> Result<String, KoriumError> {
        self.send_result(|reply| NodeCommand::GetLocalAddr { reply })
            .await
    }

    pub async fn routable_addresses(&self) -> Result<Vec<String>, KoriumError> {
        self.send(|reply| NodeCommand::GetRoutableAddresses { reply })
            .await
    }

    pub async fn primary_routable_address(&self) -> Result<String, KoriumError> {
        self.send(|reply| NodeCommand::GetPrimaryRoutableAddress { reply })
            .await
    }

    pub async fn bootstrap(
        &self,
        peer_identity: String,
        peer_addrs: Vec<String>,
    ) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::Bootstrap {
            peer_identity,
            peer_addrs,
            reply,
        })
        .await
    }

    pub async fn bootstrap_public(&self) -> Result<Option<String>, KoriumError> {
        self.send_result(|reply| NodeCommand::BootstrapPublic { reply })
            .await
    }

    pub async fn publish_address(&self, addresses: Vec<String>) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::PublishAddress { addresses, reply })
            .await
    }

    pub async fn subscribe(&self, topic: String) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::Subscribe { topic, reply })
            .await
    }

    pub async fn publish(&self, topic: String, data: Vec<u8>) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::Publish { topic, data, reply })
            .await
    }

    pub async fn send_request(&self, peer_id: String, data: Vec<u8>) -> Result<Vec<u8>, KoriumError> {
        self.send_result(|reply| NodeCommand::SendRequest {
            peer_id,
            data,
            reply,
        })
        .await
    }

    pub async fn send_message(
        &self,
        peer_id: String,
        message: ChatMessage,
    ) -> Result<ChatMessage, KoriumError> {
        self.send_result(|reply| NodeCommand::SendMessage {
            peer_id,
            message,
            reply,
        })
        .await
    }

    pub async fn resolve_peer(&self, peer_id: String) -> Result<Vec<String>, KoriumError> {
        self.send_result(|reply| NodeCommand::ResolvePeer { peer_id, reply })
            .await
    }

    pub async fn find_peers(&self, target_id: String) -> Result<Vec<String>, KoriumError> {
        self.send_result(|reply| NodeCommand::FindPeers { target_id, reply })
            .await
    }

    pub async fn get_dht_peers(
        &self,
        target_id: String,
    ) -> Result<Vec<crate::api::DhtPeer>, KoriumError> {
        self.send_result(|reply| NodeCommand::GetDhtPeers { target_id, reply })
            .await
    }

    pub async fn start_listeners(&self) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::StartListeners { reply })
            .await
    }

    pub async fn shutdown(&self) -> Result<(), KoriumError> {
        self.send_result(|reply| NodeCommand::Shutdown { reply })
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_max_command_buffer_reasonable() {
        // Verify buffer is bounded but reasonable
        assert!(MAX_COMMAND_BUFFER >= 64);
        assert!(MAX_COMMAND_BUFFER <= 1024);
    }
}
