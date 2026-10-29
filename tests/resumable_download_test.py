"""ResumableDownload against a slow, flaky local server: it must finish, resume after a stop, and handle
servers that ignore Range. Uses only the Python standard library; needs GODOT_CONSOLE."""
import gzip
import hashlib
import http.server
import os
import pathlib
import random
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from run_suite import find_godot  # noqa: E402

DATA = bytes(random.Random(7).getrandbits(8) for _ in range(3 * 1024 * 1024 + 12345))
# Like GitHub Pages: a client that accepts gzip gets ranges of a compressed copy.
GZIPPED = gzip.compress(DATA)


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    requests = 0
    drop_every = 3          # every third request is cut off mid-body
    honour_range = True
    bytes_per_second = 4 * 1024 * 1024

    def log_message(self, *args):
        pass

    def do_GET(self):
        type(self).requests += 1
        number = type(self).requests
        data = GZIPPED if "gzip" in self.headers.get("Accept-Encoding", "") else DATA
        start, end = 0, len(data) - 1
        status = 200
        header = self.headers.get("Range")
        if header and type(self).honour_range:
            first, _, last = header.removeprefix("bytes=").partition("-")
            start = int(first)
            end = min(int(last) if last else len(data) - 1, len(data) - 1)
            if start >= len(data):
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{len(data)}")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            status = 206
        body = data[start:end + 1]
        self.send_response(status)
        if data is GZIPPED:
            self.send_header("Content-Encoding", "gzip")
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        cut = len(body) // 2 if type(self).drop_every and number % type(self).drop_every == 0 else len(body)
        step = 64 * 1024
        try:
            for index in range(0, cut, step):
                self.wfile.write(body[index:min(index + step, cut)])
                time.sleep(step / type(self).bytes_per_second)
            if cut < len(body):
                self.close_connection = True
                self.connection.shutdown(2)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True  # the client stopped on purpose


class ResumableDownloadTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.godot = find_godot()
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"http://127.0.0.1:{cls.server.server_address[1]}/pack.pck"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def probe(self, out, *extra):
        command = [self.godot, "--headless", "--path", str(ROOT), "--script", "res://tests/fixtures/resumable_download_probe.gd", "--", f"--url={self.url}", f"--out={out}", *extra]
        result = subprocess.run(command, capture_output=True, text=True, timeout=180)
        lines = [line for line in result.stdout.splitlines() if line.startswith("RESULT")]
        return result.returncode, (lines[-1] if lines else result.stdout[-800:] + result.stderr[-800:])

    def test_flaky_connection_finishes_with_retries(self):
        Handler.drop_every, Handler.honour_range, Handler.requests = 3, True, 0
        with tempfile.TemporaryDirectory() as directory:
            out = os.path.join(directory, "pack.pck")
            code, line = self.probe(out)
            self.assertEqual(code, 0, line)
            self.assertIn("ok=true", line)
            self.assertNotIn("retries=0", line)
            self.assertEqual(hashlib.sha256(pathlib.Path(out).read_bytes()).hexdigest(), hashlib.sha256(DATA).hexdigest())

    def test_stopped_download_resumes(self):
        Handler.drop_every, Handler.honour_range, Handler.requests = 0, True, 0
        with tempfile.TemporaryDirectory() as directory:
            out = os.path.join(directory, "pack.pck")
            code, line = self.probe(out, "--stop-after=1048576")
            self.assertIn("stopped", line)
            code, line = self.probe(out)
            self.assertEqual(code, 0, line)
            self.assertNotIn("resumed_from=0 ", line)
            self.assertEqual(pathlib.Path(out).read_bytes(), DATA)
            # Another file (a new release) never continues this one.
            code, line = self.probe(out, "--key=other", "--stop-after=1")
            self.assertIn("stopped", line)

    def test_server_without_range_support(self):
        Handler.drop_every, Handler.honour_range, Handler.requests = 0, False, 0
        with tempfile.TemporaryDirectory() as directory:
            out = os.path.join(directory, "pack.pck")
            code, line = self.probe(out)
            self.assertEqual(code, 0, line)
            self.assertEqual(pathlib.Path(out).read_bytes(), DATA)


if __name__ == "__main__":
    unittest.main()
