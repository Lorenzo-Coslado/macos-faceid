#!/usr/bin/env bash
# Build de DISTRIBUTION : app autonome + signature Developer ID + hardened runtime
# + notarisation Apple + staple + DMG. Résultat : téléchargeable sans avertissement.
#
# Prérequis (une fois) :
#   1. Certificat "Developer ID Application" installé
#        (Xcode › Settings › Accounts › Manage Certificates › + › Developer ID Application)
#   1-bis. Certificat "Developer ID Installer" (même écran) pour signer le .pkg. C'est
#        une identité DISTINCTE : `productsign` refuse une identité d'application pour
#        un paquet. Sans elle, mettre BUILD_PKG=0.
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
APP="$HERE/dist/Mugshot.app"
ENT="$HERE/packaging/entitlements.plist"
DMG="$HERE/dist/Mugshot.dmg"
PKG="$HERE/dist/Mugshot.pkg"
NOTARY_PROFILE="${NOTARY_PROFILE:-faceid-notary}"

# Identité : arg DEV_ID, sinon on tente de détecter le certificat Developer ID Application.
DEV_ID="${DEV_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | grep 'Developer ID Application' | head -1 | sed -E 's/.*"(.*)"/\1/')}"
[ -n "$DEV_ID" ] || { echo "❌ Aucun certificat 'Developer ID Application'. Crée-le dans Xcode."; exit 1; }
echo "Signature avec : $DEV_ID"

echo "══ 1  Assemblage de l'app autonome ══"
bash scripts/build-standalone.sh

echo "══ 2  Signature inside-out (Developer ID + hardened runtime) ══"
# a) TOUS les Mach-O empaquetés par PyInstaller (dylibs, .so, binaire du
#    Python.framework sans extension…), avec timestamp sécurisé.
find "$APP/Contents/Resources/faceid" -type f -print0 | while IFS= read -r -d '' f; do
  if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
    codesign --force --timestamp --options runtime --sign "$DEV_ID" "$f"
  fi
done
# b) exécutables + module PAM (avec entitlements caméra)
for b in "$APP/Contents/Resources/faceid/faceid" \
         "$APP/Contents/Resources/helpers/touchid-helper" \
         "$APP/Contents/Resources/helpers/auth-modal" \
         "$APP/Contents/Resources/helpers/faceid-hud" \
         "$APP/Contents/Resources/helpers/camera-list" \
         "$APP/Contents/Resources/pam/pam_faceid.so"; do
  codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$DEV_ID" "$b"
done
# b-ter) daemon privilégié (hardened runtime, pas d'entitlements caméra). Signé à part
#        car c'est un 2e Mach-O dans Contents/MacOS que la signature du bundle n'englobe pas.
codesign --force --timestamp --options runtime --sign "$DEV_ID" "$APP/Contents/MacOS/MugshotHelper"
# b-bis) Sparkle : sous-bundles d'abord (on préserve leurs entitlements, ex. le
#        Downloader.xpc sandboxé + réseau), puis le framework. Surtout PAS de --deep.
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for comp in "$FW/XPCServices/Downloader.xpc" \
            "$FW/XPCServices/Installer.xpc" \
            "$FW/Autoupdate" \
            "$FW/Updater.app"; do
  codesign --force --timestamp --options runtime \
    --preserve-metadata=entitlements --sign "$DEV_ID" "$comp"
done
codesign --force --timestamp --options runtime --sign "$DEV_ID" \
  "$APP/Contents/Frameworks/Sparkle.framework"

# c) l'app elle-même, en dernier
codesign --force --timestamp --options runtime --entitlements "$ENT" --sign "$DEV_ID" "$APP"

echo "══ 3  Vérification ══"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3

echo "══ 4  DMG ══"
# Ship the /Applications symlink so the window shows the usual drag-to-install layout.
# Running the app straight from the mounted image half-works and then breaks: the
# privileged helper is registered from a path that disappears on eject, and sudo quietly
# falls back to the password.
"$HERE/.venv/bin/python" "$HERE/scripts/make_dmg_background.py" >/dev/null
bash "$HERE/scripts/make-dmg.sh" "$APP" "$DMG"
# Signer le conteneur lui-même, et pas seulement ce qu'il transporte. Sans cela il
# porte bien un ticket de notarisation, mais `spctl -a -t open` le refuse en
# « no usable signature » : rien n'atteste que l'image n'a pas été altérée après coup.
# À faire AVANT la notarisation, sinon le ticket ne correspond plus au fichier signé.
codesign --force --timestamp --sign "$DEV_ID" "$DMG"

# Le paquet contient l'app SIGNÉE ci-dessus : il doit donc être construit après l'étape 2,
# jamais avant. Il porte le chemin d'installation à une seule autorisation ;
# BUILD_PKG=0 le saute.
BUILD_PKG="${BUILD_PKG:-1}"
if [ "$BUILD_PKG" != "0" ]; then
  echo "══ 5  Paquet d'installation ══"
  bash "$HERE/scripts/build-pkg.sh" "$APP" "$PKG"
fi

echo "══ 6  Notarisation (upload + attente Apple) ══"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
if [ "$BUILD_PKG" != "0" ]; then
  xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
fi

echo "══ 7  Staple ══"
# On staple les conteneurs QUI ONT ÉTÉ SOUMIS (pas un rebuild : un conteneur recréé
# après coup n'a pas de ticket chez Apple → 'could not find ticket'). L'app est staplée
# en plus.
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
if [ "$BUILD_PKG" != "0" ]; then
  xcrun stapler staple "$PKG"
fi

echo "══ 8  Vérification Gatekeeper ══"
# Ce que verra quelqu'un qui télécharge : l'app doit être notarisée, l'image et le
# paquet doivent l'être ET porter une signature valide.
spctl -a -vv -t exec "$APP" 2>&1 | head -2
spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -2
if [ "$BUILD_PKG" != "0" ]; then
  spctl -a -vv -t install "$PKG" 2>&1 | head -2
fi

echo
echo "✅ $DMG — notarisé + staplé, prêt pour GitHub Releases."
if [ "$BUILD_PKG" != "0" ]; then
  echo "✅ $PKG — idem, installation en une seule autorisation."
fi
