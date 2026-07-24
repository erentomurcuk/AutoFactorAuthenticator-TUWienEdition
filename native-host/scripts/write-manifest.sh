#!/bin/bash
# Shared helper: write the Firefox native messaging manifest for the current user.
# Usage: write_manifest <binary_path> <os>
#   os: macos | linux | windows

set -euo pipefail

EXTENSION_ID="tuwien-auto-2fa@aGreatTUWienStudent"
HOST_NAME="com.tuwien.2fa"

get_manifest_dir() {
  case "$1" in
    macos)  echo "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts" ;;
    linux)  echo "$HOME/.mozilla/native-messaging-hosts" ;;
    windows) echo "$HOME/AppData/Local/Mozilla/NativeMessagingHosts" ;;
    *) echo "unsupported" ;;
  esac
}

write_manifest() {
  local binary_path="$1"
  local os="$2"
  local manifest_dir
  manifest_dir=$(get_manifest_dir "$os")

  if [ "$manifest_dir" = "unsupported" ]; then
    echo "Error: unsupported OS '$os'" >&2
    return 1
  fi

  mkdir -p "$manifest_dir"
  local manifest_file="$manifest_dir/$HOST_NAME.json"

  cat > "$manifest_file" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$binary_path",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF

  echo "$manifest_file"
}

# Allow direct execution
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <binary_path> <macos|linux|windows>" >&2
    exit 1
  fi
  write_manifest "$1" "$2"
fi
