# Release procedure

Public releases are Developer ID signed and notarized. The local development
certificate is deliberately not a distribution identity. Keep its keychain;
development rebuilds still use it. The release build explicitly allows a one-time
migration from that pinned local identity to Developer ID. Other identity changes
remain blocked.

## Prepare the source

Commit the release changes, update `CHANGELOG.md`, and choose a marketing version
and a strictly increasing Sparkle build. Push the commit and wait for CI on that
exact commit, including the macOS 14, 15 and 26 bundle jobs.

The build machine needs the existing Developer ID Application and Installer
certificates, the `faceid-notary` notarytool profile, the Sparkle signing key and
the python.org Python 3.12 framework. No secret belongs in the repository.

```bash
MARKETING_VERSION=1.2.0 BUILD_VERSION=9 bash scripts/build-release.sh
```

The output is `dist/Mugshot.app`, `Mugshot.dmg`, `Mugshot.pkg`, `SHA256SUMS`
and `release-manifest.json`. The manifest binds artifact hashes to the source
commit. Verification checks the real package payload as well as the staged app:
code resources must remain readable when root owns the installed bundle.

If Apple's submission is interrupted, preserve the signed artifacts and use:

```bash
bash scripts/finish-release.sh
```

This retries notarization, staples and verifies without rebuilding the containers.

## Validate on a real Mac

Automated checks do not establish that camera access and keyboard delivery work
on a real locked session. Use the exact candidate package, without resigning it:

1. Install from the package using the native macOS Installer. Confirm the installed
   version and run `codesign --verify --deep --strict /Applications/Mugshot.app`
   as the ordinary logged-in user.
2. Enroll a face, approve camera and Accessibility once, and enable the optional
   lock-screen feature. Enter the login password only in Mugshot.
3. Test `sudo -k && sudo true`, cancellation and the normal password fallback.
4. Lock an existing session and test recognition, a failed match, and wake from
   sleep. Test concurrent Touch ID/password unlocking: the saved password must
   never reach another application.
5. Revoke Accessibility and confirm that no password is typed. Re-enable it and
   check that setup recovers without repeated prompts.
6. Upgrade from the previous public release and a local build. Only an incompatible
   identity migration should require new consent; compatible updates should retain it.
7. Test uninstallation and verify that sudo and system Touch ID still work. A clean
   user or second Mac is needed to validate first-install behavior independently of
   the developer's existing TCC and Keychain state.

## Prepare and publish

Once the exact source commit has successful CI, prepare the GitHub draft from the
existing verified artifacts:

```bash
bash scripts/release.sh 1.2.0 9 --reuse
```

The draft includes the package, disk image, SHA-256 checksums, provenance manifest
and changelog. It does not update the public Sparkle feed. The script verifies the
update signature against the public key in the actual app before uploading.

After the real-Mac validation, place the reviewed source commit on `main`, then:

```bash
bash scripts/release.sh 1.2.0 9 --reuse --publish
```

Publication requires a clean checkout and the exact source commit on remote `main`.
It publishes the release, commits the generated appcast and pushes that feed.
Never replace artifacts in an existing public release. Ship a new version instead.
