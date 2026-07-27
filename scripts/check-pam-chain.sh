#!/usr/bin/env bash
# End-to-end check that sudo actually reaches our PAM module.
#
# Why this exists: 1.0.2 installed everything correctly on macOS 15 and still fell back
# to the password, because /etc/pam.d/sudo did not include sudo_local, so the module was
# never consulted. Everything "looked" installed. Only asking sudo to run and observing
# whether the module was contacted catches that.
#
# Asserting "sudo succeeded" proves nothing on CI runners, where sudo is passwordless.
# Instead we stand up a fake daemon on the socket the module talks to: if it receives a
# connection, the module ran.
#
# Destructive: installs the module system-wide. CI only.
set -euo pipefail

APP="${1:?usage: check-pam-chain.sh /path/to/Mugshot.app}"
SOCK_DIR="$HOME/Library/Application Support/faceid"
SOCK="$SOCK_DIR/faceid.sock"
WITNESS="$(mktemp -t pamchain)"
rm -f "$WITNESS"

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

mkdir -p "$SOCK_DIR"
rm -f "$SOCK"

python3 - "$SOCK" "$WITNESS" <<'PY' &
import socket, sys, os
sock_path, witness = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock_path); s.listen(1); s.settimeout(60)
try:
    conn, _ = s.accept()
    conn.recv(64)                       # the module sends "VERIFY\n"
    conn.sendall(b"OK\n")               # pretend the face matched
    conn.close()
    open(witness, "w").write("contacted")
except socket.timeout:
    pass
finally:
    s.close()
    os.unlink(sock_path)
PY
FAKE_DAEMON=$!
trap 'kill $FAKE_DAEMON 2>/dev/null || true' EXIT

for _ in $(seq 1 50); do [ -S "$SOCK" ] && break; sleep 0.1; done
[ -S "$SOCK" ] || { echo "fake daemon did not come up" >&2; exit 1; }

echo "== Installing the module the way the privileged helper does =="
sudo env HOME="$HOME" bash "$APP/Contents/Resources/scripts/pam-install-root.sh"

echo "== /etc/pam.d/sudo =="
cat /etc/pam.d/sudo

echo "== Asking sudo to authenticate =="
sudo -k
# -n so a password prompt fails immediately instead of hanging the job.
sudo -n true || true

wait "$FAKE_DAEMON" 2>/dev/null || true
if [ -f "$WITNESS" ]; then
  echo "PASS: sudo consulted pam_faceid"
  rm -f "$WITNESS"
else
  echo "FAIL: sudo never consulted pam_faceid." >&2
  echo "      The module is installed but not in sudo's chain." >&2
  exit 1
fi
