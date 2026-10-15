#!/usr/bin/env bash
# No camera, keyboard injection or consent changes. Keychain tests use a disposable dummy item.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cd "$HERE"
swiftc -swift-version 5 -module-cache-path "$STAGE/cache" \
  menubar/LockScreenUnlockCoordinator.swift tests/lock_screen_permissions.swift \
  -framework AppKit -framework ApplicationServices -o "$STAGE/permissions"
"$STAGE/permissions"
swiftc -swift-version 5 -module-cache-path "$STAGE/cache" \
  menubar/LockScreenSetup.swift tests/lock_screen_setup.swift \
  -framework SwiftUI -framework AVFoundation -o "$STAGE/setup"
"$STAGE/setup"
python3 tests/test_package_setup.py
swiftc -swift-version 5 -module-cache-path "$STAGE/cache" \
  menubar/LoginPasswordStore.swift tests/keychain_readiness.swift \
  -framework Security -framework OpenDirectory -o "$STAGE/keychain"
"$STAGE/keychain"
