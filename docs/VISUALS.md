# README visuals

The README uses **documentation illustrations**, reconstructed from the current
Mugshot views, on a shared macOS desktop. They contain a fictional account, no
camera image, no real password and no personal desktop content. They do not run
face recognition or demonstrate the security of an authentication attempt.

## Source of truth

| Scene | Native source |
| --- | --- |
| Fusion animation | `helpers/faceid-hud.swift` |
| Enrollment | `menubar/Onboarding.swift` |
| Main window | `menubar/SettingsView.swift` |
| Lock-screen setup | `menubar/LockScreenSetup.swift` |
| Authentication choices | `helpers/auth-modal.swift` |
| English labels | `i18n/en.lproj/Localizable.strings` |

The Fusion illustration follows the native 296 pt width, 64 pt glyph, 112 pt
expanded body, 90 pt success body and damped spring. The illustrated camera notch
is 240 × 32 pt; the actual app uses the display's safe areas instead of assuming
a notch size. The preview includes the separate capsule used on other displays.
Browser font rasterization and window materials can differ from the native app.
When changing the native UI, update these scenes and export the assets again.

## Wallpaper attribution

`assets/readme/macos-sequoia.jpg` is a resized copy of Apple's macOS Sequoia dark
wallpaper, downloaded from the
[macOS-Wallpapers collection](https://github.com/LAYTAT/macOS-Wallpapers/blob/main/15-Sequoia-Dark-6K.jpg).
The [original JPEG](https://raw.githubusercontent.com/LAYTAT/macOS-Wallpapers/main/15-Sequoia-Dark-6K.jpg)
was downloaded on 14 October 2026 and resized to 1920 px wide. Apple's artwork
remains Apple's property; the repository's MIT license applies to our code,
not to this wallpaper. Mugshot is an independent project.

## Preview locally

From the repository root:

```bash
python3 -m http.server 8768 --bind 127.0.0.1
```

Open <http://127.0.0.1:8768/docs/preview/>. Scene buttons switch between Terminal,
lock screen, enrollment, settings, setup and the choice panel. Replay or pause the
animation, scrub its time, choose the password fallback, or hide the camera notch.
Reduced-motion preferences pause the initial animation; explicit replay is available.

Share an exact frame using query parameters:

```text
?scene=sudo&time=1.5
?scene=lock&time=3.7
?scene=sudo&time=3.7&outcome=failure
?scene=sudo&time=1.5&notch=0
```

`export=1` removes the surrounding controls and produces a 1200 × 750 scene.
All dependencies are local; the preview works without third-party scripts or fonts.

## Export through Codex Browser

Use the Browser skill to connect a browser and obtain a tab. In its Node REPL,
with `tab` bound to that tab, import the export helper:

```js
const root = '/absolute/path/to/macos-faceid';
const { exportStills, exportFrames } = await import(`${root}/scripts/export-readme.mjs`);
await exportStills(tab, { root });
await exportFrames(tab, { root, directory: '/tmp/mugshot-sudo-frames', scene: 'sudo' });
await exportFrames(tab, { root, directory: '/tmp/mugshot-lock-frames', scene: 'lock' });
```

Frames sample the same renderer at 20 fps over six seconds. For short tool
timeouts, export batches using `start: 0, end: 30`, then `30, 60`, etc.
Screenshots are JPEG. Keep intermediate frames outside the repository.

Convert each sequence with FFmpeg (install separately if needed):

```bash
ffmpeg -y -framerate 20 -i /tmp/mugshot-sudo-frames/frame-%04d.jpg \
  -filter_complex '[0:v]scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' \
  -loop 0 assets/readme/fusion-sudo.gif
ffmpeg -y -framerate 20 -i /tmp/mugshot-lock-frames/frame-%04d.jpg \
  -filter_complex '[0:v]scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a' \
  -loop 0 assets/readme/fusion-lock.gif
```

Review scan, recognition, password fallback, retraction, and all six still images.
Check text clipping, loaded assets, and a narrow viewport before updating the README.
These exports are documentation only: do not rebuild or re-sign the installed app.
