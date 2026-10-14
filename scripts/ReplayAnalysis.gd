extends RefCounted
## Turns a replay into a "who is winning" curve plus a short list of notable moments.
## One silent pass over the deterministic re-simulation; nothing here touches the live game.

const BattleReplay = preload("res://scripts/BattleReplay.gd")

const SAMPLE_TICKS := 15            # one sample every half second at 30 Hz
const MAX_HIGHLIGHTS := 12
const BASE_MILESTONES := [0.75, 0.5, 0.25]
const MIN_LEAD_SWING := 0.3         # a lead change only counts when it is clearly decisive
const SUSTAIN_SAMPLES := 6          # ... and a deficit or lead only counts after it lasted three seconds
const CONTACT_EVENTS := ["ATTACK", "DAMAGE", "BASE_HIT", "DEATH", "STRUCTURE_DESTROYED"]
const BASE_WEIGHT := 0.35
const UNIT_WEIGHT := 1.6
const CURVE_GAIN := 1.6
const BATCH_TICKS := 512
const BUDGET_USEC := 4000

## The owner advances or discards this silent pass. Partial results are private
## until done, so trimming highlights never changes an already published list.
class AnalysisJob extends RefCounted:
	var player = null
	var out := {"samples": [], "highlights": [], "ticks": 0}
	var highlights: Array = []
	var milestone_hit := [{}, {}]
	var first_death := false
	var first_structure := false
	var last_sign := 0
	var last_sign_tick := 0
	var contested := false
	var done := false
	var valid := false
	var ticks := 0

	func _init(replay: Dictionary) -> void:
		valid = BattleReplay.valid(replay)
		if valid:
			player = BattleReplay.Player.new(replay)
		else:
			done = true

## Returns {"samples": [{"t": tick, "momentum": -1..1}], "highlights": [{"tick", "kind", "text"}], "ticks": N}.
## momentum > 0 means the blue side is ahead (base health plus living army health).
static func analyze(replay: Dictionary) -> Dictionary:
	var job := AnalysisJob.new(replay)
	while not job.done:
		advance(job)
	return job.out

## One frame of analysis. A single simulation tick can exceed the time budget.
static func advance(job: AnalysisJob) -> void:
	if job.done: return
	var started := Time.get_ticks_usec()
	for _step in BATCH_TICKS:
		var running: bool = job.player.step()
		job.ticks = job.player.ticks
		if not running:
			# Preserve the synchronous analyzer's terminal-tick boundary.
			job.player.model.combat_events.clear()
			job.out.ticks = job.ticks
			var winner: int = job.player.model.winner
			job.highlights.append({"tick": job.ticks, "kind": "finish", "text": "결정타: %s 승리" % ("블루" if winner == 0 else ("레드" if winner == 1 else "무승부"))})
			job.highlights.sort_custom(func(a, b): return int(a.tick) < int(b.tick))
			job.out.highlights = _trim(job.highlights)
			job.player = null
			job.highlights = []
			job.done = true
			return
		_observe(job)
		if Time.get_ticks_usec() - started >= BUDGET_USEC: return

static func _observe(job: AnalysisJob) -> void:
	var model: BattleModel = job.player.model
	# Events are read once and discarded without a deep copy or retained history.
	for event in model.combat_events:
		var kind := String(event.get("type", ""))
		if CONTACT_EVENTS.has(kind):
			job.contested = true
		if kind == "DEATH" and not job.first_death:
			job.first_death = true
			job.highlights.append({"tick": job.ticks, "kind": "clash", "text": "첫 교전: 첫 번째 병력이 쓰러졌습니다"})
		elif kind == "STRUCTURE_DESTROYED" and not job.first_structure:
			job.first_structure = true
			job.highlights.append({"tick": job.ticks, "kind": "structure", "text": "첫 구조물이 파괴되었습니다"})
	model.combat_events.clear()
	for side in 2:
		var fraction := float(model.base_hp[side]) / maxf(1.0, float(model.base_max_hp[side]))
		for milestone in BASE_MILESTONES:
			if fraction <= milestone and not job.milestone_hit[side].has(milestone):
				job.milestone_hit[side][milestone] = true
				var name := "블루" if side == 0 else "레드"
				job.highlights.append({"tick": job.ticks, "kind": "base", "text": "%s 기지 체력 %d%% 이하" % [name, roundi(milestone * 100.0)]})
	if job.ticks % SAMPLE_TICKS == 0:
		# Before contact, deploying first must not look like a decisive lead.
		var momentum := _momentum(model) if job.contested else 0.0
		job.out.samples.append({"t": job.ticks, "momentum": momentum})
		var sign_now := 0 if absf(momentum) < MIN_LEAD_SWING else (1 if momentum > 0.0 else -1)
		if sign_now != 0 and job.last_sign != 0 and sign_now != job.last_sign and job.ticks - job.last_sign_tick > SAMPLE_TICKS * 4:
			job.highlights.append({"tick": job.ticks, "kind": "swing", "text": "%s 쪽으로 전세가 역전되었습니다" % ("블루" if sign_now > 0 else "레드")})
		if sign_now != 0:
			if sign_now != job.last_sign:
				job.last_sign_tick = job.ticks
			job.last_sign = sign_now

