#!/bin/bash
# TU Wien 2FA — Linux launcher
# Installs/uninstalls the native messaging host for Firefox.

set -euo pipefail

RESOLVED="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/$(basename "$0")"
APPDIR="$(dirname "$RESOLVED")"
BINARY_PATH="$APPDIR/tuwien-2fa-native"
MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"
MANIFEST_FILE="$MANIFEST_DIR/com.tuwien.2fa.json"

# Detect dialog tool
if command -v zenity >/dev/null 2>&1; then
  DIALOG="zenity"
elif command -v kdialog >/dev/null 2>&1; then
  DIALOG="kdialog"
else
  echo "Error: No GUI dialog tool found. Please install zenity or kdialog." >&2
  echo "  Ubuntu/Debian: sudo apt install zenity" >&2
  echo "  Fedora/RHEL: sudo dnf install zenity" >&2
  echo "  Arch: sudo pacman -S zenity" >&2
  exit 1
fi

show_dialog() {
  local title="$1"
  local text="$2"
  local type="${3:-info}"
  
  if [ "$DIALOG" = "zenity" ]; then
    case "$type" in
      question) zenity --question --title="$title" --text="$text" --width=400 ;;
      *) zenity --"$type" --title="$title" --text="$text" --width=400 ;;
    esac
  else
    case "$type" in
      question) kdialog --title="$title" --yesno "$text" ;;
      *) kdialog --title="$title" --msgbox "$text" ;;
    esac
  fi
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

check_dependencies() {
  # Check if libsecret is available
  if ! "$BINARY_PATH" --help >/dev/null 2>&1; then
    show_dialog "Missing Dependencies" \
      "The native host binary requires libsecret to store credentials securely.\n\n\
Please install the required package:\n\n\
  Ubuntu/Debian: sudo apt install libsecret-1-0\n\
  Fedora/RHEL: sudo dnf install libsecret\n\
  Arch: sudo pacman -S libsecret" \
      error
    exit 1
  fi
}

# --- Uninstall mode ---
if [[ "${1:-}" == "--uninstall" ]]; then
  if ! show_dialog "Uninstall TU Wien 2FA?" \
      "Remove TU Wien 2FA from your system?\n\nYour TOTP seed will be deleted from the keyring." \
      question; then
    exit 0
  fi
  uninstall_manifest
  show_dialog "Uninstall Complete" "TU Wien 2FA has been uninstalled." info
  exit 0
fi

# --- Normal launch ---
if [ ! -x "$BINARY_PATH" ]; then
  show_dialog "Error" "Native host binary not found. Please reinstall the application." error
  exit 1
fi

check_dependencies

if is_installed; then
  if show_dialog "TU Wien 2FA" \
      "TU Wien 2FA is installed and ready.\n\nFirefox can communicate with the native host.\n\nWhat would you like to do?" \
      question; then
    uninstall_manifest
    show_dialog "Uninstall Complete" "TU Wien 2FA has been uninstalled." info
  fi
  exit 0
fi

if show_dialog "Install TU Wien 2FA?" \
    "TU Wien 2FA needs to register with Firefox.\n\nThis creates a configuration file so the extension can communicate with the native host.\n\nNo personal data is stored. Your TOTP seed will be saved securely in your system keyring when you configure it in the extension.\n\nDo you want to proceed?" \
    question; then
  install_manifest
  show_dialog "Installation Complete" \
    "TU Wien 2FA is now ready to use with Firefox.\n\nTo uninstall later, open this app again." \
    info
fi
