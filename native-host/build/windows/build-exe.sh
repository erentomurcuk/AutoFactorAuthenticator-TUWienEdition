#!/bin/bash
# Git Bash / MSYS twin of build-exe.ps1: builds the AutoTISS2FA Windows
# installer with Inno Setup 6.3+ (the .iss uses the 'x64compatible'
# architecture identifier, and IsARM64 when the ARM64 binary is included).
#
# Default: X64-ONLY installer - no ARM64 probing, no warning on machines that
# never built the aarch64 target. Pass --arm64 (or -Arm64) for the
# dual-architecture build.
#
# Usage: bash build-exe.sh [--arm64]
#   ISCC=/path/to/iscc.exe  overrides the compiler lookup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

BINARY_NAME="autotiss2fa-native.exe"
STAGED_X64="$SCRIPT_DIR/autotiss2fa-native-x64.exe"
STAGED_ARM64="$SCRIPT_DIR/autotiss2fa-native-arm64.exe"
ISS="$SCRIPT_DIR/inno-setup.iss"

ARM64=0
for arg in "$@"; do
  case "$arg" in
    --arm64|-Arm64) ARM64=1 ;;
    -h|--help)
      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Error: unknown option '$arg' (usage: build-exe.sh [--arm64])" >&2
      exit 2
      ;;
  esac
done

# Clean stale staged binaries from an earlier run first - otherwise a binary
# that was since deleted can be shipped by accident (and a leftover arm64
# file must never slip into an x64-only installer).
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
  echo "Error: x64 host binary not found. Build one of:" >&2
  echo "  cargo build --release" >&2
  echo "  cargo build --release --target x86_64-pc-windows-gnu" >&2
  echo "  cargo xwin build --release --target x86_64-pc-windows-msvc" >&2
  exit 1
fi

cp "$X64_BIN" "$STAGED_X64"
echo "x64 binary:    $X64_BIN"

if [ "$ARM64" -eq 1 ]; then
  ARM64_BIN="$NATIVE_HOST_DIR/target/aarch64-pc-windows-msvc/release/$BINARY_NAME"
  if [ ! -f "$ARM64_BIN" ]; then
    echo "Error: --arm64 requested but the ARM64 binary is missing:" >&2
    echo "  $ARM64_BIN" >&2
    echo "Build it first:" >&2
    echo "  rustup target add aarch64-pc-windows-msvc" >&2
    echo "  cargo build --release --target aarch64-pc-windows-msvc" >&2
    echo "Or drop --arm64 to build the x64-only installer." >&2
    exit 1
  fi
  cp "$ARM64_BIN" "$STAGED_ARM64"
  echo "ARM64 binary:  $ARM64_BIN"
else
  echo "ARM64 binary:  not included (x64-only installer; use --arm64 for dual-arch)"
fi

cat > "$SCRIPT_DIR/README.txt" << 'EOF'
AutoTISS2FA - native messaging host for Firefox
================================================

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

# --- locate ISCC --------------------------------------------------------------
# Inno Setup installs PER-USER by default (winget package JRSoftware.InnoSetup
# included): %LOCALAPPDATA%\Programs\Inno Setup 6, which is neither on PATH nor
# under Program Files. Search all of it, and honour an explicit ISCC override.
ISCC_BIN="${ISCC:-}"
if [ -z "$ISCC_BIN" ]; then
  for c in \
    "$(command -v iscc 2>/dev/null || true)" \
    "$(command -v iscc.exe 2>/dev/null || true)" \
    "${LOCALAPPDATA:-}/Programs/Inno Setup 6/ISCC.exe" \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    if [ -n "$c" ] && [ -e "$c" ]; then
      ISCC_BIN="$c"
      break
    fi
  done
fi
if [ -z "$ISCC_BIN" ]; then
  echo "Error: Inno Setup compiler (ISCC.exe) not found." >&2
  echo "" >&2
  echo "Install Inno Setup 6.3 or newer:" >&2
  echo "  winget install --id JRSoftware.InnoSetup -e --accept-package-agreements --accept-source-agreements" >&2
  echo "or https://jrsoftware.org/isdl.php" >&2
  echo "" >&2
  echo "Already installed elsewhere? Point this script at it:" >&2
  echo "  ISCC='/c/Program Files/Inno Setup 6/ISCC.exe' bash build-exe.sh" >&2
  exit 1
fi
echo "ISCC:          $ISCC_BIN"

if [ "$ARM64" -eq 1 ]; then
  "$ISCC_BIN" /DArm64 "$ISS"
else
  "$ISCC_BIN" "$ISS"
fi

if [ ! -f "$SCRIPT_DIR/AutoTISS2FA-Setup.exe" ]; then
  echo "Error: expected $SCRIPT_DIR/AutoTISS2FA-Setup.exe was not produced" >&2
  exit 1
fi

if [ "$ARM64" -eq 1 ]; then
  echo "Created: $SCRIPT_DIR/AutoTISS2FA-Setup.exe (x64 + ARM64)"
else
  echo "Created: $SCRIPT_DIR/AutoTISS2FA-Setup.exe (x64 only)"
fi
