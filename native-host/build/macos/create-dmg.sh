#!/bin/bash
# Build a DMG containing the TU Wien 2FA app with drag-to-Applications layout.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"
APP_NAME="TU Wien 2FA.app"
DMG_NAME="TUWien-Auto-2FA.dmg"
VOLUME_NAME="TU Wien Auto 2FA"

# Create app bundle
bash "$SCRIPT_DIR/create-app-bundle.sh"

# Prepare DMG staging directory
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -a "$SCRIPT_DIR/$APP_NAME" "$STAGING/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$STAGING/Applications"

# Create .DS_Store for nice layout (icon view, grid aligned)
# We create a minimal template using a Python helper
python3 -c "
import struct, sys

def create_ds_store(path, icon_size=96, grid_spacing=80):
    bundle_name = 'TU Wien 2FA.app'
    bg_color = struct.pack('>hhhh', 0x7B, 0x2D, 0x8C, 0xFFFF)  # purple-ish

    # Minimal DS_Store with icon view, aligned grid, custom icon size
    records = b''

    # Icon size
    records += b'icgo' + struct.pack('>I', 8 + 4) + struct.pack('>I', icon_size)
    # Grid spacing
    records += b'lg1s' + struct.pack('>I', 8 + 4) + struct.pack('>I', grid_spacing)
    # View style: icon view (1)
    records += b'icvt' + struct.pack('>I', 8 + 4) + struct.pack('>I', 1)
    # Background color
    records += b'icvb' + struct.pack('>I', 8 + 8) + bg_color

    for name in [bundle_name, 'Applications']:
        records += b'Iloc' + struct.pack('>I', 8 + 8) + struct.pack('>II', 0, 0)

    # Write as a fake DS_Store (bundle format)
    with open(path, 'wb') as f:
        f.write(b'\\x00\\x00\\x00\\x01Bud1' + struct.pack('>I', 0x1000))
        f.write(b'\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00')
        f.write(b'\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00\\x00')
        # Write the records
        f.write(records)

create_ds_store('$STAGING/.DS_Store')
" 2>/dev/null || true

# Create DMG
rm -f "$SCRIPT_DIR/$DMG_NAME"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$SCRIPT_DIR/$DMG_NAME"

echo "Created: $SCRIPT_DIR/$DMG_NAME"
