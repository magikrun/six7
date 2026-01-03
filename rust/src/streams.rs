//! Stream handling for Korium events exposed to Flutter.
//!
//! This module provides async streams for:
//! - Incoming PubSub messages
//! - Incoming requests from peers
//! - Connection state changes

use crate::message::{ChatMessage, MessageStatus};
use flutter_rust_bridge::frb;
use std::sync::LazyLock;
use tokio::sync::broadcast;

/// Maximum number of events to buffer in broadcast channels.
/// SECURITY: Bounded to prevent unbounded memory growth.
const MAX_CHANNEL_BUFFER: usize = 256;

/// Global broadcaster instance for streaming events to Flutter.
/// Uses LazyLock for thread-safe lazy initialization.
pub static GLOBAL_BROADCASTER: LazyLock<EventBroadcaster> = LazyLock::new(EventBroadcaster::new);

/// Event types that can be streamed to Flutter.
#[derive(Debug, Clone)]
#[frb(dart_metadata = ("freezed"))]
pub enum KoriumEvent {
    /// A PubSub message was received
    PubSubMessage {
        topic: String,
        from_identity: String,
        data: Vec<u8>,
    },

    /// A direct request was received (needs response)
    IncomingRequest {
        from_identity: String,
        request_id: String,
        data: Vec<u8>,
    },

    /// A chat message was received
    ChatMessageReceived { message: ChatMessage },

    /// A message status update was received (delivery/read receipt)
    MessageStatusUpdate {
        message_id: String,
        status: MessageStatus,
    },

    /// Connection state changed
    ConnectionStateChanged { is_connected: bool },

    /// A peer came online or went offline
    PeerPresenceChanged {
        peer_identity: String,
        is_online: bool,
    },

    /// An error occurred
    Error { message: String },
}

/// Event broadcaster for streaming events to Flutter.
/// Uses tokio broadcast channel for multi-consumer support.
#[derive(Clone)]
pub struct EventBroadcaster {
    sender: broadcast::Sender<KoriumEvent>,
}

impl EventBroadcaster {
    /// Creates a new event broadcaster.
    #[must_use]
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(MAX_CHANNEL_BUFFER);
        Self { sender }
    }

    /// Broadcasts an event to all subscribers.
    /// Silently drops if no subscribers or channel is full.
    pub fn broadcast(&self, event: KoriumEvent) {
        // Ignore send errors (no subscribers or lagged)
        let _ = self.sender.send(event);
    }

    /// Subscribes to the event stream.
    pub fn subscribe(&self) -> broadcast::Receiver<KoriumEvent> {
        self.sender.subscribe()
    }
}

impl Default for EventBroadcaster {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_max_channel_buffer_reasonable() {
        // Verify buffer size is bounded
        assert!(MAX_CHANNEL_BUFFER >= 16);
        assert!(MAX_CHANNEL_BUFFER <= 1024);
    }

    #[test]
    fn test_broadcaster_creation() {
        let broadcaster = EventBroadcaster::new();
        // Should be able to subscribe
        let _rx = broadcaster.subscribe();
    }

    #[test]
    fn test_broadcaster_default() {
        let broadcaster = EventBroadcaster::default();
        let _rx = broadcaster.subscribe();
    }

    #[test]
    fn test_broadcaster_clone() {
        let broadcaster1 = EventBroadcaster::new();
        let broadcaster2 = broadcaster1.clone();

        // Both should share the same channel
        let mut rx = broadcaster1.subscribe();
        broadcaster2.broadcast(KoriumEvent::Error {
            message: "test".to_string(),
        });

        // Should receive the event from either broadcaster
        let event = rx.try_recv();
        assert!(event.is_ok());
    }

    #[test]
    fn test_broadcast_without_subscribers() {
        let broadcaster = EventBroadcaster::new();
        // Should not panic even without subscribers
        broadcaster.broadcast(KoriumEvent::Error {
            message: "test".to_string(),
        });
    }

    #[test]
    fn test_broadcast_with_subscriber() {
        let broadcaster = EventBroadcaster::new();
        let mut rx = broadcaster.subscribe();

        broadcaster.broadcast(KoriumEvent::ConnectionStateChanged {
            is_connected: true,
        });

        let event = rx.try_recv().unwrap();
        match event {
            KoriumEvent::ConnectionStateChanged { is_connected } => {
                assert!(is_connected);
            }
            _ => panic!("Wrong event type"),
        }
    }

    #[test]
    fn test_multiple_subscribers() {
        let broadcaster = EventBroadcaster::new();
        let mut rx1 = broadcaster.subscribe();
        let mut rx2 = broadcaster.subscribe();

        broadcaster.broadcast(KoriumEvent::PkarrAddressPublished { slot_index: 0 });

        // Both should receive the event
        assert!(rx1.try_recv().is_ok());
        assert!(rx2.try_recv().is_ok());
    }

    #[test]
    fn test_channel_lagging() {
        let broadcaster = EventBroadcaster::new();
        let mut rx = broadcaster.subscribe();

        // Fill the channel beyond capacity
        for i in 0..(MAX_CHANNEL_BUFFER + 10) {
            broadcaster.broadcast(KoriumEvent::Error {
                message: format!("msg-{}", i),
            });
        }

        // First recv should indicate lagging
        let result = rx.try_recv();
        // Either we get an event or a Lagged error
        assert!(result.is_ok() || matches!(result, Err(broadcast::error::TryRecvError::Lagged(_))));
    }

    #[test]
    fn test_korium_event_clone() {
        // Test all event variants can be cloned
        let events = vec![
            KoriumEvent::PubSubMessage {
                topic: "test".to_string(),
                from_identity: "id".to_string(),
                data: vec![1, 2, 3],
            },
            KoriumEvent::IncomingRequest {
                from_identity: "id".to_string(),
                request_id: "req".to_string(),
                data: vec![4, 5, 6],
            },
            KoriumEvent::ConnectionStateChanged { is_connected: true },
            KoriumEvent::PeerPresenceChanged {
                peer_identity: "peer".to_string(),
                is_online: true,
            },
            KoriumEvent::PkarrBootstrapSuccess {
                bootstrap_addr: "127.0.0.1:8000".to_string(),
                key_index: 0,
            },
            KoriumEvent::PkarrBootstrapFailed { keys_tried: 20 },
            KoriumEvent::PkarrAddressPublished { slot_index: 5 },
            KoriumEvent::Error {
                message: "err".to_string(),
            },
        ];

        for event in events {
            let _ = event.clone(); // Should not panic
        }
    }

    #[test]
    fn test_korium_event_debug() {
        let event = KoriumEvent::Error {
            message: "test".to_string(),
        };
        let debug_str = format!("{:?}", event);
        assert!(debug_str.contains("Error"));
        assert!(debug_str.contains("test"));
    }
}
