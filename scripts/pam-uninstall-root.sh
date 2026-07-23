#!/usr/bin/env bash
# Partie privilégiée de la désactivation sudo — EXÉCUTÉE EN ROOT (via l'app).
set -euo pipefail

if [ -f /etc/pam.d/sudo_local ]; then
  sed -i '' '/pam_faceid/d' /etc/pam.d/sudo_local
fi
rm -f /usr/local/lib/pam/pam_faceid.so || true

# réactive Touch ID système
if grep -q '^#faceid# ' /etc/pam.d/sudo 2>/dev/null; then
  sed -i '' -E 's/^#faceid# //' /etc/pam.d/sudo
fi

echo "OK"
