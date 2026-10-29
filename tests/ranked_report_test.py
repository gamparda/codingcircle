"""tools/ranked_report.py: combining files, rates and the strong/weak verdicts."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import ranked_report  # noqa: E402


class RankedReportTest(unittest.TestCase):
    def test_report(self):
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory, "a.json")
            second = Path(directory, "b.json")
            first.write_text(json.dumps({"matches": 100, "cards": {"archer": {"picks": 100, "bans": 10, "wins": 70, "draws": 0}, "wall": {"picks": 10, "bans": 0, "wins": 9, "draws": 0}}}), encoding="utf-8")
            second.write_text(json.dumps({"matches": 100, "cards": {"archer": {"picks": 100, "bans": 30, "wins": 70, "draws": 0}, "healer": {"picks": 120, "bans": 0, "wins": 30, "draws": 20}}}), encoding="utf-8")
            matches, cards = ranked_report.combine([first, second])
            self.assertEqual(matches, 200)
            self.assertEqual(cards["archer"], {"picks": 200, "bans": 40, "wins": 140, "draws": 0})
            text = ranked_report.report(matches, cards)
            self.assertIn("| 궁수 | 50% | 10% | 70.0% |", text)
            self.assertIn("강함", text.split("궁수")[1].split("\n")[0])
            self.assertIn("약함", text.split("마법사")[1].split("\n")[0])
            self.assertIn("표본 적음", text.split("방벽")[1].split("\n")[0])

    def test_wilson(self):
        low, high = ranked_report.wilson(50, 100)
        self.assertLess(low, 0.5)
        self.assertGreater(high, 0.5)
        self.assertEqual(ranked_report.wilson(0, 0), (0.0, 1.0))


if __name__ == "__main__":
    unittest.main()
