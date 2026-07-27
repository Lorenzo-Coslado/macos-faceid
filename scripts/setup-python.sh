#!/usr/bin/env bash
# Provision the python.org CPython framework used to build releases.
#
# Why not Homebrew: Homebrew builds Python with MACOSX_DEPLOYMENT_TARGET set to the
# build machine's own OS, so every collected binary inherits that floor and the frozen
# app refuses to launch on older systems. PyInstaller's guidance is explicit: use
# "python.org python builds with PyPI wheels". Those are universal2 and target macOS 11.
#
# The framework is extracted (not installed) into .python/, so this touches nothing
# outside the repository and needs no administrator password.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE"

PY_VERSION="${PY_VERSION:-3.12.10}"
PKG_URL="https://www.python.org/ftp/python/${PY_VERSION}/python-${PY_VERSION}-macos11.pkg"
SYSTEM_FRAMEWORK="/Library/Frameworks/Python.framework/Versions/3.12"
DEST="$HERE/.python"
FRAMEWORK="$DEST/Python.framework"
PYBIN="$FRAMEWORK/Versions/3.12/bin/python3.12"

# Preferred path: the framework installed where python.org puts it. PyInstaller spawns
# isolated child processes, and macOS strips DYLD_* when exec'ing a hardened-runtime
# binary, so a framework running from an arbitrary directory cannot be used for builds.
if [ -x "$SYSTEM_FRAMEWORK/bin/python3.12" ]; then
  echo "== Using the python.org framework at $SYSTEM_FRAMEWORK =="
  MINOS="$(vtool -show-build "$SYSTEM_FRAMEWORK/Python" 2>/dev/null | awk '$1 == "minos" { print $2; exit }')"
  echo "== Framework deployment target: macOS ${MINOS:-unknown} =="
  rm -rf "$HERE/.venv"
  "$SYSTEM_FRAMEWORK/bin/python3.12" -m venv "$HERE/.venv"
  "$HERE/.venv/bin/python" -m pip install --upgrade pip wheel -q
  "$HERE/.venv/bin/python" -m pip install -r "$HERE/requirements.txt" -q
  rm -rf "$DEST"          # the local copy is no longer needed
  echo
  echo "Ready. .venv now targets macOS ${MINOS:-11.0} instead of the host OS."
  exit 0
fi

cat >&2 <<EOF
The python.org CPython framework is not installed.

Homebrew's Python builds for the host OS, so a release built with it refuses to launch
on anything older. PyInstaller's guidance is to use python.org builds, which target
macOS 11. Install it once (this is the only step needing your password):

  sudo installer -pkg "$HERE/.python-pkg/python-${PY_VERSION}-macos11.pkg" -target /

Then re-run: bash scripts/setup-python.sh
EOF

mkdir -p "$HERE/.python-pkg"
if [ ! -f "$HERE/.python-pkg/python-${PY_VERSION}-macos11.pkg" ]; then
  echo >&2
  echo "== Downloading the installer for you =="
  curl -fL --progress-bar -o "$HERE/.python-pkg/python-${PY_VERSION}-macos11.pkg" "$PKG_URL"
  echo "Downloaded to $HERE/.python-pkg/" >&2
fi
exit 1
