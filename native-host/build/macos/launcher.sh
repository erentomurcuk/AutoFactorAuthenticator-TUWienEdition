#!/bin/bash
# TU Wien 2FA — macOS app entry point
# Installs/uninstalls the native messaging host for Firefox.

set -euo pipefail

RESOLVED="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
APP_BUNDLE="$(dirname "$(dirname "$(dirname "$RESOLVED")")")"
BINARY_PATH="$APP_BUNDLE/Contents/MacOS/tuwien-2fa-native"
MANIFEST_DIR="$HOME/Library/Application Support/Mozilla/NativeMessagingHosts"
MANIFEST_FILE="$MANIFEST_DIR/com.tuwien.2fa.json"

show_dialog() {
  osascript -e "display dialog \"$1\" buttons {\"$2\", \"$3\"} default button \"$3\" with icon $4"
}

show_alert() {
  osascript -e "display dialog \"$1\" buttons {\"$2\"} default button \"$2\" with icon $3"
}

install_manifest() {
  mkdir -p "$MANIFEST_DIR"
  cat > "$MANIFEST_FILE" << EOF
{
  "name": "com.tuwien.2fa",
  "description": "Native host for TU Wien Auto 2FA",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_extensions": ["tuwien-auto-2fa@aGreatTUWienStudent"]
}
EOF
}

uninstall_manifest() {
  rm -f "$MANIFEST_FILE"
  if [ -x "$BINARY_PATH" ]; then
    "$BINARY_PATH" --delete-credential 2>/dev/null || true
  fi
}

is_installed() {
  [ -f "$MANIFEST_FILE" ] && [ -x "$BINARY_PATH" ]
}

move_to_trash() {
  local app_path="$APP_BUNDLE"
  osascript -e "tell application \"Finder\" to delete POSIX file \"$app_path\"" 2>/dev/null || true
}

# --- Uninstall mode ---
if [[ "${1:-}" == "--uninstall" ]]; then
  CONFIRM=$(show_dialog "Remove TU Wien 2FA from your system?\n\nYour TOTP seed will be deleted from the macOS Keychain." "Cancel" "Uninstall" caution)
  if ! echo "$CONFIRM" | grep -q "Uninstall"; then
    exit 0
  fi
  uninstall_manifest
  move_to_trash
  show_alert "TU Wien 2FA has been uninstalled.\n\nThe app has been moved to the Trash." "OK" note
  exit 0
fi

# --- Normal launch ---
if [ ! -x "$BINARY_PATH" ]; then
  show_alert "TU Wien 2FA native host was not found in the expected location.\n\nPlease make sure the app bundle is intact." "OK" stop
  exit 1
fi

if is_installed; then
  RESULT=$(show_dialog "TU Wien 2FA is installed and ready.\n\nFirefox can communicate with the native host.\n\nWhat would you like to do?" "Cancel" "Uninstall" note)
  if echo "$RESULT" | grep -q "Uninstall"; then
    uninstall_manifest
    move_to_trash
    show_alert "TU Wien 2FA has been uninstalled.\n\nThe app has been moved to the Trash." "OK" note
  fi
  exit 0
fi

RESULT=$(show_dialog "TU Wien 2FA needs to register with Firefox.\n\nThis creates a small configuration file so the extension can communicate with the native host.\n\nNo personal data is stored. Your TOTP seed will be saved securely in your macOS Keychain when you configure it in the extension.\n\nDo you want to proceed?" "Cancel" "Install" caution)
if ! echo "$RESULT" | grep -q "Install"; then
  exit 0
fi

install_manifest
show_alert "Installation complete!\n\nTU Wien 2FA is now ready to use with Firefox.\n\nTo uninstall later, open this app again." "OK" note
