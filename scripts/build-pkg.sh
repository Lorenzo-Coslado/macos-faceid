#!/usr/bin/env bash
# Construit Mugshot.pkg — le chemin d'installation à une seule autorisation.
#
# Pourquoi un paquet plutôt qu'une image disque : brancher Face ID sur `sudo` demande
# d'écrire dans /etc/pam.d, que macOS protège. Une app ne peut y arriver qu'en faisant
# accorder à la main deux autorisations distinctes (Éléments d'ouverture pour le daemon
# privilégié, puis Accès complet au disque). L'Installeur système, lui, s'exécute déjà
# en root avec ce droit : un seul mot de passe suffit, et il pose l'app au bon endroit
# au passage — donc plus de glisser-déposer ni d'app lancée depuis l'image disque.
#
# Usage : build-pkg.sh <App.app> <out.pkg>
#
# Signature : réclame un certificat « Developer ID Installer » (distinct du « Developer
# ID Application » qui signe l'app). Sans lui, la construction est refusée. Pour les
# tests locaux uniquement, ALLOW_UNSIGNED_PKG=1 permet un paquet non signé.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: build-pkg.sh <App.app> <out.pkg>}"
OUT="${2:?usage: build-pkg.sh <App.app> <out.pkg>}"
PKGDIR="$HERE/packaging/pkg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
           "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"

[ -d "$APP" ] || { echo "app introuvable : $APP" >&2; exit 1; }
[ "$(basename "$APP")" = "Mugshot.app" ] || { echo "le bundle doit s'appeler Mugshot.app" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
# Ad-hoc signatures identify a single build by its hash. TCC grants then become stale
# after an update even though System Settings can still show the old entry as checked.
# Only allow such packages explicitly for local tests, never silently for distribution.
if [ "${ALLOW_UNSIGNED_PKG:-0}" != "1" ]; then
  codesign --verify --strict -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$APP" \
    || { echo "Distribution requires a Developer ID Application signature (local tests: ALLOW_UNSIGNED_PKG=1)." >&2; exit 1; }
fi
IDENTITY="$(security find-identity -v 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)"
if [ -z "$IDENTITY" ] && [ "${ALLOW_UNSIGNED_PKG:-0}" != "1" ]; then
  echo "Distribution requires a Developer ID Installer certificate (local tests: ALLOW_UNSIGNED_PKG=1)." >&2
  exit 1
fi
# Le composant sudo appelle ce script depuis le bundle installé. S'il manque, le paquet
# s'installerait en laissant sudo inchangé sans que rien ne l'annonce.
[ -f "$APP/Contents/Resources/scripts/pam-install-root.sh" ] \
  || { echo "le bundle ne contient pas scripts/pam-install-root.sh" >&2; exit 1; }

STAGE="$(mktemp -d)"
COMPONENTS="$(mktemp -d)"
SCRIPTS="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$COMPONENTS" "$SCRIPTS"' EXIT

echo "== Composant 1/2 : l'app =="
mkdir -p "$STAGE/Applications"
# ditto plutôt que cp -R : il ne traîne ni drapeau de quarantaine ni fork de ressource
# dans l'étape de préparation. (Les entrées « ._xxx » qu'on voit ensuite dans le BOM du
# paquet sont normales : pkgbuild les génère pour chaque chemin, même depuis une racine
# sans le moindre attribut étendu — c'est son encodage des métadonnées.)
ditto --norsrc --noextattr --noqtn "$APP" "$STAGE/Applications/$(basename "$APP")"
python3 "$HERE/scripts/bundle-permissions.py" "$STAGE/Applications/$(basename "$APP")"

# Désactiver la RELOCALISATION, sinon l'installeur n'installe pas où on lui dit.
#
# macOS cherche, via Spotlight, un bundle portant déjà le même identifiant, et installe
# À CET ENDROIT plutôt que dans /Applications. Sur une machine de développement, il
# trouvait dist/Mugshot.app et y déversait le paquet :
#
#   PackageKit: Applications/Mugshot.app relocated to Users/…/dist/Mugshot.app
#
# L'utilisateur ne trouvait alors rien dans Applications, et le script postinstall,
# qui cherche l'app à son emplacement normal, échouait dans la foulée. `relocatable=false`
# sur le paquet ne suffit pas : c'est par bundle que ça se règle, via un component plist.
COMPONENT="$COMPONENTS/component.plist"
pkgbuild --analyze --root "$STAGE" "$COMPONENT" >/dev/null
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$COMPONENT"
# Local test bundles often reuse/default to a lower version than the installed
# release. Explicit local installation must actually replace that older binary.
if [ "${ALLOW_UNSIGNED_PKG:-0}" = "1" ]; then
  /usr/libexec/PlistBuddy -c "Set :0:BundleIsVersionChecked false" "$COMPONENT"
fi

cp "$PKGDIR/postinstall-app" "$SCRIPTS/postinstall"
cp "$PKGDIR/preinstall-app" "$SCRIPTS/preinstall"
/usr/bin/shasum -a 256 "$APP/Contents/MacOS/Mugshot" | /usr/bin/awk '{print $1}' > "$SCRIPTS/expected-app-sha256"
chmod +x "$SCRIPTS/postinstall" "$SCRIPTS/preinstall"
pkgbuild --root "$STAGE" \
         --component-plist "$COMPONENT" \
         --scripts "$SCRIPTS" \
         --identifier com.lorenzo.Mugshot.app \
         --version "$VERSION" \
         --install-location / \
         "$COMPONENTS/app.pkg" >/dev/null

echo "== Composant 2/2 : la règle sudo =="
# --nopayload : ce composant n'installe aucun fichier, il ne fait qu'exécuter le script
# qui écrit /etc/pam.d/sudo_local à partir du module déjà posé par le composant 1.
cp "$PKGDIR/postinstall-sudo" "$SCRIPTS/postinstall"
rm "$SCRIPTS/preinstall"
rm "$SCRIPTS/expected-app-sha256"
chmod +x "$SCRIPTS/postinstall"
pkgbuild --nopayload \
         --identifier com.lorenzo.Mugshot.sudo \
         --version "$VERSION" \
         --scripts "$SCRIPTS" \
         "$COMPONENTS/sudo.pkg" >/dev/null

echo "== Assemblage =="
cp "$PKGDIR/welcome.html" "$PKGDIR/conclusion.html" "$COMPONENTS/"
SIGN=()
if [ -n "$IDENTITY" ]; then
  echo "   signé par : $IDENTITY"
  SIGN=(--sign "$IDENTITY")
else
  echo "   ⚠️  aucun certificat « Developer ID Installer » : paquet NON signé." >&2
  echo "      Utilisable pour tester ici, refusé par Gatekeeper ailleurs." >&2
  echo "      À créer sur developer.apple.com (même équipe que le certificat app)." >&2
fi

rm -f "$OUT"
productbuild --distribution "$PKGDIR/distribution.xml" \
             --package-path "$COMPONENTS" \
             --resources "$COMPONENTS" \
             "${SIGN[@]+"${SIGN[@]}"}" \
             "$OUT" >/dev/null

echo
echo "✅ $OUT  ($(du -h "$OUT" | cut -f1))"
echo "   Vérifier le contenu :  pkgutil --expand \"$OUT\" /tmp/mugshot-pkg && ls -R /tmp/mugshot-pkg"
