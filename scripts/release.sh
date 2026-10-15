#!/usr/bin/env bash
# Prepare a verified GitHub draft; --publish is the final public release step.
# Usage: release.sh <version> <build> [--reuse] [--publish]
# --reuse resumes from existing notarized artifacts and their verification manifest.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"
MARKETING="${1:?usage: release.sh <version> <build> [--reuse] [--publish]}"
BUILD="${2:?usage: release.sh <version> <build> [--reuse] [--publish]}"
shift 2
REUSE=false
PUBLISH=false
for option in "$@"; do
  case "$option" in
    --reuse) REUSE=true ;;
    --publish) PUBLISH=true ;;
    *) echo "Unknown release option: $option" >&2; exit 1 ;;
  esac
done
[[ "$MARKETING" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Expected a numeric semantic version' >&2; exit 1; }
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || { echo 'Expected a positive build number' >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo 'Commit all release sources before building or publishing' >&2; exit 1; }
REPO=Lorenzo-Coslado/macos-faceid
TAG="v$MARKETING"
COMMIT="$(git rev-parse HEAD)"
DMG="$HERE/dist/Mugshot.dmg"
PKG="$HERE/dist/Mugshot.pkg"
SPARKLE_BIN="$HERE/vendor/sparkle/bin"
# A successful historical run on another tree is not evidence for this release.
CI="$(gh run list --repo "$REPO" --workflow ci.yml --commit "$COMMIT" --limit 10 --json status,conclusion)"
python3 -c 'import json,sys; assert any(r["status"]=="completed" and r["conclusion"]=="success" for r in json.load(sys.stdin)), "No successful CI run for this exact commit"' <<< "$CI"
if [ "$PUBLISH" = true ]; then
  REMOTE="$(git ls-remote origin refs/heads/main | awk '{print $1}')"
  [ "$REMOTE" = "$COMMIT" ] || { echo 'Publish the reviewed source commit to main first' >&2; exit 1; }
fi
# Refuse to overwrite an already public release.
EXISTING="$(gh release view "$TAG" --repo "$REPO" --json isDraft,targetCommitish 2>/dev/null || true)"
if [ -n "$EXISTING" ]; then
  python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["isDraft"], "Refusing to overwrite a published release"; assert r["targetCommitish"]==sys.argv[1], "Draft belongs to another source commit"' "$COMMIT" <<< "$EXISTING"
fi
if [ "$REUSE" = false ]; then
  export MARKETING_VERSION="$MARKETING" BUILD_VERSION="$BUILD"
  bash scripts/build-release.sh
fi
python3 scripts/verify-release.py "$MARKETING" "$BUILD"
# Updating must be monotonic; never offer a lower Sparkle build to existing users.
python3 - "$BUILD" <<'PY'
import sys, xml.etree.ElementTree as ET
root=ET.parse('appcast.xml').getroot()
versions=[int(x.text) for x in root.findall('.//{http://www.andymatuschak.org/xml-namespaces/sparkle}version')]
assert int(sys.argv[1]) > max(versions, default=0), 'Build number must increase'
PY
STAGE="$HERE/dist/appcast-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$DMG" "$STAGE/"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" "$STAGE"
# Validate the signature against the public key embedded in the actual app.
swiftc scripts/verify-update.swift -o dist/verify-update
python3 - "$STAGE/appcast.xml" "$MARKETING" "$BUILD" <<'PY'
from pathlib import Path
import plistlib, subprocess, sys, xml.etree.ElementTree as ET
root=ET.parse(sys.argv[1]).getroot()
ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
item=root.find('./channel/item')
assert item.find('s:version',ns).text == sys.argv[3]
assert item.find('s:shortVersionString',ns).text == sys.argv[2]
entry=item.find('enclosure')
assert int(entry.attrib['length']) == Path('dist/Mugshot.dmg').stat().st_size
signature=entry.attrib['{'+ns['s']+'}edSignature']
info=plistlib.loads(Path('dist/Mugshot.app/Contents/Info.plist').read_bytes())
result=subprocess.run(['dist/verify-update','dist/Mugshot.dmg',info['SUPublicEDKey'],signature],capture_output=True,text=True)
assert result.returncode==0, result.stderr
PY
python3 - "$MARKETING" <<'PY'
from pathlib import Path
import re,sys
text=Path('CHANGELOG.md').read_text()
match=re.search(r'^## \['+re.escape(sys.argv[1])+r'\].*\n(.*?)(?=^## \[|\Z)',text,re.M|re.S)
assert match, 'Missing release changelog'
Path('dist/release-notes.md').write_text(match.group(1).strip()+'\n')
PY
ASSETS=("$DMG" "$PKG" "$HERE/dist/SHA256SUMS" "$HERE/dist/release-manifest.json")
if [ -n "$EXISTING" ]; then
  gh release upload "$TAG" "${ASSETS[@]}" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --notes-file "$HERE/dist/release-notes.md"
else
  gh release create "$TAG" "${ASSETS[@]}" --repo "$REPO" --target "$COMMIT" --draft \
    --title "Mugshot $MARKETING" --notes-file "$HERE/dist/release-notes.md"
fi
if [ "$PUBLISH" = true ]; then
  gh release edit "$TAG" --repo "$REPO" --draft=false --latest
  cp "$STAGE/appcast.xml" appcast.xml
  git add appcast.xml
  git commit -m "Release $MARKETING (build $BUILD): publish verified appcast"
  git push origin HEAD:main
  echo "Mugshot $MARKETING is public; the update feed is published."
else
  echo "Draft ready. Complete the real installation/lock/uninstall checks before --reuse --publish."
fi
