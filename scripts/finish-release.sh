#!/usr/bin/env bash
# Re-soumet le DMG déjà signé à la notarisation, puis staple l'app et le DMG.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$HERE/dist/FaceID.app"
DMG="$HERE/dist/FaceID.dmg"
PROFILE="${NOTARY_PROFILE:-faceid-notary}"

echo "== Re-soumission notarisation =="
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "== Staple (app puis DMG final) =="
xcrun stapler staple "$APP"
rm -f "$DMG"
hdiutil create -volname "FaceID" -srcfolder "$APP" -ov -format UDZO "$DMG" >/dev/null
xcrun stapler staple "$DMG"
echo "✅ DMG notarisé + staplé : $DMG"
