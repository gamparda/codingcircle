import importlib.util
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("suite_runner", ROOT / "tools" / "run_suite.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)


class SuiteRunnerTests(unittest.TestCase):
    def test_timeout_keeps_stdout_and_stderr_diagnostics(self):
        with tempfile.TemporaryDirectory(prefix="suite timeout ") as directory:
            script = pathlib.Path(directory) / "failing_scene.py"
            script.write_text(
                "import sys, time\n"
                "print('scene started', flush=True)\n"
                "print('SCRIPT ERROR: missing node', file=sys.stderr, flush=True)\n"
                "time.sleep(30)\n", encoding="utf-8",
            )
            code, output, _seconds = RUNNER.run_one("unused", str(script), 2)
            self.assertEqual(code, 124)
            self.assertIn("scene started", output)
            self.assertIn("SCRIPT ERROR: missing node", output)
            self.assertIn("timed out after 2s", output)


if __name__ == "__main__":
    unittest.main()
