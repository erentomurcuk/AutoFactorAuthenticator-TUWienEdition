#!/bin/bash
# Build a Debian package (.deb) for TU Wien Auto 2FA.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

VERSION="1.0.3"
ARCH="amd64"
PKG_NAME="tuwien-auto-2fa_${VERSION}_${ARCH}"

# Ensure Linux binary exists
if [ ! -f "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" ]; then
  echo "Error: Linux binary not found. Build with: cargo build --release" >&2
  exit 1
fi

# Create package structure
BUILD_DIR="$SCRIPT_DIR/$PKG_NAME"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/opt/tuwien-2fa"
mkdir -p "$BUILD_DIR/usr/share/applications"
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps"

cp "$SCRIPT_DIR/DEBIAN/control" "$BUILD_DIR/DEBIAN/"
cp "$SCRIPT_DIR/DEBIAN/postinst" "$BUILD_DIR/DEBIAN/"
cp "$SCRIPT_DIR/DEBIAN/prerm" "$BUILD_DIR/DEBIAN/"
chmod 755 "$BUILD_DIR/DEBIAN/postinst" "$BUILD_DIR/DEBIAN/prerm"

cp "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" "$BUILD_DIR/opt/tuwien-2fa/"
chmod 755 "$BUILD_DIR/opt/tuwien-2fa/tuwien-2fa-native"

cp "$SCRIPT_DIR/launcher.sh" "$BUILD_DIR/opt/tuwien-2fa/"
chmod 755 "$BUILD_DIR/opt/tuwien-2fa/launcher.sh"

# Desktop entry
cat > "$BUILD_DIR/usr/share/applications/tuwien-2fa.desktop" << 'EOF'
[Desktop Entry]
Name=TU Wien 2FA
Comment=Auto-fills TOTP codes for TU Wien login
Exec=/opt/tuwien-2fa/launcher.sh
Icon=tuwien-2fa
Type=Application
Categories=Utility;Security;
Terminal=false
EOF

# Icon
if [ -f "$PROJECT_ROOT/extension/icons/icon.svg" ]; then
  cp "$PROJECT_ROOT/extension/icons/icon.svg" "$BUILD_DIR/usr/share/icons/hicolor/256x256/apps/tuwien-2fa.svg"
fi

# Build package
if command -v dpkg-deb >/dev/null 2>&1; then
  dpkg-deb --build "$BUILD_DIR"
  mv "$SCRIPT_DIR/$PKG_NAME.deb" "$SCRIPT_DIR/tuwien-auto-2fa_${VERSION}_${ARCH}.deb"
else
  echo "Error: dpkg-deb not found. Install with: sudo apt install dpkg-dev" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
echo "Created: $SCRIPT_DIR/tuwien-auto-2fa_${VERSION}_${ARCH}.deb"
