#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

get_binary_path_from_manifest() {
  local manifest="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['path'])" "$manifest" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    python -c "import json,sys; print(json.load(open(sys.argv[1]))['path'])" "$manifest" 2>/dev/null
  elif command -v jq >/dev/null 2>&1; then
    jq -r '.path' "$manifest" 2>/dev/null
  else
    grep -o '"path"[[:space:]]*:[[:space:]]*"[^"]*"' "$manifest" 2>/dev/null | sed 's/.*"\(.*\)"/\1/'
  fi
}

remove_credential() {
  local binary_path="$1"
  if [ -x "$binary_path" ]; then
    echo "Removing stored TOTP seed from keychain..."
    if "$binary_path" --delete-credential; then
      echo "  Keychain entry removed."
    else
      echo "  Warning: could not remove keychain entry (it may not exist)."
    fi
  else
    echo "  Warning: native host binary not found; keychain entry must be removed manually."
  fi
}

main() {
  local os
  os=$(detect_os)
  if [ "$os" = "unsupported" ]; then
    echo "Unsupported OS."
    exit 1
  fi
  local manifest_dir
  manifest_dir=$(get_manifest_dir "$os")
  local manifest="$manifest_dir/$HOST_NAME.json"
  local binary_path=""

  if [ -f "$manifest" ]; then
    binary_path=$(get_binary_path_from_manifest "$manifest")
    remove_credential "$binary_path"
    rm "$manifest"
    echo "Removed: $manifest"
  else
    echo "No manifest found at $manifest"
    # Try to locate the project-local binary anyway
    if [ "$os" = "macos" ] && [ -x "$SCRIPT_DIR/target/universal/$BINARY_NAME" ]; then
      remove_credential "$SCRIPT_DIR/target/universal/$BINARY_NAME"
    elif [ -x "$SCRIPT_DIR/target/release/$BINARY_NAME" ]; then
      remove_credential "$SCRIPT_DIR/target/release/$BINARY_NAME"
    fi
  fi

  # Clean up project-local build artifacts if they still exist
  if [ "$os" = "macos" ] && [ -d "$SCRIPT_DIR/target/universal" ]; then
    rm -f "$SCRIPT_DIR/target/universal/$BINARY_NAME"
    rmdir "$SCRIPT_DIR/target/universal" 2>/dev/null || true
  fi
  if [ -d "$SCRIPT_DIR/target/release" ]; then
    rm -f "$SCRIPT_DIR/target/release/$BINARY_NAME" "$SCRIPT_DIR/target/release/${BINARY_NAME}.exe"
  fi

  # Windows: also drop the registry pointer the installer writes.
  if [ "$os" = "windows" ] && command -v reg >/dev/null 2>&1; then
    reg delete "HKCU\\Software\\Mozilla\\NativeMessagingHosts\\$HOST_NAME" /f >/dev/null 2>&1 || true
  fi

  echo "Uninstall complete."
}

main
