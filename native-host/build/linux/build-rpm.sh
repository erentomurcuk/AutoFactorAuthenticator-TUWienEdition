#!/bin/bash
# Build an RPM package (.rpm) for AutoTISS2FA (AutoFactorAuthenticator).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

VERSION="1.2.1"
RELEASE="1"

BINARY="$NATIVE_HOST_DIR/target/release/autotiss2fa-native"
if [ ! -f "$BINARY" ]; then
  echo "Error: Linux binary not found. Build with: (cd native-host && cargo build --release)" >&2
  exit 1
fi

# The RPM spec lists the icon %files unconditionally - a silently missing SVG
# would only explode inside rpmbuild with a confusing message. Fail here,
# where the cause is obvious.
if [ ! -f "$PROJECT_ROOT/extension/icons/icon.svg" ]; then
  echo "Error: extension/icons/icon.svg missing; the RPM lists it in %files." >&2
  exit 1
fi

# Set up rpmbuild tree
RPMBUILD_DIR="$SCRIPT_DIR/rpmbuild"
rm -rf "$RPMBUILD_DIR"
mkdir -p "$RPMBUILD_DIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cp "$SCRIPT_DIR/autotiss2fa.spec" "$RPMBUILD_DIR/SPECS/"
cp "$BINARY" "$RPMBUILD_DIR/SOURCES/"
cp "$SCRIPT_DIR/launcher.sh" "$RPMBUILD_DIR/SOURCES/"

# Desktop entry
cat > "$RPMBUILD_DIR/SOURCES/autotiss2fa.desktop" << 'EOF'
[Desktop Entry]
Name=AutoTISS2FA
Comment=Auto-fills TOTP codes for the TU Wien login
Exec=/opt/autotiss2fa/launcher.sh
Icon=autotiss2fa
Type=Application
Categories=Utility;Security;
Terminal=false
EOF

cp "$PROJECT_ROOT/extension/icons/icon.svg" "$RPMBUILD_DIR/SOURCES/autotiss2fa.svg"

if command -v rpmbuild >/dev/null 2>&1; then
  rpmbuild --define "_topdir $RPMBUILD_DIR" -bb "$RPMBUILD_DIR/SPECS/autotiss2fa.spec"

  RPM=$(find "$RPMBUILD_DIR/RPMS" -name '*.rpm' | head -n1)
  if [ -n "$RPM" ]; then
    cp "$RPM" "$SCRIPT_DIR/autotiss2fa-${VERSION}-${RELEASE}.x86_64.rpm"
    echo "Created: $SCRIPT_DIR/autotiss2fa-${VERSION}-${RELEASE}.x86_64.rpm"
  else
    echo "Error: RPM build failed" >&2
    exit 1
  fi
else
  echo "Error: rpmbuild not found. Install with: sudo dnf install rpm-build" >&2
  exit 1
fi

rm -rf "$RPMBUILD_DIR"
