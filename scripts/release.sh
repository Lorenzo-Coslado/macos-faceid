#!/usr/bin/env bash
# Publie une nouvelle version de Mugshot, de bout en bout :
#   1. build + signature Developer ID + notarisation + staple  -> dist/Mugshot.dmg
#   2. signe le DMG avec la clé Sparkle et régénère appcast.xml (via generate_appcast)
#   3. crée la Release GitHub (tag vX.Y.Z) avec le DMG en asset
#   4. commit + push de appcast.xml
#
# Usage :
#   ./scripts/release.sh <version> <build>
#   ex : ./scripts/release.sh 1.0.1 2
#        <version> = numéro marketing (CFBundleShortVersionString)
#        <build>   = entier STRICTEMENT croissant (CFBundleVersion) — Sparkle compare ça.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

MARKETING="${1:?usage: release.sh <version> <build>   ex: release.sh 1.0.1 2}"
BUILD="${2:?usage: release.sh <version> <build>   ex: release.sh 1.0.1 2}"
REPO="Lorenzo-Coslado/macos-faceid"
TAG="v$MARKETING"
DMG="$HERE/dist/Mugshot.dmg"
SPARKLE_BIN="$HERE/vendor/sparkle/bin"

echo "▶︎ Release Mugshot $MARKETING (build $BUILD)"

# 1) build + notarisation (le DMG staplé atterrit dans dist/)
export MARKETING_VERSION="$MARKETING" BUILD_VERSION="$BUILD"
bash scripts/build-release.sh

# 2) appcast : generate_appcast signe le DMG (clé privée du trousseau) et calcule
#    la taille + edSignature. On isole le DMG dans un dossier de staging.
bash scripts/fetch-sparkle.sh >/dev/null
STAGE="$HERE/dist/appcast-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  "$STAGE"
cp "$STAGE/appcast.xml" "$HERE/appcast.xml"
echo "✅ appcast.xml régénéré"

# 3) Release GitHub avec le DMG
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release upload "$TAG" "$DMG" --repo "$REPO" --clobber
else
  gh release create "$TAG" "$DMG" --repo "$REPO" \
    --title "Mugshot $MARKETING" --generate-notes
fi

# 4) publier l'appcast (c'est le flux que lisent les apps installées)
git add appcast.xml
git commit -m "Release $MARKETING (build $BUILD) : appcast" || true
git push origin main

echo
echo "🎉 Mugshot $MARKETING publié. Les apps installées verront la MAJ au prochain check."
