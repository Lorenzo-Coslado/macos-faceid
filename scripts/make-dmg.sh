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

STAGE="$(mktemp -d)"
TMP_DMG="$(mktemp -u).dmg"
MOUNT="/Volumes/$VOLNAME"
cleanup() {
  hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGE"; rm -f "$TMP_DMG"
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
hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ \
  -format UDRW -ov "$TMP_DMG" >/dev/null
hdiutil attach "$TMP_DMG" -readwrite -noverify -noautoopen -mountpoint "$MOUNT" >/dev/null

echo "== Laying out the window =="
RIGHT=$(( 200 + WIN_W ))
BOTTOM=$(( 120 + WIN_H ))
osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set sidebar width of container window to 0
    -- Set the size before anything else, then again at the end: the Finder likes to
    -- restore a remembered size when the view options change under it.
    set the bounds of container window to {200, 120, $RIGHT, $BOTTOM}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to 12
    set label position of opts to bottom
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$FOLDER_X, $ICON_Y}
    set the bounds of container window to {200, 120, $RIGHT, $BOTTOM}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT

sync
hdiutil detach "$MOUNT" -quiet
trap - EXIT

echo "== Compressing =="
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -rf "$STAGE"; rm -f "$TMP_DMG"
echo "✅ $DMG"
