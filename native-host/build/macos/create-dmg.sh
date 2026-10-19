#!/bin/bash
# Build a DMG containing the AutoTISS2FA app with drag-to-Applications layout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"
APP_NAME="AutoTISS2FA.app"
DMG_NAME="AutoTISS2FA.dmg"
VOLUME_NAME="AutoTISS2FA"

# Create app bundle
bash "$SCRIPT_DIR/create-app-bundle.sh"

# Prepare DMG staging directory
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -a "$SCRIPT_DIR/$APP_NAME" "$STAGING/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$STAGING/Applications"

# Create DMG first — plain UDZO.
rm -f "$SCRIPT_DIR/$DMG_NAME"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$SCRIPT_DIR/$DMG_NAME"

# Tidy the window layout (icon size, icon positions) by asking Finder on the
# mounted volume. This only works while the volume is mounted and only on
# macOS with osascript + Finder — failures are non-fatal and the DMG stays
# perfectly usable, merely with Finder's default layout. (The old approach
# wrote a hand-rolled .DS_Store whose binary format was invented rather than
# real: Finder silently discarded it, so the "layout" it promised never
# existed. Doing it against the mounted volume is the only version that
# actually persists.)
if [ "$(uname -s)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
  MOUNT="/Volumes/$VOLUME_NAME"
  if hdiutil attach "$SCRIPT_DIR/$DMG_NAME" -quiet -mountpoint "$MOUNT" 2>/dev/null; then
    osascript <<'AS' >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "AutoTISS2FA"
    set lsprops to { arrangement type:not arranged, icon size:96 }
    open
    set current view of container window to icon view
    set icon view options of container window to lsprops
    set position of item "AutoTISS2FA.app" of container window to {150, 120}
    set position of item "Applications" of container window to {414, 120}
    close
  end tell
end tell
AS
    # Give Finder a moment to flush .DS_Store before ejecting.
    sync
    sleep 2
    hdiutil detach "$MOUNT" -quiet || true
  fi
fi

echo "Created: $SCRIPT_DIR/$DMG_NAME"
