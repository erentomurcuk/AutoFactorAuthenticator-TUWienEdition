#!/bin/bash
# Git Bash / MSYS twin of build-exe.ps1: builds the AutoTISS2FA Windows
# installer with Inno Setup 6.3+ (inno-setup.iss uses IsARM64 and the boolean
# "x64compatible arm64" architecture list, so 6.3 or newer is required).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BINARY_NAME="autotiss2fa-native.exe"
STAGED_X64="$SCRIPT_DIR/autotiss2fa-native-x64.exe"
STAGED_ARM64="$SCRIPT_DIR/autotiss2fa-native-arm64.exe"

# Clean stale staged binaries from an earlier run first - otherwise a binary
# that was since deleted can be shipped by accident.
rm -f "$STAGED_X64" "$STAGED_ARM64"

for p in \
  "$NATIVE_HOST_DIR/target/x86_64-pc-windows-msvc/release/$BINARY_NAME" \
  "$NATIVE_HOST_DIR/target/x86_64-pc-windows-gnu/release/$BINARY_NAME" \
  "$NATIVE_HOST_DIR/target/release/$BINARY_NAME"; do
  if [ -f "$p" ]; then
    X64_BIN="$p"
    break
  fi
done
if [ -z "${X64_BIN:-}" ]; then
  echo "Error: x64 binary not found. Build one of:" >&2
  echo "  cargo xwin build --release --target x86_64-pc-windows-msvc" >&2
  echo "  cargo build --release --target x86_64-pc-windows-gnu" >&2
  echo "  cargo build --release" >&2
  exit 1
fi

ARM64_BIN="$NATIVE_HOST_DIR/target/aarch64-pc-windows-msvc/release/$BINARY_NAME"
if [ -f "$ARM64_BIN" ]; then
  cp "$ARM64_BIN" "$STAGED_ARM64"
  echo "ARM64 binary found: $ARM64_BIN"
else
  echo "Warning: ARM64 binary not found, skipping (installer will support x64 only)"
fi

cp "$X64_BIN" "$STAGED_X64"

cat > "$SCRIPT_DIR/README.txt" << 'EOF'
AutoTISS2FA - native messaging host for Firefox
===============================================

This is NOT an official tool by TU Wien. Provided AS IS.
You are responsible for whatever happens when you use it.

The installer registers the native messaging host with Firefox and starts the
configuration console. Then:

  1. Install the .xpi extension in Firefox (about:addons > Install Add-on
     From File or search for it on the Builds channel).
  2. Click the extension icon and paste your TOTP secret.

Your TOTP seed is stored in Windows Credential Manager and never leaves this
computer.

Uninstall: Settings > Apps > AutoTISS2FA > Uninstall.
EOF

ISCC=""
for c in \
  "$(command -v iscc 2>/dev/null || true)" \
  "/c/Program Files (x86)/Inno Setup 6/iscc.exe" \
  "/c/Program Files/Inno Setup 6/iscc.exe"; do
  if [ -n "$c" ] && [ -e "$c" ]; then
    ISCC="$c"
    break
  fi
done
if [ -z "$ISCC" ]; then
  echo "Error: Inno Setup compiler (iscc) not found." >&2
  echo "Install Inno Setup 6.3+ from https://jrsoftware.org/isdl.php" >&2
  exit 1
fi

"$ISCC" "$SCRIPT_DIR/inno-setup.iss"

echo "Created: $SCRIPT_DIR/AutoTISS2FA-Setup.exe"
