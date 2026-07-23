#!/usr/bin/env bash
# Désinstalle proprement. Retire la règle PAM (sudo) et l'agent utilisateur.
set -euo pipefail

LABEL="com.lorenzo.faceid"

echo "== Retrait de la règle PAM (sudo) =="
if [ -f /etc/pam.d/sudo_local ]; then
  sudo sed -i '' '/pam_faceid/d' /etc/pam.d/sudo_local
  echo "  ligne pam_faceid retirée de /etc/pam.d/sudo_local"
fi
sudo rm -f /usr/local/lib/pam/pam_faceid.so || true

echo "== Réactivation de pam_tid.so (Touch ID système) =="
if sudo grep -q '^#faceid# ' /etc/pam.d/sudo 2>/dev/null; then
  sudo sed -i '' -E 's/^#faceid# //' /etc/pam.d/sudo
  echo "  pam_tid.so réactivé"
fi

echo "== Déchargement de l'agent utilisateur =="
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
rm -f "${HOME}/Library/LaunchAgents/${LABEL}.plist"

echo "Désinstallé. (Les modèles et embeddings dans ~/Library/Application Support/faceid restent.)"
echo "Pour tout effacer :  rm -rf ~/Library/Application\\ Support/faceid"
