#!/bin/bash
# Shared helper: remove the Firefox native messaging manifest and the stored TOTP seed.
# Usage: cleanup_native_host <os> [binary_path]
#   os: macos | linux | windows
#   binary_path: optional path to the native host binary for keychain cleanup

set -euo pipefail

HOST_NAME="com.tuwien.2fa"

get_manifest_dir() {
  case "$1" in
    macos)  echo "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" ;;
    linux)  echo "$HOME/.mozilla/native-messaging-hosts" ;;
    windows) echo "$HOME/AppData/Local/Mozilla/NativeMessagingHosts" ;;
    *) echo "unsupported" ;;
  esac
}

delete_credential_with() {
  local binary_path="$1"
  if [ -x "$binary_path" ]; then
    echo "Removing stored TOTP seed from keychain..."
    if "$binary_path" --delete-credential; then
      echo "  Keychain entry removed."
    else
      echo "  Warning: could not remove keychain entry (it may not exist)."
    fi
  else
    echo "  Warning: native host binary not found at $binary_path; keychain entry must be removed manually."
  fi
}

cleanup_native_host() {
  local os="$1"
  local binary_path="${2:-}"
  local manifest_dir
  manifest_dir=$(get_manifest_dir "$os")

  if [ "$manifest_dir" = "unsupported" ]; then
    echo "Error: unsupported OS '$os'" >&2
    return 1
  fi

  local manifest="$manifest_dir/$HOST_NAME.json"
  if [ -f "$manifest" ]; then
    rm "$manifest"
    echo "Removed: $manifest"
  else
    echo "No manifest found at $manifest"
  fi

  if [ -n "$binary_path" ]; then
    delete_credential_with "$binary_path"
  fi
}

# Allow direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <macos|linux|windows> [binary_path]" >&2
    exit 1
  fi
  cleanup_native_host "$1" "${2:-}"
fi
