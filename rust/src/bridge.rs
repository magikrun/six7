//! Flutter Rust Bridge initialization and stream handling.

use flutter_rust_bridge::frb;

/// Initializes the Rust library.
/// This should be called once at app startup.
#[frb(init)]
pub fn init_app() {
    // Initialize logging
    #[cfg(debug_assertions)]
    {
        use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
        let _ = tracing_subscriber::registry()
            .with(tracing_subscriber::fmt::layer())
            .with(
                tracing_subscriber::EnvFilter::try_from_default_env()
                    .unwrap_or_else(|_| "korium_chat_native=debug".into()),
            )
            .try_init();
    }

    tracing::info!("Korium Chat Native library initialized");
}
