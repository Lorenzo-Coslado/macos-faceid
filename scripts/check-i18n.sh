#!/usr/bin/env bash
# Vérifie que chaque clé L("...") utilisée par l'app existe dans les traductions, et
# qu'aucune clé n'est définie deux fois.
#
# Les deux défauts sont déjà arrivés : une clé manquante s'affiche telle quelle dans
# l'interface, et `set.behavior.camera` était défini deux fois — la seconde écrasait la
# première, si bien que le sélecteur de caméra s'intitulait « Réglages caméra système… ».
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STRINGS="$HERE/i18n/en.lproj/Localizable.strings"
STATUS=0

[ -f "$STRINGS" ] || { echo "traductions absentes : lancer scripts/make_i18n.py" >&2; exit 1; }

defined="$(sed -n 's/^"\([^"]*\)" = .*/\1/p' "$STRINGS" | sort)"

echo "== Clés utilisées mais non définies =="
used="$(grep -rhoE 'L\("[A-Za-z0-9._-]+"\)' "$HERE"/menubar/*.swift \
        | sed 's/^L("//; s/")$//' | sort -u)"
# Les clés d'erreur du moteur sont construites à l'exécution (err.<code>) : on les
# recoupe avec les codes que le moteur émet réellement plutôt qu'avec le littéral.
missing="$(comm -23 <(echo "$used" | grep -v '^err\.$') <(echo "$defined" | sort -u) || true)"
if [ -n "$missing" ]; then
  echo "$missing" | sed 's/^/  MANQUE  /'
  STATUS=1
else
  echo "  aucune"
fi

echo "== Codes d'erreur du moteur sans traduction =="
codes="$(grep -ohE 'msg="[a-z-]+"' "$HERE"/faceid/*.py | sed 's/msg="//; s/"//' | sort -u)"
for code in $codes; do
  if ! echo "$defined" | grep -qx "err.$code"; then
    echo "  MANQUE  err.$code"
    STATUS=1
  fi
done
[ "$STATUS" -eq 0 ] && echo "  aucun"

echo "== Clés définies deux fois =="
dupes="$(echo "$defined" | uniq -d)"
if [ -n "$dupes" ]; then
  echo "$dupes" | sed 's/^/  DOUBLON  /'
  STATUS=1
else
  echo "  aucune"
fi

exit "$STATUS"
