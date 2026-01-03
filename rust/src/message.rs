//! Chat message types for the Korium Chat native library.

use flutter_rust_bridge::frb;
use serde::{Deserialize, Serialize};

/// Status of a chat message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum MessageStatus {
    /// Message is pending to be sent.
    Pending,
    /// Message has been sent to the network.
    Sent,
    /// Message has been delivered to the recipient.
    Delivered,
    /// Message has been read by the recipient.
    Read,
    /// Message failed to send.
    Failed,
}

/// Type of chat message.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[frb]
pub enum MessageType {
    /// Plain text message.
    Text,
    /// Image message.
    Image,
    /// Video message.
    Video,
    /// Audio message.
    Audio,
    /// Document/file message.
    Document,
    /// Location message.
    Location,
    /// Contact card message.
    Contact,
}

/// A chat message.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[frb(dart_metadata = ("freezed"))]
pub struct ChatMessage {
    /// Unique message ID (UUID).
    pub id: String,

    /// Identity of the sender.
    pub sender_id: String,

    /// Identity of the recipient.
    pub recipient_id: String,

    /// Message content (text or path/URL for media).
    pub text: String,

    /// Type of message.
    pub message_type: MessageType,

    /// Timestamp in milliseconds since Unix epoch.
    pub timestamp_ms: i64,

    /// Message status.
    pub status: MessageStatus,

    /// Whether the message is from the current user.
    pub is_from_me: bool,

    /// Optional reply-to message ID.
    pub reply_to_id: Option<String>,

    /// Optional media URL.
    pub media_url: Option<String>,

    /// Optional media thumbnail URL.
    pub thumbnail_url: Option<String>,

    /// Optional media size in bytes.
    pub media_size_bytes: Option<i64>,

    /// Optional media duration in milliseconds.
    pub media_duration_ms: Option<i64>,
}

impl ChatMessage {
    /// Creates a new text message.
    #[must_use]
    pub fn new_text(
        id: String,
        sender_id: String,
        recipient_id: String,
        text: String,
        is_from_me: bool,
    ) -> Self {
        Self {
            id,
            sender_id,
            recipient_id,
            text,
            message_type: MessageType::Text,
            timestamp_ms: chrono_timestamp_ms(),
            status: MessageStatus::Pending,
            is_from_me,
            reply_to_id: None,
            media_url: None,
            thumbnail_url: None,
            media_size_bytes: None,
            media_duration_ms: None,
        }
    }

    /// Updates the message status.
    #[must_use]
    pub fn with_status(mut self, status: MessageStatus) -> Self {
        self.status = status;
        self
    }

    /// Serializes the message to bytes for transmission.
    ///
    /// # Errors
    /// Returns an error if serialization fails.
    pub fn to_bytes(&self) -> Result<Vec<u8>, serde_json::Error> {
        serde_json::to_vec(self)
    }

    /// Deserializes a message from bytes.
    ///
    /// # Errors
    /// Returns an error if deserialization fails.
    pub fn from_bytes(data: &[u8]) -> Result<Self, serde_json::Error> {
        serde_json::from_slice(data)
    }
}

