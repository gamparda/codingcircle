"""Summarize completed engine tournaments. Uses only the Python standard library."""
import argparse
from collections import Counter, defaultdict
import csv
import glob
import hashlib
import json
from pathlib import Path
import random
import statistics

NAMES = {"shield": "탱커", "swordsman": "검사", "archer": "궁수", "healer": "마법사", "berserker": "광전사", "warlock": "흑마법사", "necromancer": "네크로맨서"}


def load(patterns, allow_partial=False):
    rows, metadata, sources = [], [], []
    seen = set()
    paths = sorted({path for pattern in patterns for path in glob.glob(pattern)})
    rules_signature = None
    ai_signatures = {}
    if not paths:
        raise ValueError("No input files matched")
    for name in paths:
        path = Path(name)
        content = path.read_bytes()
        lines = content.decode("utf-8").splitlines()
        records = []
        for index, line in enumerate(lines):
            if not line.strip():
                continue
            try:
                records.append(json.loads(line))
            except json.JSONDecodeError:
                if not allow_partial or index != len(lines)-1:
                    raise
        headers = [row for row in records if row["type"] == "metadata"]
        completions = [row for row in records if row["type"] == "completion"]
        matches = [row for row in records if row["type"] == "match"]
        if len(headers) != 1 or (not allow_partial and len(completions) != 1):
            raise ValueError(f"Missing metadata/completion: {path}")
        if completions and completions[0]["matches"] != len(matches):
            raise ValueError(f"Completion count does not match records: {path}")
        header = headers[0]
        signature = json.dumps({key: header.get(key) for key in ["unit_stats", "structure_stats", "summon_interval", "model_sha256", "bot_sha256"]}, sort_keys=True)
        if rules_signature is not None and signature != rules_signature:
            raise ValueError("Inputs contain different rules or benchmark players")
        rules_signature = signature
        suite = header["options"].get("suite", "pvp")
        ai_signature = header.get("ai_sha256")
        if suite in ai_signatures and ai_signatures[suite] != ai_signature:
            raise ValueError("Inputs contain different AI revisions within a suite")
        ai_signatures[suite] = ai_signature
        header["file"] = path.name
        metadata.append(header)
        sources.append({"file": path.name, "sha256": hashlib.sha256(content).hexdigest(), "matches": len(matches), "complete": bool(completions)})
        for row in matches:
            row["dt"] = header["options"]["dt"]
            row["growth"] = header["options"]["growth"]
            row["time_limit"] = header["options"].get("timeout", 600.0)
            row["tester_sha256"] = header.get("bot_sha256")
            key = match_key(row)
            if key in seen:
                raise ValueError(f"Duplicate match: {key}")
            seen.add(key)
            if row["result_a"] not in ("win", "loss", "draw", "timeout"):
                raise ValueError("Unexpected match result")
            rows.append(row)
    # Completed studies must contain both orientations for every logical pair.
    if not allow_partial:
        pairs = Counter(key[:-1] for key in seen)
        if any(count != 2 for count in pairs.values()):
            raise ValueError("A side-swapped match is missing")
    return rows, metadata, sources


def match_key(row):
    # Campaign enemy decks are the treatment being calibrated. Player choices,
    # tester revision, censoring limit, and PvP opponents must still match.
    opponent = (tuple(row.get("deck_b", [])), tuple(row.get("structures_b", []))) if row["suite"] == "pvp" else ()
    return (row["suite"], row["dt"], row["growth"], row.get("time_limit", 600.0), row.get("tester_sha256"), row["repetition"], row["policy"], row["pair_id"], row.get("seed"), tuple(row.get("deck_a", [])), tuple(row.get("structures_a", [])), opponent, row["side_a"])


def score(result):
    return {"win": 1.0, "loss": 0.0, "draw": 0.5}.get(result)


def summary(rows):
    counts = Counter(row["result_a"] for row in rows)
    scores = [score(row["result_a"]) for row in rows if score(row["result_a"]) is not None]
    times = sorted(row["elapsed"] for row in rows)
    return {"matches": len(rows), **{key: counts[key] for key in ["win", "loss", "draw", "timeout"]},
            "resolved_score": statistics.mean(scores) if scores else None,
            "median_seconds": statistics.median(times) if times else None,
            "p90_seconds": times[min(len(times)-1, int(len(times)*0.9))] if times else None,
            "peak_units": max((row["peak_units"] for row in rows), default=0),
            "unit_cap_matches": sum(row["capped_steps"] > 0 for row in rows)}


def reverse(row):
    return {**row, "deck_a": row["deck_b"], "deck_b": row["deck_a"], "result_a": {"win": "loss", "loss": "win"}.get(row["result_a"], row["result_a"]), "report_a": row["report_b"], "report_b": row["report_a"], "side_a": 1-row["side_a"]}


