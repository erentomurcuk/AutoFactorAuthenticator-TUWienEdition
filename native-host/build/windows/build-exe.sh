#!/bin/bash
# Build the Windows EXE installer using Inno Setup.
# This script is intended to run on Windows with Inno Setup installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"

# Find a Windows binary (cross-compiled or native)
BINARY=""
for path in \
  "$NATIVE_HOST_DIR/target/x86_64-pc-windows-msvc/release/tuwien-2fa-native.exe" \
  "$NATIVE_HOST_DIR/target/x86_64-pc-windows-gnu/release/tuwien-2fa-native.exe" \
  "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native.exe"; do
  if [ -f "$path" ]; then
    BINARY="$path"
    break
  fi
done

if [ -z "$BINARY" ]; then
  echo "Error: Windows binary not found. Build with one of:" >&2
  echo "  cargo xwin build --release --target x86_64-pc-windows-msvc" >&2
  echo "  cargo build --release --target x86_64-pc-windows-gnu" >&2
  exit 1
fi

# Stage files
cp "$BINARY" "$SCRIPT_DIR/tuwien-2fa-native.exe"
cp "$SCRIPT_DIR/launcher.bat" "$SCRIPT_DIR/launcher.bat"

cat > "$SCRIPT_DIR/README.txt" <<'EOF'
TU Wien Auto 2FA
================

This is NOT an official tool by TU Wien. It is a self-made project
provided AS IS. You are responsible for any possible damages or problems.

Installation
------------
1. Run the installer.
2. After installation, the launcher will open automatically.
3. Click "Y" to register with Firefox.
4. Click the extension icon in Firefox and paste your TOTP secret key.

Uninstallation
--------------
Use Windows Settings > Apps > TU Wien Auto 2FA > Uninstall.
Your TOTP seed will be removed from Windows Credential Manager.
EOF

# Compile with Inno Setup
if command -v iscc >/dev/null 2>&1; then
  iscc "$SCRIPT_DIR/inno-setup.iss"
elif [ -x "/c/Program Files (x86)/Inno Setup 6/iscc.exe" ]; then
  "/c/Program Files (x86)/Inno Setup 6/iscc.exe" "$SCRIPT_DIR/inno-setup.iss"
elif [ -x "/c/Program Files/Inno Setup 6/iscc.exe" ]; then
  "/c/Program Files/Inno Setup 6/iscc.exe" "$SCRIPT_DIR/inno-setup.iss"
else
  echo "Error: Inno Setup compiler (iscc) not found." >&2
  echo "Install Inno Setup 6 from https://jrsoftware.org/isdl.php" >&2
  exit 1
fi

echo "Created: $SCRIPT_DIR/TUWien-Auto-2FA-Setup.exe"
