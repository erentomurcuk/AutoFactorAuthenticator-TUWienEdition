#!/bin/bash
# Convert an SVG file to a macOS .icns icon set.
# Usage: svg-to-icns.sh <input.svg> <output.icns>

set -euo pipefail

INPUT_SVG="$1"
OUTPUT_ICNS="$2"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

ICONSET="$WORKDIR/icon.iconset"
mkdir -p "$ICONSET"

# Try multiple renderers, fall back gracefully
render_svg() {
  local size="$1"
  local output="$2"
  
  # 1. qlmanage (macOS QuickLook)
  if command -v qlmanage >/dev/null 2>&1; then
    qlmanage -t -s "$size" -o "$WORKDIR" "$INPUT_SVG" >/dev/null 2>&1 || true
    local preview="$WORKDIR/$(basename "$INPUT_SVG").png"
    if [ -f "$preview" ]; then
      sips -z "$size" "$size" "$preview" --out "$output" >/dev/null 2>&1 && return 0
    fi
  fi
  
  # 2. sips direct (macOS sometimes handles SVG)
  sips -z "$size" "$size" "$INPUT_SVG" --out "$output" >/dev/null 2>&1 && return 0

  # 3. rsvg-convert (librsvg)
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$size" -h "$size" "$INPUT_SVG" -o "$output" >/dev/null 2>&1 && return 0
  fi

  # 4. ImageMagick
  if command -v convert >/dev/null 2>&1; then
    convert "$INPUT_SVG" -resize "${size}x${size}" "$output" >/dev/null 2>&1 && return 0
  fi

  # 5. Python cairosvg
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "
import sys
try:
    import cairosvg
    cairosvg.svg2png(url='$INPUT_SVG', output_width=$size, output_height=$size, write_to='$output')
    sys.exit(0)
except Exception as e:
    sys.exit(1)
" 2>/dev/null && return 0
  fi
  
  echo "Error: could not render SVG to PNG (size $size)" >&2
  return 1
}

SIZES=(16 32 64 128 256 512)
for size in "${SIZES[@]}"; do
  render_svg "$size" "$ICONSET/icon_${size}x${size}.png"
  if [ "$size" -lt 512 ]; then
    cp "$ICONSET/icon_${size}x${size}.png" "$ICONSET/icon_${size}x${size}@2x.png"
  fi
done

iconutil -c icns "$ICONSET" -o "$OUTPUT_ICNS"
echo "Created: $OUTPUT_ICNS"
