extends RefCounted
## Turns a replay into a "who is winning" curve plus a short list of notable moments.
## One silent pass over the deterministic re-simulation; nothing here touches the live game.

const BattleReplay = preload("res://scripts/BattleReplay.gd")

const SAMPLE_TICKS := 15            # one sample every half second at 30 Hz
const MAX_HIGHLIGHTS := 12
const BASE_MILESTONES := [0.75, 0.5, 0.25]
const MIN_LEAD_SWING := 0.18        # a lead change only counts when it is clearly decisive
const BASE_WEIGHT := 0.35
const UNIT_WEIGHT := 1.6
const CURVE_GAIN := 1.6

## Returns {"samples": [{"t": tick, "momentum": -1..1}], "highlights": [{"tick", "kind", "text"}], "ticks": N}.
## momentum > 0 means the blue side is ahead (base health plus living army health).
static func analyze(replay: Dictionary) -> Dictionary:
	var out := {"samples": [], "highlights": [], "ticks": 0}
	if not BattleReplay.valid(replay):
		return out
	var player := BattleReplay.Player.new(replay)
	var highlights: Array = []
	var milestone_hit := [{}, {}]
	var first_death := false
	var first_structure := false
	var last_sign := 0
	var last_sign_tick := 0
	var strongest_swing := 0.0
	while player.step():
		var model: BattleModel = player.model
		for event in model.drain_combat_events():
			var kind := String(event.get("type", ""))
			if kind == "DEATH" and not first_death:
				first_death = true
				highlights.append({"tick": player.ticks, "kind": "clash", "text": "첫 교전: 첫 번째 병력이 쓰러졌습니다"})
			elif kind == "STRUCTURE_DESTROYED" and not first_structure:
				first_structure = true
				highlights.append({"tick": player.ticks, "kind": "structure", "text": "첫 구조물이 파괴되었습니다"})
		for side in 2:
			var fraction := float(model.base_hp[side]) / maxf(1.0, float(model.base_max_hp[side]))
			for milestone in BASE_MILESTONES:
				if fraction <= milestone and not milestone_hit[side].has(milestone):
					milestone_hit[side][milestone] = true
					var name := "블루" if side == 0 else "레드"
					highlights.append({"tick": player.ticks, "kind": "base", "text": "%s 기지 체력 %d%% 이하" % [name, roundi(milestone * 100.0)]})
		if player.ticks % SAMPLE_TICKS == 0:
			var momentum := _momentum(model)
			out.samples.append({"t": player.ticks, "momentum": momentum})
			var sign_now := 0 if absf(momentum) < MIN_LEAD_SWING else (1 if momentum > 0.0 else -1)
			if sign_now != 0 and last_sign != 0 and sign_now != last_sign and player.ticks - last_sign_tick > SAMPLE_TICKS * 4:
				highlights.append({"tick": player.ticks, "kind": "swing", "text": "%s 쪽으로 전세가 역전되었습니다" % ("블루" if sign_now > 0 else "레드")})
				strongest_swing = maxf(strongest_swing, absf(momentum))
			if sign_now != 0:
				if sign_now != last_sign:
					last_sign_tick = player.ticks
				last_sign = sign_now
	out.ticks = player.ticks
	var winner: int = player.model.winner
	highlights.append({"tick": player.ticks, "kind": "finish", "text": "결정타: %s 승리" % ("블루" if winner == 0 else ("레드" if winner == 1 else "무승부"))})
	highlights.sort_custom(func(a, b): return int(a.tick) < int(b.tick))
	out.highlights = _trim(highlights)
	return out

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
	if curve.size() < 4 or winner < 0:
		return ""
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
		if lowest <= -0.3:
			return "한때 크게 밀렸지만 뒤집었습니다. 역전승!"
		return "접전 끝에 승리했습니다."
	if highest >= 0.3:
		return "초반엔 앞섰지만 이후 전세를 내줬습니다."
	if highest < 0.1:
		return "처음부터 밀렸습니다. 초반 구성을 점검해 보세요."
	return "접전이었지만 한 끗이 모자랐습니다."

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