static func _momentum(model: BattleModel) -> float:
	# Armies decide fights, bases only decide the ending, so units weigh much more than base health.
	var power := [0.0, 0.0]
	for side in 2:
		power[side] = maxf(0.0, float(model.base_hp[side])) * BASE_WEIGHT
	for unit in model.units:
		if float(unit.hp) > 0.0:
			power[int(unit.side)] += float(unit.hp) * UNIT_WEIGHT
	var total: float = power[0] + power[1]
	return 0.0 if total <= 0.0 else clampf((power[0] - power[1]) / total * CURVE_GAIN, -1.0, 1.0)

## Same curve as `_momentum`, computed from a network/local snapshot (used live during battles).
static func momentum_from_snapshot(data: Dictionary) -> float:
	var power := [0.0, 0.0]
	var bases: Array = data.get("base_hp", [0.0, 0.0])
	for side in 2:
		power[side] = maxf(0.0, float(bases[side])) * BASE_WEIGHT
	for unit in data.get("units", []):
		if float(unit.hp) > 0.0:
			power[int(unit.side)] += float(unit.hp) * UNIT_WEIGHT
	var total: float = power[0] + power[1]
	return 0.0 if total <= 0.0 else clampf((power[0] - power[1]) / total * CURVE_GAIN, -1.0, 1.0)

## One sentence about how the battle went for `own_side`, from its momentum curve (blue-positive).
static func summary_line(curve: Array, winner: int, own_side: int) -> String:
	var observations: Array = curve.filter(func(value): return value != null)
	if observations.size() < 4 or winner < 0:
		return ""
	# Avoid claims about the entire match when only some intervals were seen.
	if observations.size() != curve.size():
		return "확인한 구간에서 크게 밀렸다가 역전했습니다." if winner == own_side and sustained_deficit(curve, own_side) else "일부 전세 기록이 없습니다. 전투 요약에서 확인하세요."
	var sign := 1.0 if own_side == 0 else -1.0
	var lowest := 1.0
	var highest := -1.0
	for value in curve:
		var mine: float = float(value) * sign
		lowest = minf(lowest, mine)
		highest = maxf(highest, mine)
	if winner == 2:
		return "팽팽한 무승부였습니다."
	if winner == own_side:
		if lowest >= -0.1:
			return "시종일관 앞선 안정적인 승리였습니다."
		if sustained_deficit(curve, own_side):
			return "한때 크게 밀렸지만 뒤집었습니다. 역전승!"
		return "접전 끝에 승리했습니다."
	if sustained_lead(curve, own_side):
		return "초반엔 앞섰지만 이후 전세를 내줬습니다."
	if highest < 0.1:
		return "처음부터 밀렸습니다. 초반 구성을 점검해 보세요."
	return "접전이었지만 한 끗이 모자랐습니다."

## True when `own_side` was clearly behind (curve is blue-positive) for SUSTAIN_SAMPLES samples in a row.
static func sustained_deficit(curve: Array, own_side: int) -> bool:
	return _sustained(curve, 1.0 if own_side == 0 else -1.0, -MIN_LEAD_SWING, false)

static func sustained_lead(curve: Array, own_side: int) -> bool:
	return _sustained(curve, 1.0 if own_side == 0 else -1.0, MIN_LEAD_SWING, true)

static func _sustained(curve: Array, sign: float, threshold: float, above: bool) -> bool:
	var run := 0
	for value in curve:
		if value == null:
			run = 0
			continue
		var mine: float = float(value) * sign
		if (mine >= threshold) if above else (mine <= threshold):
			run += 1
			if run >= SUSTAIN_SAMPLES:
				return true
		else:
			run = 0
	return false

## Keeps the list readable: never more than MAX_HIGHLIGHTS and no two within two seconds of each other.
static func _trim(items: Array) -> Array:
	var kept: Array = []
	for item in items:
		if not kept.is_empty() and int(item.tick) - int(kept.back().tick) < 60 and item.kind != "finish":
			continue
		kept.append(item)
	while kept.size() > MAX_HIGHLIGHTS:
		kept.remove_at(1 + (kept.size() - 2) / 2)
	return kept

## First highlight strictly after `tick`, or {} when there is none (used by the "next moment" button).
static func next_after(highlights: Array, tick: int) -> Dictionary:
	for item in highlights:
		if int(item.tick) > tick + 1:
			return item
	return {}

static func previous_before(highlights: Array, tick: int) -> Dictionary:
	var found := {}
	for item in highlights:
		if int(item.tick) < tick - 30:
			found = item
	return found
