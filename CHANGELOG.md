# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Opening Mugshot now opens a window. It used to place an icon in the menu bar and show
  nothing, and clicking the app again while it ran did nothing at all — reopening was
  never handled. The window stays hidden when macOS launches the app at login.
- That window opens on a one-line verdict — *Ready*, *No face registered yet*, or *Not
  enabled for sudo* — next to the button that fixes what is missing.
- Enabling Face ID for sudo is now a list of the macOS approvals it requires. Each step
  ticks itself off when you grant it, so you never re-flip a switch you already flipped.
  The helper is asked whether it can write to `/etc/pam.d` before the attempt, instead of
  the answer being inferred from a failure halfway through.
- **Uninstall Mugshot…**, which undoes the `sudo` rule, restores the system Touch ID
  rule, unregisters the helper and the login item, and offers to delete the enrolled
  face. Dragging the app to the Trash left all of that behind, including system Touch ID
  for `sudo`, which stayed switched off with no way to restore it from the interface.
- **Add an appearance…**, which adds to the enrolled face instead of replacing it —
  glasses, a beard, evening light.
- Quitting while Face ID for sudo is on now says what that costs, since it silently sent
  `sudo` back to the password prompt.
- An installer package (`scripts/build-pkg.sh`, wired into `build-release.sh`). The
  system Installer already runs as root with the right to write `/etc/pam.d`, so a single
  password replaces the two approvals — and it puts the app in Applications itself.
  Enabling `sudo` is an optional, pre-selected choice in the installer. It is signed with
  a *Developer ID Installer* identity, which macOS requires for packages and which is
  distinct from the Application identity that signs the app; `BUILD_PKG=0` skips it.
- Offering to move the app to Applications when launched from elsewhere, instead of only
  explaining the problem.
- Sensitivity as three named levels, the raw cosine value kept under *Advanced*.
- **Copy diagnostics** in the window, and `diagnose.sh` shipped inside the bundle — it
  previously required cloning the repository.

### Changed

- No choice panel before each `sudo` by default: the scan starts straight away. Clicking
  the capsule falls back to the password without waiting for the timeout. The panel
  remains available in Settings.
- The camera opens through AVFoundation explicitly at 640×480, and warm-up now stops once
  exposure settles rather than always discarding a fixed number of frames.
- The menu says what Face ID's state is rather than a daemon's. *Stop Daemon*, which cut
  `sudo` off in one click without saying so, is replaced by *Restart Face ID*, shown only
  when it is stopped.
- The app is called Mugshot throughout; parts of the interface still said FaceID.

### Fixed

- The engine spoke French to everyone. Enrolment errors, the fallback dialog and the
  Touch ID prompt were hardcoded French strings surfacing in an interface translated into
  eleven languages. The engine now emits stable codes, and its prompts come from the same
  translation table as the app.
- Dragging the sensitivity slider restarted the engine on every increment, leaving a
  dozen processes competing for the same socket. The threshold is applied on release, and
  restarts are serialised.
- The camera picker in Settings was labelled *System camera settings…*: two translation
  keys shared a name and one overwrote the other.
- An environment flag that was set but empty (`FACEID_MODAL=`) counted as enabled.
- Removing the `sudo` integration restored `pam_tid.so` with `sed -i`, which renames the
  file — an operation SIP can refuse on `/etc/pam.d/sudo`, leaving system Touch ID off.
  It is now rewritten in place and validated, as the install path already did.

### Packaging

- `opencv-contrib-python` replaced by `opencv-python-headless`, unused Haar cascades and
  stdlib modules excluded, symbols stripped: 189 → 175 MB installed, 94 → 89 MB to
  download. `packaging/faceid.spec` was regenerated and discarded on every build, so none
  of its settings had ever applied; it is now used as written.

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
