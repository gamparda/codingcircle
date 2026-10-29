import hashlib
import http.server
import importlib.util
import json
import pathlib
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("suite_runner", ROOT / "tools" / "run_suite.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
PAYLOAD = b"download regression\x00" * (8 * 1024 * 1024 // 20)


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Length", str(len(PAYLOAD)))
        self.end_headers()
        try:
            self.wfile.write(PAYLOAD)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_args):
        pass


class WindowsDownloadTests(unittest.TestCase):
    def run_download(self, corrupt=False):
        with tempfile.TemporaryDirectory(prefix="updater-download-") as directory:
            project = pathlib.Path(directory)
            (project / "scripts").mkdir()
            for name in ("UpdateManager.gd", "Bootstrap.gd", "Localization.gd", "ResumableDownload.gd"):
                shutil.copyfile(ROOT / "scripts" / name, project / "scripts" / name)
            shutil.copyfile(ROOT / "tests" / "fixtures" / "windows_download_probe.gd", project / "probe.gd")
            (project / "project.godot").write_text(
                'config_version=5\n[application]\nconfig/name="Keepfall updater download regression"\n',
                encoding="utf-8",
            )
            (project / "build_info.json").write_text(json.dumps({"windows_version": "0.0.0"}), encoding="utf-8")
            server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                digest = "0" * 64 if corrupt else hashlib.sha256(PAYLOAD).hexdigest()
                result = subprocess.run(
                    [RUNNER.find_godot(), "--headless", "--path", str(project), "--script", "probe.gd", "--",
                     f"http://127.0.0.1:{server.server_port}/installer.exe", digest, "corrupt" if corrupt else "valid"],
                    capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=12,
                )
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=5)

    def test_large_download_completes_even_at_five_frames_per_second(self):
        self.run_download()

    def test_corrupt_download_never_becomes_ready_to_install(self):
        self.run_download(corrupt=True)


if __name__ == "__main__":
    unittest.main()
