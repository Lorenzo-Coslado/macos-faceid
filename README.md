<div align="center">

# FaceID for Mac

**Unlock `sudo` with your face.** A native macOS menu bar app — face recognition,
a choice panel, and a Dynamic Island-style scan animation.

[![CI](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml/badge.svg)](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/arch-Apple%20Silicon-black)
![License](https://img.shields.io/badge/license-MIT-3ba55d)
![Notarized](https://img.shields.io/badge/Apple-notarized-3ba55d?logo=apple)

![FaceID Dynamic Island demo](assets/demo.gif)

### [⬇︎ Download FaceID.dmg](https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg)

<sub>Notarized by Apple — no Gatekeeper warning. Just open it.</sub>

</div>

---

> [!WARNING]
> **This is a fun project, not a security product.** A 2D webcam can be fooled by
> a photo — it is **not** more secure than Touch ID or your password. `sudo` always
> keeps the password as a fallback, so you can never lock yourself out.

## ✨ Features

- 🧠 **Face ID for `sudo`** — type `sudo`, the camera recognizes you, no password.
- 🎛️ **Native menu bar app** (Swift / SwiftUI) — guided enrollment, settings, one-click enable.
- 🪄 **Choice panel** — Face ID / Fingerprint (Touch ID) / Password.
- ✨ **Dynamic Island** scan animation (→ ✅ on success).
- 🌍 **11 languages** — follows your system language (English by default).
- 🔒 **100% local & offline** — nothing leaves your Mac. Password fallback guaranteed.
- 📦 **Self-contained** — one app, nothing else to install.

## 🚀 Install

### Download (recommended)

1. **[Download `FaceID.dmg`](https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg)**
2. Open the DMG and drag **FaceID** into **Applications**.
3. Launch **FaceID** — a small face icon appears in your menu bar.
4. Click it → **Set Up My Face** and follow the enrollment (allow camera when asked).
5. **Settings → Enable Face ID for sudo** (enter your admin password once).
6. Test it, in a terminal:
   ```bash
   sudo -k && sudo true
   ```
   The camera lights up, recognizes you, and `sudo` unlocks — no password.

It's a normal notarized app, so there is **no “unidentified developer” warning**.

### Build from source (developers)

<details>
<summary>Requirements & steps</summary>

Requirements: macOS (Apple Silicon), Xcode Command Line Tools (`xcode-select --install`),
Python 3.12 (`brew install python@3.12`).

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh          # venv, deps, models, native helpers, builds & installs the app (dev mode)
```

To produce the distributable, notarized DMG (needs a *Developer ID Application*
certificate + a `notarytool` keychain profile named `faceid-notary`):

```bash
./scripts/build-release.sh
```
</details>

## 🧩 How it works

```
sudo ─▶ PAM module (root) ──unix socket──▶ daemon (your session, owns the camera)
        pam_faceid.so                        └─ YuNet (detect) + SFace (embeddings)
                                                 └─ cosine match ▶ OK / FAIL
```

A root process launched by `sudo` cannot access the camera (blocked by TCC), so a
tiny **PAM module** delegates to a **daemon** running in your user session. The daemon
detects your face ([YuNet](https://github.com/opencv/opencv_zoo)), computes an embedding
([SFace](https://github.com/opencv/opencv_zoo)) and compares it (cosine similarity) to
your enrolled face. The PAM rule is `sufficient`: on failure it simply falls back to your
password.

## 🔐 Security — read this

- **Weak anti-spoofing.** An RGB 2D webcam can be tricked by a photo. That's exactly
  why Apple requires an IR (TrueDepth) sensor for real Face ID.
- **Password always works.** The `sufficient` PAM rule means a failed match (or a
  stopped daemon, or a deleted app) falls back to your password. No lockout, ever.
- **Local only.** Your face embeddings live in `~/Library/Application Support/faceid`
  and never leave your Mac. FileVault at boot still uses your password.

Treat it as a fun convenience, keep Touch ID / password as your real security.

## ❓ FAQ

**Can it unlock the lock screen / login window?**
No. macOS protects the screen-unlock path (SIP + Apple restrictions on third-party
auth plugins — confirmed by Apple DTS). Use **Apple Watch** for hands-free screen
unlock. The full exploration is documented in [`LOCK-SCREEN-PLAN.md`](LOCK-SCREEN-PLAN.md).

**Will I get a Gatekeeper warning?**
No — the release is signed with a Developer ID and notarized by Apple. (If you build
from source it's ad-hoc signed and runs locally without issue.)

**How do I uninstall?**
Menu bar → **Settings → disable Face ID for sudo**, quit the app, then drag
`FaceID.app` to the Trash. To wipe your enrolled face:
`rm -rf ~/Library/Application\ Support/faceid`.

## 📄 License

MIT — see [LICENSE](LICENSE). Made for fun. No warranty.
