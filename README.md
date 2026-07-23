<div align="center">

<img src="assets/logo.png" width="116" alt="FaceID" />

# FaceID

Unlock `sudo` with your face. A native macOS menu bar app that runs face
recognition fully on your Mac.

<p>
  <a href="https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml"><img src="https://github.com/Lorenzo-Coslado/macos-faceid/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <img src="https://img.shields.io/badge/macOS-13+-1d1d1f?logo=apple" alt="macOS 13+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon-1d1d1f" alt="Apple Silicon" />
  <img src="https://img.shields.io/badge/license-MIT-3ba55d" alt="MIT" />
</p>

<a href="https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg">
  <img src="assets/download-macos.png" width="230" alt="Download for macOS" />
</a>

<br><br>

<img src="assets/unlock.gif" width="540" alt="Face ID unlocking sudo" />

</div>

## What it is

You type `sudo`, the camera recognizes you, and it unlocks. No password to type.

It started as a weekend hack and turned into a small but complete app: a guided
enrollment, a settings window, and a choice on every prompt between Face ID, Touch ID,
and your password. Everything is bundled into a single signed app, and nothing ever
leaves your Mac.

> [!IMPORTANT]
> This is a fun project, not a security product. A 2D webcam can be tricked by a photo,
> so it is not more secure than Touch ID. `sudo` always keeps your password as a
> fallback, so you can never lock yourself out.

## Screenshots

<table>
  <tr>
    <td width="50%"><img src="assets/onboarding.png" alt="Guided enrollment" /></td>
    <td width="50%"><img src="assets/modal.png" alt="Choice panel" /></td>
  </tr>
  <tr>
    <td align="center"><b>Guided enrollment</b></td>
    <td align="center"><b>Face&nbsp;ID, Touch&nbsp;ID, or password</b></td>
  </tr>
</table>

## Install

1. [Download `FaceID.dmg`](https://github.com/Lorenzo-Coslado/macos-faceid/releases/latest/download/FaceID.dmg), open it, and drag **FaceID** into your **Applications** folder.
2. Launch **FaceID**. A small face icon appears in the menu bar.
3. Click it, choose **Set Up My Face**, and allow the camera when asked.
4. Open **Settings** and turn on **Enable Face ID for sudo** (enter your admin password once).
5. Try it in a terminal:

```bash
sudo -k && sudo true
```

The camera turns on, recognizes you, and `sudo` unlocks. Python, OpenCV and the
recognition models are bundled inside the app, so there is nothing else to install.
The app is signed and notarized by Apple, so there is no security warning on first open.

## How it works

<div align="center">
  <img src="assets/architecture.svg" width="840" alt="Architecture: sudo to PAM module to the daemon that owns the camera and runs recognition" />
</div>

A root process started by `sudo` cannot reach the camera, because macOS blocks camera
access in that context (TCC). So a small **PAM module** hands the request to a **daemon**
that runs in your login session and owns the camera. The daemon finds your face with
[YuNet](https://github.com/opencv/opencv_zoo), turns it into an embedding with
[SFace](https://github.com/opencv/opencv_zoo), and compares it to the face you enrolled.
The PAM rule is `sufficient`, so a failed match simply falls through to your password.

## Security

A few things worth being clear about:

* **Spoofing.** An RGB webcam can be fooled by a printed photo or a video. Real Face ID
  uses an infrared depth sensor precisely to avoid this. FaceID has no such protection.
* **Fallback.** Because the PAM rule is `sufficient`, a failed match, a stopped daemon,
  or even a deleted app all fall back to your password. You cannot get locked out.
* **Privacy.** Your face embeddings stay in `~/Library/Application Support/faceid` and
  never leave your machine. FileVault at boot still uses your password.

## Build from source

<details>
<summary>For developers</summary>

You need macOS on Apple Silicon, the Xcode Command Line Tools
(`xcode-select --install`) and Python 3.12 (`brew install python@3.12`).

```bash
git clone https://github.com/Lorenzo-Coslado/macos-faceid.git
cd macos-faceid
./install.sh
```

`install.sh` sets up a virtual environment, downloads the models, builds the native
helpers, and installs a development build of the app.

To produce the signed and notarized DMG you need a *Developer ID Application*
certificate and a `notarytool` keychain profile named `faceid-notary`:

```bash
./scripts/build-release.sh
```

</details>

## FAQ

**Can it unlock the lock screen or the login window?**
No. macOS protects the screen unlock path with SIP and does not let a third party plug
into it without losing Touch ID and the native UI. Apple engineers confirmed this on the
developer forums. For hands-free unlock, use an Apple Watch. The full write-up is in
[`LOCK-SCREEN-PLAN.md`](LOCK-SCREEN-PLAN.md).

**Will macOS say the app is from an unidentified developer?**
No. The download is signed with a Developer ID and notarized by Apple.

**How do I uninstall it?**
Open Settings, turn off Face ID for sudo, quit the app, and move `FaceID.app` to the
Trash. To delete your enrolled face, run `rm -rf ~/Library/Application\ Support/faceid`.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Acknowledgments

Face detection and recognition use the [YuNet and SFace](https://github.com/opencv/opencv_zoo)
models from OpenCV Zoo. Built with OpenCV, Swift and SwiftUI.

## License

[MIT](LICENSE).
