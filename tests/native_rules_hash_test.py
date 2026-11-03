"""The rules hash in scripts/BattleRulesHash.gd must match scripts/BattleModel.gd (run tools/update_rules_hash.py
after editing it). The native battle engine is used only when its compiled-in hash matches this one, so a stale
file would silently run every battle on the slower GDScript engine (or, worse, pair new rules with an old engine)."""
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class NativeRulesHashTest(unittest.TestCase):
    def test_hash_is_current(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "update_rules_hash.py"), "--check"], cwd=ROOT)
        self.assertEqual(result.returncode, 0, "scripts/BattleRulesHash.gd is stale: run tools/update_rules_hash.py")

    def test_engine_hashes_the_same_source(self):
        cmake = (ROOT / "native" / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn("scripts/BattleModel.gd", cmake)
        self.assertIn('string(REPLACE "\\r" ""', cmake)


if __name__ == "__main__":
    unittest.main()
