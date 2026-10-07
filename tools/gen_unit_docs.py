#!/usr/bin/env python3
"""Generate docs/UNITS.md from the data/*.tres resources (the single source of balance numbers).

    python tools/gen_unit_docs.py          # rewrite docs/UNITS.md
    python tools/gen_unit_docs.py --check  # exit 1 if docs/UNITS.md is stale
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "docs" / "UNITS.md"


def parse_tres(path: pathlib.Path) -> dict:
    """Reads the flat key = value lines of a [resource] section (numbers, strings, bools, dicts)."""
    text = path.read_text(encoding="utf-8")
    body = text.split("[resource]", 1)[1]
    values = {}
    for key, raw in re.findall(r"^(\w+) = (.+?)(?=^\w+ = |\Z)", body, re.S | re.M):
        raw = raw.strip()
        if raw.startswith("{"):
            values[key] = {k: _scalar(v) for k, v in re.findall(r'"(\w+)":\s*([^,\n}]+)', raw)}
        elif key != "script":
            values[key] = _scalar(raw)
    return values


def _scalar(raw: str):
    raw = raw.strip()
    if raw.startswith('"'):
        return raw.strip('"')
    if raw in ("true", "false"):
        return raw == "true"
    return float(raw) if "." in raw else int(raw)


def load(folder: str) -> list:
    items = [parse_tres(p) for p in sorted((ROOT / "data" / folder).glob("*.tres"))]
    return sorted(items, key=lambda item: item["order"])


def fmt(value) -> str:
    return f"{value:g}" if isinstance(value, float) else str(value)


def render() -> str:
    units = [u for u in load("units") if not u["summon_only"]]
    summons = [u for u in load("units") if u["summon_only"]]
    structures = load("structures")
    out = [
        "# 유닛·구조물 수치",
        "",
        "<!-- 자동 생성: python tools/gen_unit_docs.py. 직접 수정하지 마세요. 수치는 data/units, data/structures의 .tres에서 바꿉니다. -->",
        "",
        "이 표는 전투·UI·AI가 실제로 읽는 `data/` 리소스에서 생성됩니다. 능력 설명(특수 효과)은 `scripts/BattleModel.gd`가 정의합니다.",
        "",
        "## 유닛",
        "",
        "| 유닛 | 비용 | 체력 | 공격력 | 공격 간격(초) | 이동 | 사거리 |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for u in units + summons:
        tag = " (소환 전용)" if u["summon_only"] else ""
        out.append(f"| {u['display_name']}{tag} | {fmt(u['cost'])} | {fmt(u['hp'])} | {fmt(u['damage'])} | {fmt(u['interval'])} | {fmt(u['speed'])} | {fmt(u['range'])} |")
    out += ["", "## 구조물", "", "| 구조물 | 비용 | 체력 | 추가 수치 |", "|---|---:|---:|---|"]
    for s in structures:
        extra = ", ".join(f"{key} {fmt(value)}" for key, value in s.get("params", {}).items())
        out.append(f"| {s['display_name']} | {fmt(s['cost'])} | {fmt(s['hp'])} | {extra} |")
    return "\n".join(out) + "\n"


def main(argv: list) -> int:
    text = render()
    if "--check" in argv:
        current = OUTPUT.read_text(encoding="utf-8").replace("\r\n", "\n") if OUTPUT.exists() else ""
        if current != text:
            print("docs/UNITS.md is stale: run `python tools/gen_unit_docs.py`")
            return 1
        return 0
    OUTPUT.write_bytes(text.encode("utf-8"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
