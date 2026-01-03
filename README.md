# Six7 - Ephemeral Mobile Messenger

A secure, decentralized messenger built with Flutter and powered by [Korium](https://crates.io/crates/korium).

## Features

- **End-to-end Encryption** - All messages are encrypted using Ed25519 cryptography
- **Decentralized** - No central servers, messages travel directly between peers via QUIC
- **Self-Sovereign Identity** - Your identity is your cryptographic key (with PoW spam protection)
- **NAT Traversal** - Works behind firewalls and NATs using Korium's SmartSock
- **Cross-Platform** - Runs on iOS, Android, macOS, Windows, and Linux
- **Offline-First** - Messages queued locally, synced when peers reconnect

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
│  │        Platform Channel (chat.six7/korium)          ││
│  └──────────────────────┬──────────────────────────────┘│
└─────────────────────────┼───────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────┐
│                   Native Bridge Layer                   │
│  ┌────────────────────┐    ┌────────────────────────┐   │
│  │  KoriumBridge.kt   │    │  KoriumBridge.swift    │   │
│  │    (Android)       │    │      (iOS)             │   │
│  └─────────┬──────────┘    └──────────┬─────────────┘   │
│            └──────────────┬───────────┘                 │
│                           ▼                             │
│  ┌─────────────────────────────────────────────────────┐│
│  │         Korium UniFFI Bindings (korium.kt/.swift)   ││
│  └──────────────────────┬──────────────────────────────┘│
│                         ▼                               │
│  ┌─────────────────────────────────────────────────────┐│
│  │                 Korium Native Library               ││
│  │  - QUIC-based P2P networking                        ││
│  │  - DHT for peer discovery                           ││
│  │  - GossipSub for group messaging                    ││
│  │  - Ed25519 identities & mTLS                        ││
│  │  - NAT traversal (SmartSock)                        ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

## Prerequisites

- **Flutter SDK** >= 3.27.0
- **Xcode** (for iOS/macOS builds)
- **Android Studio** with NDK (for Android builds)
- **Rust** >= 1.83.0 (to build Korium from source)

### Install Flutter

Follow the [Flutter installation guide](https://docs.flutter.dev/get-started/install) for your platform.

### Install Rust (for building Korium)

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add aarch64-linux-android  # For Android arm64
```

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/six7chat/six7.git
cd six7
```

### 2. Get Flutter dependencies

```bash
flutter pub get
```

### 3. Generate Dart code (freezed, json_serializable)

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 4. Run the app

```bash
flutter run
```

## Building for Android

### Option A: Use the build script (recommended)

The `android.sh` script handles everything:
- Builds Korium from source with cross-compilation
- Copies UniFFI bindings and native library
- Generates app icons from SVG
- Builds Flutter APKs

```bash
# Set Korium source location (default: ~/git/magikrun/korium)
export KORIUM_DIR=/path/to/korium

# Build
./android.sh
```

Output APKs will be in `release/`:
- `six7-v{version}-arm64-v8a.apk` (most devices)
- `six7-v{version}-armeabi-v7a.apk` (older devices)
- `six7-v{version}-x86_64.apk` (emulators)
- `six7-v{version}.apk` (universal, larger)

### Option B: Manual build

```bash
# 1. Build Korium for Android (in korium repo)
cd /path/to/korium
cargo build --release --target aarch64-linux-android

# 2. Copy native library
cp target/aarch64-linux-android/release/libkorium.so \
   /path/to/six7/android/app/src/main/jniLibs/arm64-v8a/

# 3. Copy UniFFI bindings
cp bindings/kotlin/uniffi/korium/korium.kt \
   /path/to/six7/android/app/src/main/kotlin/uniffi/korium/

# 4. Build APK
cd /path/to/six7
flutter build apk --release --split-per-abi
```

## Building for iOS

```bash
flutter build ios --release
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
│       │   ├── notifications/    # Local notifications
│       │   ├── router/           # GoRouter configuration
│       │   ├── storage/          # Hive persistence
│       │   └── theme/            # App theming
│       ├── features/
│       │   ├── auth/             # Onboarding screens
│       │   ├── chat/             # Chat conversation UI
│       │   ├── contacts/         # Contact management
│       │   ├── groups/           # Group chat support
│       │   ├── home/             # Chat list & tabs
│       │   ├── messaging/        # Korium integration
│       │   ├── profile/          # User profile
│       │   ├── qr/               # QR code display/scanning
│       │   ├── search/           # Message search
│       │   └── settings/         # App settings
│       └── korium/
│           └── korium_bridge.dart  # Platform channel interface
├── android/
│   └── app/src/main/
│       ├── kotlin/
│       │   ├── chat/six7/app/
│       │   │   ├── KoriumBridge.kt       # Android native bridge
│       │   │   └── KoriumForegroundService.kt
│       │   └── uniffi/korium/
│       │       └── korium.kt             # UniFFI bindings
│       └── jniLibs/
│           └── arm64-v8a/
│               └── libkorium.so          # Native library
├── ios/Runner/
│   ├── KoriumBridge.swift        # iOS native bridge
│   ├── korium.swift              # UniFFI bindings
│   └── koriumFFI.h               # FFI header
├── android.sh                    # Android build script
├── pubspec.yaml                  # Flutter dependencies
└── AGENTS.md                     # Security guidelines
```

## Korium Integration

Six7 uses Korium for all P2P communication:

### Identity
- Each user has a unique Ed25519 keypair with Proof-of-Work
- The public key (64 hex chars) serves as the user's identity
- PoW prevents Sybil attacks and spam
- No phone numbers or emails required

### Messaging
- **Direct Messages**: Request-response via `send()` with automatic ACK
- **Group Messages**: GossipSub pub/sub for group chats
- All connections use mutual TLS with Ed25519 certificates

### Discovery
- Peers bootstrap via `bootstrapPublic()` (DNS-based seed nodes)
- DHT stores peer contact information
- QR codes contain identity + routable addresses for direct connection

### NAT Traversal
- SmartSock handles UDP hole punching
- Relay fallback for symmetric NAT
- Works on mobile networks and behind firewalls

## Message Flow

```
┌─────────┐                                           ┌─────────┐
│  Alice  │                                           │   Bob   │
└────┬────┘                                           └────┬────┘
     │                                                     │
     │  1. Alice adds Bob (QR scan or identity)            │
     │ ─────────────────────────────────────────────────>  │
     │                                                     │
     │  2. Alice sends contactRequest                      │
     │ ─────────────────────────────────────────────────>  │
     │                    [Korium send()]                  │
     │                                                     │
     │  3. Bob auto-accepts, adds Alice                    │
     │  4. Bob sends contactAccepted                       │
     │ <─────────────────────────────────────────────────  │
     │                    [Korium send()]                  │
     │                                                     │
     │  5. Normal chat messages                            │
     │ <────────────────────────────────────────────────>  │
     │           [Korium send() with ACK]                  │
     │                                                     │
```

## Security Considerations

Per the [AGENTS.md](AGENTS.md) guidelines:

- **Input Validation**: All network inputs validated for size and format
- **Bounded Collections**: Event buffers and caches have explicit limits
- **Timeouts**: All network operations have configurable timeouts
- **Resource Bounds**: Message sizes capped (64KB max)
- **Error Handling**: Explicit Result types, no silent failures
- **Identity Verification**: Sender identity verified against Korium-authenticated source

## Development

### Running Tests

```bash
flutter test
```

### Code Generation

After modifying `@freezed` classes or JSON models:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Linting

```bash
flutter analyze
```

## Troubleshooting

### Bootstrap fails on emulator

Android emulators use NAT (10.0.2.x network) which prevents incoming UDP connections. Options:
1. Test on a real device
2. Use two emulators on the same host (they can communicate locally)
3. Use port forwarding: `adb forward tcp:PORT tcp:PORT`

### "Content hash mismatch" error

Rebuild native libraries after Rust code changes:
```bash
./android.sh  # For Android
```

### Build fails with NDK error

Ensure Android NDK is installed and `ANDROID_NDK_HOME` is set:
```bash
export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/VERSION"
```

## Acknowledgments

- [Korium](https://crates.io/crates/korium) - Next-gen P2P networking fabric
- [Flutter](https://flutter.dev/) - Cross-platform UI framework
- [Riverpod](https://riverpod.dev/) - State management
- [UniFFI](https://mozilla.github.io/uniffi-rs/) - Rust FFI bindings

## License

MIT License - see [LICENSE](LICENSE) for details.
