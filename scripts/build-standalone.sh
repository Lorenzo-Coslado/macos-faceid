#!/usr/bin/env bash
# Construit Mugshot.app AUTONOME : moteur Python + OpenCV + modèles + helpers +
# module PAM, tout embarqué. Aucune dépendance au dossier projet ni au venv.
# (Signature ad-hoc ici ; Developer ID + notarisation = build-release.sh.)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/macos-target.sh"
cd "$HERE"
PY="$HERE/.venv/bin/python"
export PYINSTALLER_CONFIG_DIR="${PYINSTALLER_CONFIG_DIR:-/tmp/mugshot-pyinstaller}"
APP="$HERE/dist/Mugshot.app"
RES="$APP/Contents/Resources"
BUNDLE_ID="com.lorenzo.Mugshot"
MARKETING_VERSION="${MARKETING_VERSION:-1.0}"   # ex: 1.0.1 (surchargé par release.sh)
BUILD_VERSION="${BUILD_VERSION:-1}"             # entier monotone (Sparkle compare ceci)
MODELS="${FACEID_MODELS_DIR:-$HOME/Library/Application Support/faceid/models}"

echo "══ 1/6  Prérequis (modèles, helpers, module PAM, assets, i18n) ══"
[ -f "$MODELS/face_recognition_sface_2021dec.onnx" ] || bash scripts/download-models.sh
bash scripts/build-helpers.sh >/dev/null
bash scripts/fetch-sparkle.sh >/dev/null
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
if ! iconutil -c icns "$ICONSET" -o "$HERE/assets/Mugshot.icns"; then
  [ -f "$HERE/assets/Mugshot.icns" ] || exit 1
  echo "Avertissement: iconutil a échoué; réutilisation de assets/Mugshot.icns" >&2
fi

echo "══ 2/6  Moteur Python autonome (PyInstaller) ══"
# Utilise packaging/faceid.spec (exclusions + strip). L'ancienne invocation le
# régénérait à chaque build, donc ses réglages n'étaient jamais appliqués.
rm -rf packaging/dist packaging/build
# La sortie part dans un journal plutôt que dans /dev/null : elle est trop bavarde pour
# le terminal, mais l'envoyer au néant rendait tout échec muet — sur CI, on ne voyait
# qu'un « exit code 1 » sans la moindre cause.
# Hors de --workpath : `--clean` vide ce répertoire et emporterait le journal avec lui.
PYI_LOG="$HERE/packaging/pyinstaller.log"
if ! "$HERE/.venv/bin/pyinstaller" --noconfirm --clean \
      --distpath packaging/dist --workpath packaging/build \
      packaging/faceid.spec > "$PYI_LOG" 2>&1; then
  echo "❌ PyInstaller a échoué. Fin du journal ($PYI_LOG) :" >&2
  tail -40 "$PYI_LOG" >&2
  exit 1
fi

echo "══ 3/6  Compilation de l'app Swift ══"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$RES"
swiftc -O -swift-version 5 -target "$MUGSHOT_SWIFT_TARGET" -o "$APP/Contents/MacOS/Mugshot" \
  menubar/Branding.swift menubar/Onboarding.swift menubar/SettingsView.swift menubar/SetupFlow.swift menubar/SetupSheet.swift menubar/Uninstaller.swift \
  menubar/HelperManager.swift helpertool/HelperProtocol.swift menubar/FaceIDApp.swift \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework ServiceManagement -framework Security \
  -F "$HERE/vendor/sparkle" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks
# daemon privilégié root (SMAppService + XPC)
swiftc -O -swift-version 5 -target "$MUGSHOT_SWIFT_TARGET" -o "$APP/Contents/MacOS/MugshotHelper" \
  helpertool/main.swift helpertool/HelperProtocol.swift helpertool/CodesignCheck.swift \
  -framework Foundation -framework Security

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
  <key>CFBundleShortVersionString</key> <string>${MARKETING_VERSION}</string>
  <key>CFBundleVersion</key>         <string>${BUILD_VERSION}</string>
  <key>LSUIElement</key>             <true/>
  <key>LSMinimumSystemVersion</key>  <string>${MACOSX_DEPLOYMENT_TARGET}</string>
  <key>SUFeedURL</key>               <string>https://raw.githubusercontent.com/Lorenzo-Coslado/macos-faceid/main/appcast.xml</string>
  <key>SUPublicEDKey</key>           <string>MYs0iwYg/b5lDERYBHVBBiIw8R2awqExOluwOfZlp0w=</string>
  <key>SUEnableAutomaticChecks</key> <true/>
  <key>NSCameraUsageDescription</key>
  <string>Reconnaissance faciale locale pour déverrouiller sudo.</string>
</dict>
</plist>
PLIST

echo "══ 5/6  Ressources embarquées ══"
mkdir -p "$APP/Contents/Frameworks"
cp -R "$HERE/vendor/sparkle/Sparkle.framework" "$APP/Contents/Frameworks/"   # auto-update
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp "$HERE/helpertool/com.lorenzo.Mugshot.Helper.plist" "$APP/Contents/Library/LaunchDaemons/"  # daemon root
cp "$HERE/assets/Mugshot.icns" "$RES/Mugshot.icns"
cp "$HERE/assets/faceid-icon.png" "$RES/faceid-icon.png"
cp "$HERE/assets/menubar-icon.png" "$RES/menubar-icon.png"
cp -R "$HERE/packaging/dist/faceid" "$RES/faceid"                 # moteur Python autonome
mkdir -p "$RES/helpers" "$RES/assets" "$RES/models" "$RES/pam" "$RES/scripts"
cp "$HERE/helpers/touchid-helper" "$HERE/helpers/auth-modal" "$HERE/helpers/faceid-hud" "$HERE/helpers/camera-list" "$RES/helpers/"
cp "$HERE/assets/faceid-icon.png" "$RES/assets/"
# Icône du dialogue de repli osascript. Elle venait de assets/FaceID.icns, reliquat de
# l'ancien nom du projet ; Mugshot.icns est régénérée à chaque build depuis la même
# source (appicon-1024.png).
cp "$HERE/assets/Mugshot.icns" "$RES/assets/faceid-icon.icns"
cp "$MODELS/"*.onnx "$RES/models/"
cp "$HERE/pam/pam_faceid.so" "$RES/pam/"
cp "$HERE/scripts/pam-install-root.sh" "$HERE/scripts/pam-uninstall-root.sh" "$RES/scripts/"
# diagnose.sh répond à « pourquoi sudo ne me demande pas mon visage ? ». Il n'était pas
# embarqué : il fallait cloner le dépôt pour l'obtenir.
cp "$HERE/scripts/diagnose.sh" "$RES/scripts/"
cp -R "$HERE"/i18n/*.lproj "$RES/"
mkdir -p "$RES/i18n"
cp "$HERE/i18n/engine.json" "$RES/i18n/"      # invites du moteur, hors bundle Swift

echo "══ 6/6  Signature ad-hoc (test local) ══"
bash "$HERE/scripts/check-macos-compat.sh" "$APP"
codesign --force --deep --sign - "$APP" 2>/dev/null

SIZE=$(du -sh "$APP" | cut -f1)
echo
echo "✅ Mugshot.app autonome ($SIZE) : $APP"
echo "   Test : déplace/renomme le venv puis lance l'app — elle doit tourner sans le projet."
