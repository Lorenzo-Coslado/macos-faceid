#!/usr/bin/env python3
"""Persistent, certificate-backed identity for local Mugshot builds.

The private key lives in a dedicated macOS keychain, outside the checkout. Never
rotate this identity automatically: TCC and Keychain grants follow its certificate.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NAME = "Mugshot Local Development"
HOME = Path(os.environ.get("MUGSHOT_SIGNING_HOME",
                           str(Path.home() / "Library/Application Support/Mugshot/Signing")))


def run(args, *, check=True, secret=""):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    if check and result.returncode:
        detail = result.stderr.strip().replace(secret, "<REDACTED>") if secret else result.stderr.strip()
        raise RuntimeError(f"{Path(str(args[0])).name} failed: {detail[-1600:]}")
    return result


def requirement(app):
    result = run(["/usr/bin/codesign", "-d", "-r-", "--verbose=4", app], check=False)
    match = re.search(r"^(?:# )?designated => (.+)$", result.stdout + result.stderr, re.M)
    if result.returncode or not match:
        raise RuntimeError(f"Cannot read signing identity: {app}")
    return match.group(1)


def identity():
    manifest = HOME / "identity.json"
    keychain = HOME / "identity.keychain-db"
    password_file = HOME / "keychain-password"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        if not keychain.exists() or not password_file.exists():
            raise RuntimeError("Signing identity is incomplete. Restore its keychain and password; do not regenerate it.")
        ensure_trusted(data, keychain)
        return data, keychain, password_file.read_text().strip()
    if HOME.exists() and any(HOME.iterdir()):
        raise RuntimeError("Signing directory is incomplete. Recover it before creating another identity.")
    installed = Path("/Applications/Mugshot.app")
    if installed.exists() and "MUGSHOT_SIGNING_HOME" not in os.environ:
        details = run(["/usr/bin/codesign", "-dv", installed], check=False).stderr
        if f"Authority={NAME}" in details:
            raise RuntimeError("The installed app already uses the local certificate. Restore its signing keychain instead of replacing its identity.")
    HOME.mkdir(parents=True, mode=0o700, exist_ok=True)
    HOME.chmod(0o700)
    password = secrets.token_urlsafe(40)
    password_file.write_text(password)
    password_file.chmod(0o600)
    cert = HOME / "certificate.pem"
    # Private PEM and PKCS#12 exist only while importing into the isolated keychain.
    with tempfile.TemporaryDirectory(prefix="mugshot-signing-") as temp:
        stage = Path(temp)
        config = stage / "openssl.cnf"
        config.write_text("""[req]
