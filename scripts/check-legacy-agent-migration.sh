#!/usr/bin/env bash
# Isolated launchd fixture only with --integration; never changes the real old job.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
swiftc -swift-version 5 -module-cache-path "$STAGE/cache" \
  "$HERE/menubar/LegacyAgentMigration.swift" "$HERE/tests/legacy_agent_migration.swift" \
  -o "$STAGE/check-migration"
"$STAGE/check-migration" "$@"
