extends RefCounted
## What the helper programs compute. A job is planned into small independent chunks (so work can be handed out,
## handed back half way and handed to someone else), each chunk runs in time slices, and the chunk results are
## combined into the job's final answer. Everything is deterministic: the same chunk always gives the same result.

const DeckSimulator = preload("res://scripts/DeckSimulator.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")

## capability = the checkbox on the assist window that allows this kind of work.
const TYPES := {
	"balance": {"title": "밸런스 실험", "capability": "balance"},
	"replay": {"title": "리플레이 검증", "capability": "replay"},
	"selftest": {"title": "연결 점검", "capability": "selftest"},
}
const CAPABILITIES := ["balance", "replay", "selftest"]
const MAX_CHUNKS := 2000
const MAX_MATCHES := 200
const BALANCE_CHUNK_MATCHES := 20
const MAX_REPLAYS := 200
const MAX_REPLAY_CHARS := 400000

static func known(type: String) -> bool:
	return TYPES.has(type)

static func capability_for(type: String) -> String:
	return String(TYPES.get(type, {}).get("capability", ""))

static func title_for(type: String) -> String:
	return String(TYPES.get(type, {}).get("title", type))

## Every legal set of three unit kinds.
static func all_unit_decks() -> Array:
	var kinds: Array = BattleModel.UNIT_STATS.keys()
	kinds.sort()
	var decks: Array = []
	for a in kinds.size():
		for b in range(a + 1, kinds.size()):
			for c in range(b + 1, kinds.size()):
				decks.append([kinds[a], kinds[b], kinds[c]])
	return decks

## {"ok": bool, "error": String, "chunks": [params per chunk]}.
static func plan(type: String, params: Dictionary) -> Dictionary:
	match type:
		"balance": return _plan_balance(params)
		"replay": return _plan_replay(params)
		"selftest": return _plan_selftest(params)
	return {"ok": false, "error": "알 수 없는 작업 종류입니다.", "chunks": []}

