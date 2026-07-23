#!/usr/bin/env bash
# Installation complète de FaceID en une commande.
# Prérequis : macOS (Apple Silicon), Xcode Command Line Tools, Python 3.12, webcam.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "════════════════════════════════════════════════════════"
echo "  FaceID — installation"
echo "════════════════════════════════════════════════════════"

# 1) venv + dépendances + modèles + helpers + selftest
bash scripts/setup.sh

# 2) app (icône, traductions, bundle signé -> /Applications)
bash scripts/build-app.sh

echo
echo "✅ Installé. FaceID est dans /Applications."
echo "   Ouverture de l'app…"
open /Applications/FaceID.app || true
echo
echo "Étapes suivantes, dans l'app (icône dans la barre de menus) :"
echo "  1. « Configurer mon visage » pour enrôler ton visage."
echo "  2. « Réglages » → activer « Face ID pour sudo »."
echo "  3. teste : sudo -k && sudo true  (regarde la caméra)"
