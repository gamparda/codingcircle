import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class DocsPolicyTest(unittest.TestCase):
    def test_units_doc_matches_the_data_resources(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "gen_unit_docs.py"), "--check"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + "(run: python tools/gen_unit_docs.py)")

    def test_readme_leaves_balance_numbers_to_the_data(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        stat_words = "비용|체력|공격력|공격|사거리|이동속도|공속"
        offenders = re.findall(rf"(?:{stat_words})\s*[+\-]?\d+", readme)
        self.assertEqual(offenders, [], "put balance numbers in data/*.tres, not the README")
        self.assertIn("docs/UNITS.md", readme)

    def test_every_listed_source_file_exists(self):
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        tree = readme.split("## 소스 구조", 1)[1].split("```text", 1)[1].split("```", 1)[0]
        for line in tree.splitlines():
            token = line.split()[0] if line.strip() else ""
            if token and "/" in token or token.endswith((".json", ".godot")):
                path = token.split(",")[0].rstrip("/")
                self.assertTrue(list(ROOT.glob(path + "*")) or (ROOT / path).exists(), f"README lists missing path: {token}")


if __name__ == "__main__":
    unittest.main()
