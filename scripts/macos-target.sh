#!/usr/bin/env bash
# Shared deployment target for every native component in the app bundle.
# Keep this in sync with Info.plist, appcast.xml, README, and CI.
: "${MACOSX_DEPLOYMENT_TARGET:=15.0}"
: "${MUGSHOT_SWIFT_TARGET:=arm64-apple-macosx${MACOSX_DEPLOYMENT_TARGET}}"

export MACOSX_DEPLOYMENT_TARGET
export MUGSHOT_SWIFT_TARGET
