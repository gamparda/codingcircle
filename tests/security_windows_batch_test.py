import os
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
START_SERVER = ROOT / "server" / "StartServer.cmd"


class WindowsBatchSecurityTests(unittest.TestCase):
    def test_start_server_never_interpolates_command_line_argument(self):
        text = START_SERVER.read_text(encoding="utf-8")
        self.assertNotIn("%~1", text)
        self.assertIn("CATWAR_PORT", text)
        self.assertIn("validated_port", text.lower())

        marker = pathlib.Path(tempfile.gettempdir()) / "catwar-startserver-injection.txt"
        marker.unlink(missing_ok=True)
        payload = f'7777&echo PWNED>{marker}'
        env = os.environ.copy()
        env["CATWAR_PORT"] = payload
        result = subprocess.run(
            ["cmd.exe", "/d", "/c", str(START_SERVER)],
            env=env,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=10,
            check=False,
        )
        self.assertFalse(marker.exists(), result.stdout.decode(errors="replace"))

    def test_updater_disables_redirects_that_could_escape_allowlist(self):
        text = (ROOT / "scripts" / "UpdateManager.gd").read_text(encoding="utf-8")
        self.assertIn("http.max_redirects = 0", text)

    def test_updater_uses_full_directory_backup_and_verified_restore(self):
        text = (ROOT / "scripts" / "UpdateManager.gd").read_text(encoding="utf-8")
        self.assertGreaterEqual(text.lower().count("robocopy"), 2)
        self.assertIn("/MIR", text)
        self.assertIn("if errorlevel 8 goto restore_failed", text)
        self.assertIn("if not exist", text)
        self.assertIn("goto restore_failed", text)

    def test_installer_uses_predictable_non_restarting_transaction_policy(self):
        text = (ROOT / "installer" / "CatWar.iss").read_text(encoding="utf-8")
        for directive in (
            "CloseApplications=yes",
            "RestartApplications=no",
            "UsePreviousAppDir=yes",
            "Uninstallable=yes",
        ):
            self.assertIn(directive, text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
