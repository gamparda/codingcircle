"""The rules hash (tools/update_rules_hash.py) stays honest: scripts/BattleRulesHash.gd matches the engine
source, the native build compiles in the same hash, and every constant the engine wants is handed over."""
import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class NativeRulesHashTest(unittest.TestCase):
    def test_hash_is_current(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "update_rules_hash.py"), "--check"], cwd=ROOT)
        self.assertEqual(result.returncode, 0, "scripts/BattleRulesHash.gd is stale: run tools/update_rules_hash.py")

    def test_engine_compiles_the_same_hash(self):
        cmake = (ROOT / "native" / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn("tools/update_rules_hash.py --print", cmake)
        self.assertIn("BATTLE_RULES_HASH", cmake)

    def test_constants_are_handed_over(self):
        source = (ROOT / "scripts" / "BattleModel.gd").read_text(encoding="utf-8")
        engine = (ROOT / "native" / "src" / "battle_core.cpp").read_text(encoding="utf-8")
        handed = set(re.findall(r'^\t\t"([A-Z_]+)": [A-Z_]+,?$', source.split("static func native_constants()", 1)[1].split("\n\n", 1)[0], re.M))
        wanted = set(re.findall(r'^(?:double|int64_t) ([A-Z_]+) = 0', engine, re.M))
        self.assertTrue(wanted, "the engine declares its constants")
        self.assertEqual(wanted, handed, "native_constants() must hand over exactly the constants the engine uses")


if __name__ == "__main__":
    unittest.main()
