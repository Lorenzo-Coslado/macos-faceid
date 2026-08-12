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
# ID Application » qui signe l'app). Sans lui, le paquet se construit mais Gatekeeper le
# refusera chez les autres — utile pour tester en local, pas pour publier.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?usage: build-pkg.sh <App.app> <out.pkg>}"
OUT="${2:?usage: build-pkg.sh <App.app> <out.pkg>}"
PKGDIR="$HERE/packaging/pkg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
           "$APP/Contents/Info.plist" 2>/dev/null || echo 1.0)"

[ -d "$APP" ] || { echo "app introuvable : $APP" >&2; exit 1; }
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
pkgbuild --root "$STAGE" \
         --identifier com.lorenzo.Mugshot.app \
         --version "$VERSION" \
         --install-location / \
         "$COMPONENTS/app.pkg" >/dev/null

echo "== Composant 2/2 : la règle sudo =="
# --nopayload : ce composant n'installe aucun fichier, il ne fait qu'exécuter le script
# qui écrit /etc/pam.d/sudo_local à partir du module déjà posé par le composant 1.
cp "$PKGDIR/postinstall-sudo" "$SCRIPTS/postinstall"
chmod +x "$SCRIPTS/postinstall"
pkgbuild --nopayload \
         --identifier com.lorenzo.Mugshot.sudo \
         --version "$VERSION" \
         --scripts "$SCRIPTS" \
         "$COMPONENTS/sudo.pkg" >/dev/null

echo "== Assemblage =="
cp "$PKGDIR/welcome.html" "$PKGDIR/conclusion.html" "$COMPONENTS/"
SIGN=()
IDENTITY="$(security find-identity -v 2>/dev/null \
            | sed -n 's/.*"\(Developer ID Installer: [^"]*\)".*/\1/p' | head -1)"
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