/// Returns the current timestamp in milliseconds since Unix epoch.
fn chrono_timestamp_ms() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};

    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_message_serialization() {
        let msg = ChatMessage::new_text(
            "msg-123".to_string(),
            "sender-id".to_string(),
            "recipient-id".to_string(),
            "Hello, World!".to_string(),
            true,
        );

        let bytes = msg.to_bytes().expect("serialization should succeed");
        let recovered = ChatMessage::from_bytes(&bytes).expect("deserialization should succeed");

        assert_eq!(msg.id, recovered.id);
        assert_eq!(msg.text, recovered.text);
        assert_eq!(msg.sender_id, recovered.sender_id);
    }

    #[test]
    fn test_message_status_default() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        assert_eq!(msg.status, MessageStatus::Pending);
    }

    #[test]
    fn test_message_with_status() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        )
        .with_status(MessageStatus::Sent);
        assert_eq!(msg.status, MessageStatus::Sent);
    }

    #[test]
    fn test_message_type_default() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            false,
        );
        assert_eq!(msg.message_type, MessageType::Text);
    }

    #[test]
    fn test_message_is_from_me() {
        let msg_from_me = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        assert!(msg_from_me.is_from_me);

        let msg_from_other = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            false,
        );
        assert!(!msg_from_other.is_from_me);
    }

    #[test]
    fn test_message_optional_fields_none() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        assert!(msg.reply_to_id.is_none());
        assert!(msg.media_url.is_none());
        assert!(msg.thumbnail_url.is_none());
        assert!(msg.media_size_bytes.is_none());
        assert!(msg.media_duration_ms.is_none());
    }

    #[test]
    fn test_message_timestamp_is_recent() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );

        let now_ms = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_millis() as i64;

        // Timestamp should be within 1 second of now
        assert!((msg.timestamp_ms - now_ms).abs() < 1000);
    }

    #[test]
    fn test_message_deserialization_invalid_json() {
        let invalid_json = b"not valid json";
        let result = ChatMessage::from_bytes(invalid_json);
        assert!(result.is_err());
    }

    #[test]
    fn test_message_deserialization_empty() {
        let result = ChatMessage::from_bytes(&[]);
        assert!(result.is_err());
    }

    #[test]
    fn test_message_serialization_roundtrip_with_optional_fields() {
        let mut msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        msg.reply_to_id = Some("reply-id".to_string());
        msg.media_url = Some("https://example.com/media.jpg".to_string());
        msg.thumbnail_url = Some("https://example.com/thumb.jpg".to_string());
        msg.media_size_bytes = Some(12345);
        msg.media_duration_ms = Some(60000);

        let bytes = msg.to_bytes().unwrap();
        let recovered = ChatMessage::from_bytes(&bytes).unwrap();

        assert_eq!(msg.reply_to_id, recovered.reply_to_id);
        assert_eq!(msg.media_url, recovered.media_url);
        assert_eq!(msg.thumbnail_url, recovered.thumbnail_url);
        assert_eq!(msg.media_size_bytes, recovered.media_size_bytes);
        assert_eq!(msg.media_duration_ms, recovered.media_duration_ms);
    }

    #[test]
    fn test_message_status_variants() {
        // Ensure all status variants exist and are distinct
        let statuses = [
            MessageStatus::Pending,
            MessageStatus::Sent,
            MessageStatus::Delivered,
            MessageStatus::Read,
            MessageStatus::Failed,
        ];
        for (i, s1) in statuses.iter().enumerate() {
            for (j, s2) in statuses.iter().enumerate() {
                if i == j {
                    assert_eq!(s1, s2);
                } else {
                    assert_ne!(s1, s2);
                }
            }
        }
    }

    #[test]
    fn test_message_type_variants() {
        // Ensure all type variants exist and are distinct
        let types = [
            MessageType::Text,
            MessageType::Image,
            MessageType::Video,
            MessageType::Audio,
            MessageType::Document,
            MessageType::Location,
            MessageType::Contact,
        ];
        for (i, t1) in types.iter().enumerate() {
            for (j, t2) in types.iter().enumerate() {
                if i == j {
                    assert_eq!(t1, t2);
                } else {
                    assert_ne!(t1, t2);
                }
            }
        }
    }

    #[test]
    fn test_message_clone() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        let cloned = msg.clone();
        assert_eq!(msg.id, cloned.id);
        assert_eq!(msg.text, cloned.text);
    }

    #[test]
    fn test_message_debug() {
        let msg = ChatMessage::new_text(
            "id".to_string(),
            "sender".to_string(),
            "recipient".to_string(),
            "text".to_string(),
            true,
        );
        let debug_str = format!("{:?}", msg);
        assert!(debug_str.contains("ChatMessage"));
        assert!(debug_str.contains("id"));
    }
}
