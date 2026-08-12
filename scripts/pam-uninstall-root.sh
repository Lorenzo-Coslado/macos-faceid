#!/usr/bin/env bash
# Partie privilégiée de la désactivation sudo — EXÉCUTÉE EN ROOT (via l'app).
set -euo pipefail

# Retire nos lignes, écriture EN PLACE (printf >), sans sed -i (rename risqué côté SIP).
if [ -f /etc/pam.d/sudo_local ]; then
  remaining="$(grep -v pam_faceid /etc/pam.d/sudo_local 2>/dev/null || true)"
  printf '%s\n' "$remaining" > /etc/pam.d/sudo_local
fi
rm -f /usr/local/lib/pam/pam_faceid.so || true

# Réactive Touch ID système. Écriture EN PLACE (cat >) comme à l'installation : `sed -i`
# passe par un fichier temporaire puis un rename, ce que SIP peut refuser sur
# /etc/pam.d/sudo — et un échec ici laisserait Touch ID désactivé pour toujours.
if grep -q '^#faceid# ' /etc/pam.d/sudo 2>/dev/null; then
  tmp="$(mktemp)"
  if sed -E 's/^#faceid# //' /etc/pam.d/sudo > "$tmp" \
     && grep -q 'pam_opendirectory.so' "$tmp"; then
    chmod u+w /etc/pam.d/sudo 2>/dev/null || true
    cat "$tmp" > /etc/pam.d/sudo 2>/dev/null \
      || echo "warning: could not restore pam_tid.so in /etc/pam.d/sudo" >&2
    chown root:wheel /etc/pam.d/sudo 2>/dev/null || true
    chmod 444 /etc/pam.d/sudo 2>/dev/null || true
  fi
  rm -f "$tmp"
fi

echo "OK"
