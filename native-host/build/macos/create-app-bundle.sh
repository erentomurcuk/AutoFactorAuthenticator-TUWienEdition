#!/bin/bash
# Create a macOS .app bundle with the native host, launcher, and helpers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"
APP_NAME="TU Wien 2FA.app"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME"
BINARY_NAME="tuwien-2fa-native"

echo "Building universal binary..."
cd "$NATIVE_HOST_DIR"
rustup target add x86_64-apple-darwin aarch64-apple-darwin 2>/dev/null || true
cargo build --release --target x86_64-apple-darwin
cargo build --release --target aarch64-apple-darwin
lipo -create -output "$SCRIPT_DIR/$BINARY_NAME" \
  "target/x86_64-apple-darwin/release/$BINARY_NAME" \
  "target/aarch64-apple-darwin/release/$BINARY_NAME"

# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"
cp "$SCRIPT_DIR/$BINARY_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$SCRIPT_DIR/launcher.sh" "$APP_BUNDLE/Contents/MacOS/"
chmod 755 "$APP_BUNDLE/Contents/MacOS/launcher.sh"

# Generate ICNS from project SVG icon
if [ -f "$PROJECT_ROOT/extension/icons/icon.svg" ]; then
  echo "Generating app icon..."
  "$SCRIPT_DIR/svg-to-icns.sh" "$PROJECT_ROOT/extension/icons/icon.svg" "$SCRIPT_DIR/icon.icns"
  cp "$SCRIPT_DIR/icon.icns" "$APP_BUNDLE/Contents/Resources/"
fi

# Ad-hoc sign the app
codesign --sign - --force --deep "$APP_BUNDLE" 2>/dev/null || true

echo "Created: $APP_BUNDLE"
