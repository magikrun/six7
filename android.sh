#!/bin/bash
# Build script for Six7 Android APK
# This ensures Rust native libraries are compiled with the correct content hash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# PROJECT_DIR is the same as SCRIPT_DIR when script is at project root
PROJECT_DIR="$SCRIPT_DIR"

# Ensure Rust toolchain is in PATH
# For cross-compilation, use rustup's toolchain (manages Android targets)
# Homebrew Rust doesn't support rustup target management
export RUSTUP_HOME="${RUSTUP_HOME:-$HOME/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export PATH="$RUSTUP_HOME/toolchains/stable-aarch64-apple-darwin/bin:$CARGO_HOME/bin:$PATH"

# Fix ffigen stdlib.h issue on macOS - set SDK path for clang
MACOS_SDK_PATH="$(xcrun --show-sdk-path 2>/dev/null || echo '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk')"
export CPATH="$MACOS_SDK_PATH/usr/include"
export SDKROOT="$MACOS_SDK_PATH"

echo "🔧 Six7 Android Build Script"
echo "============================"

# Step 0: Generate app icons from SVG
echo ""
echo "🎨 Step 0: Generating app icons from SVG..."
ASSETS_DIR="$PROJECT_DIR/assets/images"
RES_DIR="$PROJECT_DIR/android/app/src/main/res"

if command -v rsvg-convert &> /dev/null; then
    # Generate launcher icons (ic_launcher.png) for each density
    # mdpi: 48x48, hdpi: 72x72, xhdpi: 96x96, xxhdpi: 144x144, xxxhdpi: 192x192
    rsvg-convert -w 48 -h 48 "$ASSETS_DIR/app_icon.svg" -o "$RES_DIR/mipmap-mdpi/ic_launcher.png"
    rsvg-convert -w 72 -h 72 "$ASSETS_DIR/app_icon.svg" -o "$RES_DIR/mipmap-hdpi/ic_launcher.png"
    rsvg-convert -w 96 -h 96 "$ASSETS_DIR/app_icon.svg" -o "$RES_DIR/mipmap-xhdpi/ic_launcher.png"
    rsvg-convert -w 144 -h 144 "$ASSETS_DIR/app_icon.svg" -o "$RES_DIR/mipmap-xxhdpi/ic_launcher.png"
    rsvg-convert -w 192 -h 192 "$ASSETS_DIR/app_icon.svg" -o "$RES_DIR/mipmap-xxxhdpi/ic_launcher.png"
    
    # Generate foreground icons for adaptive icons (needs to be larger for safe zone)
    # Foreground: 108dp with 72dp visible = mdpi:108, hdpi:162, xhdpi:216, xxhdpi:324, xxxhdpi:432
    rsvg-convert -w 108 -h 108 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/drawable-mdpi/ic_launcher_foreground.png"
    rsvg-convert -w 162 -h 162 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/drawable-hdpi/ic_launcher_foreground.png"
    rsvg-convert -w 216 -h 216 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/drawable-xhdpi/ic_launcher_foreground.png"
    rsvg-convert -w 324 -h 324 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/drawable-xxhdpi/ic_launcher_foreground.png"
    rsvg-convert -w 432 -h 432 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/drawable-xxxhdpi/ic_launcher_foreground.png"
    
    # Also update mipmap foreground (some launchers use this)
    rsvg-convert -w 108 -h 108 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/mipmap-mdpi/ic_launcher_foreground.png"
    rsvg-convert -w 162 -h 162 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/mipmap-hdpi/ic_launcher_foreground.png"
    rsvg-convert -w 216 -h 216 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/mipmap-xhdpi/ic_launcher_foreground.png"
    rsvg-convert -w 324 -h 324 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/mipmap-xxhdpi/ic_launcher_foreground.png"
    rsvg-convert -w 432 -h 432 "$ASSETS_DIR/ic_foreground.svg" -o "$RES_DIR/mipmap-xxxhdpi/ic_launcher_foreground.png"
    
    # Generate high-res assets for Flutter
    rsvg-convert -w 1024 -h 1024 "$ASSETS_DIR/app_icon.svg" -o "$ASSETS_DIR/app_icon_1024.png"
    rsvg-convert -w 432 -h 432 "$ASSETS_DIR/ic_foreground.svg" -o "$ASSETS_DIR/app_icon_foreground.png"
    rsvg-convert -w 432 -h 432 "$ASSETS_DIR/logo.svg" -o "$ASSETS_DIR/logo.png"
    
    echo "✅ App icons generated from SVG"
else
    echo "⚠️  rsvg-convert not found. Using existing PNG icons."
    echo "   Install with: brew install librsvg"
fi

# NOTE: Hive adapters are now inline in the model files (no separate .g.dart files)
# This was done because hive_generator is incompatible with freezed 3.x

# Step 1: Regenerate Flutter-Rust bridge bindings
echo ""
echo "📦 Step 1: Regenerating Flutter-Rust bridge bindings..."
cd "$PROJECT_DIR"
flutter_rust_bridge_codegen generate

# Step 2: Cross-compile Rust for Android
echo ""
echo "🦀 Step 2: Cross-compiling Rust for Android..."
cd "$PROJECT_DIR/rust"

# Ensure Android targets are installed
echo "Checking Rust Android targets..."
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android 2>/dev/null || true

# Check if cargo-ndk is installed
if ! command -v cargo-ndk &> /dev/null; then
    echo "Installing cargo-ndk..."
    cargo install cargo-ndk
fi

# Set NDK path if not set
if [ -z "$ANDROID_NDK_HOME" ]; then
    # Try common locations
    if [ -d "$HOME/Library/Android/sdk/ndk" ]; then
        NDK_VERSION=$(ls "$HOME/Library/Android/sdk/ndk" | sort -V | tail -1)
        export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/$NDK_VERSION"
    fi
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
    echo "❌ Error: ANDROID_NDK_HOME not set and NDK not found"
    exit 1
fi

echo "Using NDK: $ANDROID_NDK_HOME"

# Build for all Android architectures
cargo ndk \
    -t arm64-v8a \
    -t armeabi-v7a \
    -t x86_64 \
    -o "$PROJECT_DIR/android/app/src/main/jniLibs" \
    build --release

# Step 3: Build Flutter APK
echo ""
echo "📱 Step 3: Building Flutter APK..."
cd "$PROJECT_DIR"

flutter clean
flutter pub get

flutter build apk --release --split-per-abi

# Step 4: Copy to release folder
echo ""
echo "📁 Step 4: Copying to release folder..."
mkdir -p "$PROJECT_DIR/release"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk release/six7-v1.0.0-arm64-v8a.apk
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk release/six7-v1.0.0-armeabi-v7a.apk
cp build/app/outputs/flutter-apk/app-x86_64-release.apk release/six7-v1.0.0-x86_64.apk

# Also build universal APK
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk release/six7-v1.0.0.apk

echo ""
echo "✅ Build complete! APKs are in the release/ folder:"
ls -la "$PROJECT_DIR/release/"
