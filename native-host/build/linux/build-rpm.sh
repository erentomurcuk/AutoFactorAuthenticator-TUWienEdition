#!/bin/bash
# Build an RPM package (.rpm) for TU Wien Auto 2FA.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

VERSION="1.1.0"
RELEASE="1"

# Ensure Linux binary exists
if [ ! -f "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" ]; then
  echo "Error: Linux binary not found. Build with: cargo build --release" >&2
  exit 1
fi

# Set up rpmbuild tree
RPMBUILD_DIR="$SCRIPT_DIR/rpmbuild"
rm -rf "$RPMBUILD_DIR"
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp "$SCRIPT_DIR/tuwien-auto-2fa.spec" "$RPMBUILD_DIR/SPECS/"
cp "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" "$RPMBUILD_DIR/SOURCES/"
cp "$SCRIPT_DIR/launcher.sh" "$RPMBUILD_DIR/SOURCES/"

# Desktop entry
cat > "$RPMBUILD_DIR/SOURCES/tuwien-2fa.desktop" << 'EOF'
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
  cp "$PROJECT_ROOT/extension/icons/icon.svg" "$RPMBUILD_DIR/SOURCES/tuwien-2fa.svg"
fi

if command -v rpmbuild >/dev/null 2>&1; then
  rpmbuild --define "_topdir $RPMBUILD_DIR" -bb "$RPMBUILD_DIR/SPECS/tuwien-auto-2fa.spec"
  
  RPM=$(find "$RPMBUILD_DIR/RPMS" -name '*.rpm' | head -n1)
  if [ -n "$RPM" ]; then
    cp "$RPM" "$SCRIPT_DIR/tuwien-auto-2fa-${VERSION}-${RELEASE}.x86_64.rpm"
    echo "Created: $SCRIPT_DIR/tuwien-auto-2fa-${VERSION}-${RELEASE}.x86_64.rpm"
  else
    echo "Error: RPM build failed" >&2
    exit 1
  fi
else
  echo "Error: rpmbuild not found. Install with: sudo dnf install rpm-build" >&2
  exit 1
fi

rm -rf "$RPMBUILD_DIR"
