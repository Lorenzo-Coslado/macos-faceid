# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-10-21

### Added

- Face enrollment expands from the camera notch with a live, mirrored camera
  preview and 72 green ticks showing the head angles actually captured.
- Two guided scans cover eight head directions, with a Continue step between scans
  and positioning instructions when the face is too close, too far away or off-center.
  Capture pauses when multiple faces are visible. Camera frames stay in memory.

### Fixed

- Large camera events are decoded across pipe reads without losing preview frames
  or the final completion event. Closing enrollment or pressing Escape stops capture,
  and stale events from an earlier session cannot affect a new scan.
- Enrollment uses the selected camera and preserves existing face data when a scan
  is interrupted. Adding an appearance retains the previously enrolled samples.

## [1.2.0] - 2026-10-15

### Added

- Optional face unlock for an already logged-in, locked session, with a continuous
  camera, Accessibility and Mac login-password setup. FileVault and first login
  after a restart still require normal authentication.
- Fusion: a taller animated HUD attached to the camera notch, with scanning,
  recognition and password-fallback states. Displays without a notch use a capsule.
- Reusable macOS documentation previews and new README animations and images.

### Fixed

- Local rebuilds now keep a persistent signing certificate instead of invalidating
  macOS consent every time a HUD resource changes. Migration to Developer ID is
  explicit; compatible updates preserve the application's permission identity.
- Signature resources remain readable after Installer changes their owner to root.
  Packages validate the installed signature as the logged-in user before setup.
- Lock-screen password events target the genuine Apple loginwindow process. Session,
  feature state and permissions are rechecked after Keychain retrieval; changing
  users or unlocking concurrently cancels delivery instead of typing into another app.
- Stale permission dialogs no longer repeat on every configuration attempt. Setup
  resumes after restart and detects camera and Accessibility approvals automatically.
- Packages stop the previous app, install into Applications, verify the exact
  executable and open that copy rather than a development URL handler.

### Release tooling

- Distribution verifies Developer ID, hardened runtime, timestamps, notarization,
  Gatekeeper, package payload permissions and Sparkle signatures against the embedded
  public key. Releases are tied to a clean source commit with successful CI.
- Release preparation creates a GitHub draft. Existing notarized artifacts can be
  resumed without rebuilding, and public releases cannot be silently overwritten.
- DMG layout is generated without opening or automating Finder.

### Fixed

- A `sudo` you did not look at cost eight seconds of a saturated core. The recognition
  loop spent its whole budget even when the camera had not seen a single face — the
  common case, since you type the command and keep reading your screen. Measured on an
  M-series Air, a scan that runs to its budget burns 7.55 s of CPU over 162 frames,
  webcam and capsule on top. It now gives up after three seconds without any face
  (`FACEID_NO_FACE_ABORT`), which is where the password prompt was heading anyway; the
  full budget still applies as soon as somebody is actually detected.
- Enrolment held the camera indefinitely. Its capture loop had no time budget at all,
  unlike the verification loop, so an enrolment nobody completed kept the webcam and a
  core busy until the end of the session. It now stops after a minute
  (`FACEID_ENROLL_TIMEOUT`) and reports why instead of waiting forever.
- Closing the enrolment window left the scan running behind it. `cancel()` existed but
  was never called from anywhere, and the window merely hides itself, so the engine
  went on filming with the green light on and nothing to say so. Closing the window now
  cancels the scan, and reopening enrolment no longer starts a second one alongside the
  first.

### Changed

- The build now installs from `requirements-lock.txt` instead of the version ranges.
  Every build used to take whatever PyPI served that day, so two builds of the same
  Mugshot version did not necessarily contain the same OpenCV. For something that
  guards `sudo`, what goes into the bundle should be a decision, not a date.
- `scripts/download-models.sh` verifies the SHA-256 of both ONNX models. They are
  pulled from the zoo's `main` branch, where a file can change under the same name —
  and `COSINE_THRESHOLD` is calibrated for this exact SFace model, as are the
  `embeddings.npy` people already enrolled. A silent swap would have moved the
  threshold's meaning with nothing to catch it.
- Dependabot no longer proposes OpenCV 5. Measured against 4.14, SFace itself is
  numerically identical (cosine 1.000000 on fixed inputs), but `alignCrop` changed
  interpolation — 62 % of the pixels in the 112×112 crop differ. The move is a
  deliberate pass with a threshold re-measured on real faces, not an automated bump.

## [1.1.1] - 2026-08-18

### Fixed

- The installer package installed somewhere else entirely. macOS looks for a bundle
  already carrying the same identifier and installs over *that* — bundle relocation — so
  on any machine holding another copy the app never reached Applications:
  `PackageKit: Applications/Mugshot.app relocated to …/dist/Mugshot.app`. Relocation is
  decided per bundle through a component plist, not by the package-level
  `relocatable="false"`; the `<relocate>` block is now gone.
- The package's postinstall then failed behind it, looking for the app at a hardcoded
  `/Applications`. It exits 0 when it cannot find it, so `sudo` silently went unwired
  while the installer reported success. It now derives the path from the target volume.
- Uninstalling, and disabling sudo, did nothing after a package install. That path writes
  the sudo rule with the installer's own privileges, so no helper is ever registered and
  the XPC call went to a service that does not exist. Both now register the helper on
  demand, and failures surface as an alert with the terminal command on offer, rather
  than as grey text at the bottom of a scrolling window.
- The installer's welcome page displayed its own markup: the file opened with an HTML
  comment and had no doctype, so the Installer rendered the source as plain text.
- The one choice the package asks about was hidden behind a Customize button nobody
  clicks. The Installation Type step now opens on the list, and the package states that
  it installs system-wide instead of letting the destination step vanish unexplained.
- `finish-release.sh` stapled the notarized disk image, then deleted it and rebuilt one
  with `hdiutil` — a different file, with no ticket at Apple. Anyone using it would have
  shipped an unnotarized image believing otherwise.

### Changed

- The README leads with the installer package: one password instead of two macOS
  permissions. The disk image stays available for those who prefer dragging.
- Screenshots redone from the current build.


## [1.1.0] - 2026-08-14

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

[Unreleased]: https://github.com/Lorenzo-Coslado/macos-faceid/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/Lorenzo-Coslado/macos-faceid/compare/v1.0.3...v1.1.0
[1.0.3]: https://github.com/Lorenzo-Coslado/macos-faceid/compare/v1.0.2...v1.0.3
[1.0.2]: https://github.com/Lorenzo-Coslado/macos-faceid/compare/v1.0.0...v1.0.2
[1.0.0]: https://github.com/Lorenzo-Coslado/macos-faceid/releases/tag/v1.0.0
