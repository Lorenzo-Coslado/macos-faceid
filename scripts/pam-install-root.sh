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

if [ ! -f /etc/pam.d/sudo_local ]; then
  printf '%s\n' "$LINE" > /etc/pam.d/sudo_local
elif ! grep -q pam_faceid /etc/pam.d/sudo_local; then
  sed -i '' "1i\\
${LINE}
" /etc/pam.d/sudo_local
fi

# neutralise le Touch ID système pour que le modal de l'app passe en premier
if grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo; then
  cp -n /etc/pam.d/sudo /etc/pam.d/sudo.bak-faceid || true
  sed -i '' -E 's/^(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so)/#faceid# \1/' /etc/pam.d/sudo
fi

echo "OK"
