#!/usr/bin/env bash
# Build the styled disk image: app on the left, Applications on the right, arrow between.
#
# Running the app straight from the mounted image half-works and then breaks, because the
# privileged helper is registered from a path that disappears on eject. The window exists
# to make dragging to Applications the obvious move.
#
# Usage: make-dmg.sh <App.app> <out.dmg>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: make-dmg.sh <App.app> <out.dmg>}"
DMG="${2:?usage: make-dmg.sh <App.app> <out.dmg>}"
VOLNAME="Mugshot"
APP_NAME="$(basename "$APP")"

# Window geometry; mirrored in scripts/make_dmg_background.py.
WIN_W=600; WIN_H=340
ICON_Y=155; APP_X=150; FOLDER_X=450; ICON_SIZE=112

WORK="$(mktemp -d)"
STAGE="$WORK/root"
TMP_DMG="$WORK/working.dmg"
MOUNT="$WORK/mount"
mkdir -p "$STAGE" "$MOUNT"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "== Staging =="
cp -R "$APP" "$STAGE/"
# Hide the .app extension so the window reads "Mugshot" regardless of the viewer's
# Finder preferences.
SetFile -a E "$STAGE/$APP_NAME" 2>/dev/null || true
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
# Multi-resolution TIFF so the backdrop stays sharp on Retina.
tiffutil -cathidpicheck "$HERE/assets/dmg-background.png" "$HERE/assets/dmg-background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null

echo "== Creating a writable image =="
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
  -format UDRW -ov "$TMP_DMG" >/dev/null
hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT" >/dev/null

echo "== Laying out the window =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_dmg_layout.py" "$MOUNT" "$APP_NAME"

sync
hdiutil detach "$MOUNT" -quiet

echo "== Compressing =="
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
echo "✅ $DMG"
