#!/usr/bin/env bash
# Construit FaceID.app (menu bar + fenêtres) et l'installe dans /Applications.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HERE/build/FaceID.app"
BUNDLE_ID="com.lorenzo.FaceID"
DEST="/Applications/FaceID.app"

echo "== Arrêt d'une instance existante =="
pkill -f "FaceID.app/Contents/MacOS/FaceID" 2>/dev/null || true
pkill -f "faceid.daemon" 2>/dev/null || true
sleep 1

echo "== Régénération du glyphe source =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_icon.py"

echo "== Icône (.icns) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_appicon.py"
ICONSET="$HERE/build/FaceID.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="$HERE/assets/appicon-1024.png"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz     "$SRC" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$HERE/assets/FaceID.icns"

echo "== Assemblage du bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>FaceID</string>
  <key>CFBundleDisplayName</key>     <string>FaceID</string>
  <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>      <string>FaceID</string>
  <key>CFBundleIconFile</key>        <string>FaceID</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>LSUIElement</key>             <true/>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>CFBundleDevelopmentRegion</key> <string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string><string>fr</string><string>es</string><string>de</string>
    <string>it</string><string>pt-BR</string><string>nl</string><string>ja</string>
    <string>zh-Hans</string><string>ko</string><string>ru</string>
  </array>
  <key>NSCameraUsageDescription</key>
  <string>Reconnaissance faciale locale pour déverrouiller sudo.</string>
  <key>FaceIDProjectRoot</key>       <string>${HERE}</string>
</dict>
</plist>
PLIST

cp "$HERE/assets/FaceID.icns" "$APP/Contents/Resources/FaceID.icns"
cp "$HERE/assets/faceid-icon.png" "$APP/Contents/Resources/faceid-icon.png"
cp "$HERE/assets/menubar-icon.png" "$APP/Contents/Resources/menubar-icon.png"

echo "== Traductions (.lproj) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_i18n.py"
cp -R "$HERE"/i18n/*.lproj "$APP/Contents/Resources/"

echo "== Compilation Swift (4 fichiers) =="
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/FaceID" \
  "$HERE/menubar/Branding.swift" \
  "$HERE/menubar/Onboarding.swift" \
  "$HERE/menubar/SettingsView.swift" \
  "$HERE/menubar/FaceIDApp.swift" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement

echo "== Scripts exécutables =="
chmod +x "$HERE"/scripts/*.sh 2>/dev/null || true

echo "== Signature ad-hoc =="
codesign --force --deep --sign - "$APP"

echo "== Installation dans /Applications =="
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "   -> $DEST"

echo
echo "FaceID.app installé. Lance-le :  open \"$DEST\""
