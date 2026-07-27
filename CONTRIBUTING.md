# Contributing to FaceID

Thanks for your interest! This is a small, fun project, contributions are welcome.

## Ground rules

- Be kind. See the [Code of Conduct](CODE_OF_CONDUCT.md).
- Keep it honest: this is **not** a security product. Don't add claims that suggest
  it is (see the security note in the README).
- One focused change per pull request.

## Dev setup

Requirements: macOS 14 or later (Apple Silicon), Xcode Command Line Tools, Python 3.12 or later.

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh          # venv, deps, models, native helpers, builds the app (dev mode)
```

### Building a release

Releases must be frozen with the python.org CPython framework, not Homebrew's. Homebrew
builds Python with the deployment target set to the machine's own macOS version, so every
binary it collects inherits that floor and the app refuses to launch on older systems.
PyInstaller's guidance is to use python.org builds, which target macOS 11.

```bash
bash scripts/setup-python.sh   # downloads the installer and rebuilds .venv from it
```

`scripts/check-macos-compat.sh` runs at the end of every build and fails if any bundled
Mach-O requires a newer macOS than the baseline in `scripts/macos-target.sh`.

Useful commands:

```bash
./.venv/bin/python -m faceid.selftest      # recognition pipeline sanity check
./.venv/bin/python -m faceid.diag          # live camera + score diagnostics
bash scripts/build-helpers.sh              # rebuild the Swift helpers
make -C pam                                # rebuild the PAM module
bash scripts/build-app.sh                  # rebuild & install the dev app
```

## Project layout

| Path | What |
|------|------|
| `faceid/` | Python engine: daemon, enrollment, recognition (OpenCV YuNet + SFace) |
| `menubar/` | Swift/SwiftUI menu bar app |
| `helpers/` | Native helpers: Touch ID, choice panel, Dynamic Island HUD |
| `pam/` | The `pam_faceid` PAM module (C) |
| `scripts/` | Build, packaging, install/uninstall |
| `packaging/` | PyInstaller entry + entitlements for the self-contained app |

## Pull requests

- Make sure `faceid.selftest` passes and the app compiles (CI checks both).
- Match the surrounding code style; comments in the code are in French, that's fine.
- Update the `CHANGELOG.md` under **Unreleased** if the change is user-facing.

## Reporting bugs / ideas

Use the issue templates. For anything security-sensitive, see [SECURITY.md](SECURITY.md).