def interval(rows):
    """Resample paired matchups together; two orientations are not independent."""
    groups = defaultdict(list)
    for row in rows:
        value = score(row["result_a"])
        if value is not None:
            groups[(row["repetition"], row["policy"], row["pair_id"])].append(value)
    values = [statistics.mean(group) for group in groups.values()]
    if not values:
        return [None, None]
    rng = random.Random(20261003)
    estimates = sorted(statistics.mean(rng.choices(values, k=len(values))) for _ in range(500))
    return [estimates[12], estimates[487]]


def analyze(rows):
    pvp = [row for row in rows if row["suite"] == "pvp"]
    both = pvp + [reverse(row) for row in pvp]
    decks = defaultdict(list)
    for row in both:
        decks["/".join(row["deck_a"])].append(row)
    deck_stats = [{"deck": deck, **summary(group), "paired_bootstrap_95": interval(group)} for deck, group in decks.items()]
    deck_stats.sort(key=lambda row: row["resolved_score"] or 0, reverse=True)
    unit_stats = []
    for kind in NAMES:
        group = [row for row in both if kind in row["deck_a"]]
        purchases = sum(row["report_a"]["units"][kind]["purchased"] for row in group)
        damage = sum(row["report_a"]["units"][kind]["damage"] for row in group)
        unit_stats.append({"unit": kind, **summary(group), "purchased": purchases, "damage": damage, "damage_per_purchase": damage / purchases if purchases else 0})
    campaigns = [row for row in rows if row["suite"] == "campaign" and row["side_a"] == 0]
    stages = [{"stage": stage, **summary([row for row in campaigns if row["stage"] == stage]), "policies": {policy: summary([row for row in campaigns if row["stage"] == stage and row["policy"] == policy]) for policy in ["cycle", "adaptive", "weighted"]}} for stage in range(1, 9)]
    mirrors = [row for row in rows if row["suite"] == "mirror"]
    return {"total_matches": len(rows), "pvp": summary(pvp), "pvp_blue": summary([row if row["side_a"] == 0 else reverse(row) for row in pvp]), "decks": deck_stats, "units": unit_stats, "campaign_player_blue": stages,
            "mirrors": summary(mirrors), "mirror_blue": summary([row if row["side_a"] == 0 else reverse(row) for row in mirrors]), "by_policy": {policy: summary([row for row in pvp if row["policy"] == policy]) for policy in ["cycle", "adaptive", "weighted"]}}


def pct(value):
    return "—" if value is None else f"{value*100:.1f}%"


def deck_name(deck):
    return " + ".join(NAMES[kind] for kind in deck.split("/"))


