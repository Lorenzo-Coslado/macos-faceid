#!/usr/bin/env bash
# Verify the PAM module is actually loadable and exports the entry points sudo calls.
#
# A module built for a newer macOS than the host loads fine on the build machine and
# fails on the user's, so this runs in CI on the oldest supported release too. dlopen
# is what pam(3) itself does, so a success here means sudo can load the module.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODULE="${1:-$HERE/pam/pam_faceid.so}"
[ -f "$MODULE" ] || { echo "PAM module not found: $MODULE" >&2; exit 2; }

echo "== Module: $MODULE =="
vtool -show-build "$MODULE" 2>/dev/null | awk '$1 == "minos" || $1 == "sdk" { print "   " $1 " " $2 }'

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/probe.c" <<'C'
#include <dlfcn.h>
#include <stdio.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: probe <module>\n"); return 2; }
    void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen failed: %s\n", dlerror()); return 1; }

    const char *symbols[] = { "pam_sm_authenticate", "pam_sm_setcred" };
    int missing = 0;
    for (unsigned i = 0; i < sizeof(symbols) / sizeof(*symbols); i++) {
        if (dlsym(h, symbols[i])) {
            printf("   %s present\n", symbols[i]);
        } else {
            fprintf(stderr, "   %s MISSING\n", symbols[i]);
            missing = 1;
        }
    }
    dlclose(h);
    return missing;
}
C

cc -Wall -O1 -o "$TMP/probe" "$TMP/probe.c"
"$TMP/probe" "$MODULE"
echo "PAM MODULE OK: loadable, entry points present"
