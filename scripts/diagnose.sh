#!/usr/bin/env bash
# Report why "sudo" is not prompting for a face.
#
# The PAM rule is `sufficient`, so anything that goes wrong (module missing, module
# refusing to load, daemon down, no enrolled face) degrades silently to the password
# prompt. This prints which of those it is.
#
# Read-only: changes nothing, needs no password.

APP="${1:-/Applications/Mugshot.app}"
RES="$APP/Contents/Resources"
SUPPORT="$HOME/Library/Application Support/faceid"
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }
info() { printf '        %s\n' "$1"; }

echo "== System =="
info "macOS $(sw_vers -productVersion) ($(uname -m))"
[ -d "$APP" ] && ok "app installed: $APP" || { bad "no app at $APP"; exit 1; }
info "version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null)"

echo "== 1. Is sudo wired to the module? =="
if grep -q pam_faceid /etc/pam.d/sudo_local 2>/dev/null; then
  ok "/etc/pam.d/sudo_local references pam_faceid"
else
  bad "/etc/pam.d/sudo_local missing or does not reference pam_faceid"
  info "=> Face ID for sudo was never enabled, or enabling it failed."
  info "   Open Mugshot > Settings and switch on 'Enable Face ID for sudo'."
fi
grep -qE '^auth[[:space:]]+include[[:space:]]+sudo_local' /etc/pam.d/sudo 2>/dev/null \
  && ok "/etc/pam.d/sudo includes sudo_local" \
  || bad "/etc/pam.d/sudo does not include sudo_local (unusual on macOS 14+)"

echo "== 2. Is the module installed and loadable? =="
MOD=/usr/local/lib/pam/pam_faceid.so
if [ -f "$MOD" ]; then
  ok "module present: $MOD"
  info "requires macOS $(vtool -show-build "$MOD" 2>/dev/null | awk '$1=="minos"{print $2; exit}')"
  info "signed by: $(codesign -dv "$MOD" 2>&1 | awk -F'=' '/^Authority/{print $2; exit}')"
  codesign --verify "$MOD" 2>/dev/null \
    && ok "signature valid" \
    || bad "signature invalid: sudo will refuse the module"
else
  bad "module missing: $MOD"
  info "=> Enabling Face ID for sudo did not complete."
fi

echo "== 3. Is a face enrolled? =="
[ -f "$SUPPORT/embeddings.npy" ] \
  && ok "enrolled ($(stat -f%z "$SUPPORT/embeddings.npy") bytes)" \
  || bad "no enrolled face: open Mugshot > Set Up My Face"

echo "== 4. Is the daemon running and listening? =="
pgrep -f "faceid daemon" >/dev/null && ok "daemon running" || bad "daemon not running (launch Mugshot)"
[ -S "$SUPPORT/faceid.sock" ] && ok "socket present" || bad "no socket at $SUPPORT/faceid.sock"

echo "== 5. What did the module report? =="
# Note: "Library Validation failed ... pam_faceid.so" in the system log is expected and
# harmless. sudo holds the com.apple.private.security.clear-library-validation
# entitlement and retries the load, so the module still ends up running.
#
# The module's os_log output lives in a volatile buffer that `log show` does not read
# back reliably, so the daemon's own file is the record that survives. To watch the
# module live instead, run this and trigger sudo from another terminal:
#   log stream --predicate 'subsystem == "com.lorenzo.Mugshot"'
DLOG="$SUPPORT/logs/daemon.log"
if [ -f "$DLOG" ]; then
  tail -3 "$DLOG" | sed 's/^/        /'
  grep -q "verify -> OK" "$DLOG" 2>/dev/null \
    && ok "the daemon has authenticated at least once" \
    || info "no successful verify recorded yet; run 'sudo -k; sudo true' and re-run this"
else
  info "no daemon log at $DLOG yet"
fi

echo
echo "Done. Paste this output back if anything says FAIL."
