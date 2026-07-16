#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="com.keyhaptic.app"
APP_NAME="KeyHaptic.app"
DIST="$ROOT/dist/$APP_NAME"
INSTALL="/Applications/$APP_NAME"

SKIP_INSTALL=0
MAKE_DMG=1
for arg in "$@"; do
  case "$arg" in
    --skip-install) SKIP_INSTALL=1 ;;
    --no-dmg) MAKE_DMG=0 ;;
    --help|-h)
      echo "Usage: ./scripts/build.sh [--skip-install] [--no-dmg]"
      exit 0
      ;;
  esac
done

ICON_SRC=""
if [[ -f "$ROOT/cap-icon.png" ]]; then
  ICON_SRC="$ROOT/cap-icon.png"
  cp -f "$ICON_SRC" "$ROOT/icon.png"
elif [[ -f "$ROOT/icon.png" ]]; then
  ICON_SRC="$ROOT/icon.png"
fi

if [[ -n "$ICON_SRC" ]]; then
  ICONSET="$(mktemp -d)/KeyHaptic.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$ICON_SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
  swift "$ROOT/scripts/make-status-icon.swift" "$ICON_SRC" 36 "$ROOT/Resources/StatusIcon.png"
  swift "$ROOT/scripts/make-status-icon.swift" "$ICON_SRC" 72 "$ROOT/Resources/StatusIcon@2x.png"
fi

swift build -c release
BINARY="$ROOT/.build/release/KeyHaptic"

killall KeyHaptic 2>/dev/null || true
sleep 0.3

rm -rf "$DIST"
mkdir -p "$DIST/Contents/MacOS"
mkdir -p "$DIST/Contents/Resources"

cp "$BINARY" "$DIST/Contents/MacOS/KeyHaptic"
cp "$ROOT/Resources/Info.plist" "$DIST/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$DIST/Contents/Resources/AppIcon.icns"
cp "$ROOT/Resources/StatusIcon.png" "$DIST/Contents/Resources/StatusIcon.png"
cp "$ROOT/Resources/StatusIcon@2x.png" "$DIST/Contents/Resources/StatusIcon@2x.png"

codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ROOT/Resources/KeyHaptic.entitlements" \
  "$DIST"

echo "Built: $DIST"

if [[ "$MAKE_DMG" -eq 1 ]]; then
  "$ROOT/scripts/package-dmg.sh"
fi

if [[ "$SKIP_INSTALL" -eq 1 ]]; then
  echo "Skipping /Applications install (--skip-install)."
  exit 0
fi

rm -rf "$INSTALL"
cp -R "$DIST" "$INSTALL"
codesign --force --deep --sign - \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ROOT/Resources/KeyHaptic.entitlements" \
  "$INSTALL"

echo "Resetting Input Monitoring + Accessibility for $BUNDLE_ID…"
tccutil reset ListenEvent "$BUNDLE_ID" >/dev/null 2>&1 || true
tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true

rm -f "$HOME/Library/Logs/KeyHaptic.log"

open "$INSTALL"
sleep 0.6
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
sleep 0.3
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

echo ""
echo "Built & installed: $INSTALL"
echo ""
echo "REQUIRED after every build:"
echo "  1. Input Monitoring  → enable KeyHaptic"
echo "  2. Accessibility     → enable KeyHaptic"
echo "  3. Click Quit & Reopen (or run: killall KeyHaptic; open /Applications/KeyHaptic.app)"
echo ""
echo "Menu should then say: Listening — type or scroll"
