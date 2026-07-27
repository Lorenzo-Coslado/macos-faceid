#!/usr/bin/env bash
# Compile les helpers natifs (Touch ID en Swift). Aucun sudo requis.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/macos-target.sh"
SRC="$HERE/helpers/touchid-helper.swift"
OUT="$HERE/helpers/touchid-helper"

echo "== Compilation touchid-helper =="
swiftc -O -target "$MUGSHOT_SWIFT_TARGET" -o "$OUT" "$SRC" -framework LocalAuthentication
echo "   -> $OUT"

echo "== Vérification de la disponibilité Touch ID =="
"$OUT" --check || echo "   (Touch ID indisponible sur cette machine ?)"

echo "== Compilation auth-modal (panneau natif) =="
swiftc -O -target "$MUGSHOT_SWIFT_TARGET" -o "$HERE/helpers/auth-modal" "$HERE/helpers/auth-modal.swift" -framework AppKit
echo "   -> $HERE/helpers/auth-modal"

echo "== Compilation faceid-hud (capsule Dynamic Island) =="
swiftc -O -target "$MUGSHOT_SWIFT_TARGET" -o "$HERE/helpers/faceid-hud" "$HERE/helpers/faceid-hud.swift" -framework AppKit -framework QuartzCore
echo "   -> $HERE/helpers/faceid-hud"

# camera-list: lets the daemon avoid the paired iPhone (Continuity Camera)
swiftc -O -target "$MUGSHOT_SWIFT_TARGET" -o "$HERE/helpers/camera-list" \
  "$HERE/helpers/camera-list.swift" -framework AVFoundation
