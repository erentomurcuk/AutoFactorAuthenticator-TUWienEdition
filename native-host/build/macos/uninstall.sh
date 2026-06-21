#!/bin/bash
# Uninstall TU Wien 2FA from macOS.
# This is kept inside the .app bundle and called by launcher.sh --uninstall.
# It can also be run directly from Terminal.

set -euo pipefail

RESOLVED="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
APP_BUNDLE="$(dirname "$(dirname "$(dirname "$RESOLVED")")")"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/tuwien-2fa-native"

# Remove manifest
rm -f "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.tuwien.2fa.json"

# Remove keychain entry
if [ -x "$BINARY_PATH" ]; then
  "$BINARY_PATH" --delete-credential 2>/dev/null || true
fi

echo "Uninstall complete."
