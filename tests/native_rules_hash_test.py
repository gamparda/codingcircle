"""The rules hash (tools/update_rules_hash.py) stays honest: scripts/BattleRulesHash.gd is current, the native
build compiles in the same hash, and the hashed functions are complete: every BattleModel function the listed
rule functions call is itself listed (or a declared callback the engine runs in GDScript). A helper left out
could change without turning the native engine off, and the two engines would then disagree."""
import importlib.util
import pathlib
import re
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("update_rules_hash", ROOT / "tools" / "update_rules_hash.py")
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


class NativeRulesHashTest(unittest.TestCase):
    def test_hash_is_current(self):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / "update_rules_hash.py"), "--check"], cwd=ROOT)
        self.assertEqual(result.returncode, 0, "scripts/BattleRulesHash.gd is stale: run tools/update_rules_hash.py")

    def test_engine_compiles_the_same_hash(self):
        cmake = (ROOT / "native" / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn("tools/update_rules_hash.py --print", cmake)
        self.assertIn("BATTLE_RULES_HASH", cmake)

    def test_rule_functions_are_closed(self):
        model = rules.functions(ROOT / "scripts" / "BattleModel.gd")
        listed = {name for name in rules.RULE_FUNCTIONS if "::" not in name}
        missing = set()
        for name in listed:
            for line in rules.code_lines(model[name])[1:]:
                for called in re.findall(r"(?<![\w.])([A-Za-z_]\w*)\s*\(", line):
                    if called in model and called not in listed and called not in rules.CALLBACKS:
                        missing.add(f"{name} -> {called}")
        self.assertFalse(missing, "rule functions call unlisted BattleModel functions: " + ", ".join(sorted(missing)))

    def test_constants_are_handed_over(self):
        source = (ROOT / "scripts" / "BattleModel.gd").read_text(encoding="utf-8")
        engine = (ROOT / "native" / "src" / "battle_core.cpp").read_text(encoding="utf-8")
        handed = set(re.findall(r'^\t\t"([A-Z_]+)": [A-Z_]+,?$', source.split("static func native_constants()", 1)[1].split("\n\n", 1)[0], re.M))
        wanted = set(re.findall(r'^(?:double|int64_t) ([A-Z_]+) = 0', engine, re.M))
        self.assertTrue(wanted, "the engine declares its constants")
        self.assertEqual(wanted, handed, "native_constants() must hand over exactly the constants the engine uses")


if __name__ == "__main__":
    unittest.main()
