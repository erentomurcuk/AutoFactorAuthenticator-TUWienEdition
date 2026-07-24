#!/bin/bash
# Main orchestrator for building platform-native installers.
# Usage: ./build-packages.sh [platform]
#   platform: macos | windows | linux | all (default: all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"
BUILD_DIR="$NATIVE_HOST_DIR/build"

# Detect the current host OS.
host_os() {
  case "$(uname -s)" in
    Darwin) echo "macos" ;;
    Linux)  echo "linux" ;;
    MINGW*|MSYS*|CYGWIN*) echo "windows" ;;
    *) echo "unsupported" ;;
  esac
}

print_usage() {
  echo "Usage: $0 [macos|windows|linux|all]"
  echo "  macos   - Build DMG installer"
  echo "  windows - Build EXE installer"
  echo "  linux   - Build deb, rpm, and AppImage"
  echo "  all     - Build everything (default)"
}

# Decide whether a given target platform can be built on the current host.
# A platform is buildable if either:
#   * the host matches the target (native build), or
#   * a prebuilt per-target binary is already present in target/ (cross-compile).
can_build() {
  local target="$1"
  local host
  host="$(host_os)"
  if [ "$host" = "$target" ]; then
    return 0
  fi
  # Cross-compile cases we support: prebuilt binaries must exist.
  case "$target" in
    windows)
      [ -f "$NATIVE_HOST_DIR/target/x86_64-pc-windows-msvc/release/tuwien-2fa-native.exe" ] || \
      [ -f "$NATIVE_HOST_DIR/target/x86_64-pc-windows-gnu/release/tuwien-2fa-native.exe" ]
      ;;
    linux)
      [ -f "$NATIVE_HOST_DIR/target/release/tuwien-2fa-native" ]
      ;;
    macos)
      [ -f "$NATIVE_HOST_DIR/target/x86_64-apple-darwin/release/tuwien-2fa-native" ] && \
      [ -f "$NATIVE_HOST_DIR/target/aarch64-apple-darwin/release/tuwien-2fa-native" ]
      ;;
    *)
      return 1
      ;;
  esac
}

build_macos() {
  echo ""
  echo "=== Building macOS DMG ==="
  cd "$BUILD_DIR/macos"
  bash create-dmg.sh
  cd - >/dev/null
}

build_windows() {
  echo ""
  echo "=== Building Windows installer ==="
  cd "$BUILD_DIR/windows"
  bash build-exe.sh
  cd - >/dev/null
}

build_linux() {
  echo ""
  echo "=== Building Linux packages ==="
  cd "$BUILD_DIR/linux"
  bash build-deb.sh
  bash build-rpm.sh
  bash build-appimage.sh
  cd - >/dev/null
}

run_or_skip() {
  local target="$1"
  if can_build "$target"; then
    "build_$target"
  else
    echo ""
    echo "Skipping $target: not the current host and no prebuilt $target binary found."
    echo "  Cross-compile first, e.g.:"
    case "$target" in
      windows) echo "    cargo xwin build --release --target x86_64-pc-windows-msvc" ;;
      linux)   echo "    cargo build --release" ;;
      macos)   echo "    cargo build --release --target x86_64-apple-darwin --target aarch64-apple-darwin" ;;
    esac
  fi
}

main() {
  local platform="${1:-all}"

  case "$platform" in
    macos|windows|linux|all) ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "Error: unknown platform '$platform'" >&2
      print_usage
      exit 1
      ;;
  esac

  case "$platform" in
    all)
      run_or_skip macos
      run_or_skip windows
      run_or_skip linux
      ;;
    macos)   run_or_skip macos ;;
    windows) run_or_skip windows ;;
    linux)   run_or_skip linux ;;
  esac

  echo ""
  echo "=== Build complete ==="
  echo "Artifacts:"
  find "$BUILD_DIR" -maxdepth 3 -type f \( -name '*.dmg' -o -name '*.exe' -o -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \) -print 2>/dev/null | sed 's/^/  /' || true
}

main "$@"
