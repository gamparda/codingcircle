import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
POWERSHELL = shutil.which("powershell.exe")


class ManagedAgentPackageTests(unittest.TestCase):
    def test_no_installer_payload_can_enter_game_or_android_packs(self):
        presets = (ROOT / "export_presets.cfg").read_text(encoding="utf-8")
        filters = re.findall(r'^exclude_filter="([^"]+)"', presets, re.MULTILINE)
        self.assertEqual(len(filters), 3) # Windows, Android and the ONE store Android build
        for excluded in filters:
            for directory in ("installer/**", "tools/**", "dist/**", "builds/**"):
                self.assertIn(directory, excluded.split(","))

    def test_fresh_agent_is_visible_and_has_no_shared_credentials(self):
        config = json.loads((ROOT / "tools" / "managed_agent_config.json").read_text(encoding="utf-8"))
        self.assertTrue(config["tray_icon"])
        self.assertFalse(config["direct_lan"])
        self.assertFalse(set(config) & {"device_token", "token", "device_secret"})

    def test_public_windows_build_requires_the_verified_agent(self):
        build = (ROOT / "tools" / "build_release.ps1").read_text(encoding="utf-8")
        self.assertIn("build_managed_client.ps1", build)
        self.assertIn("-SetupFilename 'CatWarSetup'", build)
        installer = (ROOT / "installer" / "CatWar.iss").read_text(encoding="utf-8")
        self.assertIn("#error ManagedAgentSetup must point", installer)
        self.assertNotIn("#ifdef ManagedAgentSetup", installer)
        pin = json.loads((ROOT / "tools" / "managed_agent.json").read_text(encoding="utf-8"))
        self.assertTrue(pin["download_url"].startswith(
            "https://github.com/gamparda/codingcircle/releases/download/"))
        self.assertRegex(pin["sha256"], r"^[a-f0-9]{64}$")

    def test_interactive_default_does_not_opt_in_silent_game_updaters(self):
        installer = (ROOT / "installer" / "CatWar.iss").read_text(encoding="utf-8")
        task = next(line for line in installer.splitlines() if line.startswith('Name: "pcremoteagent";'))
        self.assertIn("checkedonce", task)
        self.assertNotIn("unchecked", task)
        self.assertIn("파일 접근", task)
        self.assertIn("Check: ShouldInstallManagedAgent", installer)
        self.assertIn("not WizardSilent", installer)
        self.assertIn("{param:INSTALLPCREMOTEAGENT|0}", installer)
        self.assertIn("RegKeyExists(HKCU64", installer)
        updater = (ROOT / "scripts" / "UpdateManager.gd").read_text(encoding="utf-8")
        self.assertNotIn("INSTALLPCREMOTEAGENT", updater)

    @unittest.skipUnless(os.name == "nt" and POWERSHELL, "Windows PowerShell required")
    def test_unverified_binary_is_rejected_before_build_tools_run(self):
        with tempfile.TemporaryDirectory(prefix="agent path & spaces ") as directory:
            directory = pathlib.Path(directory)
            payload = directory / "unverified agent.exe"
            payload.write_bytes(b"not an approved release")
            marker = directory / "compiler-ran.txt"
            compiler = directory / "compiler.cmd"
            compiler.write_text(f'@echo unexpected>"{marker}"\n', encoding="utf-8")
            result = subprocess.run(
                [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                 "-File", str(ROOT / "tools" / "build_managed_client.ps1"),
                 "-AgentPath", str(payload), "-IsccPath", str(compiler)],
                capture_output=True, timeout=20,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn(b"SHA-256 mismatch", result.stdout + result.stderr)
            self.assertFalse(marker.exists(), "an unverified binary reached the compiler")

    @unittest.skipUnless(os.name == "nt" and POWERSHELL, "Windows PowerShell required")
    def test_stop_matches_installation_path_and_leaves_other_agents_running(self):
        with tempfile.TemporaryDirectory(prefix="agent scope ") as directory:
            root = pathlib.Path(directory)
            processes = []
            try:
                for name in ("managed", "unrelated"):
                    destination = root / name
                    destination.mkdir()
                    executable = destination / "PCRemoteAgent.exe"
                    shutil.copyfile(pathlib.Path(os.environ["SystemRoot"]) / "System32" / "cmd.exe", executable)
                    processes.append(subprocess.Popen(
                        [str(executable), "/d", "/q", "/k", "echo agent-ready"], stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                        creationflags=subprocess.CREATE_NO_WINDOW,
                    ))
                    self.assertEqual(processes[-1].stdout.readline().strip(), b"agent-ready")
                result = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
                     "-File", str(ROOT / "installer" / "managed_agent_stop.ps1"),
                     "-InstallDirectory", str(root / "managed"), "-Verbose"],
                    capture_output=True, timeout=20,
                )
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                try:
                    processes[0].wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.fail("the target agent was left running: " + (result.stdout + result.stderr).decode(errors="replace"))
                self.assertIsNone(processes[1].poll(), "an unrelated agent was terminated")
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                    process.wait(timeout=10)
                    if process.stdin:
                        process.stdin.close()
                    if process.stdout:
                        process.stdout.close()

    @unittest.skipUnless(os.name == "nt" and POWERSHELL, "Windows PowerShell required")
    def test_stop_does_not_require_wmi_image_paths(self):
        with tempfile.TemporaryDirectory(prefix="agent wmi ") as directory:
            executable = pathlib.Path(directory) / "PCRemoteAgent.exe"
            shutil.copyfile(pathlib.Path(os.environ["SystemRoot"]) / "System32" / "cmd.exe", executable)
            process = subprocess.Popen(
                [str(executable), "/d", "/q", "/k", "echo agent-ready"], stdin=subprocess.PIPE,
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW,
            )
            try:
                self.assertEqual(process.stdout.readline().strip(), b"agent-ready")
                wrapper = pathlib.Path(directory) / "without-wmi-path.ps1"
                wrapper.write_text(
                    "param([string]$StopScript, [string]$Target)\n"
                    "function Get-CimInstance { [pscustomobject]@{ ExecutablePath = $null; CommandLine = '' } }\n"
                    "& $StopScript -InstallDirectory $Target\n", encoding="utf-8",
                )
                result = subprocess.run(
                    [POWERSHELL, "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", str(wrapper),
                     "-StopScript", str(ROOT / "installer" / "managed_agent_stop.ps1"), "-Target", directory],
                    capture_output=True, timeout=20,
                )
                self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
                process.wait(timeout=5)
            finally:
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=10)
                process.stdin.close()
                process.stdout.close()


if __name__ == "__main__":
    unittest.main(verbosity=2)
