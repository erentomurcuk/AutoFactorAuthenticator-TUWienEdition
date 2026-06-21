#!/bin/bash
# Main orchestrator for building platform-native installers.
# Usage: ./build-packages.sh [platform]
#   platform: macos | windows | linux | all (default: all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NATIVE_HOST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$NATIVE_HOST_DIR/.." && pwd)"
BUILD_DIR="$NATIVE_HOST_DIR/build"

print_usage() {
  echo "Usage: $0 [macos|windows|linux|all]"
  echo "  macos   - Build DMG installer"
  echo "  windows - Build EXE installer"
  echo "  linux   - Build deb, rpm, and AppImage"
  echo "  all     - Build everything (default)"
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
      build_macos
      build_windows
      build_linux
      ;;
    macos)   build_macos ;;
    windows) build_windows ;;
    linux)   build_linux ;;
  esac

  echo ""
  echo "=== Build complete ==="
  echo "Artifacts:"
  find "$BUILD_DIR" -maxdepth 3 -type f \( -name '*.dmg' -o -name '*.exe' -o -name '*.deb' -o -name '*.rpm' -o -name '*.AppImage' \) -print 2>/dev/null | sed 's/^/  /' || true
}

main "$@"
