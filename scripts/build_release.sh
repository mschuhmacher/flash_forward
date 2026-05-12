#!/bin/bash
#
# Usage:
#   ./scripts/build_release.sh          # both platforms
#   ./scripts/build_release.sh android  # Android only
#   ./scripts/build_release.sh ios      # iOS only

set -e

SYMBOLS_DIR="build/debug-symbols"

usage() {
  echo "Usage: $0 [android|ios|all]"
  echo "  android  Build AAB and upload debug symbols to Sentry"
  echo "  ios      Upload Dart debug symbols to Sentry (archive in Xcode manually)"
  echo "  all      Do both"
  exit 1
}

check_version() {
  current_version=$(grep '^version:' pubspec.yaml | awk '{print $2}')
  echo ""
  echo "Current version in pubspec.yaml: $current_version"
  echo "Have you updated the version for this release? (y/n)"
  read -r answer
  if [[ "$answer" != "y" ]]; then
    echo "Update the version in pubspec.yaml first, then re-run this script."
    exit 1
  fi
}

build_android() {
  echo "==> Building Android App Bundle..."
  flutter build appbundle \
    --dart-define-from-file=config.json \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR"

  echo "==> Uploading debug symbols to Sentry..."
  flutter packages pub run sentry_dart_plugin

  echo ""
  echo "Android done. AAB is at build/app/outputs/bundle/release/app-release.aab"
}

build_ios() {
  echo "==> Building Flutter iOS release (no archive — do that in Xcode)..."
  flutter build ios \
    --dart-define-from-file=config.json \
    --obfuscate \
    --split-debug-info="$SYMBOLS_DIR" \
    --release

  echo "==> Uploading Dart debug symbols to Sentry..."
  flutter packages pub run sentry_dart_plugin

  echo ""
  echo "iOS Dart symbols uploaded."
  echo "Next: open Xcode, archive Runner, and distribute to App Store Connect."
}

TARGET="${1:-all}"

case "$TARGET" in
  android|ios|all) ;;
  *) usage ;;
esac

check_version

case "$TARGET" in
  android) build_android ;;
  ios)     build_ios ;;
  all)     build_android && build_ios ;;
esac

echo ""
echo "Done."
