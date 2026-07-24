#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSION_ID="tuwien-auto-2fa@aGreatTUWienStudent"
HOST_NAME="com.tuwien.2fa"
BINARY_NAME="tuwien-2fa-native"

detect_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unsupported" ;;
  esac
}

get_manifest_dir() {
  case "$1" in
    macos)  echo "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" ;;
    linux)  echo "$HOME/.mozilla/native-messaging-hosts" ;;
    windows) echo "$HOME/AppData/Local/Mozilla/NativeMessagingHosts" ;;
  esac
}

build_macos_universal() {
  echo "Building macOS universal binary..."
  rustup target add x86_64-apple-darwin 2>/dev/null || true
  rustup target add aarch64-apple-darwin 2>/dev/null || true
  echo "  Building for x86_64-apple-darwin..."
  cargo build --release --target x86_64-apple-darwin
  echo "  Building for aarch64-apple-darwin..."
  cargo build --release --target aarch64-apple-darwin
  mkdir -p "$SCRIPT_DIR/target/universal"
  lipo -create -output "$SCRIPT_DIR/target/universal/$BINARY_NAME" \
    "$SCRIPT_DIR/target/x86_64-apple-darwin/release/$BINARY_NAME" \
    "$SCRIPT_DIR/target/aarch64-apple-darwin/release/$BINARY_NAME"
  BINARY_PATH="$SCRIPT_DIR/target/universal/$BINARY_NAME"
  echo "  Created universal binary at $BINARY_PATH"
}

build_native() {
  local os="$1"
  echo "Building for $os..."
  cargo build --release
  BINARY_PATH="$SCRIPT_DIR/target/release/$BINARY_NAME"
  if [ "$os" = "windows" ]; then
    BINARY_PATH="${BINARY_PATH}.exe"
  fi
  echo "  Binary at $BINARY_PATH"
}

install_manifest() {
  local manifest_dir="$1"
  local binary_path="$2"
  mkdir -p "$manifest_dir"
  cat > "$manifest_dir/$HOST_NAME.json" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native host for TU Wien Auto 2FA - stores TOTP seed in OS keychain",
  "path": "$binary_path",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF
  echo "  Installed native manifest: $manifest_dir/$HOST_NAME.json"
}

main() {
  echo "=== TU Wien Auto 2FA - Native Host Installer ==="
  local os
  os=$(detect_os)
  echo "Detected OS: $os"
  if [ "$os" = "unsupported" ]; then
    echo "Error: Unsupported operating system."
    exit 1
  fi
  cd "$SCRIPT_DIR"
  if [ "$os" = "macos" ]; then
    build_macos_universal
  else
    build_native "$os"
  fi
  local manifest_dir
  manifest_dir=$(get_manifest_dir "$os")
  install_manifest "$manifest_dir" "$BINARY_PATH"
  echo ""
  echo "=== Installation complete ==="
  echo ""
  echo "Next steps:"
  echo "  1. Restart Firefox if it was running"
  echo "  2. Go to about:debugging#/runtime/this-firefox"
  echo "  3. Load the extension from: $SCRIPT_DIR/../extension"
  echo "  4. Click the extension icon and paste your TOTP seed"
  echo ""
  echo "Or use web-ext for development:"
  echo "  npm run dev    # from the project root"
}

main
