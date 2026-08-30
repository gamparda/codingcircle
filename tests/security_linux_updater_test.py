import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[1]
UPDATER = REPO / "server" / "linux" / "update-server.sh"
UNIT = REPO / "server" / "linux" / "catwar-update.service"
BASH = Path(r"C:\Program Files\Git\usr\bin\bash.exe") if os.name == "nt" else Path("/bin/bash")


def run(*args, cwd=None, env=None, check=False):
    return subprocess.run(
        [str(arg) for arg in args],
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=check,
    )


class LinuxUpdaterSecurityTests(unittest.TestCase):
    def test_systemd_runs_immutable_installed_updater(self):
        unit = UNIT.read_text(encoding="utf-8")
        self.assertIn("ExecStart=/usr/local/libexec/catwar/update-server.sh", unit)
        self.assertNotIn("ExecStart=/opt/catwar/app/", unit)

    def test_root_operated_paths_are_validated_before_creation_or_lock_open(self):
        text = UPDATER.read_text(encoding="utf-8")
        self.assertIn("validate_root_paths", text)
        definition = text.index("validate_root_paths()")
        call = text.index("\nvalidate_root_paths\n", definition) + 1
        creation = text.index('install -d -o root -g root -m 0700 -- "$CONTROL_DIR"')
        lock_open = text.index('exec 9>"$LOCK_FILE"')
        self.assertLess(call, creation)
        self.assertLess(call, lock_open)
        for path in ("APP_DIR", "RELEASES_DIR", "CONTROL_DIR", "LOCK_FILE"):
            self.assertIn(path, text[definition:call])

    def test_updater_uses_separate_root_control_directory(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertIn("/var/lib/catwar-updater", script)
        self.assertIn("trusted-commit", script)
        self.assertNotIn('mktemp "$STATE_DIR/', script)

    def test_drain_marker_is_created_without_root_file_access(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertIn('run_as_service_user /usr/bin/touch -- "$pending_file"', script)
        self.assertNotIn('chown catwar:catwar "$pending_file"', script)
        self.assertIn('[[ ! -L "$STATE_DIR" ]]', script)

    def test_untrusted_checkout_is_never_executed_as_root(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertIn('run_as_service_user "$GODOT_BIN" --headless', script)
        self.assertNotIn("GODOT_SILENCE_ROOT_WARNING=1", script)

    def test_deprecated_github_manifest_signing_path_is_removed(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertNotIn("verify_manifest", script)
        self.assertNotIn("MANIFEST_SIGNATURE_URL", script)
        self.assertNotIn("CATWAR_UPDATE_PUBLIC_KEY", script)

    def test_manifest_update_path_does_not_require_detached_signature(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertIn('target_commit=$(read_manifest_commit "$manifest_file")', script)
        runtime = script[script.index('curl --fail --silent --show-error --location'):]
        self.assertNotIn('"$MANIFEST_SIGNATURE_URL"', runtime)
        self.assertNotIn('target_commit=$(verify_manifest', runtime)

    def test_update_graph_rejects_downgrades_and_non_main_commits(self):
        with tempfile.TemporaryDirectory() as td:
            repo = Path(td)
            run("git", "init", "-q", "-b", "main", repo, check=True)
            run("git", "config", "user.email", "security-test@example.invalid", cwd=repo, check=True)
            run("git", "config", "user.name", "Security Test", cwd=repo, check=True)
            tracked = repo / "tracked"
            tracked.write_text("one", encoding="utf-8")
            run("git", "add", "tracked", cwd=repo, check=True)
            run("git", "commit", "-qm", "one", cwd=repo, check=True)
            first = run("git", "rev-parse", "HEAD", cwd=repo, check=True).stdout.strip()
            tracked.write_text("two", encoding="utf-8")
            run("git", "commit", "-qam", "two", cwd=repo, check=True)
            second = run("git", "rev-parse", "HEAD", cwd=repo, check=True).stdout.strip()
            run("git", "update-ref", "refs/remotes/origin/main", second, cwd=repo, check=True)

            forward = run(BASH, UPDATER, "--validate-update-graph", repo, first, second)
            self.assertEqual(forward.returncode, 0, forward.stderr)
            downgrade = run(BASH, UPDATER, "--validate-update-graph", repo, second, first)
            self.assertNotEqual(downgrade.returncode, 0)

            run("git", "checkout", "-qb", "side", first, cwd=repo, check=True)
            tracked.write_text("side", encoding="utf-8")
            run("git", "commit", "-qam", "side", cwd=repo, check=True)
            side = run("git", "rev-parse", "HEAD", cwd=repo, check=True).stdout.strip()
            off_main = run(BASH, UPDATER, "--validate-update-graph", repo, first, side)
            self.assertNotEqual(off_main.returncode, 0)

    def test_readiness_requires_configured_port_owned_by_service_main_pid(self):
        script = UPDATER.read_text(encoding="utf-8")
        self.assertNotIn(":7777", script)
        self.assertIn("MainPID", script)
        with tempfile.TemporaryDirectory() as td:
            bindir = Path(td)
            systemctl = bindir / "systemctl"
            ss = bindir / "ss"
            systemctl.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ $1 == is-active ]]; then exit 0; fi\n"
                "if [[ $1 == show ]]; then printf '4242\\n'; exit 0; fi\n"
                "exit 1\n",
                encoding="utf-8",
            )
            ss.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'UNCONN 0 0 0.0.0.0:8123 0.0.0.0:* users:((\\\"godot\\\",pid=4242,fd=7))\\n'\n",
                encoding="utf-8",
            )
            systemctl.chmod(systemctl.stat().st_mode | stat.S_IXUSR)
            ss.chmod(ss.stat().st_mode | stat.S_IXUSR)
            env = os.environ.copy()
            env["PATH"] = str(bindir) + os.pathsep + env["PATH"]
            ready = run(BASH, UPDATER, "--check-readiness", "catwar-server.service", "8123", env=env)
            self.assertEqual(ready.returncode, 0, ready.stderr)
            wrong_port = run(BASH, UPDATER, "--check-readiness", "catwar-server.service", "9000", env=env)
            self.assertNotEqual(wrong_port.returncode, 0)
            ss.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'UNCONN 0 0 0.0.0.0:8123 0.0.0.0:* users:((\\\"other\\\",pid=9999,fd=7))\\n'\n",
                encoding="utf-8",
            )
            wrong_pid = run(BASH, UPDATER, "--check-readiness", "catwar-server.service", "8123", env=env)
            self.assertNotEqual(wrong_pid.returncode, 0)
            ss.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'UNCONN 0 0 0.0.0.0:8123 0.0.0.0:* users:((\\\"other\\\",pid=9999,fd=7))\\n'\n"
                "printf 'UNCONN 0 0 0.0.0.0:9000 0.0.0.0:* users:((\\\"godot\\\",pid=4242,fd=7))\\n'\n",
                encoding="utf-8",
            )
            split_evidence = run(BASH, UPDATER, "--check-readiness", "catwar-server.service", "8123", env=env)
            self.assertNotEqual(split_evidence.returncode, 0)


if __name__ == "__main__":
    unittest.main()
