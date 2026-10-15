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

# 2) staged app + verified package; administrator authentication happens in Installer
bash scripts/build-app.sh

echo
echo "✅ Package ready: $DIR/build/Mugshot-dev.pkg"
echo "   Open this package to install Mugshot; it opens setup after installation."
echo
echo "Next, in the app window that opens:"
echo "  1. Register your face."
echo "  2. Complete the guided permissions for optional lock-screen unlock."
echo "  3. Try it:  sudo -k && sudo true   (look at the camera)"
