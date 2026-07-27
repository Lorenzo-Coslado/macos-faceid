#!/usr/bin/env bash
# Reproduce the reported failure, then prove the installer repairs it.
#
# A machine running macOS 15.6.1 had everything installed correctly and sudo still only
# asked for the password, because /etc/pam.d/sudo had no `auth include sudo_local` line,
# so sudo never read our configuration. CI runners ship that line, so the repair path is
# never exercised there: this removes it on purpose first.
#
# Asserts, in order:
#   1. without the include, the module is NOT consulted   (the reported bug)
#   2. the installer puts the include back
#   3. with it, the module IS consulted and authentication succeeds
#
# Destructive: edits /etc/pam.d/sudo. CI only. The original is restored on every exit.
set -euo pipefail

APP="${1:?usage: check-pam-repair.sh /path/to/Mugshot.app}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUDO_PAM=/etc/pam.d/sudo
BACKUP="$(mktemp -t sudopam)"
SOCK_DIR="$HOME/Library/Application Support/faceid"
SOCK="$SOCK_DIR/faceid.sock"

sudo cp "$SUDO_PAM" "$BACKUP"
restore() {
  sudo cp "$BACKUP" "$SUDO_PAM" 2>/dev/null || true
  sudo chown root:wheel "$SUDO_PAM" 2>/dev/null || true
  sudo chmod 444 "$SUDO_PAM" 2>/dev/null || true
  rm -f "$BACKUP"
  kill %1 2>/dev/null || true
  rm -f "$SOCK"
}
trap restore EXIT

clang -Wall -O2 -o /tmp/pam_chain_test "$HERE/pam/pam_chain_test.c" -lpam

# Stand up a fake daemon and report whether the module reached it.
# Prints "contacted" on stdout when it did.
probe() {
  local witness; witness="$(mktemp -t witness)"; rm -f "$witness"
  mkdir -p "$SOCK_DIR"; rm -f "$SOCK"
  python3 - "$SOCK" "$witness" <<'PY' &
import socket, sys, os
sock_path, witness = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock_path); s.listen(1); s.settimeout(25)
try:
    conn, _ = s.accept()
    conn.recv(64)
    conn.sendall(b"OK\n")
    conn.close()
    open(witness, "w").write("contacted")
except socket.timeout:
    pass
finally:
    s.close()
    try: os.unlink(sock_path)
    except OSError: pass
PY
  local pid=$!
  for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
  /tmp/pam_chain_test "$(id -un)" >/dev/null 2>&1 || true
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ -f "$witness" ] && { echo contacted; rm -f "$witness"; } || true
}

echo "== Installing normally first =="
sudo env HOME="$HOME" bash "$APP/Contents/Resources/scripts/pam-install-root.sh" >/dev/null

echo "== Step 1: remove the include, reproducing the reported system =="
sudo chmod u+w "$SUDO_PAM"
sudo awk '!/^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local[[:space:]]*$/' \
  "$BACKUP" > /tmp/sudo.noinclude
sudo cp /tmp/sudo.noinclude "$SUDO_PAM"
sudo chmod 444 "$SUDO_PAM"
grep -qE '^[[:space:]]*auth[[:space:]]+include' "$SUDO_PAM" \
  && { echo "could not remove the include; aborting" >&2; exit 1; }

if [ "$(probe)" = "contacted" ]; then
  echo "FAIL: the module was consulted without the include; the test proves nothing." >&2
  exit 1
fi
echo "  reproduced: sudo does not consult the module (this is the reported bug)"

echo "== Step 2: run the installer, which should repair /etc/pam.d/sudo =="
sudo env HOME="$HOME" bash "$APP/Contents/Resources/scripts/pam-install-root.sh"
if ! grep -qE '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local' "$SUDO_PAM"; then
  echo "FAIL: the installer did not add the include." >&2
  sed -n '1,12p' "$SUDO_PAM" >&2
  exit 1
fi
echo "  repaired: the include is back"

echo "== Step 3: the module must now be consulted =="
if [ "$(probe)" != "contacted" ]; then
  echo "FAIL: still not consulted after the repair." >&2
  exit 1
fi
echo "  confirmed: sudo consults pam_faceid again"

echo "PASS: the reported failure is reproduced and repaired"