def write_report(result, sources, output, label, comparison=None):
    lines = [f"# Keepfall 밸런스 실험 — {label}", "", f"완료된 자동 전투 **{result['total_matches']:,}경기**. 실제 Godot BattleModel과 ServerAI를 실행한 데이터입니다.", "",
             "## 실험 조건과 해석", "", "- 합법적인 3유닛 덱 35개. cycle(순환), adaptive(전술 점수), weighted(시드별 선호 가중치) 구매 정책.",
             "- 대전은 같은 시드·구매 순서를 유지하고 두 진영을 교환한 짝으로 비교. PvP 구매 봇은 AI 추가 수입·병력 강화를 받지 않습니다.",
             "- 구조물 3장 조합은 시드로 배정하며 진영 교환 시 그대로 유지합니다. 구조물 조합 전체를 완전 탐색한 실험은 아닙니다.",
             "- AI 난이도 표는 실제 플레이어 위치인 파랑 진영만 집계. 성장은 단계-1이며 모든 덱에 이미 접근할 수 있는 조건입니다. 실제 신규 플레이어 해금 경로와는 다릅니다.",
             "- 승점률은 완료 경기에서 승리=1, 무승부=0.5. 제한 시간 초과는 따로 표시하고 승패에 넣지 않습니다.",
             "- 덱 구간은 같은 대결의 두 진영을 함께 재표집한 95% 부트스트랩 구간입니다. 반복은 독립된 인간 표본이 아니며 인간 승률의 신뢰구간으로 해석할 수 없습니다.",
             "- 유닛 포함 승점률은 덱·정책·구조물과 함께 변합니다. 유닛 자체의 인과 효과가 아닙니다. 마법사·흑마법사의 지원 기여는 직접 피해량만으로 평가할 수 없습니다.",
             "- 0.1초 간격의 대량 탐색과 1/30초 서버 간격의 검증은 별도 결과 파일로 구분합니다. 제한 시간은 메타데이터에 기록합니다.", "", "## 대전 결과", "",
             "| 항목 | 결과 |", "|---|---:|", f"| 경기 수 | {result['pvp']['matches']:,} |", f"| 파랑 진영 승점률 | {pct(result['pvp_blue']['resolved_score'])} |", f"| 제한 시간 초과 | {result['pvp']['timeout']} |", f"| 경기 시간 중앙값 | {result['pvp']['median_seconds']}초 |", f"| 동일 덱 파랑 승점률 | {pct(result['mirror_blue']['resolved_score'])} |", f"| 동일 덱 무승부 / 시간 초과 | {result['mirrors']['draw']} / {result['mirrors']['timeout']} |", "", "## 덱별 승점률", "", "| 덱 | 경기 | 승점률 | 95% 짝 재표집 구간 | 시간 초과 |", "|---|---:|---:|---:|---:|"]
    for row in result["decks"]:
        bounds = row["paired_bootstrap_95"]
        lines.append(f"| {deck_name(row['deck'])} | {row['matches']} | {pct(row['resolved_score'])} | {pct(bounds[0])}–{pct(bounds[1])} | {row['timeout']} |")
    lines += ["", "## 유닛 포함 덱의 결과", "", "| 유닛 | 포함 덱 승점률 | 구매 수 | 구매당 직접 피해 |", "|---|---:|---:|---:|"]
    for row in result["units"]:
        lines.append(f"| {NAMES[row['unit']]} | {pct(row['resolved_score'])} | {row['purchased']:,} | {row['damage_per_purchase']:.1f} |")
    lines += ["", "## AI 1~8단계 — 플레이어 승점률", "", "| 단계 | 경기 | 전체 | 순환 | 전술 | 가중치 | 시간 초과 | 중앙 시간 |", "|---|---:|---:|---:|---:|---:|---:|---:|"]
    for row in result["campaign_player_blue"]:
        lines.append(f"| {row['stage']} | {row['matches']} | {pct(row['resolved_score'])} | {pct(row['policies']['cycle']['resolved_score'])} | {pct(row['policies']['adaptive']['resolved_score'])} | {pct(row['policies']['weighted']['resolved_score'])} | {row['timeout']} | {row['median_seconds']} |")
    if comparison:
        lines += ["", "## 같은 조건의 변경 전후", "", "| 지표 | 이전 | 현재 |", "|---|---:|---:|", f"| 파랑 진영 승점률 | {pct(comparison['pvp_blue']['resolved_score'])} | {pct(result['pvp_blue']['resolved_score'])} |", f"| 동일 덱 파랑 승점률 | {pct(comparison['mirror_blue']['resolved_score'])} | {pct(result['mirror_blue']['resolved_score'])} |", f"| PvP 시간 초과 | {comparison['pvp']['timeout']} | {result['pvp']['timeout']} |"]
        for old, new in zip(comparison["campaign_player_blue"], result["campaign_player_blue"]):
            lines.append(f"| AI {new['stage']}단계 플레이어 승점률 | {pct(old['resolved_score'])} | {pct(new['resolved_score'])} |")
    lines += ["", "## 원본 데이터", "", "모든 원본에 실험 설정, 엔진 버전, 적용 수치, 개별 경기 결과·유닛 구매/피해/소환 기록과 완료 표시가 포함됩니다.", "", "| 파일 | 경기 | SHA-256 |", "|---|---:|---|"]
    lines += [f"| {row['file']} | {row['matches']} | `{row['sha256']}` |" for row in sources]
    output.write_text("\n".join(lines)+"\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--label", default="baseline")
    parser.add_argument("--compare", nargs="+")
    parser.add_argument("--allow-partial", action="store_true")
    args = parser.parse_args()
    rows, metadata, sources = load(args.inputs, args.allow_partial)
    result = analyze(rows)
    result["metadata"] = metadata
    result["sources"] = sources
    comparison = None
    if args.compare:
        old_rows, _, _ = load(args.compare)
        current_keys = {match_key(row) for row in rows}
        if not current_keys.issubset({match_key(row) for row in old_rows}):
            raise ValueError("Before inputs must contain every current fixture")
        # Extra baseline repetitions are excluded, never substituted for a fixture.
        comparison = analyze([row for row in old_rows if match_key(row) in current_keys])
        result["matched_baseline"] = comparison
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    write_report(result, sources, args.output / "report.md", args.label, comparison)
    with (args.output / "matches.csv").open("w", newline="", encoding="utf-8-sig") as file:
        keys = ["suite", "dt", "growth", "repetition", "pair_id", "seed", "policy", "side_a", "stage", "deck_a", "deck_b", "structures_a", "structures_b", "result_a", "elapsed", "base_a", "base_b", "peak_units", "capped_steps"]
        writer = csv.DictWriter(file, fieldnames=keys)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: "/".join(row[key]) if isinstance(row[key], list) else row[key] for key in keys})
    print(json.dumps({key: result[key] for key in ["total_matches", "pvp", "pvp_blue", "mirror_blue", "campaign_player_blue"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
