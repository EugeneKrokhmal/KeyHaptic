#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/dist/KeyHaptic.app"
if [[ ! -d "$APP" ]]; then
  echo "Missing $APP — run ./scripts/build.sh first (or with --skip-install)." >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
DMG_NAME="KeyHaptic-${VERSION}.dmg"
DMG_PATH="$ROOT/dist/$DMG_NAME"

STAGE="$(mktemp -d)/KeyHaptic-dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/KeyHaptic.app"
ln -s /Applications "$STAGE/Applications"

# Short install note for first-run permissions
cat > "$STAGE/Permissions.txt" <<'EOF'
After installing KeyHaptic to Applications:

1. Open the app once from Applications
2. System Settings → Privacy & Security → Input Monitoring → enable KeyHaptic
3. System Settings → Privacy & Security → Accessibility → enable KeyHaptic
4. Quit & Reopen KeyHaptic

Menu bar icon should then say it is listening.
EOF

rm -f "$DMG_PATH"
hdiutil create \
  -volname "KeyHaptic" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH"

# Ad-hoc sign the DMG (optional; notarization needs Developer ID)
codesign --force --sign - "$DMG_PATH" 2>/dev/null || true

rm -rf "$(dirname "$STAGE")"

echo ""
echo "DMG ready: $DMG_PATH"
echo "Open with: open \"$DMG_PATH\""
ls -lh "$DMG_PATH"
