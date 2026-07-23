<div align="center">

<img src="assets/logo.png" width="118" alt="FaceID" />

# FaceID

**Unlock `sudo` with your face.**
A native macOS menu-bar app — **100 % on-device** face recognition, a proper
choice panel, and a Dynamic Island-style scan animation.

<br>

[![CI](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml/badge.svg)](https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml)
&nbsp;![macOS 13+](https://img.shields.io/badge/macOS-13%2B-1d1d1f?logo=apple)
&nbsp;![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-1d1d1f)
&nbsp;![MIT](https://img.shields.io/badge/license-MIT-3ba55d)

<br>

<a href="https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg">
  <img src="https://img.shields.io/badge/Download%20for%20macOS-1d1d1f?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="46" />
</a>

<sub>Signed &amp; notarized by Apple — no Gatekeeper warning. Just open it.</sub>

<br><br>

<img src="assets/unlock.gif" width="560" alt="Face ID unlocking sudo" />

</div>

---

## What it is

You type `sudo`, the camera recognizes you, and it's unlocked — no password.
What started as a weekend hack grew into a real little app: guided enrollment,
settings, a choice between Face ID / Touch ID / password, all packed into a
**self-contained `.app`**. Nothing leaves your Mac, and `sudo` always keeps your
password as a fallback, so you can never lock yourself out.

> [!IMPORTANT]
> **This is a fun project, not a security product.** A 2D webcam can be fooled by a
> photo — it is **not** more secure than Touch ID. Keep it for terminal convenience,
> not for protecting anything sensitive.

## Screenshots

<table>
<tr>
<td width="50%"><img src="assets/onboarding.png" alt="Guided enrollment" /></td>
<td width="50%"><img src="assets/modal.png" alt="Choice panel" /></td>
</tr>
<tr>
<td align="center"><b>Guided enrollment</b><br><sub>Your face registered in a few seconds.</sub></td>
<td align="center"><b>Face ID · Fingerprint · Password</b><br><sub>A native panel on every <code>sudo</code>.</sub></td>
</tr>
</table>

## Install

1. **[Download `FaceID.dmg`](https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg)**, open it, drag **FaceID** into **Applications**.
2. Launch **FaceID** — a small face icon appears in your menu bar.
3. Click it → **Set Up My Face** (allow the camera when asked).
4. **Settings → Enable Face ID for sudo** (your admin password, once).
5. Try it:
   ```bash
   sudo -k && sudo true
   ```
   The camera lights up, recognizes you, and `sudo` unlocks. ✨

Nothing else to install: Python, OpenCV and the models are **bundled inside the app**.

## How it works

```
sudo ─▶ PAM module (root) ──socket──▶ daemon (your session, owns the camera)
        pam_faceid.so                   └─ YuNet (detect) + SFace (embeddings)
                                             └─ cosine similarity ▶ OK / FAIL
```

A root process launched by `sudo` cannot reach the camera (blocked by TCC), so a tiny
**PAM module** delegates to a **daemon** in your user session. It detects your face
([YuNet](https://github.com/opencv/opencv_zoo)), computes an embedding
([SFace](https://github.com/opencv/opencv_zoo)) and compares it to your enrolled face.
The PAM rule is `sufficient`: on failure it **falls back to your password**.

## Security — the honest version

- **Weak anti-spoofing.** An RGB 2D webcam can be tricked by a photo. That's exactly
  why Apple requires an IR (TrueDepth) sensor for real Face ID.
- **Your password always works.** The `sufficient` rule means a failed match, a
  stopped daemon, or a deleted app all fall back to your password. No lockout, ever.
- **Local only.** Your embeddings live in `~/Library/Application Support/faceid` and
  never leave your machine. FileVault at boot still uses your password.

## Build from source

<details>
<summary>For developers</summary>

Requirements: macOS (Apple Silicon), Xcode Command Line Tools
(`xcode-select --install`), Python 3.12 (`brew install python@3.12`).

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh                    # venv, deps, models, helpers, dev app
```

Produce the signed &amp; notarized DMG (needs a *Developer ID Application* certificate
and a `notarytool` keychain profile named `faceid-notary`):

```bash
./scripts/build-release.sh
```
</details>

## FAQ

**Can it unlock the lock screen / login window?**
No. macOS protects the screen-unlock path (SIP + Apple's restrictions on third-party
auth plugins — confirmed by Apple DTS). For hands-free unlock, use an **Apple Watch**.
The full write-up is in [`LOCK-SCREEN-PLAN.md`](LOCK-SCREEN-PLAN.md).

**Will I get an “unidentified developer” warning?**
No — the download is Developer ID-signed and notarized by Apple.

**How do I uninstall?**
Settings → disable Face ID for sudo, quit the app, move `FaceID.app` to the Trash.
To wipe your face: `rm -rf ~/Library/Application\ Support/faceid`.

## License

[MIT](LICENSE) · made for fun · no warranty.
