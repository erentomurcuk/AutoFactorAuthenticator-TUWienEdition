#!/bin/bash
# Build an AppImage for AutoTISS2FA (AutoFactorAuthenticator).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

BINARY="$NATIVE_HOST_DIR/target/release/autotiss2fa-native"
APP_DIR="$SCRIPT_DIR/AppDir"
RESULT="$SCRIPT_DIR/AutoTISS2FA-x86_64.AppImage"

if [ ! -f "$BINARY" ]; then
  echo "Error: Linux binary not found. Build with: (cd native-host && cargo build --release)" >&2
  exit 1
fi

# Convert SVG to PNG for the desktop icon (optional - linuxdeploy ships an
# iconless AppImage without it, which still works).
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import sys
try:
    import cairosvg
    cairosvg.svg2png(url='$PROJECT_ROOT/extension/icons/icon.svg', output_width=256, output_height=256, write_to='$SCRIPT_DIR/appimage/autotiss2fa.png')
    sys.exit(0)
except Exception:
    sys.exit(1)
" 2>/dev/null || true
fi

# Create AppDir
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/usr/bin"

cp "$BINARY" "$APP_DIR/usr/bin/"
chmod 755 "$APP_DIR/usr/bin/autotiss2fa-native"

cp "$SCRIPT_DIR/launcher.sh" "$APP_DIR/usr/bin/"
chmod 755 "$APP_DIR/usr/bin/launcher.sh"

cp "$SCRIPT_DIR/appimage/AppRun" "$APP_DIR/"
chmod 755 "$APP_DIR/AppRun"

cp "$SCRIPT_DIR/appimage/autotiss2fa.desktop" "$APP_DIR/"

if [ -f "$SCRIPT_DIR/appimage/autotiss2fa.png" ]; then
  cp "$SCRIPT_DIR/appimage/autotiss2fa.png" "$APP_DIR/"
fi

# Download linuxdeploy if not present
LINUXDEPLOY="$SCRIPT_DIR/linuxdeploy-x86_64.AppImage"
if [ ! -x "$LINUXDEPLOY" ]; then
  echo "Downloading linuxdeploy..."
  wget -q --show-progress -O "$LINUXDEPLOY" "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" || {
    echo "Error: failed to download linuxdeploy" >&2
    exit 1
  }
  chmod +x "$LINUXDEPLOY"
fi

# Build AppImage inside an isolated directory. The appimage output plugin
# writes into its own current working directory, so cd'ing there gives us a
# container with exactly one file. linuxdeploy names its result after the
# desktop entry, and the script directory already contains the linuxdeploy
# AppImage itself plus possibly earlier builds - finding the new one by
# "-name '*.AppImage'" in $SCRIPT_DIR was a real race: it could pick the
# linuxdeploy image (or a stale artifact) and mv it onto itself.
OUT_DIR=$(mktemp -d)
trap 'rm -rf "$OUT_DIR" "$APP_DIR"' EXIT

(
  cd "$OUT_DIR"
  "$LINUXDEPLOY" --appdir "$APP_DIR" --output appimage
)

BUILT=$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.AppImage' | head -n1)
if [ -z "$BUILT" ]; then
  echo "Error: linuxdeploy produced no AppImage" >&2
  exit 1
fi

mv -f "$BUILT" "$RESULT"
echo "Created: $RESULT"
