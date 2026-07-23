#!/usr/bin/env bash
# Télécharge Sparkle (version épinglée) dans vendor/sparkle si absent.
# Fournit Sparkle.framework (embarqué dans l'app) + les outils bin/ (generate_keys,
# sign_update, generate_appcast). Idempotent : ne re-télécharge pas si déjà là.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VER="2.9.4"
DEST="$HERE/vendor/sparkle"
FRAMEWORK="$DEST/Sparkle.framework"

if [ -d "$FRAMEWORK" ]; then
  echo "Sparkle $VER déjà présent ($DEST)"
  exit 0
fi

mkdir -p "$DEST"
TARBALL="/tmp/Sparkle-$VER.tar.xz"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VER/Sparkle-$VER.tar.xz"
echo "Téléchargement de Sparkle $VER…"
curl -fL "$URL" -o "$TARBALL"
tar -xJf "$TARBALL" -C "$DEST"
echo "✅ Sparkle $VER extrait dans $DEST"
