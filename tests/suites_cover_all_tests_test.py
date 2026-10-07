import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Manual tooling, not tests.
NOT_TESTS = {"tests/layout_capture.gd"}


class SuitesCoverAllTests(unittest.TestCase):
    def test_every_test_file_belongs_to_exactly_one_suite(self):
        suites = json.loads((ROOT / "tests" / "suites.json").read_text(encoding="utf-8"))
        listed = [path for paths in suites.values() for path in paths]
        self.assertEqual(len(listed), len(set(listed)), "a test is listed in more than one suite")
        on_disk = {
            "tests/" + p.name
            for p in (ROOT / "tests").iterdir()
            if p.suffix in (".gd", ".py") and not p.name.endswith("suites_cover_all_tests_test.py")
        } - NOT_TESTS
        missing = on_disk - set(listed) - {"tests/suites_cover_all_tests_test.py"}
        self.assertFalse(missing, f"tests not assigned to a suite: {sorted(missing)}")
        for path in listed:
            self.assertTrue((ROOT / path).exists(), f"suites.json lists a missing file: {path}")


if __name__ == "__main__":
    unittest.main()