prompt = no
distinguished_name = subject
x509_extensions = codesign
[subject]
CN = Mugshot Local Development
O = Mugshot Local Development
[codesign]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
""")
        key = stage / "key.pem"
        p12 = stage / "identity.p12"
        run(["/usr/bin/openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-days", "3650", "-config", config, "-keyout", key, "-out", cert])
        key.chmod(0o600)
        run(["/usr/bin/openssl", "pkcs12", "-export", "-inkey", key, "-in", cert,
             "-out", p12, "-passout", f"file:{password_file}"])
        p12.chmod(0o600)
        run(["/usr/bin/security", "create-keychain", "-p", password, keychain], secret=password)
        run(["/usr/bin/security", "set-keychain-settings", "-lut", "21600", keychain])
        run(["/usr/bin/security", "unlock-keychain", "-p", password, keychain], secret=password)
        run(["/usr/bin/security", "import", p12, "-k", keychain, "-P", password,
             "-x", "-T", "/usr/bin/codesign"], secret=password)
        run(["/usr/bin/security", "set-key-partition-list", "-S", "apple-tool:,apple:",
             "-s", "-k", password, keychain], secret=password)
    fingerprint = run(["/usr/bin/openssl", "x509", "-in", cert, "-noout", "-fingerprint", "-sha1"]).stdout
    fingerprint = fingerprint.split("=", 1)[1].strip().replace(":", "")
    data = {"name": NAME, "fingerprint": fingerprint}
    manifest.write_text(json.dumps(data, indent=2) + "\n")
    manifest.chmod(0o600)
    ensure_trusted(data, keychain)
    return data, keychain, password


def ensure_trusted(data, keychain):
    if not re.fullmatch(r"[A-Fa-f0-9]{40}", data["fingerprint"]):
        raise RuntimeError("Invalid signing certificate fingerprint")
    search = shlex.split(run(["/usr/bin/security", "list-keychains", "-d", "user"]).stdout)
    if str(keychain) not in search:
        run(["/usr/bin/security", "list-keychains", "-d", "user", "-s", *search, keychain])
    valid = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning", keychain]).stdout
    domain = os.environ.get("MUGSHOT_SIGN_TRUST_DOMAIN", "admin")
    if data["fingerprint"] not in valid or (domain == "admin" and not has_admin_trust(data["fingerprint"])):
        # Restricted to CodeSigning. Admin-domain trust lets Installer/root helpers
        # validate the same certificate; this does not add a TLS trust policy.
        if domain == "admin":
            trust = ["/usr/bin/security", "add-trusted-cert", "-d"]
            if os.environ.get("CI") == "true":
                # Disposable headless CI has passwordless sudo, no SecurityAgent UI.
                trust = ["/usr/bin/sudo", "-n", *trust]
        elif domain == "user":
            trust = ["/usr/bin/security", "add-trusted-cert"]
        else:
            raise RuntimeError("MUGSHOT_SIGN_TRUST_DOMAIN must be user or admin")
        run(trust + ["-r", "trustRoot", "-p", "codeSign", HOME / "certificate.pem"])
        valid = run(["/usr/bin/security", "find-identity", "-v", "-p", "codesigning", keychain]).stdout
        if data["fingerprint"] not in valid:
            raise RuntimeError("The local code-signing certificate is not trusted; complete the native macOS authorization")


def has_admin_trust(fingerprint):
    with tempfile.TemporaryDirectory(prefix="mugshot-trust-") as folder:
        path = Path(folder) / "trust.plist"
        result = run(["/usr/bin/security", "trust-settings-export", "-d", path], check=False)
        if result.returncode or not path.exists():
            return False
        entry = plistlib.loads(path.read_bytes()).get("trustList", {}).get(fingerprint.upper(), {})
        return any(setting.get("kSecTrustSettingsPolicyName") == "CodeSigning"
                   and setting.get("kSecTrustSettingsResult", 1) in (1, 2)
                   for setting in entry.get("trustSettings", []))


def external_identity():
    selected = os.environ.get("LOCAL_SIGN_IDENTITY")
    if not selected:
        return None
    if selected == "-":
        raise RuntimeError("Ad-hoc signing is disabled: use the persistent local certificate or an explicit signing identity")
    args = ["/usr/bin/security", "find-identity", "-v", "-p", "codesigning"]
    keychain = os.environ.get("LOCAL_SIGN_KEYCHAIN")
    if keychain:
        args.append(keychain)
    matches = re.findall(r'\d+\) ([A-Fa-f0-9]{40}) "([^"]+)"', run(args).stdout)
    matches = [(fingerprint, name) for fingerprint, name in matches
               if selected.lower() == fingerprint.lower() or selected == name]
    if len(matches) != 1:
        raise RuntimeError("LOCAL_SIGN_IDENTITY must name exactly one valid certificate")
    return {"fingerprint": matches[0][0], "name": matches[0][1]}, keychain


def sign(app, *, reference=None, allow_development_migration=False):
    app = Path(app).resolve()
    if app.name != "Mugshot.app" or not (app / "Contents/MacOS/Mugshot").is_file():
        raise RuntimeError("Expected a complete Mugshot.app bundle")
    if str(app).startswith("/Applications/"):
        raise RuntimeError("Stage the app outside Applications before signing, then install the verified package")
    external = external_identity()
    if external:
        data, keychain = external
    else:
        data, keychain, password = identity()
        run(["/usr/bin/security", "unlock-keychain", "-p", password, keychain], secret=password)
    fingerprint = data["fingerprint"]
    expected = f'identifier "com.lorenzo.Mugshot" and certificate leaf = H"{fingerprint}"'
    reference_requirement = requirement(reference) if reference else None
    if reference_requirement and "cdhash " not in reference_requirement and not external:
        # Verify compatibility before changing any staged files.
        references_local = fingerprint.lower() in reference_requirement.lower()
        if not references_local:
            raise RuntimeError("The reference app uses a different signing certificate. Keep that identity; explicit migration is required.")
    common = ["/usr/bin/codesign", "--force", "--timestamp=none", "--sign", fingerprint]
    if keychain:
        common += ["--keychain", keychain]
    main = app / "Contents/MacOS/Mugshot"
    bundles = []
    for folder, dirs, files in os.walk(app, followlinks=False):
        base = Path(folder)
        if base != app and base.suffix in (".app", ".xpc", ".framework", ".bundle"):
            bundles.append(base)
        for name in files:
            path = base / name
            if path == main or path.is_symlink():
                continue
            if "Mach-O" in run(["/usr/bin/file", "-b", path]).stdout:
                run(common + ["--preserve-metadata=entitlements", path])
    for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
        run(common + ["--preserve-metadata=entitlements", bundle])
    root_args = common + ["--entitlements", ROOT / "packaging/entitlements.plist"]
    if not external:
        root_args += ["--requirements", "=designated => " + expected]
    run(root_args + [app])
    # The private signing keychain uses umask 077. App resources do not: Installer
    # changes their owner to root, so even CodeResources must be world-readable.
    run([sys.executable, ROOT / 'scripts/bundle-permissions.py', '--fix', app])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "-R", "=" + expected, app])
    if reference_requirement and "cdhash " not in reference_requirement:
        compatible = run(["/usr/bin/codesign", "--verify", "--strict", "-R", "=" + reference_requirement, app], check=False)
        if compatible.returncode:
            manifest = HOME / 'identity.json'
            local = json.loads(manifest.read_text()) if manifest.exists() else {}
            old_local = f'identifier "com.lorenzo.Mugshot" and certificate leaf = H"{local.get("fingerprint", "")}"'
            developer_id = run(["/usr/bin/codesign", "--verify", "--strict", '-R',
                                '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists', app], check=False)
            if not (allow_development_migration and external and developer_id.returncode == 0
                    and reference_requirement.lower() == old_local.lower()):
                raise RuntimeError('Signing identity changed. Only an explicit local-development to Developer ID migration is allowed.')
            print('Explicit local-development to Developer ID migration; Installer will request fresh consent once.')
    print(f"Signed with persistent local identity: {fingerprint}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("init")
    command = sub.add_parser("sign")
    command.add_argument("app")
    command.add_argument("--reference", help="Installed or previous app whose stable identity must remain compatible")
    command.add_argument('--allow-development-migration', action='store_true',
                         help='Allow the pinned local certificate to migrate to a verified Developer ID release')
    args = parser.parse_args()
    if args.command == "init":
        external = external_identity()
        data = external[0] if external else identity()[0]
        print(f"Persistent local identity ready: {data['fingerprint']}")
    else:
        sign(args.app, reference=args.reference, allow_development_migration=args.allow_development_migration)


if __name__ == "__main__":
    os.umask(0o077)
    try:
        main()
    except (RuntimeError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
