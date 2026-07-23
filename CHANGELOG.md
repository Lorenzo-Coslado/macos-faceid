# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
