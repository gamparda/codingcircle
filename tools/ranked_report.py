"""Balance report from the server's ranked card statistics (ranked_cards_<season>_<ruleset>.json).

Usage: python tools/ranked_report.py <stats.json> [more.json ...] [--min-picks 30]
Files of the same ruleset can be combined (for example several seasons). Prints a Markdown table:
pick, ban and win rate per card with a 95% Wilson interval, and flags cards whose interval lies
entirely above or below 50%. Uses only the Python standard library.
"""
import argparse
import json
import math
from pathlib import Path

NAMES = {"shield": "탱커", "swordsman": "검사", "archer": "궁수", "healer": "마법사", "berserker": "광전사", "warlock": "흑마법사",
         "necromancer": "네크로맨서", "zombie": "좀비", "paladin": "성기사", "sniper": "저격수", "demon_lord": "마왕",
         "wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기", "lightning": "낙뢰", "fireball": "화염구",
         "frost": "빙결", "blessing": "축복", "seraph": "천사 강림"}
FIELDS = ("picks", "bans", "wins", "draws")


def wilson(wins, games, z=1.96):
    if games <= 0:
        return (0.0, 1.0)
    p = wins / games
    centre = (p + z * z / (2 * games)) / (1 + z * z / games)
    margin = z * math.sqrt(p * (1 - p) / games + z * z / (4 * games * games)) / (1 + z * z / games)
    return (max(0.0, centre - margin), min(1.0, centre + margin))


def combine(paths):
    matches, cards = 0, {}
    for path in paths:
        data = json.loads(Path(path).read_text(encoding="utf-8"))
        matches += int(data.get("matches", 0))
        for kind, entry in data.get("cards", {}).items():
            row = cards.setdefault(kind, dict.fromkeys(FIELDS, 0))
            for field in FIELDS:
                row[field] += int(entry.get(field, 0))
    return matches, cards


def report(matches, cards, min_picks=30):
    decks = max(1, matches * 2)
    rows = []
    for kind, row in cards.items():
        decided = row["picks"] - row["draws"]
        low, high = wilson(row["wins"], decided)
        verdict = ""
        if row["picks"] < min_picks:
            verdict = "표본 적음"
        elif low > 0.5:
            verdict = "강함"
        elif high < 0.5:
            verdict = "약함"
        rows.append((row["wins"] / decided if decided else 0.0, kind, row, low, high, verdict))
    rows.sort(key=lambda item: item[0], reverse=True)
    lines = [f"랭크 {matches}경기 · 사용률=덱에 넣은 비율 · 금지율=상대에게 금지당한 비율 · 승률은 무승부 제외", "",
             "| 카드 | 사용률 | 금지율 | 승률 | 95% 구간 | 판정 |", "|---|---:|---:|---:|---:|---|"]
    for rate, kind, row, low, high, verdict in rows:
        lines.append(f"| {NAMES.get(kind, kind)} | {row['picks'] / decks:.0%} | {row['bans'] / decks:.0%} | {rate:.1%} | {low:.0%}–{high:.0%} | {verdict} |")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("files", nargs="+")
    parser.add_argument("--min-picks", type=int, default=30)
    args = parser.parse_args()
    print(report(*combine(args.files), min_picks=args.min_picks))


if __name__ == "__main__":
    main()
