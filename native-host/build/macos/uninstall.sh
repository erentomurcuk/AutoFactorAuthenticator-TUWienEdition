#!/bin/bash
# Uninstall AutoTISS2FA from macOS.
# Standalone helper: removes the native-messaging manifest and the keychain
# entry. The .app launcher (launcher.sh) implements the same steps inline so
# they stay one click apart in the GUI; keep both in sync when HostName or
# paths change. This script can also be run directly from Terminal.

set -euo pipefail

RESOLVED="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
APP_BUNDLE="$(dirname "$(dirname "$(dirname "$RESOLVED")")")"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/autotiss2fa-native"

# Remove manifest
rm -f "$HOME/Library/Application Support/Mozilla/NativeMessagingHosts/com.autofactor.autotiss2fa.json"

# Remove keychain entry
if [ -x "$BINARY_PATH" ]; then
  "$BINARY_PATH" --delete-credential 2>/dev/null || true
fi

echo "Uninstall complete."
