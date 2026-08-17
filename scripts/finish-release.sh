#!/usr/bin/env bash
# Reprend une release dont la notarisation a échoué, sans rien reconstruire.
#
# Utile quand build-release.sh est allé jusqu'au bout de la signature puis s'est arrêté
# sur l'envoi à Apple — une coupure réseau, un filtre qui tue un transfert de 90 Mo.
# Les artefacts signés sont déjà là ; il ne reste qu'à les faire notariser et stapler.
#
#   ./scripts/finish-release.sh
#
# ATTENTION à ce que ce script ne fait PAS, et ne doit jamais faire : recréer les
# conteneurs. Une image recréée après la notarisation est un fichier différent, dont
# Apple n'a jamais vu le contenu — `stapler` échoue alors sur « could not find ticket »,
# et pire, on publierait un DMG non notarisé en croyant l'inverse. C'est exactement le
# défaut que cette version corrige.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HERE/dist/Mugshot.app"
DMG="$HERE/dist/Mugshot.dmg"
PKG="$HERE/dist/Mugshot.pkg"
PROFILE="${NOTARY_PROFILE:-faceid-notary}"
TRIES="${NOTARY_TRIES:-3}"

[ -d "$APP" ] || { echo "❌ pas d'app dans dist/ — lance d'abord scripts/build-release.sh" >&2; exit 1; }

# Un conteneur non signé ne servirait à rien : le ticket seul ne suffit pas, Gatekeeper
# refuse en « no usable signature ». Mieux vaut le dire ici que le découvrir publié.
require_signed() {
  codesign --verify --strict "$1" 2>/dev/null && return 0
  echo "❌ $(basename "$1") n'est pas signé. Relance scripts/build-release.sh." >&2
  return 1
}

notarize() {
  local file="$1" name; name="$(basename "$file")"
  echo "== Notarisation de $name =="
  local out verdict
  for i in $(seq 1 "$TRIES"); do
    out="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait 2>&1)" || true
    # La DERNIÈRE ligne « status: », pas la première : les lignes de progression
    # affichent « Current status: In Progress » et feraient conclure à un échec.
    verdict="$(printf '%s\n' "$out" | grep -E '^ *status:' | tail -1 | awk '{print $2}')"
    [ "$verdict" = "Accepted" ] && { echo "   accepté"; return 0; }
    echo "   tentative $i/$TRIES : ${verdict:-réseau}" >&2
    printf '%s\n' "$out" | grep -iE "offline|abortedUpload|Invalid" | head -1 >&2 || true
    sleep 15
  done
  echo "❌ $name refusé ou injoignable après $TRIES tentatives." >&2
  return 1
}

for artefact in "$DMG" "$PKG"; do
  [ -f "$artefact" ] || continue
  require_signed "$artefact"
  notarize "$artefact"
done

echo "== Staple =="
# On staple les fichiers QUI ONT ÉTÉ SOUMIS, tels quels.
xcrun stapler staple "$APP"
if [ -f "$DMG" ]; then xcrun stapler staple "$DMG"; fi
if [ -f "$PKG" ]; then xcrun stapler staple "$PKG"; fi

echo "== Vérification Gatekeeper =="
# `[ -f … ] && cmd` en fin de script ferait sortir en erreur quand le fichier manque.
spctl -a -vv -t exec "$APP" 2>&1 | head -2
if [ -f "$DMG" ]; then spctl -a -vv -t open --context context:primary-signature "$DMG" 2>&1 | head -2; fi
if [ -f "$PKG" ]; then spctl -a -vv -t install "$PKG" 2>&1 | head -2; fi

echo
echo "✅ Artefacts notarisés et staplés. Publie avec :"
echo "   ./scripts/release.sh <version> <build>   (reprend à l'appcast)"
