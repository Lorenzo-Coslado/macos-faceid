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
- The optional lock-screen feature exposing or incorrectly granting access to the saved
  Mac login password.
- Enrolled face data leaving the machine (it should never, it lives only in
  `~/Library/Application Support/faceid`).
- The privileged install scripts doing something unintended as root.

Out of scope (known and documented): spoofing the 2D webcam with a photo or video.
That is an inherent limitation, not a vulnerability.

## Optional lock-screen unlock

This feature is disabled by default. When enabled, Mugshot verifies the Mac login
password and stores it in this Mac's Keychain. Developer ID builds prefer the Data
Protection Keychain with an after-first-unlock, device-only accessibility class; local
development builds fall back to the local macOS Keychain because they do not have an
Apple application-identifier entitlement. Following a face match, the app retrieves and
types that password into the genuine Apple `loginwindow` process using its Accessibility
permission. Events are addressed to that process, not the global keyboard stream.
The current user must own the active console session, have completed their first
login, and still be locked. These conditions and consent are rechecked after reading
the Keychain item. Ambiguous or changed destinations abort the attempt.

This is not an integration with Apple's Secure Enclave or Face ID. It cannot unlock
FileVault or perform the first login after a restart, and it is less secure than Touch ID
or Apple Watch unlock. Disabling the feature or uninstalling Mugshot deletes the saved
password.

## Reporting a vulnerability

Please **do not open a public issue** for a real vulnerability. Instead, open a
private report via GitHub:

**Security → Advisories → Report a vulnerability** on
<https://github.com/Lorenzo-Coslado/macos-faceid/security/advisories/new>

Include steps to reproduce and the macOS version. Best-effort response, this is a
side project maintained on free time.
