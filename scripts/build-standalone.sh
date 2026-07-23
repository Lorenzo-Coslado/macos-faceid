#!/usr/bin/env bash
# Construit Mugshot.app AUTONOME : moteur Python + OpenCV + modèles + helpers +
# module PAM, tout embarqué. Aucune dépendance au dossier projet ni au venv.
# (Signature ad-hoc ici ; Developer ID + notarisation = build-release.sh.)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
PY="$HERE/.venv/bin/python"
APP="$HERE/dist/Mugshot.app"
RES="$APP/Contents/Resources"
BUNDLE_ID="com.lorenzo.Mugshot"
MODELS="$HOME/Library/Application Support/faceid/models"

echo "══ 1/6  Prérequis (modèles, helpers, module PAM, assets, i18n) ══"
[ -f "$MODELS/face_recognition_sface_2021dec.onnx" ] || bash scripts/download-models.sh
bash scripts/build-helpers.sh >/dev/null
make -C pam >/dev/null
"$PY" scripts/make_icon.py >/dev/null
"$PY" scripts/make_appicon.py >/dev/null
"$PY" scripts/make_i18n.py >/dev/null
ICONSET="$HERE/dist/Mugshot.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
SRC="$HERE/assets/appicon-1024.png"
for sz in 16 32 128 256 512; do
  sips -z $sz $sz "$SRC" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
  sips -z $((sz*2)) $((sz*2)) "$SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
cp "$SRC" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$HERE/assets/Mugshot.icns"

echo "══ 2/6  Moteur Python autonome (PyInstaller) ══"
rm -rf packaging/dist packaging/build packaging/*.spec
"$HERE/.venv/bin/pyinstaller" --onedir --name faceid --noconfirm --clean --paths . \
  --distpath packaging/dist --workpath packaging/build --specpath packaging \
  packaging/faceid_entry.py >/dev/null 2>&1

echo "══ 3/6  Compilation de l'app Swift ══"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/Mugshot" \
  menubar/Branding.swift menubar/Onboarding.swift menubar/SettingsView.swift menubar/FaceIDApp.swift \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement

echo "══ 4/6  Info.plist ══"
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
  <key>NSCameraUsageDescription</key>
  <string>Reconnaissance faciale locale pour déverrouiller sudo.</string>
</dict>
</plist>
PLIST

echo "══ 5/6  Ressources embarquées ══"
cp "$HERE/assets/Mugshot.icns" "$RES/Mugshot.icns"
cp "$HERE/assets/faceid-icon.png" "$RES/faceid-icon.png"
cp "$HERE/assets/menubar-icon.png" "$RES/menubar-icon.png"
cp -R "$HERE/packaging/dist/faceid" "$RES/faceid"                 # moteur Python autonome
mkdir -p "$RES/helpers" "$RES/assets" "$RES/models" "$RES/pam" "$RES/scripts"
cp "$HERE/helpers/touchid-helper" "$HERE/helpers/auth-modal" "$HERE/helpers/faceid-hud" "$RES/helpers/"
cp "$HERE/assets/faceid-icon.png" "$HERE/assets/faceid-icon.icns" "$RES/assets/"
cp "$MODELS/"*.onnx "$RES/models/"
cp "$HERE/pam/pam_faceid.so" "$RES/pam/"
cp "$HERE/scripts/pam-install-root.sh" "$HERE/scripts/pam-uninstall-root.sh" "$RES/scripts/"
cp -R "$HERE"/i18n/*.lproj "$RES/"

echo "══ 6/6  Signature ad-hoc (test local) ══"
codesign --force --deep --sign - "$APP" 2>/dev/null

SIZE=$(du -sh "$APP" | cut -f1)
echo
echo "✅ Mugshot.app autonome ($SIZE) : $APP"
echo "   Test : déplace/renomme le venv puis lance l'app — elle doit tourner sans le projet."
