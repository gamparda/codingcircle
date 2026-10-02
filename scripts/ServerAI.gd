class_name ServerAI
extends RefCounted

const Localization = preload("res://scripts/Localization.gd")

const MIN_STAGE := 1
const MAX_STAGE := 8
const STAGE_NAMES := [
	"입문", "견습", "전진", "수비", "전술",
	"공세", "정예", "최종전",
]
const ATTACK_ORDER := ["swordsman", "shield", "archer", "healer", "berserker", "warlock", "necromancer"]
const STRUCTURE_ORDER := ["generator", "wall", "swamp", "turret"]
const LONG_BATTLE_START := 180.0
const LONG_BATTLE_STEP := 60.0
const LONG_BATTLE_MAX_TIER := 6

var side: int
var stage: int
var spawn_timer := 0.0
var structure_timer := 0.0
var unit_cursor := 0
var structure_cursor := 0

func _init(ai_side: int = 1, difficulty_stage: int = 1) -> void:
	side = clampi(ai_side, 0, 1)
	stage = clampi(difficulty_stage, MIN_STAGE, MAX_STAGE)

static func stage_name(difficulty_stage: int) -> String:
	var index := clampi(difficulty_stage, MIN_STAGE, MAX_STAGE) - 1
	return Localization.text(String(STAGE_NAMES[index]))

static func stage_summary(difficulty_stage: int) -> String:
	return ["기본 전투", "광전사 공세", "장판·방어", "공속 지원", "지원 공세", "해골 군단", "저주·소환", "복합 전술"][clampi(difficulty_stage, MIN_STAGE, MAX_STAGE) - 1]

static func stage_unit_deck(difficulty_stage: int) -> Array:
	var decks := [
		["swordsman", "shield", "archer"], ["swordsman", "berserker", "archer"],
		["shield", "archer", "warlock"], ["shield", "warlock", "healer"],
		["berserker", "archer", "healer"], ["shield", "healer", "necromancer"],
		["berserker", "warlock", "necromancer"], ["shield", "warlock", "necromancer"],
	]
	return decks[clampi(difficulty_stage, MIN_STAGE, MAX_STAGE) - 1].duplicate()

static func stage_structure_deck(difficulty_stage: int) -> Array:
	var decks := [
		["wall", "swamp", "generator"], ["wall", "swamp", "generator"],
		["wall", "turret", "generator"], ["wall", "swamp", "generator"],
		["wall", "swamp", "turret"], ["wall", "turret", "generator"],
		["wall", "swamp", "generator"], ["swamp", "turret", "generator"],
	]
	return decks[clampi(difficulty_stage, MIN_STAGE, MAX_STAGE) - 1].duplicate()

func update(model: BattleModel, delta: float) -> void:
	if model.winner != -1:
		return
	_current_elapsed = model.elapsed
	if stage > 1:
		var bonus_income := float(stage - 1) * 0.40 * delta
		model.resources[side] = min(model.resource_capacity(side), float(model.resources[side]) + bonus_income)
	var endurance_tier := long_battle_tier(model.elapsed)
	if endurance_tier > 0:
		model.resources[side] = min(model.resource_capacity(side), float(model.resources[side]) + float(endurance_tier) * 0.5 * delta)
	spawn_timer -= delta
	structure_timer += delta
	if spawn_timer <= 0.0:
		_try_spawn(model)
	if stage >= 3 and structure_timer >= _structure_interval():
		_try_place_structure(model)

# Decisions scan the live field only when a purchase/build decision is due.
func tactical_state(model: BattleModel) -> Dictionary:
	var state := {"own": 0, "enemy": 0, "frontline": 0, "buff_need": 0,
		"enemy_melee": 0, "counts": {}, "nearest_enemy": -1.0, "distance": INF, "danger": false}
	var base_x := BattleModel.FIELD_LEFT if side == 0 else BattleModel.FIELD_RIGHT
	for unit in model.units:
		if float(unit.hp) <= 0.0: continue
		var kind := String(unit.kind)
		if int(unit.side) == side:
			state.own += 1
			state.counts[kind] = int(state.counts.get(kind, 0)) + 1
			if float(unit.range) <= 40.0: state.frontline += 1
			if float(unit.damage) > 0.0 and int(unit.get("support_stacks", 0)) < BattleModel.SUPPORT_MAX_STACKS: state.buff_need += 1
		else:
			state.enemy += 1
			if float(unit.range) <= 40.0: state.enemy_melee += 1
			var distance := absf(float(unit.x) - base_x)
			if distance < float(state.distance):
				state.distance = distance
				state.nearest_enemy = float(unit.x)
	state.danger = float(state.distance) < 330.0
	return state

func _unit_score(kind: String, state: Dictionary) -> float:
	var count := int(state.counts.get(kind, 0))
	match kind:
		"shield": return (85.0 if state.danger or (state.frontline == 0 and state.own > 0) else 45.0) - count * 12.0
		"swordsman": return 49.0 - count * 5.0
		"berserker": return (65.0 if state.frontline == 0 else 55.0) - count * 7.0
		"archer": return (68.0 if state.frontline > 0 else 50.0) - count * 7.0
		"warlock": return (82.0 if state.enemy_melee >= 2 else 62.0) - count * 18.0
		"necromancer": return (88.0 if count == 0 and not state.danger else 58.0) - count * 18.0
		"healer":
			if state.buff_need < 2: return 2.0
			return (96.0 if count == 0 else 72.0 if state.buff_need > count * 5 else 8.0) - count * 8.0
	return 0.0