static func _plan_balance(params: Dictionary) -> Dictionary:
	var stage := clampi(int(params.get("stage", 3)), ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
	var matches := clampi(int(params.get("matches", 20)), 1, MAX_MATCHES)
	var structures: Array = params.get("structures", BattleModel.DEFAULT_STRUCTURE_DECK)
	var decks: Array = []
	if params.get("decks", "all") is Array:
		decks = params.decks
	else:
		decks = all_unit_decks()
	if decks.is_empty() or not BattleModel._valid_deck(structures, BattleModel.STRUCTURE_STATS):
		return {"ok": false, "error": "덱 설정이 올바르지 않습니다.", "chunks": []}
	var chunks: Array = []
	for deck in decks:
		if not deck is Array or not BattleModel._valid_deck(deck, BattleModel.UNIT_STATS):
			return {"ok": false, "error": "덱 설정이 올바르지 않습니다.", "chunks": []}
		var offset := 0
		while offset < matches:
			var count := mini(BALANCE_CHUNK_MATCHES, matches - offset)
			chunks.append({"units": deck.duplicate(), "structures": structures.duplicate(), "stage": stage, "offset": offset, "count": count})
			offset += count
	if chunks.size() > MAX_CHUNKS:
		return {"ok": false, "error": "작업이 너무 큽니다. 판수나 덱을 줄여 주세요.", "chunks": []}
	return {"ok": true, "error": "", "chunks": chunks}

static func _plan_replay(params: Dictionary) -> Dictionary:
	var texts = params.get("texts", [])
	if not texts is Array or texts.is_empty() or texts.size() > MAX_REPLAYS:
		return {"ok": false, "error": "검증할 리플레이가 없거나 너무 많습니다.", "chunks": []}
	var chunks: Array = []
	for text in texts:
		if not text is String or String(text).length() > MAX_REPLAY_CHARS:
			return {"ok": false, "error": "리플레이 형식이 올바르지 않습니다.", "chunks": []}
		chunks.append({"text": text})
	return {"ok": true, "error": "", "chunks": chunks}

static func _plan_selftest(params: Dictionary) -> Dictionary:
	var count := clampi(int(params.get("chunks", 6)), 1, 50)
	var chunks: Array = []
	for index in count:
		chunks.append({"value": index + 1})
	return {"ok": true, "error": "", "chunks": chunks}

## A runnable chunk: `step(budget_msec)` returns true when finished, `result()` is the chunk's answer.
static func new_run(type: String, params: Dictionary):
	match type:
		"balance": return BalanceRun.new(params)
		"replay": return ReplayRun.new(params)
		"selftest": return SelfTestRun.new(params)
	return null

class BalanceRun extends RefCounted:
	var run
	func _init(params: Dictionary) -> void:
		run = preload("res://scripts/DeckSimulator.gd").Run.new(params.units, params.structures, int(params.stage), int(params.count), int(params.offset))
	func step(budget_msec: int = 10) -> bool:
		return run.step(budget_msec)
	func progress() -> float:
		return run.progress()
	func result() -> Dictionary:
		var out := {"matches": run.results.size(), "wins": 0, "losses": 0, "draws": 0, "timeouts": 0, "seconds": 0.0, "base": 0.0}
		for entry in run.results:
			out.seconds += float(entry.seconds)
			match String(entry.result):
				"win":
					out.wins += 1
					out.base += float(entry.base)
				"loss": out.losses += 1
				"draw": out.draws += 1
				_: out.timeouts += 1
		return out

class ReplayRun extends RefCounted:
	var text := ""
	var finished := false
	var answer := {}
	func _init(params: Dictionary) -> void:
		text = String(params.text)
	func step(_budget_msec: int = 10) -> bool:
		if not finished:
			var replay := preload("res://scripts/BattleReplay.gd").from_share_text(text)
			if replay.is_empty():
				answer = {"valid": false, "ok": false, "ticks": 0, "winner": -1}
			else:
				var verdict := preload("res://scripts/BattleReplay.gd").verify(replay)
				answer = {"valid": true, "ok": bool(verdict.ok), "ticks": int(replay.result.get("ticks", 0)), "winner": int(replay.result.get("winner", -1))}
			finished = true
		return true
	func progress() -> float:
		return 1.0 if finished else 0.0
	func result() -> Dictionary:
		return answer

class SelfTestRun extends RefCounted:
	var value := 0
	var ticks := 0
	func _init(params: Dictionary) -> void:
		value = int(params.value)
	func step(_budget_msec: int = 10) -> bool:
		ticks += 1
		return ticks >= 2 # takes more than one slice so hand-overs can be observed
	func progress() -> float:
		return clampf(float(ticks) / 2.0, 0.0, 1.0)
	func result() -> Dictionary:
		return {"value": value * 2}

## Final answer of a finished job from its chunks' params and results (same order).
static func combine(type: String, chunk_params: Array, chunk_results: Array) -> Dictionary:
	match type:
		"balance": return _combine_balance(chunk_params, chunk_results)
		"replay": return _combine_replay(chunk_results)
		"selftest": return {"sum": chunk_results.reduce(func(total, entry): return total + int(entry.get("value", 0)), 0), "chunks": chunk_results.size()}
	return {}

static func _combine_balance(chunk_params: Array, chunk_results: Array) -> Dictionary:
	var rows := {}
	for index in chunk_params.size():
		var params: Dictionary = chunk_params[index]
		var result: Dictionary = chunk_results[index]
		var key := ",".join(PackedStringArray(params.units))
		if not rows.has(key):
			rows[key] = {"deck": params.units.duplicate(), "stage": int(params.stage), "matches": 0, "wins": 0, "losses": 0, "draws": 0, "timeouts": 0, "seconds": 0.0}
		var row: Dictionary = rows[key]
		for field in ["matches", "wins", "losses", "draws", "timeouts"]:
			row[field] = int(row[field]) + int(result.get(field, 0))
		row.seconds = float(row.seconds) + float(result.get("seconds", 0.0))
	var list: Array = []
	for key in rows:
		var row: Dictionary = rows[key]
		row["win_rate"] = float(row.wins) / maxf(1.0, float(row.matches))
		row["average_seconds"] = float(row.seconds) / maxf(1.0, float(row.matches))
		list.append(row)
	list.sort_custom(func(a, b): return float(a.win_rate) > float(b.win_rate) or (float(a.win_rate) == float(b.win_rate) and ",".join(PackedStringArray(a.deck)) < ",".join(PackedStringArray(b.deck))))
	var matches := 0
	for row in list:
		matches += int(row.matches)
	return {"rows": list, "matches": matches}

static func _combine_replay(chunk_results: Array) -> Dictionary:
	var failed: Array = []
	for index in chunk_results.size():
		if not bool(chunk_results[index].get("ok", false)):
			failed.append(index)
	return {"checked": chunk_results.size(), "ok": chunk_results.size() - failed.size(), "failed": failed}
