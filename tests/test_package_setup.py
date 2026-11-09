"""Exercise installer failure paths without touching the host's PAM or permissions."""
import subprocess
import os
import shlex
import shutil
import plistlib
import hashlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PackageSetupTests(unittest.TestCase):
    def run_sudo_fixture(self, volume, pam_script=None, target="/"):
        app = Path(volume) / "Applications/Mugshot.app"
        if pam_script is not None:
            installer = app / "Contents/Resources/scripts/pam-install-root.sh"
            installer.parent.mkdir(parents=True)
            installer.write_text(pam_script)
        # Replace only the installed path. The real control flow and subprocess run.
        source = (ROOT / "packaging/pkg/postinstall-sudo").read_text()
        source = source.replace('APP="${VOLUME%/}/Applications/Mugshot.app"',
                                f"APP={shlex.quote(str(app))}")
        fixture = Path(volume) / "postinstall-sudo"
        fixture.write_text(source)
        return subprocess.run(["bash", str(fixture), "package", "/", target],
                              capture_output=True, text=True)

    def test_missing_payload_is_reported_as_failure(self):
        with tempfile.TemporaryDirectory() as volume:
            result = self.run_sudo_fixture(volume)
            self.assertNotEqual(result.returncode, 0,
                                "Installer reports success although sudo setup never ran")
            self.assertIn("introuvable", result.stderr)

    def test_other_volume_never_runs_host_pam_installer(self):
        with tempfile.TemporaryDirectory() as volume:
            marker = Path(volume) / "ran"
            result = self.run_sudo_fixture(volume, f"touch '{marker}'\n", target=volume)
            self.assertFalse(marker.exists(), "Offline install modified the running system")
            self.assertNotEqual(result.returncode, 0)

    def test_sudo_installer_failure_propagates(self):
        with tempfile.TemporaryDirectory() as volume:
            result = self.run_sudo_fixture(volume, "exit 42\n")
            self.assertEqual(result.returncode, 42)

    def test_sudo_installer_runs_once(self):
        with tempfile.TemporaryDirectory() as volume:
            marker = Path(volume) / "ran"
            result = self.run_sudo_fixture(volume, f"echo run >> '{marker}'\n")
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(marker.read_text(), "run\n")

    def run_preinstall_fixture(self, folder, target="/", status=0):
        log = Path(folder) / "stopped"
        kill = Path(folder) / "pkill"
        kill.write_text('#!/bin/bash\nprintf "%s\\n" "$@" >> "$TEST_STOP_LOG"\nexit "$TEST_STOP_STATUS"\n')
        kill.chmod(0o755)
        source = (ROOT / "packaging/pkg/preinstall-app").read_text()
        source = source.replace("/usr/bin/pkill", shlex.quote(str(kill)))
        fixture = Path(folder) / "preinstall"
        fixture.write_text(source)
        result = subprocess.run(["bash", str(fixture), "pkg", "/", target],
                                env=dict(os.environ, TEST_STOP_LOG=str(log), TEST_STOP_STATUS=str(status)),
                                capture_output=True, text=True)
        return result, log

    def test_upgrade_stops_only_the_installed_app_and_engines(self):
        with tempfile.TemporaryDirectory() as folder:
            result, log = self.run_preinstall_fixture(folder)
            self.assertEqual(result.returncode, 0, result.stderr)
            calls = log.read_text().splitlines()
            self.assertEqual(calls, [
                "-TERM", "-f", r"^/Applications/Mugshot\.app/Contents/MacOS/Mugshot([[:space:]]|$)",
                "-TERM", "-f", r"^/Applications/Mugshot\.app/Contents/Resources/faceid/faceid daemon([[:space:]]|$)",
            ])

    def test_fresh_install_without_running_processes_succeeds(self):
        with tempfile.TemporaryDirectory() as folder:
            result, _ = self.run_preinstall_fixture(folder, status=1)
            self.assertEqual(result.returncode, 0)

    def test_offline_install_cannot_stop_host_processes(self):
        with tempfile.TemporaryDirectory() as folder:
            result, log = self.run_preinstall_fixture(folder, target=folder)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())

    def run_app_fixture(self, volume, console_user="alice", launch_status=0, signature="DeveloperID", stale=False,
                        previous=False, requirement_status=0, user_signature_status=0):
        app = Path(volume) / "Mugshot.app"
        app.mkdir()
        binary = app / "Contents/MacOS/Mugshot"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"current-bundle")
        digest = hashlib.sha256(b"previous-bundle" if stale else binary.read_bytes()).hexdigest()
        (Path(volume) / "expected-app-sha256").write_text(digest + "\n")
        if previous:
            (Path(volume) / "previous-app-requirement").write_text('identifier "com.lorenzo.Mugshot"\n')
        stat = Path(volume) / "stat"
        stat.write_text('#!/bin/bash\nif [ "$2" = %u ]; then echo 501; else echo "$TEST_CONSOLE_USER"; fi\n')
        launch = Path(volume) / "launchctl"
        launch.write_text('#!/bin/bash\nif [[ "$*" == *codesign* ]]; then exit "$TEST_USER_SIGNATURE_STATUS"; fi\nlog="$TEST_LAUNCH_LOG"\nif [[ "$*" == *tccutil* ]]; then log="$TEST_RESET_LOG"; fi\nif [[ "$*" == *"reset Camera"* ]]; then log="$TEST_CAMERA_RESET_LOG"; fi\nif [[ "$*" == *pkill* ]]; then log="$TEST_SETTINGS_STOP_LOG"; fi\nprintf "%s\\n" "$@" > "$log"\nexit "$TEST_LAUNCH_STATUS"\n')
        signing = Path(volume) / "codesign"
        signing.write_text('#!/bin/bash\nif [[ "$*" == *"-R "* ]]; then exit "$TEST_REQUIREMENT_STATUS"; fi\necho "Signature=$TEST_SIGNATURE" >&2\n')
        signing.chmod(0o755)
        stat.chmod(0o755); launch.chmod(0o755)
        source = (ROOT / "packaging/pkg/postinstall-app").read_text()
        source = source.replace("APP=/Applications/Mugshot.app", f"APP={shlex.quote(str(app))}")
        source = source.replace("/usr/bin/stat", shlex.quote(str(stat)))
        source = source.replace("/bin/launchctl", shlex.quote(str(launch)))
        source = source.replace("/usr/bin/codesign", shlex.quote(str(signing)))
        fixture = Path(volume) / "postinstall-app"
        fixture.write_text(source)
        log = Path(volume) / "launch.log"
        env = dict(os.environ, TEST_CONSOLE_USER=console_user, TEST_LAUNCH_LOG=str(log),
                   TEST_LAUNCH_STATUS=str(launch_status), TEST_SIGNATURE=signature,
                   TEST_REQUIREMENT_STATUS=str(requirement_status),
                   TEST_USER_SIGNATURE_STATUS=str(user_signature_status),
                   TEST_SETTINGS_STOP_LOG=str(Path(volume) / "settings-stop.log"),
                   TEST_CAMERA_RESET_LOG=str(Path(volume) / "camera-reset.log"),
                   TEST_RESET_LOG=str(Path(volume) / "reset.log"))
        result = subprocess.run(["bash", str(fixture), "package", "/", "/"],
                                env=env, capture_output=True, text=True)
        return result, log

    def test_unreadable_installed_signature_cannot_report_success(self):
        with tempfile.TemporaryDirectory() as volume:
            result, log = self.run_app_fixture(volume, user_signature_status=65)
            self.assertEqual(result.returncode, 65)
            self.assertFalse(log.exists(), 'Never open an app whose signature only validates as root')

    def test_setup_launches_in_console_user_session(self):
        with tempfile.TemporaryDirectory() as volume:
            result, log = self.run_app_fixture(volume)
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = log.read_text().splitlines()
            self.assertEqual(arguments[:5], ["asuser", "501", "/usr/bin/sudo", "-u", "#501"])
            self.assertEqual(arguments[-2:], ["--args", "--setup"],
                             "A shared URL handler can route setup to another copy of Mugshot")
            self.assertFalse((Path(volume) / "reset.log").exists(), "Stable releases preserve grants")

    def test_local_build_clears_only_its_stale_grant_as_console_user(self):
        with tempfile.TemporaryDirectory() as volume:
            result, _ = self.run_app_fixture(volume, signature="adhoc")
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = (Path(volume) / "reset.log").read_text().splitlines()
            self.assertEqual(arguments, ["asuser", "501", "/usr/bin/sudo", "-u", "#501",
                                        "/usr/bin/tccutil", "reset", "Accessibility", "com.lorenzo.Mugshot"])

    def test_kept_old_app_fails_before_resetting_permissions_or_launching(self):
        with tempfile.TemporaryDirectory() as volume:
            result, log = self.run_app_fixture(volume, signature="adhoc", stale=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("different app version", result.stderr)
            self.assertFalse(log.exists())
            self.assertFalse((Path(volume) / "reset.log").exists())
            self.assertFalse((Path(volume) / "settings-stop.log").exists())

    def test_rebuilding_with_same_certificate_preserves_existing_grants(self):
        with tempfile.TemporaryDirectory() as volume:
            result, _ = self.run_app_fixture(volume, signature="local-certificate", previous=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse((Path(volume) / "reset.log").exists())
            self.assertFalse((Path(volume) / "camera-reset.log").exists())

    def test_one_time_certificate_migration_resets_only_old_accessibility_grant(self):
        with tempfile.TemporaryDirectory() as volume:
            result, _ = self.run_app_fixture(volume, signature="local-certificate", previous=True, requirement_status=1)
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = (Path(volume) / "reset.log").read_text().splitlines()
            self.assertEqual(arguments[-3:], ["reset", "Accessibility", "com.lorenzo.Mugshot"])
            camera = (Path(volume) / "camera-reset.log").read_text().splitlines()
            self.assertEqual(camera[-3:], ["reset", "Camera", "com.lorenzo.Mugshot"])
            stop = (Path(volume) / "settings-stop.log").read_text().splitlines()
            self.assertEqual(stop[-4:], ["/usr/bin/pkill", "-TERM", "-x", "System Settings"])

    def test_login_window_never_gets_user_setup(self):
        with tempfile.TemporaryDirectory() as volume:
            result, log = self.run_app_fixture(volume, console_user="root")
            self.assertEqual(result.returncode, 0)
            self.assertFalse(log.exists())

    def test_failed_gui_launch_explains_manual_recovery(self):
        with tempfile.TemporaryDirectory() as volume:
            result, _ = self.run_app_fixture(volume, launch_status=1)
            self.assertEqual(result.returncode, 0)
            self.assertIn("open Mugshot from Applications", result.stderr)

    def test_distribution_rejects_ad_hoc_permission_identity(self):
        with tempfile.TemporaryDirectory() as folder:
            app = Path(folder) / "Mugshot.app"
            (app / "Contents/MacOS").mkdir(parents=True)
            executable = app / "Contents/MacOS/Mugshot"
            shutil.copyfile("/usr/bin/true", executable)
            executable.chmod(0o755)
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
                "CFBundleIdentifier": "com.lorenzo.Mugshot",
                "CFBundleExecutable": "Mugshot", "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1",
            }))
            subprocess.run(["codesign", "--force", "--sign", "-", str(app)],
                           check=True, capture_output=True)
            output = Path(folder) / "Mugshot.pkg"
            env = dict(os.environ, ALLOW_UNSIGNED_PKG="0")
            result = subprocess.run(["bash", str(ROOT / "scripts/build-pkg.sh"), str(app), str(output)],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("Developer ID Application", result.stderr)
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
