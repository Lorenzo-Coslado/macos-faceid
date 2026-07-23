#!/usr/bin/env bash
# Build de DISTRIBUTION : app autonome + signature Developer ID + hardened runtime
# + notarisation Apple + staple + DMG. Résultat : téléchargeable sans avertissement.
#
# Prérequis (une fois) :
#   1. Certificat "Developer ID Application" installé
#        (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application)
#   2. Profil notarytool enregistré dans le trousseau :
#        xcrun notarytool store-credentials faceid-notary \
#           --apple-id "TON_APPLE_ID" --team-id "TEAM_ID" --password "MOT_DE_PASSE_APP"
#      (mot de passe d'app : appleid.apple.com › Sécurité › Mots de passe pour app)
#
# Usage :
#   DEV_ID="Developer ID Application: Ton Nom (TEAMID)" ./scripts/build-release.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
APP="$HERE/dist/FaceID.app"
ENT="$HERE/packaging/entitlements.plist"
DMG="$HERE/dist/FaceID.dmg"
NOTARY_PROFILE="${NOTARY_PROFILE:-faceid-notary}"

# Identité : arg DEV_ID, sinon on tente de détecter le certificat Developer ID Application.
DEV_ID="${DEV_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$DEV_ID" ] || { echo "❌ Aucun certificat 'Developer ID Application'. Crée-le dans Xcode."; exit 1; }
echo "Signature avec : $DEV_ID"

echo "══ 1  Assemblage de l'app autonome ══"
bash scripts/build-standalone.sh

echo "══ 2  Signature inside-out (Developer ID + hardened runtime) ══"
# a) dylibs/.so empaquetés par PyInstaller (sans entitlements)
find "$APP/Contents/Resources/faceid" -type f \( -name "*.dylib" -o -name "*.so" \) -print0 \
  | xargs -0 -I{} codesign --force --timestamp --options runtime --sign "$DEV_ID" {} 2>/dev/null
# b) exécutables + module PAM (avec entitlements caméra)
for b in "$APP/Contents/Resources/faceid/faceid" \
         "$APP/Contents/Resources/helpers/touchid-helper" \
         "$APP/Contents/Resources/helpers/auth-modal" \
         "$APP/Contents/Resources/helpers/faceid-hud" \
         "$APP/Contents/Resources/pam/pam_faceid.so"; do
  codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$DEV_ID" "$b"
done
# c) l'app elle-même, en dernier
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$DEV_ID" "$APP"

echo "══ 3  Vérification ══"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "══ 4  DMG ══"
rm -f "$DMG"
hdiutil create -volname "FaceID" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null

echo "══ 5  Notarisation (upload + attente Apple) ══"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "══ 6  Staple (app puis DMG) ══"
xcrun stapler staple "$APP"
rm -f "$DMG"
hdiutil create -volname "FaceID" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
xcrun stapler staple "$DMG"

echo
echo "✅ $DMG — notarisé + staplé, prêt pour GitHub Releases."
