#!/bin/bash
# Build an AppImage for TU Wien Auto 2FA.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

# Ensure Linux binary exists
if [ ! -f "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" ]; then
  echo "Error: Linux binary not found. Build with: cargo build --release" >&2
  exit 1
fi

# Convert SVG to PNG for desktop icon
if command -v python3 >/dev/null 2>&1; then
  python3 -c "
import sys
try:
    import cairosvg
    cairosvg.svg2png(url='$PROJECT_ROOT/extension/icons/icon.svg', output_width=256, output_height=256, write_to='$SCRIPT_DIR/appimage/tuwien-2fa.png')
except Exception:
    sys.exit(1)
" 2>/dev/null || true
fi

# Create AppDir
APPDIR="$SCRIPT_DIR/AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin"

cp "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" "$APPDIR/usr/bin/"
chmod 755 "$APPDIR/usr/bin/tuwien-2fa-native"

cp "$SCRIPT_DIR/launcher.sh" "$APPDIR/usr/bin/"
chmod 755 "$APPDIR/usr/bin/launcher.sh"

cp "$SCRIPT_DIR/appimage/AppRun" "$APPDIR/"
chmod 755 "$APPDIR/AppRun"

cp "$SCRIPT_DIR/appimage/tuwien-2fa.desktop" "$APPDIR/"

if [ -f "$SCRIPT_DIR/appimage/tuwien-2fa.png" ]; then
  cp "$SCRIPT_DIR/appimage/tuwien-2fa.png" "$APPDIR/"
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

# Build AppImage
"$LINUXDEPLOY" --appdir "$APPDIR" --output appimage

# Move result to predictable name
APPIMAGE=$(find "$SCRIPT_DIR" -maxdepth 1 -name '*.AppImage' | head -n1)
if [ -n "$APPIMAGE" ]; then
  mv "$APPIMAGE" "$SCRIPT_DIR/TUWien-Auto-2FA-x86_64.AppImage"
  echo "Created: $SCRIPT_DIR/TUWien-Auto-2FA-x86_64.AppImage"
else
  echo "Error: AppImage build failed" >&2
  exit 1
fi

rm -rf "$APPDIR"
