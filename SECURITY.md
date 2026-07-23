# Security Policy

## First, the honest disclaimer

**FaceID is a fun project, not a security product.** It authenticates against a 2D
RGB webcam, which can be fooled by a photo. It is **not** a hardening measure and
**not** more secure than Touch ID or a password. The PAM rule is `sufficient`, so your
password always remains a valid fallback.

Do not deploy it where real security matters.

## Scope

Reports that are in scope:

- The daemon socket or PAM module allowing **another local user** to obtain `sudo`.
- Enrolled face data leaving the machine (it should never, it lives only in
  `~/Library/Application Support/faceid`).
- The privileged install scripts doing something unintended as root.

Out of scope (known and documented): spoofing the 2D webcam with a photo or video.
That is an inherent limitation, not a vulnerability.

## Reporting a vulnerability

Please **do not open a public issue** for a real vulnerability. Instead, open a
private report via GitHub:

**Security → Advisories → Report a vulnerability** on
<https://github.com/Lorenzo-Coslado/macos-faceid/security/advisories/new>

Include steps to reproduce and the macOS version. Best-effort response, this is a
side project maintained on free time.
