# Six7 ephemeral mobile messenger built on Korium

A secure, decentralized messenger built with Flutter and powered by [Korium](https://crates.io/crates/korium).

## Features

- **End-to-end Encryption** - All messages are encrypted using Ed25519 cryptography
- **Decentralized** - No central servers, messages travel directly between peers
- **Self-Sovereign Identity** - Your identity is your cryptographic key
- **NAT Traversal** - Works behind firewalls and NATs using Korium's SmartSock
- **Cross-Platform** - Runs on iOS, Android, macOS, Windows, and Linux

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Flutter UI                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────┐  │
│  │   Chats     │  │   Chat      │  │   Contacts      │  │
│  │   List      │  │   Screen    │  │   Screen        │  │
│  └──────┬──────┘  └──────┬──────┘  └────────┬────────┘  │
│         └────────────────┼──────────────────┘           │
│                          ▼                              │
│  ┌─────────────────────────────────────────────────────┐│
│  │              Riverpod State Management              ││
│  │   (KoriumNodeProvider, MessageProvider, etc.)       ││
│  └──────────────────────┬──────────────────────────────┘│
│                         ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │           Flutter Rust Bridge (FFI)                 ││
│  └──────────────────────┬──────────────────────────────┘│
└─────────────────────────┼───────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────┐
│                   Rust Native Library                   │
│  ┌─────────────────────────────────────────────────────┐│
│  │                  KoriumNode Wrapper                 ││
│  │  - Message handling                                 ││
│  │  - Peer management                                  ││
│  │  - PubSub subscriptions                             ││
│  └──────────────────────┬──────────────────────────────┘│
│                         ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │                    Korium Crate                     ││
│  │  - P2P networking (DHT, GossipSub)                  ││
│  │  - NAT traversal (SmartSock, Relay)                 ││
│  │  - Ed25519 identities & mTLS                        ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Flutter SDK** >= 3.27.0
- **Rust** >= 1.83.0
- **flutter_rust_bridge_codegen** (installed globally)

### Install Rust

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Install Flutter

Follow the [Flutter installation guide](https://docs.flutter.dev/get-started/install) for your platform.

### Install flutter_rust_bridge_codegen

```bash
cargo install flutter_rust_bridge_codegen
```

### Install cargo-ndk (for Android builds)

```bash
cargo install cargo-ndk
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
```

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/magikrun/six7.git
cd six7
```

### 2. Generate Rust-Flutter bindings

```bash
flutter_rust_bridge_codegen generate
```

### 3. Build the Rust library

```bash
cd rust
cargo build --release
cd ..
```

### 4. Build for Android (includes cross-compiling Rust)

**Option A: Use the build script (recommended)**
```bash
./android.sh
```

**Option B: Manual build**
```bash
# Cross-compile Rust for Android (required after any Rust code change)
cd rust
cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../android/app/src/main/jniLibs build --release
cd ..

# Build APK
flutter build apk --release --split-per-abi
```

> ⚠️ **Important**: You MUST rebuild the native libraries whenever you modify Rust code or regenerate bindings, otherwise you'll get a "Content hash mismatch" error at runtime.

### 5. Get Flutter dependencies

```bash
flutter pub get
```

### 5. Generate Dart code (freezed, json_serializable)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 6. Run the app

```bash
flutter run
```

## Project Structure

```
six7/
├── lib/
│   ├── main.dart                 # App entry point
│   └── src/
│       ├── app.dart              # MaterialApp configuration
│       ├── core/
│       │   ├── constants/        # App-wide constants
│       │   ├── router/           # GoRouter configuration
│       │   ├── theme/            # App theming
│       │   └── utils/            # Utilities (Result type, etc.)
│       ├── features/
│       │   ├── auth/             # Onboarding screens
│       │   ├── chat/             # Chat conversation UI
│       │   ├── contacts/         # Contact management
│       │   ├── home/             # Chat list & tabs
│       │   ├── messaging/        # Message handling & Korium integration
│       │   └── settings/         # App settings
│       └── rust/
│           ├── api/              # Generated Dart API
│           └── frb_generated.dart
├── rust/
│   ├── Cargo.toml                # Rust dependencies
│   └── src/
│       ├── lib.rs                # Library entry point
│       ├── api.rs                # FFI API definitions
│       ├── bootstrap.rs          # STUN + Pkarr bootstrap
│       ├── bridge.rs             # FRB initialization
│       ├── error.rs              # Error types
│       ├── message.rs            # Chat message types
│       └── node.rs               # Korium node wrapper
├── pubspec.yaml                  # Flutter dependencies
└── flutter_rust_bridge.yaml      # FRB configuration
```

## Korium Integration

This app uses Korium for all P2P communication:

### Identity
- Each user has a unique Ed25519 keypair
- The public key (64 hex chars) serves as the user's identity
- No phone numbers or emails required

### Messaging
- Messages are sent directly between peers using request-response
- GossipSub can be used for group chats and presence
- All connections use mutual TLS with Ed25519 certificates

### Discovery
- Peers are discovered via Korium's DHT
- Published addresses allow others to find you
- NAT traversal is automatic via SmartSock

## Security Considerations

Per the AGENTS.md guidelines:

- **Input Validation**: All network inputs are validated for size and format
- **Timeouts**: All network operations have configurable timeouts (30s default)
- **Resource Bounds**: Message sizes are capped at 64KB (Korium's limit)
- **Error Handling**: Explicit Result types instead of exceptions
- **No Magic Numbers**: All constants are named and documented

## Development

### Running Tests

```bash
# Rust tests
cd rust && cargo test

# Flutter tests
flutter test
```

### Building for Release

```bash
# iOS
flutter build ios --release

# Android
flutter build apk --release

# macOS
flutter build macos --release
```

# Six7 Bootstrap Flow

This document describes the complete bootstrap mechanism for Six7 nodes to join the Korium P2P network.

## Overview

Six7 uses a **Pkarr DHT-based bootstrap** system. Unlike traditional P2P networks that rely on hardcoded bootstrap servers, Six7 uses the Mainline DHT (BitTorrent's distributed hash table) to discover peers dynamically.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BOOTSTRAP ARCHITECTURE                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    ┌──────────┐         ┌──────────────┐         ┌──────────────┐           │
│    │  STUN    │         │   Mainline   │         │   Korium     │           │
│    │ Servers  │         │     DHT      │         │    Node      │           │
│    └────┬─────┘         └──────┬───────┘         └──────┬───────┘           │
│         │                      │                        │                    │
│         │ ①Discover            │                        │                    │
│         │  External IP         │                        │                    │
│         │<─────────────────────┤                        │                    │
│         │                      │                        │                    │
│         │                      │ ②Resolve 20           │                    │
│         │                      │  Bootstrap Keys        │                    │
│         │                      │<───────────────────────┤                    │
│         │                      │                        │                    │
│         │                      │ ③Found Node?           │                    │
│         │                      │────────────────────────>│                   │
│         │                      │                        │                    │
│         │                      │                        │ ④mTLS Connect      │
│         │                      │                        │───────────────────>│
│         │                      │                        │                    │
│         │                      │ ⑤Publish Our          │                    │
│         │                      │  Address               │                    │
│         │                      │<───────────────────────┤                    │
│         │                      │                        │                    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Detailed Flow

### Phase 1: Node Creation (`KoriumNode::create`)

```rust
// Rust: api.rs
pub async fn create(bind_addr: String) -> Result<KoriumNode, KoriumError>
```

1. **Bind QUIC Socket**: Creates a QUIC server on `0.0.0.0:0` (random port)
2. **Generate/Load Identity**: Ed25519 keypair for node identity
3. **Auto-Bootstrap** (if `enable_pkarr_bootstrap=true`):
   - Calls `join_via_pkarr_bootstrap()`
   - Calls `publish_to_pkarr_bootstrap()`

### Phase 2: Join via Pkarr Bootstrap

```rust
// Rust: api.rs
async fn join_via_pkarr_bootstrap(&self) -> Result<bool, KoriumError>
```

1. **Create Pkarr Client**: Connects to Mainline DHT
2. **Resolve 20 Bootstrap Keys**: Queries all well-known Pkarr public keys
3. **For Each Found Node**:
   - Apply exponential backoff between failures
   - Attempt `node.bootstrap(identity, address)`
   - mTLS ensures identity verification
4. **Return**: `true` if any node connected, `false` if none found

### Phase 3: Publish to Pkarr Bootstrap

```rust
// Rust: api.rs
async fn publish_to_pkarr_bootstrap(&self) -> Result<Option<usize>, KoriumError>
```

1. **STUN Discovery**: Query 5 STUN servers in parallel for external IP
2. **Find Empty Slot**: Check all 20 bootstrap keys for empty/stale slots
3. **Random Jitter**: Wait 0-5000ms to prevent DHT rate limiting
4. **Publish TXT Record**:
   - Key: Derived from `BLAKE3("six7-bootstrap-slot-v1-" || slot_index)`
   - Name: Our Korium identity (64 hex chars)
   - Value: Our address (IP:PORT)
   - TTL: 300 seconds (5 minutes)

## The 20 Bootstrap Keys

Bootstrap keys are derived deterministically:

```rust
/// Derivation: BLAKE3("six7-bootstrap-slot-v1-" || slot_index) -> Ed25519 keypair
pub const BOOTSTRAP_KEYS: [&str; 20] = [
    "hc3mppwsmpuoqncctf1tfqne4soghac6898tzxkxa1bamtkchdoo", // slot 0
    "zdci3ohndsydatdj1fx6joornzdx4rmc16t8en59e9wxx9ocduuy", // slot 1
    // ... 18 more slots
];
```

**Key Properties**:
- Any node can derive the keypair for any slot (shared secret)
- This enables decentralized, self-healing bootstrap pool
- Stale slots (TTL expired) can be reclaimed by any node

## TXT Record Format

```
Pkarr Key: hc3mppwsmpuoqncctf1tfqne4soghac6898tzxkxa1bamtkchdoo
Record Name: six7.chat
Record Type: TXT
Record Value: "<IP>:<PORT>/<64-char-identity>"
TTL: 300 seconds
```

**Why this format?**
- Address comes first - can be used directly to connect
- Identity at end - for verification after connection
- `/` delimiter is unambiguous (IP addresses don't contain `/`)
- Ed25519 hex identities are 64 chars (exceeds 63-char DNS label limit)

Example:
```
Name: six7.chat
Type: TXT
Value: "192.168.1.100:45678/7fa3b2c1e9d8a7f6b5c4d3e2f1a0b9c8d7e6f5a4b3c2d1e0f9a8b7c6d5e4f3a2"
        <---- address ---->/<----------------------- 64 chars ----------------------->
```

## STUN Discovery

```rust
// Rust: bootstrap/stun.rs
pub async fn discover_external_address() -> Result<SocketAddr, KoriumError>
```

**STUN Servers** (queried in parallel):
1. `stun.l.google.com:19302`
2. `stun1.l.google.com:19302`
3. `stun2.l.google.com:19302`
4. `stun.cloudflare.com:3478`
5. `stun.nextcloud.com:3478`

**Parallel Query Strategy**:
- All 5 servers queried simultaneously via `futures::future::join_all`
- First successful response wins
- Timeout: 5 seconds per query

## Security Properties

### Identity Verification (mTLS)

Korium uses mTLS where the peer's Ed25519 public key IS the TLS certificate:
- If connection succeeds → peer identity is cryptographically verified
- Attacker cannot spoof a different identity
- DHT slot poisoning only allows publishing legitimate identities

### Attack Model

An attacker can:
1. ✅ Publish their own legitimate identity to claim a slot
2. ✅ Become a routing table entry
3. ❌ Impersonate other nodes (mTLS prevents this)
4. ❌ MITM connections (QUIC+mTLS encryption)

## Failure Modes

### 1. No Bootstrap Nodes Found (Empty Network)

**Symptom**: `Pkarr: no bootstrap nodes found in DHT`

**Cause**: All 20 slots are empty - this is expected for a fresh network

**Behavior**: Node sets `is_bootstrapped=true` (we ARE the network) and publishes to a slot

### 2. STUN Discovery Failed

**Symptom**: `STUN discovery failed: <error>`

**Cause**: 
- Firewall blocking UDP port 19302/3478
- Emulator with restricted networking
- All 5 STUN servers unreachable

**Behavior**: Falls back to local routable address (may not work through NAT)

### 3. Pkarr Client Creation Failed

**Symptom**: `Failed to create Pkarr client: <error>`

**Cause**: Cannot connect to Mainline DHT (network issues)

**Behavior**: Bootstrap fails, node operates in isolated mode

### 4. All Bootstrap Nodes Unreachable

**Symptom**: `Pkarr: ❌ failed to join via any bootstrap node`

**Cause**:
- Published nodes went offline
- NAT traversal failed
- Network partition

**Behavior**: Exponential backoff between attempts (1s→2s→4s→...→30s max)

### 5. Slot Publishing Failed

**Symptom**: `Failed to publish: <error>`

**Cause**: DHT rate limiting, network issues

**Behavior**: Jitter (0-5s) applied before publish to prevent rate limiting

## Constants

```rust
// bootstrap/pkarr/constants.rs
pub const BOOTSTRAP_ENTRY_COUNT: usize = 20;
pub const RECORD_TTL_SECS: u32 = 300;           // 5 minutes
pub const RESOLVE_TIMEOUT_SECS: u64 = 10;
pub const PUBLISH_JITTER_MAX_MS: u64 = 5000;    // 0-5s random jitter
pub const BOOTSTRAP_RETRY_BASE_MS: u64 = 1000;  // Initial backoff
pub const BOOTSTRAP_RETRY_MAX_MS: u64 = 30000;  // Max backoff (30s)
```

## Diagnostics

### Check Bootstrap Status

```dart
// Dart
final node = await rust.KoriumNode.create(bindAddr: '0.0.0.0:0');
print('Is Bootstrapped: ${node.isBootstrapped}');
print('Identity: ${node.identity}');
print('Local Address: ${node.localAddr}');

// Get routable address (STUN-discovered if available)
final routableAddr = await node.primaryRoutableAddress();
print('Routable Address: $routableAddr');
```

### Check STUN Discovery

```dart
// Dart
try {
  final externalAddr = await rust.discoverExternalAddress();
  print('External Address: $externalAddr');
} catch (e) {
  print('STUN Failed: $e');
}
```

### Enable Debug Logging (Rust)

Set environment variable:
```bash
RUST_LOG=six7_native=debug,pkarr=debug
```

This will show:
- Each bootstrap key resolution attempt
- STUN queries and responses
- Slot publishing attempts

## Troubleshooting

### Problem: Bootstrap Always Succeeds But No Peers Connect

**Check**:
1. Is STUN returning a routable address? (Not `0.0.0.0` or `127.0.0.1`)
2. Is the port open in NAT/firewall?
3. Are other nodes actually online?

### Problem: STUN Returns Wrong Address

**Check**:
1. Are you behind multiple NATs (carrier-grade NAT)?
2. Is your router implementing symmetric NAT?

### Problem: Bootstrap Hangs

**Check**:
1. DHT connectivity - can you reach other BitTorrent nodes?
2. Timeout configuration - increase `RESOLVE_TIMEOUT_SECS` for slow networks

## Implementation Files

| File | Purpose |
|------|---------|
| `rust/src/api.rs` | FFI API, orchestrates bootstrap flow |
| `rust/src/bootstrap.rs` | STUN + Pkarr implementations |
| `rust/src/bootstrap/stun.rs` | STUN protocol implementation |
| `rust/src/bootstrap/pkarr.rs` | Pkarr DHT client wrapper |
| `lib/.../korium_node_provider.dart` | Dart-side node lifecycle |

## Acknowledgments

- [Korium](https://crates.io/crates/korium) - The next gen networking fabric
- [flutter_rust_bridge](https://crates.io/crates/flutter_rust_bridge) - Rust-Flutter FFI
- [Riverpod](https://riverpod.dev/) - State management
