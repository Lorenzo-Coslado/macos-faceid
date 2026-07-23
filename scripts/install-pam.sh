#!/usr/bin/env bash
# =========================================================================
#  À LANCER TOI-MÊME. Ce script modifie la configuration d'authentification
#  de sudo (sécurité système) et demande donc sudo.
#
#  SÉCURITÉ : garde un shell root de secours ouvert dans une AUTRE fenêtre
#  AVANT de lancer ce script, au cas où :
#        sudo -s        # laisse cette fenêtre ouverte
#
#  La règle installée est "sufficient" et placée AVANT le mot de passe :
#  si le visage échoue, sudo retombe sur ton mot de passe. Pas de lockout.
# =========================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE_SRC="${HERE}/pam/pam_faceid.so"
MODULE_DST="/usr/local/lib/pam/pam_faceid.so"
LINE='auth       sufficient     /usr/local/lib/pam/pam_faceid.so'

echo "== Compilation du module PAM =="
make -C "${HERE}/pam"

echo "== Installation dans /usr/local/lib/pam (root) =="
sudo mkdir -p /usr/local/lib/pam
sudo cp "$MODULE_SRC" "$MODULE_DST"
sudo chown root:wheel "$MODULE_DST"
sudo chmod 644 "$MODULE_DST"

echo "== Configuration de /etc/pam.d/sudo_local =="
if [ ! -f /etc/pam.d/sudo_local ]; then
  printf '%s\n' "$LINE" | sudo tee /etc/pam.d/sudo_local >/dev/null
elif ! sudo grep -q pam_faceid /etc/pam.d/sudo_local; then
  # insère notre ligne en tête
  sudo sed -i '' "1i\\
${LINE}
" /etc/pam.d/sudo_local
else
  echo "  (déjà présent)"
fi

echo "== Désactivation de pam_tid.so (pour que NOTRE modal passe en premier) =="
# Notre modal propose déjà l'empreinte (Touch ID via le helper Swift), donc on
# neutralise le prompt Touch ID système qui s'afficherait sinon avant le modal.
if sudo grep -qE '^auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' /etc/pam.d/sudo; then
  sudo cp -n /etc/pam.d/sudo /etc/pam.d/sudo.bak-faceid || true
  sudo sed -i '' -E 's/^(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so)/#faceid# \1/' /etc/pam.d/sudo
  echo "  pam_tid.so commenté (backup : /etc/pam.d/sudo.bak-faceid)"
else
  echo "  (déjà désactivé ou absent)"
fi

echo
echo "Contenu de /etc/pam.d/sudo_local :"
sudo cat /etc/pam.d/sudo_local
echo
echo "Terminé. Teste dans un NOUVEAU terminal :"
echo "    sudo -k && sudo true"
echo "La caméra doit s'allumer ~2 s ; si ton visage matche, pas de mot de passe."
