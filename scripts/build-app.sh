#!/usr/bin/env bash
# Construit Mugshot.app (menu bar + fenêtres) et l'installe dans /Applications.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HERE/build/Mugshot.app"
BUNDLE_ID="com.lorenzo.Mugshot"
DEST="/Applications/Mugshot.app"

echo "== Arrêt d'une instance existante =="
pkill -f "Mugshot.app/Contents/MacOS/Mugshot" 2>/dev/null || true
pkill -f "faceid.daemon" 2>/dev/null || true
sleep 1

echo "== Régénération du glyphe source =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_icon.py"

echo "== Sparkle (auto-update) =="
bash "$HERE/scripts/fetch-sparkle.sh"

echo "== Icône (.icns) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_appicon.py"
ICONSET="$HERE/build/Mugshot.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="$HERE/assets/appicon-1024.png"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz     "$SRC" --out "$ICONSET/icon_${sz}x${sz}.png"     >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$HERE/assets/Mugshot.icns"

echo "== Assemblage du bundle =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>            <string>Mugshot</string>
  <key>CFBundleDisplayName</key>     <string>Mugshot</string>
  <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
  <key>CFBundleExecutable</key>      <string>Mugshot</string>
  <key>CFBundleIconFile</key>        <string>Mugshot</string>
  <key>CFBundlePackageType</key>     <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>1.0</string>
  <key>CFBundleVersion</key>         <string>1</string>
  <key>LSUIElement</key>             <true/>
  <key>LSMinimumSystemVersion</key>  <string>13.0</string>
  <key>SUFeedURL</key>               <string>https://raw.githubusercontent.com/Lorenzo-Coslado/macos-faceid/main/appcast.xml</string>
  <key>SUPublicEDKey</key>           <string>MYs0iwYg/b5lDERYBHVBBiIw8R2awqExOluwOfZlp0w=</string>
  <key>SUEnableAutomaticChecks</key> <true/>
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

cp "$HERE/assets/Mugshot.icns" "$APP/Contents/Resources/Mugshot.icns"
cp "$HERE/assets/faceid-icon.png" "$APP/Contents/Resources/faceid-icon.png"
cp "$HERE/assets/menubar-icon.png" "$APP/Contents/Resources/menubar-icon.png"
mkdir -p "$APP/Contents/Frameworks"
cp -R "$HERE/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/"
# daemon privilégié (SMAppService) : plist du LaunchDaemon
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp "$HERE/helpertool/com.lorenzo.Mugshot.Helper.plist" "$APP/Contents/Library/LaunchDaemons/"
# module PAM + scripts privilégiés : le daemon les lit depuis Resources (comme la release)
make -C "$HERE/pam" >/dev/null 2>&1 || true
mkdir -p "$APP/Contents/Resources/pam" "$APP/Contents/Resources/scripts"
cp "$HERE/pam/pam_faceid.so" "$APP/Contents/Resources/pam/" 2>/dev/null || true
cp "$HERE/scripts/pam-install-root.sh" "$HERE/scripts/pam-uninstall-root.sh" "$APP/Contents/Resources/scripts/"

echo "== Traductions (.lproj) =="
"$HERE/.venv/bin/python" "$HERE/scripts/make_i18n.py"
cp -R "$HERE"/i18n/*.lproj "$APP/Contents/Resources/"

echo "== Compilation de l'app =="
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/Mugshot" \
  "$HERE/menubar/Branding.swift" \
  "$HERE/menubar/Onboarding.swift" \
  "$HERE/menubar/SettingsView.swift" \
  "$HERE/menubar/HelperManager.swift" \
  "$HERE/helpertool/HelperProtocol.swift" \
  "$HERE/menubar/FaceIDApp.swift" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement \
  -F "$HERE/vendor/sparkle" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks

echo "== Compilation du daemon privilégié (MugshotHelper) =="
swiftc -O -swift-version 5 \
  -o "$APP/Contents/MacOS/MugshotHelper" \
  "$HERE/helpertool/main.swift" \
  "$HERE/helpertool/HelperProtocol.swift" \
  "$HERE/helpertool/CodesignCheck.swift" \
  -framework Foundation -framework Security

echo "== Scripts exécutables =="
chmod +x "$HERE"/scripts/*.sh 2>/dev/null || true

echo "== Signature ad-hoc =="
codesign --force --deep --sign - "$APP"

echo "== Installation dans /Applications =="
rm -rf "$DEST"
cp -R "$APP" "$DEST"
echo "   -> $DEST"

echo
echo "Mugshot.app installé. Lance-le :  open \"$DEST\""
