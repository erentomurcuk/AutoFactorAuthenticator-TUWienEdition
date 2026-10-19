#!/bin/bash
# Build a Debian package (.deb) for AutoTISS2FA (AutoFactorAuthenticator).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

VERSION="1.2.1"
ARCH="amd64"
PKG_NAME="autotiss2fa_${VERSION}_${ARCH}"

# NOTE: dpkg control files do not allow comments; the dependency rationale
# lives here. The host links ONLY libdbus-1.so.3 (readelf on the shipped
# binary). The old "Depends: libsecret-1-0" was fictional - libsecret was
# never linked, and a system WITH libsecret but WITHOUT dbus was still left
# broken. Run-time keyring access needs a Secret Service provider (GNOME
# Keyring, KDE Wallet or KeePassXC's Secret Service plugin); the Recommends
# guarantees a GUI dialog tool exists.

BINARY="$NATIVE_HOST_DIR/target/release/autotiss2fa-native"
if [ ! -f "$BINARY" ]; then
  echo "Error: Linux binary not found. Build with: (cd native-host && cargo build --release)" >&2
  exit 1
fi

# Create package structure
BUILD_DIR="$SCRIPT_DIR/$PKG_NAME"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/DEBIAN"
mkdir -p "$BUILD_DIR/opt/autotiss2fa"
mkdir -p "$BUILD_DIR/usr/share/applications"
# SVG icons are size-independent: they belong under scalable/, not 256x256.
mkdir -p "$BUILD_DIR/usr/share/icons/hicolor/scalable/apps"

cp "$SCRIPT_DIR/DEBIAN/control" "$BUILD_DIR/DEBIAN/"
cp "$SCRIPT_DIR/DEBIAN/postinst" "$BUILD_DIR/DEBIAN/"
cp "$SCRIPT_DIR/DEBIAN/prerm" "$BUILD_DIR/DEBIAN/"
chmod 755 "$BUILD_DIR/DEBIAN/postinst" "$BUILD_DIR/DEBIAN/prerm"

cp "$BINARY" "$BUILD_DIR/opt/autotiss2fa/"
chmod 755 "$BUILD_DIR/opt/autotiss2fa/autotiss2fa-native"

cp "$SCRIPT_DIR/launcher.sh" "$BUILD_DIR/opt/autotiss2fa/"
chmod 755 "$BUILD_DIR/opt/autotiss2fa/launcher.sh"

# Desktop entry
cat > "$BUILD_DIR/usr/share/applications/autotiss2fa.desktop" << 'EOF'
[Desktop Entry]
Name=AutoTISS2FA
Comment=Auto-fills TOTP codes for the TU Wien login
Exec=/opt/autotiss2fa/launcher.sh
Icon=autotiss2fa
Type=Application
Categories=Utility;Security;
Terminal=false
EOF

# Icon
if [ -f "$PROJECT_ROOT/extension/icons/icon.svg" ]; then
  cp "$PROJECT_ROOT/extension/icons/icon.svg" "$BUILD_DIR/usr/share/icons/hicolor/scalable/apps/autotiss2fa.svg"
fi

# Build package
if command -v dpkg-deb >/dev/null 2>&1; then
  # --root-owner-group: without it the package keeps the build user's
  # uid:gid on every file, which lands on target systems with confusing
  # ownership (dpkg's rootless-builds hint).
  dpkg-deb --build --root-owner-group "$BUILD_DIR"
  echo "Created: $SCRIPT_DIR/${PKG_NAME}.deb"
else
  echo "Error: dpkg-deb not found. Install with: sudo apt install dpkg-dev" >&2
  exit 1
fi

rm -rf "$BUILD_DIR"
