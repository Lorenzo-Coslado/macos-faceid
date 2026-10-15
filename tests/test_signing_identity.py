"""Real macOS signature tests: resource updates preserve identity, tampering fails."""
import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def command(args, env=None):
    return subprocess.run([str(x) for x in args], env=env, capture_output=True, text=True)


def designated(app):
    result = command(["codesign", "-d", "-r-", "--verbose=4", app])
    return next(line.split("=> ", 1)[1] for line in (result.stdout + result.stderr).splitlines() if "designated =>" in line)


class SigningIdentityTests(unittest.TestCase):
    @unittest.skipUnless(os.environ.get('MUGSHOT_TEST_DEVELOPER_ID'), 'Requires an actual Developer ID private key')
    def test_local_to_developer_id_requires_explicit_migration(self):
        with tempfile.TemporaryDirectory() as folder:
            local = self.fixture(folder, 'local', 'local appearance')
            release = self.fixture(folder, 'release', 'release appearance')
            successor = self.fixture(folder, 'successor', 'next release appearance')
            result = command(['python3', ROOT / 'scripts/local-signing.py', 'sign', local])
            self.assertEqual(result.returncode, 0, result.stderr)
            env = dict(os.environ, LOCAL_SIGN_IDENTITY=os.environ['MUGSHOT_TEST_DEVELOPER_ID'])
            args = ['python3', ROOT / 'scripts/local-signing.py', 'sign', release, '--reference', local]
            result = command(args, env)
            self.assertNotEqual(result.returncode, 0, 'A certificate change must never be silent')
            result = command(args + ['--allow-development-migration'], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('Explicit local-development to Developer ID migration', result.stdout)
            result = command(['python3', ROOT / 'scripts/local-signing.py', 'sign', successor,
                              '--reference', release], env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(designated(release), designated(successor))

    def test_fresh_signature_is_readable_after_root_installation(self):
        with tempfile.TemporaryDirectory() as folder:
            app = self.fixture(folder, "fresh", "current appearance")
            result = command(["python3", ROOT / "scripts/local-signing.py", "sign", app])
            self.assertEqual(result.returncode, 0, result.stderr)
            seal = app / "Contents/_CodeSignature/CodeResources"
            self.assertTrue(seal.stat().st_mode & stat.S_IROTH,
                            "A fresh signature cannot be read after Installer changes its owner to root")

    def test_explicit_ad_hoc_fallback_is_refused(self):
        result = command(["python3", ROOT / "scripts/local-signing.py", "init"],
                         dict(os.environ, LOCAL_SIGN_IDENTITY="-"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Ad-hoc signing is disabled", result.stderr)

    def test_missing_keychain_never_rotates_an_existing_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            home = Path(folder) / "signing"
            home.mkdir()
            marker = {"name": "Mugshot Local Development", "fingerprint": "A" * 40}
            manifest = home / "identity.json"
            manifest.write_text(json.dumps(marker))
            env = dict(os.environ, MUGSHOT_SIGNING_HOME=str(home))
            env.pop("LOCAL_SIGN_IDENTITY", None)
            result = command(["python3", ROOT / "scripts/local-signing.py", "init"], env)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Restore", result.stderr)
            self.assertEqual(marker, json.loads(manifest.read_text()))

    def fixture(self, folder, name, appearance):
        app = Path(folder) / name / "Mugshot.app"
        main = app / "Contents/MacOS/Mugshot"
        main.parent.mkdir(parents=True)
        shutil.copyfile("/usr/bin/true", main)
        main.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "com.lorenzo.Mugshot", "CFBundleExecutable": "Mugshot",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        }))
        resources = app / "Contents/Resources"
        resources.mkdir()
        (resources / "hud.txt").write_text(appearance)
        return app

    def test_visual_change_keeps_certificate_identity_and_integrity(self):
        with tempfile.TemporaryDirectory() as folder:
            default_home = Path.home() / "Library/Application Support/Mugshot/Signing"
            shared = os.environ.get("MUGSHOT_TEST_SIGNING_HOME")
            if not shared and (default_home / "identity.json").exists():
                shared = str(default_home)
            home = Path(shared) if shared else Path(folder) / "signing"
            env = dict(os.environ, MUGSHOT_SIGNING_HOME=str(home))
            first = self.fixture(folder, "first", "old appearance")
            second = self.fixture(folder, "second", "new appearance")
            # Reproduce the original defect with the real codesign tool first.
            for app in (first, second):
                result = command(["codesign", "--force", "--sign", "-", app])
                self.assertEqual(result.returncode, 0, result.stderr)
            old_ad_hoc = designated(first)
            result = command(["codesign", "--verify", "-R", "=" + old_ad_hoc, second])
            self.assertNotEqual(result.returncode, 0, "Ad-hoc resource update must reproduce the identity mismatch")
            try:
                for app in (first, second):
                    args = ["python3", ROOT / "scripts/local-signing.py", "sign", app]
                    if app == second:
                        args += ["--reference", first]
                    result = command(args, env)
                    self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(designated(first), designated(second))
                # Installer changes ownership to root. The signing seal must stay
                # readable by an ordinary user, not just the build's owner.
                seal = second / "Contents/_CodeSignature/CodeResources"
                self.assertTrue(seal.stat().st_mode & stat.S_IROTH,
                                "Installed CodeResources would be unreadable after root takes ownership")
                self.assertNotIn("cdhash ", designated(second))
                result = command(["codesign", "--verify", "--deep", "--strict", "-R", "=" + designated(first), second])
                self.assertEqual(result.returncode, 0, result.stderr)
                fingerprint = json.loads((home / "identity.json").read_text())["fingerprint"]
                result = command(["python3", ROOT / "scripts/local-signing.py", "init"], env)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(fingerprint, json.loads((home / "identity.json").read_text())["fingerprint"])
                self.assertEqual(stat.S_IMODE((home / 'keychain-password').stat().st_mode), 0o600)
                (second / "Contents/Resources/hud.txt").write_text("unsigned tampering")
                result = command(["codesign", "--verify", "--deep", "--strict", second])
                self.assertNotEqual(result.returncode, 0, "Stable identity must still reject modified unsigned resources")
            finally:
                keychain = home / "identity.keychain-db"
                if not shared and keychain.exists():
                    if os.environ.get("MUGSHOT_SIGN_TRUST_DOMAIN", "admin") == "admin":
                        removal = ["security", "remove-trusted-cert", "-d", home / "certificate.pem"]
                        if os.environ.get("CI") == "true":
                            removal = ["sudo", "-n", *removal]
                        command(removal)
                    else:
                        command(["security", "remove-trusted-cert", home / "certificate.pem"])
                    command(["security", "delete-keychain", keychain])


if __name__ == "__main__":
    unittest.main()
