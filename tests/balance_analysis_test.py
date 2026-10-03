"""Guard against reporting incomplete, duplicate, or mixed-rule experiments."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("analysis", Path(__file__).resolve().parents[1] / "tools/analyze_balance.py")
analysis = importlib.util.module_from_spec(spec)
spec.loader.exec_module(analysis)


class AnalysisTest(unittest.TestCase):
    def fixture(self, sides=(0, 1), completion=True, rules=1):
        records = [{"type": "metadata", "unit_stats": {"test": rules}, "options": {"dt": 0.1, "growth": "progression"}}]
        records += [{"type": "match", "suite": "pvp", "repetition": 0, "policy": "cycle", "pair_id": 0, "side_a": side, "result_a": "win"} for side in sides]
        if completion:
            records.append({"type": "completion", "matches": len(sides)})
        return "\n".join(json.dumps(record) for record in records)+"\n"

    def test_complete_pair(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.jsonl"
            path.write_text(self.fixture())
            rows, _, _ = analysis.load([str(path)])
            self.assertEqual(len(rows), 2)

    def test_incomplete_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.jsonl"
            path.write_text(self.fixture(completion=False))
            with self.assertRaises(ValueError):
                analysis.load([str(path)])

    def test_missing_side_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.jsonl"
            path.write_text(self.fixture(sides=(0,)))
            with self.assertRaises(ValueError):
                analysis.load([str(path)])

    def test_duplicate_matches_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = [Path(folder)/name for name in ["a.jsonl", "b.jsonl"]]
            for path in paths:
                path.write_text(self.fixture())
            with self.assertRaises(ValueError):
                analysis.load([str(path) for path in paths])

    def test_mixed_rules_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            paths = [Path(folder)/name for name in ["a.jsonl", "b.jsonl"]]
            for i, path in enumerate(paths):
                path.write_text(self.fixture(rules=i))
            with self.assertRaisesRegex(ValueError, "different rules"):
                analysis.load([str(path) for path in paths])

    def test_timeout_is_not_a_loss(self):
        rows = [{"result_a": result, "elapsed": 600, "peak_units": 1, "capped_steps": 0} for result in ["win", "loss", "draw", "timeout"]]
        result = analysis.summary(rows)
        self.assertEqual(result["resolved_score"], 0.5)
        self.assertEqual(result["timeout"], 1)
        self.assertEqual(result["loss"], 1)

    def test_comparison_rejects_different_tester_or_timeout(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)/"data.jsonl"
            path.write_text(self.fixture())
            rows, _, _ = analysis.load([str(path)])
            current = rows[0]
            self.assertNotEqual(analysis.match_key(current), analysis.match_key({**current,"tester_sha256":"different"}))
            self.assertNotEqual(analysis.match_key(current), analysis.match_key({**current,"time_limit":120.0}))

    def test_partial_preview_skips_only_unfinished_last_line(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "data.jsonl"
            path.write_text(self.fixture(completion=False)+'{"type":')
            rows, _, sources = analysis.load([str(path)], allow_partial=True)
            self.assertEqual(len(rows), 2)
            self.assertFalse(sources[0]["complete"])


if __name__ == "__main__":
    unittest.main()