func _try_spawn(model: BattleModel) -> void:
	var state := tactical_state(model)
	# A short battle check exposed cheap-unit purchases starving safe economy.
	if stage >= 3 and model.elapsed >= _structure_interval() and model.elapsed < 120.0 and state.own >= 2 and not state.danger and model.structure_decks[side].has("generator") and model._owned_structure_count(side, "generator") == 0:
		var generator_x := BattleModel.BLUE_BUILD_MIN + 35.0 if side == 0 else BattleModel.RED_BUILD_MAX - 35.0
		var error := model.structure_placement_error(side, "generator", generator_x)
		if error.is_empty() or error == "자원이 부족합니다.":
			if model.place_structure(side, "generator", generator_x): structure_timer = 0.0
			spawn_timer = 0.5
			return
	if int(state.own) >= 32:
		spawn_timer = 0.8
		return
	var available: Array = []
	for kind in ATTACK_ORDER:
		if model.unit_decks[side].has(kind) and float(model.spawn_cooldowns[side].get(kind, 0.0)) <= 0.0:
			available.append(kind)
	if available.is_empty():
		spawn_timer = 0.25
		return
	if stage <= 2:
		# Introductory stages keep a predictable rotating attack rather than hard counters.
		var first := unit_cursor % available.size()
		available = available.slice(first) + available.slice(0, first)
	else:
		available.sort_custom(func(a, b): return _unit_score(a, state) > _unit_score(b, state))
	var preferred := String(available[0])
	# Protect the first summoner, curse counter or needed support purchase from cheap-unit spam.
	var key_purchase: bool = (preferred == "necromancer" and int(state.counts.get(preferred, 0)) == 0) or (preferred == "warlock" and int(state.counts.get(preferred, 0)) == 0 and state.enemy_melee >= 2) or (preferred == "healer" and int(state.counts.get(preferred, 0)) == 0 and state.buff_need >= 2)
	if stage >= 3 and key_purchase and not state.danger and float(model.resources[side]) < float(BattleModel.UNIT_STATS[preferred].cost):
		spawn_timer = 0.5
		return
	for kind in available:
		if stage >= 3 and kind == "healer" and _unit_score(kind, state) <= 8.0: continue
		if model.spawn_unit(side, String(kind)):
			_apply_stage_unit_bonus(model.units.back())
			unit_cursor += 1
			spawn_timer = _spawn_interval()
			return
	spawn_timer = 0.25

func _apply_stage_unit_bonus(unit: Dictionary) -> void:
	var endurance_scale := 1.0 + float(long_battle_tier_from_spawn_time()) * 0.05
	var hp_scale := (0.84 + float(stage) * 0.04) * endurance_scale
	var damage_scale := (0.80 + float(stage) * 0.04) * endurance_scale
	unit.max_hp = float(unit.max_hp) * hp_scale
	unit.hp = float(unit.max_hp)
	unit.damage = float(unit.damage) * damage_scale
	if String(unit.kind) == "healer":
		unit.heal = float(unit.heal) * damage_scale

func _try_place_structure(model: BattleModel) -> void:
	structure_timer = 0.0
	var state := tactical_state(model)
	var available: Array = []
	for kind in STRUCTURE_ORDER:
		if not model.structure_decks[side].has(kind): continue
		var limit := int(BattleModel.STRUCTURE_STATS[kind].get("max_count", 1))
		if model._owned_structure_count(side, kind) < limit: available.append(kind)
	if available.is_empty(): return
	var build_min := BattleModel.BLUE_BUILD_MIN if side == 0 else BattleModel.RED_BUILD_MIN
	var build_max := BattleModel.BLUE_BUILD_MAX if side == 0 else BattleModel.RED_BUILD_MAX
	var enemy_x := float(state.nearest_enemy)
	var toward_base := -1.0 if side == 0 else 1.0
	var candidates: Array = []
	if state.danger and state.enemy_melee >= 2 and available.has("swamp") and enemy_x >= build_min - 70.0 and enemy_x <= build_max + 70.0:
		candidates.append("swamp")
	if state.danger and available.has("wall"): candidates.append("wall")
	if available.has("generator") and state.own > 0 and not state.danger and model.elapsed < 120.0:
		candidates.append("generator")
	if state.enemy > 0 and available.has("turret") and float(state.distance) < 650.0: candidates.append("turret")
	if candidates.is_empty(): return
	for kind in candidates:
		var anchor := clampf(enemy_x + toward_base * (110.0 if kind == "turret" else 25.0 if kind == "wall" else 0.0), build_min, build_max)
		var positions := [anchor, anchor + toward_base * 80.0, anchor - toward_base * 80.0]
		if kind == "generator":
			positions = [BattleModel.BLUE_BUILD_MIN + 35.0 if side == 0 else BattleModel.RED_BUILD_MAX - 35.0]
		for x in positions:
			if float(x) < build_min or float(x) > build_max: continue
			if kind == "swamp" and absf(float(x) - enemy_x) > float(BattleModel.STRUCTURE_STATS.swamp.radius): continue
			if model.place_structure(side, String(kind), float(x)):
				structure_cursor += 1
				return

func _spawn_interval() -> float:
	return 1.85 - float(stage - 1) * 0.115

func _structure_interval() -> float:
	return 9.0 - float(stage - 1) * 0.5

func long_battle_tier(elapsed: float) -> int:
	if elapsed < LONG_BATTLE_START:
		return 0
	return mini(LONG_BATTLE_MAX_TIER, 1 + int((elapsed - LONG_BATTLE_START) / LONG_BATTLE_STEP))

var _current_elapsed := 0.0

func long_battle_tier_from_spawn_time() -> int:
	return long_battle_tier(_current_elapsed)
