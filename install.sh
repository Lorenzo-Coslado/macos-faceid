#!/usr/bin/env bash
# Full development install, in one command.
# Requires macOS 14+ (Apple Silicon), the Xcode Command Line Tools, Python 3.12, a webcam.
#
# This builds a *development* app that still depends on this checkout and its virtualenv.
# For a self-contained bundle, use scripts/build-standalone.sh; for a signed release,
# scripts/build-release.sh.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "════════════════════════════════════════════════════════"
echo "  Mugshot — development install"
echo "════════════════════════════════════════════════════════"

# 1) virtualenv, dependencies, models, native helpers, selftest
bash scripts/setup.sh

# 2) app bundle (icon, translations, signed bundle -> /Applications)
bash scripts/build-app.sh

echo
echo "✅ Installed. Mugshot is in /Applications."
echo "   Opening it…"
open /Applications/Mugshot.app || true
echo
echo "Next, in the app window that opens:"
echo "  1. Register your face."
echo "  2. Enable Face ID for sudo, and follow the two macOS approvals."
echo "  3. Try it:  sudo -k && sudo true   (look at the camera)"
