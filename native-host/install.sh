#!/bin/bash
set -euo pipefail

# Builds the native messaging host and registers it with Firefox for the
# current user. Windows support goes through Git Bash / MSYS the same way the
# Windows launcher does: manifest path with forward slashes, plus an HKCU
# registry entry (Firefox on Windows finds the manifest via the registry, not
# the directory).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXTENSION_ID="autotiss2fa@autofactorauthenticator"
HOST_NAME="com.autofactor.autotiss2fa"
BINARY_NAME="autotiss2fa-native"

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

require_cargo() {
  if ! command -v cargo >/dev/null 2>&1; then
    echo "Error: cargo not found. Install the Rust toolchain first:"
    echo "  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    exit 1
  fi
}

# MSYS/Cygwin build paths are "/c/Users/...", Firefox on Windows needs a
# Windows-style path. Forward slashes are valid JSON and accepted by
# CreateProcess; backslashes in the JSON would need \\ escaping.
to_windows_path() {
  local p="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$p"
  else
    echo "$p"
  fi
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
  "description": "Native host for AutoTISS2FA - stores TOTP seed in OS keychain",
  "path": "$binary_path",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF
  echo "  Installed native manifest: $manifest_dir/$HOST_NAME.json"
}

register_windows() {
  # Firefox on Windows resolves the manifest through the registry; the file
  # location is ours to choose. Keep both steps in one place.
  local manifest_file="$1"
  if command -v reg >/dev/null 2>&1; then
    reg add "HKCU\\Software\\Mozilla\\NativeMessagingHosts\\$HOST_NAME" /ve /d "$manifest_file" /f >/dev/null
    echo "  Registered manifest path in the registry (HKCU)."
  else
    echo "  Warning: reg.exe not found; run this from Git Bash / MSYS so the"
    echo "  registry key can be written, or the manifest will have no"
    echo "  registration and Firefox will not find the host."
  fi
}

main() {
  echo "=== AutoTISS2FA — native host installer (AutoFactorAuthenticator) ==="
  local os
  os=$(detect_os)
  echo "Detected OS: $os"
  if [ "$os" = "unsupported" ]; then
    echo "Error: Unsupported operating system."
    exit 1
  fi
  cd "$SCRIPT_DIR"
  require_cargo
  if [ "$os" = "macos" ]; then
    build_macos_universal
  else
    build_native "$os"
  fi

  case "$os" in
    windows)
      BINARY_PATH=$(to_windows_path "$BINARY_PATH")
      ;;
    *)
      BINARY_PATH=$(cd "$(dirname "$BINARY_PATH")" && pwd)/$(basename "$BINARY_PATH")
      ;;
  esac

  local manifest_dir
  manifest_dir=$(get_manifest_dir "$os")
  install_manifest "$manifest_dir" "$BINARY_PATH"

  case "$os" in
    windows)
      register_windows "$manifest_dir/$HOST_NAME.json"
      ;;
  esac

  echo ""
  echo "=== Installation complete ==="
  echo ""
  echo "Next steps:"
  echo "  1. Restart Firefox if it was running"
  echo "  2. Install the extension (.xpi from releases, or load extension/ via about:debugging)"
  echo "  3. Click the extension icon and paste your TOTP seed"
  echo ""
  echo "Or use web-ext for development:"
  echo "  pnpm run dev    # from the project root"
}

main
