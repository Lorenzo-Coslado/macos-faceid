# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.3] - 2026-07-27

### Fixed

- Face ID now actually triggers for `sudo`. On systems whose `/etc/pam.d/sudo` lacks the
  `auth include sudo_local` line, everything installed correctly and was silently ignored:
  `sudo` never read our configuration and simply asked for the password. Apple has shipped
  that include since macOS 14, but it is missing on some machines (reported on 15.6.1).
  Enabling Face ID for sudo now adds it when absent, after backing the file up and
  validating the result.
- The PAM module logs to `LOG_AUTH` at every exit path. The rule is `sufficient`, so any
  failure degrades to the password prompt with no explanation; there is now a trail.
  Inspect with `log show --last 2m --predicate 'eventMessage contains "pam_faceid"'`.

- Unlocking no longer wakes a paired iPhone. macOS exposes it as a Continuity Camera and
  sometimes lists it first, so `sudo` would light up the phone instead of using the
  webcam. The built-in camera is now preferred, and a picker in Settings overrides it.

### Added

- Camera selection in Settings, shown when more than one camera is available. iPhone
  entries are labelled as such.
- `scripts/diagnose.sh` reports which link of the chain is broken: the sudo wiring, the
  module, the enrolment, or the daemon.
- The disk image now contains the usual `Applications` shortcut, and the app warns when
  launched from the image or from outside Applications, where the privileged helper
  cannot survive.
- CI assembles the bundle and drives the real `sudo` PAM stack on macOS 14, 15 and 26.

## [1.0.2] - 2026-07-27

### Fixed

- The app now launches on macOS 14 and 15. Releases 1.0 and 1.0.1 were frozen with a
  Homebrew Python, which builds against the host OS, so every bundled binary required
  macOS 26 while the app advertised 13.0. Releases are now built with the python.org
  CPython framework, as PyInstaller recommends. If you are on macOS 14 or 15, download
  1.0.2 manually: the older build cannot start, so it cannot update itself.

### Changed

- Set macOS 14 as the supported baseline across native builds, packaging, CI, and documentation.
- Reject app bundles containing Mach-O binaries that require a newer macOS release.

### Security

- Reject XPC clients whose signature does not match the helper. Two ad-hoc binaries
  previously compared equal (both report an empty certificate chain), so any ad-hoc
  process could drive the privileged helper in a development build.
- Stop silently ignoring a failed `setCodeSigningRequirement` on the XPC connection.
  Developer ID builds require the app's own team; local builds pin the helper's cdhash.

Thanks to [@reycn](https://github.com/reycn) for reporting and fixing the signature
checks and for adding the deployment-target audit ([#5](https://github.com/Lorenzo-Coslado/macos-faceid/pull/5)).

## [1.0.0] - 2026-07-23

### Added

- Face ID for `sudo` via a PAM module + a user-session daemon (OpenCV YuNet + SFace).
- Native menu bar app (Swift/SwiftUI): guided enrollment, settings, one-click enable.
- Choice panel: Face ID / Touch ID / password.
- Animated "Dynamic Island" HUD during the face scan.
- Localization in 11 languages (follows the system language, English by default).
- Self-contained, signed & notarized `.app`, no external download needed to run it.
- Launch at login via `SMAppService`.

### Security

- The PAM rule is `sufficient`: any failure falls back to the password, no lockout.
- Face embeddings stay local and never leave the machine.

[Unreleased]: https://github.com/Lorenzo-Coslado/macos-faceid/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Lorenzo-Coslado/macos-faceid/releases/tag/v1.0.0
