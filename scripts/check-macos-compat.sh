#!/usr/bin/env bash
# Fail when a Mach-O inside an app requires a newer macOS than our baseline.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$HERE/scripts/macos-target.sh"

APP="${1:?usage: check-macos-compat.sh /path/to/App.app}"
[ -d "$APP" ] || { echo "app introuvable : $APP" >&2; exit 2; }

version_gt() {
  awk -v lhs="$1" -v rhs="$2" 'BEGIN {
    split(lhs, a, "."); split(rhs, b, ".")
    for (i = 1; i <= 3; i++) {
      av = (a[i] == "" ? 0 : a[i]) + 0
      bv = (b[i] == "" ? 0 : b[i]) + 0
      if (av > bv) exit 0
      if (av < bv) exit 1
    }
    exit 1
  }'
}

failed=0
count=0
while IFS= read -r -d '' file_path; do
  if ! file -b "$file_path" 2>/dev/null | grep -q 'Mach-O'; then
    continue
  fi
  count=$((count + 1))
  while IFS= read -r minos; do
    [ -n "$minos" ] || continue
    if version_gt "$minos" "$MACOSX_DEPLOYMENT_TARGET"; then
      echo "incompatible: $file_path requires macOS $minos (baseline $MACOSX_DEPLOYMENT_TARGET)" >&2
      failed=1
    fi
  done < <(xcrun vtool -show-build "$file_path" 2>/dev/null | awk '$1 == "minos" { print $2 }')
done < <(find "$APP" -type f -print0)

[ "$count" -gt 0 ] || { echo "aucun Mach-O trouvé dans $APP" >&2; exit 2; }
[ "$failed" -eq 0 ] || exit 1
echo "Compatibility OK: $count Mach-O file(s), macOS <= $MACOSX_DEPLOYMENT_TARGET"
