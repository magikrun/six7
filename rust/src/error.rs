//! Error types for the Korium Chat native library.

use flutter_rust_bridge::frb;
use thiserror::Error;

/// Errors that can occur in the Korium Chat native library.
#[derive(Debug, Error)]
#[frb(dart_metadata = ("freezed"))]
pub enum KoriumError {
    /// Failed to bind to the specified address.
    #[error("Failed to bind to address: {0}")]
    BindError(String),

    /// Failed to bootstrap with the specified peer.
    #[error("Bootstrap failed: {0}")]
    BootstrapError(String),

    /// Failed to connect to a peer.
    #[error("Connection failed: {0}")]
    ConnectionError(String),

    /// Failed to send a message.
    #[error("Send failed: {0}")]
    SendError(String),

    /// Failed to receive a message.
    #[error("Receive failed: {0}")]
    ReceiveError(String),

    /// The specified peer was not found.
    #[error("Peer not found: {0}")]
    PeerNotFound(String),

    /// The operation timed out.
    #[error("Operation timed out: {0}")]
    Timeout(String),

    /// Invalid identity format.
    #[error("Invalid identity: {0}")]
    InvalidIdentity(String),

    /// Serialization/deserialization error.
    #[error("Serialization error: {0}")]
    SerializationError(String),

    /// Node is not initialized.
    #[error("Node not initialized")]
    NotInitialized,

    /// Node is already shut down.
    #[error("Node is shut down")]
    ShutDown,

    /// Internal error.
    #[error("Internal error: {0}")]
    Internal(String),
}

impl From<anyhow::Error> for KoriumError {
    fn from(err: anyhow::Error) -> Self {
        KoriumError::Internal(err.to_string())
    }
}

impl From<std::io::Error> for KoriumError {
    fn from(err: std::io::Error) -> Self {
        KoriumError::Internal(err.to_string())
    }
}

impl From<serde_json::Error> for KoriumError {
    fn from(err: serde_json::Error) -> Self {
        KoriumError::SerializationError(err.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_error_display_bind() {
        let err = KoriumError::BindError("port in use".to_string());
        let display = format!("{}", err);
        assert!(display.contains("bind"));
        assert!(display.contains("port in use"));
    }

    #[test]
    fn test_error_display_bootstrap() {
        let err = KoriumError::BootstrapError("no peers".to_string());
        let display = format!("{}", err);
        assert!(display.contains("ootstrap")); // Case-insensitive match
        assert!(display.contains("no peers"));
    }

    #[test]
    fn test_error_display_connection() {
        let err = KoriumError::ConnectionError("timeout".to_string());
        let display = format!("{}", err);
        assert!(display.contains("onnection")); // Case-insensitive match
        assert!(display.contains("timeout"));
    }

    #[test]
    fn test_error_display_send() {
        let err = KoriumError::SendError("network down".to_string());
        let display = format!("{}", err);
        assert!(display.contains("end")); // Case-insensitive match
        assert!(display.contains("network down"));
    }

    #[test]
    fn test_error_display_receive() {
        let err = KoriumError::ReceiveError("corrupted".to_string());
        let display = format!("{}", err);
        assert!(display.contains("eceive")); // Case-insensitive match
        assert!(display.contains("corrupted"));
    }

    #[test]
    fn test_error_display_peer_not_found() {
        let err = KoriumError::PeerNotFound("abc123".to_string());
        let display = format!("{}", err);
        assert!(display.contains("not found"));
        assert!(display.contains("abc123"));
    }

    #[test]
    fn test_error_display_timeout() {
        let err = KoriumError::Timeout("30s".to_string());
        let display = format!("{}", err);
        assert!(display.contains("timed out"));
        assert!(display.contains("30s"));
    }

    #[test]
    fn test_error_display_invalid_identity() {
        let err = KoriumError::InvalidIdentity("bad hex".to_string());
        let display = format!("{}", err);
        assert!(display.contains("identity"));
        assert!(display.contains("bad hex"));
    }

    #[test]
    fn test_error_display_serialization() {
        let err = KoriumError::SerializationError("invalid json".to_string());
        let display = format!("{}", err);
        assert!(display.contains("erialization")); // Case-insensitive match
        assert!(display.contains("invalid json"));
    }

    #[test]
    fn test_error_display_not_initialized() {
        let err = KoriumError::NotInitialized;
        let display = format!("{}", err);
        assert!(display.contains("not initialized"));
    }

    #[test]
    fn test_error_display_shutdown() {
        let err = KoriumError::ShutDown;
        let display = format!("{}", err);
        assert!(display.contains("shut down"));
    }

    #[test]
    fn test_error_display_internal() {
        let err = KoriumError::Internal("unexpected".to_string());
        let display = format!("{}", err);
        assert!(display.contains("nternal")); // Case-insensitive match
        assert!(display.contains("unexpected"));
    }

    #[test]
    fn test_from_anyhow_error() {
        let anyhow_err = anyhow::anyhow!("anyhow error message");
        let korium_err: KoriumError = anyhow_err.into();
        match korium_err {
            KoriumError::Internal(msg) => assert!(msg.contains("anyhow error message")),
            _ => panic!("Expected Internal error"),
        }
    }

    #[test]
    fn test_from_io_error() {
        let io_err = std::io::Error::new(std::io::ErrorKind::NotFound, "file not found");
        let korium_err: KoriumError = io_err.into();
        match korium_err {
            KoriumError::Internal(msg) => assert!(msg.contains("file not found")),
            _ => panic!("Expected Internal error"),
        }
    }

    #[test]
    fn test_from_serde_json_error() {
        let json_result: Result<String, _> = serde_json::from_str("invalid json");
        let json_err = json_result.unwrap_err();
        let korium_err: KoriumError = json_err.into();
        match korium_err {
            KoriumError::SerializationError(_) => {} // Expected
            _ => panic!("Expected SerializationError"),
        }
    }

    #[test]
    fn test_error_debug() {
        let err = KoriumError::Internal("test".to_string());
        let debug_str = format!("{:?}", err);
        assert!(debug_str.contains("Internal"));
        assert!(debug_str.contains("test"));
    }
}
