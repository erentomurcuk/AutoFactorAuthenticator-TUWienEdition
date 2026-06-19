#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOST_NAME="com.tuwien.2fa"

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
  if [ -f "$manifest" ]; then
    rm "$manifest"
    echo "Removed: $manifest"
  else
    echo "No manifest found at $manifest"
  fi
  echo "Uninstall complete."
}

main
