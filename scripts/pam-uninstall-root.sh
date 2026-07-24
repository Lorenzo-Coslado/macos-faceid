#!/usr/bin/env bash
# Partie privilégiée de la désactivation sudo — EXÉCUTÉE EN ROOT (via l'app).
set -euo pipefail

# Retire nos lignes, écriture EN PLACE (printf >), sans sed -i (rename risqué côté SIP).
if [ -f /etc/pam.d/sudo_local ]; then
  remaining="$(grep -v pam_faceid /etc/pam.d/sudo_local 2>/dev/null || true)"
  printf '%s\n' "$remaining" > /etc/pam.d/sudo_local
fi
rm -f /usr/local/lib/pam/pam_faceid.so || true

# réactive Touch ID système
if grep -q '^#faceid# ' /etc/pam.d/sudo 2>/dev/null; then
  sed -i '' -E 's/^#faceid# //' /etc/pam.d/sudo
fi

echo "OK"
