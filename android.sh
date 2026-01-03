#!/bin/bash
# Build script for Six7 Android APK
# 
# Architecture:
# - Flutter app with platform channels to native code
# - Korium provides UniFFI bindings for Kotlin/Swift
# - Native bridges: KoriumBridge.kt (Android), KoriumBridge.swift (iOS)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"

# Korium source directory (adjust path as needed)
KORIUM_DIR="${KORIUM_DIR:-$HOME/git/magikrun/korium}"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f1)
BUILD_NUMBER=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | cut -d'+' -f2)

echo "🔧 Six7 Android Build Script"
echo "============================"
echo "📦 Version: $VERSION (build $BUILD_NUMBER)"

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

# Step 1: Build Korium native library
echo ""
echo "🦀 Step 1: Building Korium native library..."

if [ -d "$KORIUM_DIR" ]; then
    cd "$KORIUM_DIR"
    
    # Get Korium version
    KORIUM_VERSION=$(grep '^version' Cargo.toml | head -1 | sed 's/version = "//' | sed 's/"//')
    echo "   Korium version: $KORIUM_VERSION"
    
    # Set up Android NDK environment for cross-compilation
    NDK_VERSION=$(ls ~/Library/Android/sdk/ndk/ | sort -V | tail -1)
    export ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/$NDK_VERSION"
    NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/darwin-x86_64/bin"
    
    # Set CC and AR for aarch64-linux-android target
    export CC_aarch64_linux_android="$NDK_TOOLCHAIN/aarch64-linux-android35-clang"
    export AR_aarch64_linux_android="$NDK_TOOLCHAIN/llvm-ar"
    
    echo "   Using NDK: $NDK_VERSION"
    
    # Build for Android arm64
    echo "   Building for aarch64-linux-android..."
    cargo build --release --target aarch64-linux-android
    
    # Copy library and bindings to six7
    JNILIBS_DIR="$PROJECT_DIR/android/app/src/main/jniLibs/arm64-v8a"
    mkdir -p "$JNILIBS_DIR"
    cp "$KORIUM_DIR/target/aarch64-linux-android/release/libkorium.so" "$JNILIBS_DIR/libkorium.so"
    
    # Copy Kotlin bindings
    KORIUM_KOTLIN_SRC="$KORIUM_DIR/bindings/kotlin/uniffi/korium/korium.kt"
    KORIUM_KOTLIN_DST="$PROJECT_DIR/android/app/src/main/kotlin/uniffi/korium/korium.kt"
    if [ -f "$KORIUM_KOTLIN_SRC" ]; then
        cp "$KORIUM_KOTLIN_SRC" "$KORIUM_KOTLIN_DST"
        
        echo "✅ Korium $KORIUM_VERSION built and copied"
    else
        echo "⚠️  Kotlin bindings not found at $KORIUM_KOTLIN_SRC"
        echo "   Run 'cargo build --release' in korium to generate bindings"
    fi
    
    cd "$PROJECT_DIR"
else
    echo "⚠️  Korium source not found at $KORIUM_DIR"
    echo "   Set KORIUM_DIR environment variable or clone korium repo"
    echo "   Checking for existing bindings..."
fi

# Step 2: Verify korium UniFFI bindings are present
echo ""
echo "📦 Step 2: Checking korium UniFFI bindings..."

KORIUM_KOTLIN="$PROJECT_DIR/android/app/src/main/kotlin/uniffi/korium/korium.kt"
if [ ! -f "$KORIUM_KOTLIN" ]; then
    echo "❌ Error: korium.kt not found at $KORIUM_KOTLIN"
    echo "   Please add the korium UniFFI Kotlin bindings"
    exit 1
fi
echo "✅ korium.kt found"

# Check for native libraries
JNILIBS_DIR="$PROJECT_DIR/android/app/src/main/jniLibs"
if [ -d "$JNILIBS_DIR" ] && [ -f "$JNILIBS_DIR/arm64-v8a/libkorium.so" ]; then
    echo "✅ Native library found: libkorium.so"
    ls -lh "$JNILIBS_DIR/arm64-v8a/libkorium.so"
else
    echo "❌ Error: libkorium.so not found in jniLibs/arm64-v8a/"
    echo "   Build korium with: cargo build --release --target aarch64-linux-android"
    exit 1
fi

# Step 3: Build Flutter APK
echo ""
echo "📱 Step 3: Building Flutter APK..."
cd "$PROJECT_DIR"

flutter clean
flutter pub get

flutter build apk --release --split-per-abi

# Step 3: Copy to release folder
echo ""
echo "📁 Step 3: Copying to release folder..."
mkdir -p "$PROJECT_DIR/release"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "release/six7-v${VERSION}-arm64-v8a.apk"
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "release/six7-v${VERSION}-armeabi-v7a.apk"
cp build/app/outputs/flutter-apk/app-x86_64-release.apk "release/six7-v${VERSION}-x86_64.apk"

# Also build universal APK
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk "release/six7-v${VERSION}.apk"

echo ""
echo "✅ Build complete! APKs are in the release/ folder:"
ls -la "$PROJECT_DIR/release/"
