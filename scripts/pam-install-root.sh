#!/usr/bin/env bash
# Partie privilégiée de l'activation sudo — EXÉCUTÉE EN ROOT (via l'app, prompt
# admin macOS). Le module doit déjà être compilé (pam/pam_faceid.so).
# Pas de `sudo` ici : on est déjà root.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_SRC="${HERE}/pam/pam_faceid.so"
MODULE_DST="/usr/local/lib/pam/pam_faceid.so"
LINE='auth       sufficient     /usr/local/lib/pam/pam_faceid.so'

[ -f "$MODULE_SRC" ] || { echo "module non compilé : $MODULE_SRC" >&2; exit 1; }

mkdir -p /usr/local/lib/pam
cp "$MODULE_SRC" "$MODULE_DST"
chown root:wheel "$MODULE_DST"
chmod 644 "$MODULE_DST"

# Écriture EN PLACE (printf >), robuste : gère fichier absent / vide / existant, et
# évite le sed (fragile sur fichier vide, et son temp+rename plus risqué côté SIP).
# Notre ligne en tête, suivie de tout contenu existant qui n'est pas à nous.
existing=""
[ -f /etc/pam.d/sudo_local ] && existing="$(grep -v pam_faceid /etc/pam.d/sudo_local 2>/dev/null || true)"
if [ -n "$existing" ]; then
  printf '%s\n%s\n' "$LINE" "$existing" > /etc/pam.d/sudo_local
else
  printf '%s\n' "$LINE" > /etc/pam.d/sudo_local
fi
chown root:wheel /etc/pam.d/sudo_local 2>/dev/null || true
chmod 644 /etc/pam.d/sudo_local 2>/dev/null || true

# Optionnel : si Touch ID système est présent dans /etc/pam.d/sudo, on tente de le
# neutraliser pour que le modal de l'app passe en premier. NON-BLOQUANT : /etc/pam.d/sudo
# est un fichier système souvent protégé par SIP ; un échec ici ne doit PAS casser
# l'installation (le coeur — module + sudo_local — est déjà en place). On réécrit en
# place (cat >) pour préserver le propriétaire root:wheel (sed -i le cassait).
if grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo 2>/dev/null; then
  cp -n /etc/pam.d/sudo /etc/pam.d/sudo.bak-faceid 2>/dev/null || true
  tmp="$(mktemp)"
  if sed -E 's/^(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so)/#faceid# \1/' /etc/pam.d/sudo > "$tmp" \
     && cat "$tmp" > /etc/pam.d/sudo 2>/dev/null; then
    chown root:wheel /etc/pam.d/sudo 2>/dev/null || true
    chmod 444 /etc/pam.d/sudo 2>/dev/null || true
  else
    echo "note: Touch ID système non neutralisé (/etc/pam.d/sudo protégé) — sans impact" >&2
  fi
  rm -f "$tmp"
fi

echo "OK"
