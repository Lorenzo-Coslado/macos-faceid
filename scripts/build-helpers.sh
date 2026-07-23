#!/usr/bin/env bash
# Compile les helpers natifs (Touch ID en Swift). Aucun sudo requis.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/helpers/touchid-helper.swift"
OUT="$HERE/helpers/touchid-helper"

echo "== Compilation touchid-helper =="
swiftc -O -o "$OUT" "$SRC" -framework LocalAuthentication
echo "   -> $OUT"

echo "== Vérification de la disponibilité Touch ID =="
"$OUT" --check || echo "   (Touch ID indisponible sur cette machine ?)"

echo "== Compilation auth-modal (panneau natif) =="
swiftc -O -o "$HERE/helpers/auth-modal" "$HERE/helpers/auth-modal.swift" -framework AppKit
echo "   -> $HERE/helpers/auth-modal"

echo "== Compilation faceid-hud (capsule Dynamic Island) =="
swiftc -O -o "$HERE/helpers/faceid-hud" "$HERE/helpers/faceid-hud.swift" -framework AppKit -framework QuartzCore
echo "   -> $HERE/helpers/faceid-hud"
