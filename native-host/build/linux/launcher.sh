#!/bin/bash
# AutoTISS2FA (AutoFactorAuthenticator) - Linux launcher.
# First run: GUI consent, then writes the Firefox native-messaging manifest
# for the invoking user (NOT root - see rpm %post / deb postinst). Later runs:
# offer uninstall.

set -euo pipefail

RESOLVED="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)/$(basename "$0")"
APPDIR="$(dirname "$RESOLVED")"
BINARY_PATH="$APPDIR/autotiss2fa-native"
EXTENSION_ID="autotiss2fa@autofactorauthenticator"
HOST_NAME="com.autofactor.autotiss2fa"
MANIFEST_DIR="$HOME/.mozilla/native-messaging-hosts"
MANIFEST_FILE="$MANIFEST_DIR/$HOST_NAME.json"

# ---- dialog helper: zenity, kdialog, or plain stdout ----------------------
DIALOG_TOOL=""
detect_dialog() {
  if command -v zenity >/dev/null 2>&1; then
    DIALOG_TOOL="zenity"
  elif command -v kdialog >/dev/null 2>&1; then
    DIALOG_TOOL="kdialog"
  fi
}

show_dialog() {
  local title="$1"
  local text="$2"
  local type="${3:-info}"

  case "$type" in
    question)
      case "$DIALOG_TOOL" in
        zenity)  zenity --question --title="$title" --text="$text" --width=400 ;;
        kdialog) kdialog --title="$title" --yesno "$text" ;;
        *)       printf '%s: %s\n' "$title" "$text" >&2; return 1 ;;
      esac
      ;;
    *)
      case "$DIALOG_TOOL" in
        zenity)  zenity --"$type" --title="$title" --text="$text" --width=400 ;;
        kdialog) kdialog --title="$title" --msgbox "$text" ;;
        *)       printf '%s: %s\n' "$title" "$text" >&2 ;;
      esac
      ;;
  esac
}

# ---- probe: can the binary actually reach the keyring daemon? -------------
check_dependencies() {
  # Send a real native-messaging frame (u32 LE length + JSON) for the "probe"
  # command. NoEntry counts as a pass: the daemon is reachable, just empty.
  # The frame is printf'd straight into the pipe, and the prefix is built in
  # two steps because bash CANNOT nest "%02x" inside a "\x" escape
  # ("\x%02x" -> "missing hex digit for \x" -> a corrupt frame on the wire).
  # The %b pass expands the escapes AFTER building them; no command
  # substitution touches the raw bytes, so no trailing NUL is ever stripped.
  local payload='{"command":"probe"}'
  local esc
  esc=$(printf '\\x%02x\\x00\\x00\\x00' "${#payload}")
  local resp
  resp=$(printf '%b%s' "$esc" "$payload" \
      | "$BINARY_PATH" 2>/dev/null | tail -c +5) || true
  if ! printf '%s' "$resp" | grep -aq '"status"[[:space:]]*:[[:space:]]*"ok"'; then
    show_dialog "AutoTISS2FA" \
"This machine cannot reach its keyring daemon.\n\nThe keyring needs a Secret Service provider: GNOME Keyring (gnome-keyring), KDE Wallet (kwalletd), or KeePassXC with the Secret Service plugin.\n\nRaw response: ${resp:-<none>}" \
      "error"
    exit 1
  fi
}

install_manifest() {
  mkdir -p "$MANIFEST_DIR"
  cat > "$MANIFEST_FILE" << EOF
{
  "name": "$HOST_NAME",
  "description": "Native host for AutoTISS2FA",
  "path": "$BINARY_PATH",
  "type": "stdio",
  "allowed_extensions": ["$EXTENSION_ID"]
}
EOF
}

uninstall_manifest() {
  rm -f "$MANIFEST_FILE"
  "$BINARY_PATH" --delete-credential >/dev/null 2>&1 || true
}

is_installed() {
  [ -f "$MANIFEST_FILE" ] && [ -x "$BINARY_PATH" ]
}

move_warn() {
  echo "$1" >&2
}

# ---- CLI -------------------------------------------------------------------
case "${1:-}" in
  --uninstall)
    if [ -f "$MANIFEST_FILE" ]; then
      if show_dialog "Uninstall AutoTISS2FA" \
        "Remove AutoTISS2FA from your system?\n\nYour TOTP seed will be deleted from the system keyring." question; then
        uninstall_manifest
        show_dialog "Uninstall Complete" "AutoTISS2FA has been removed. You can now uninstall the package (sudo dpkg -r autotiss2fa / rpm -e autotiss2fa)." info
      fi
    else
      show_dialog "AutoTISS2FA" "Not installed for this user (no manifest found)." info
    fi
    exit 0
    ;;
esac

if [ ! -x "$BINARY_PATH" ]; then
  show_dialog "AutoTISS2FA" "Native host binary missing at $BINARY_PATH" error
  exit 1
fi

detect_dialog
if [ -z "$DIALOG_TOOL" ]; then
  show_dialog "AutoTISS2FA" \
"Neither zenity nor kdialog was found.\n\nInstall one to finish registration:\n  Debian/Ubuntu: sudo apt install zenity\n  Fedora: sudo dnf install zenity\n  Arch: sudo pacman -S zenity" \
    "error"
  exit 1
fi

if is_installed; then
  if show_dialog "AutoTISS2FA" "It is already installed for this user.\n\nRun it again to unregister? (this also deletes your TOTP seed from the keyring)" question; then
    uninstall_manifest
    show_dialog "Uninstall Complete" "Unregistered AutoTISS2FA from Firefox." info
  fi
else
  if show_dialog "Install AutoTISS2FA" \
    "AutoTISS2FA needs to register with Firefox.\n\nThis will create a configuration file that allows the Firefox extension to communicate with the native host.\n\nNo personal data is stored. Your TOTP seed will be saved securely in your system keyring.\n\nDo you want to proceed?" question; then
    check_dependencies
    install_manifest
    show_dialog "Install Complete" "AutoTISS2FA is now registered with Firefox.\n\nRestart Firefox if it was open, then install the extension (.xpi) in Firefox." info
  fi
fi
