//! Korium Chat Native Library
//!
//! Rust backend for the Flutter WhatsApp clone using Korium for P2P messaging.
//! This library exposes a safe, async API via flutter_rust_bridge.
//!
//! # Architecture
//! Uses the actor pattern for the node: a single `NodeActor` owns all node state
//! and processes commands sequentially via message passing. This eliminates lock
//! contention and makes the code easier to reason about.

mod frb_generated;

mod actor;
pub mod api;
mod bridge;
mod error;
mod message;
mod node;
mod streams;

pub use error::KoriumError;
pub use streams::{EventBroadcaster, KoriumEvent};


