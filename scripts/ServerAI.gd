class_name ServerAI
extends RefCounted

const Localization = preload("res://scripts/Localization.gd")

const MIN_STAGE := 1
const MAX_STAGE := 10
const STAGE_NAMES := [
	"입문", "견습", "전진", "수비", "전술",
	"공세", "정예", "맹공", "지휘관", "최종전",
]
const ATTACK_ORDER := ["swordsman", "shield", "archer", "healer"]
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
	var value := clampi(difficulty_stage, MIN_STAGE, MAX_STAGE)
	if value <= 2:
		return Localization.text("기본 병력 운용")
	if value <= 4:
		return Localization.text("적극적 방어와 구조물 운용")
	if value <= 6:
		return Localization.text("회복·경제·지형 전술")
	if value <= 8:
		return Localization.text("고속 공세와 강화 전력")
	return Localization.text("최대 전력·자원 보너스")

func update(model: BattleModel, delta: float) -> void:
	if model.winner != -1:
		return
	_current_elapsed = model.elapsed
	if stage > 1:
		var bonus_income := float(stage - 1) * 0.40 * delta
		model.resources[side] = min(BattleModel.MAX_RESOURCE, float(model.resources[side]) + bonus_income)
	var endurance_tier := long_battle_tier(model.elapsed)
	if endurance_tier > 0:
		model.resources[side] = min(BattleModel.MAX_RESOURCE, float(model.resources[side]) + float(endurance_tier) * 0.5 * delta)
	spawn_timer -= delta
	structure_timer += delta
	if spawn_timer <= 0.0:
		_try_spawn(model)
	if stage >= 3 and structure_timer >= _structure_interval():
		_try_place_structure(model)

func _try_spawn(model: BattleModel) -> void:
	var enemy_side := 1 - side
	var own_count := 0
	var enemy_count := 0
	var own_healers := 0
	for unit in model.units:
		if int(unit.side) == side:
			own_count += 1
			if String(unit.kind) == "healer":
				own_healers += 1
		elif int(unit.side) == enemy_side:
			enemy_count += 1

	var available: Array = []
	for kind in ATTACK_ORDER:
		if model.unit_decks[side].has(kind):
			available.append(kind)
	if available.is_empty():
		return
	var preferred := String(available[unit_cursor % available.size()])
	if stage >= 2 and enemy_count >= own_count + 2 and available.has("shield"):
		preferred = "shield"
	elif stage >= 3 and enemy_count > own_count and available.has("archer"):
		preferred = "archer"
	elif stage >= 5 and own_count >= 2 and own_healers == 0 and available.has("healer"):
		preferred = "healer"

	if model.spawn_unit(side, preferred):
		_apply_stage_unit_bonus(model.units.back())
		unit_cursor += 1
		spawn_timer = _spawn_interval()
	else:
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
	var available: Array = []
	for candidate in STRUCTURE_ORDER:
		if model.structure_decks[side].has(candidate):
			available.append(candidate)
	if available.is_empty():
		structure_timer = 0.0
		return
	var enemy_side := 1 - side
	var own_units := model.units.filter(func(unit): return int(unit.side) == side).size()
	var enemy_units := model.units.filter(func(unit): return int(unit.side) == enemy_side).size()
	var kind := String(available[structure_cursor % available.size()])
	if model.elapsed < 35.0 and own_units >= enemy_units and available.has("generator") and model._owned_structure_count(side, "generator") == 0:
		kind = "generator"
	elif enemy_units >= own_units + 2 and available.has("wall"):
		kind = "wall"
	elif enemy_units > own_units and available.has("swamp"):
		kind = "swamp"
	elif enemy_units > 0 and available.has("turret"):
		kind = "turret"

	var positions := [1000.0, 915.0, 835.0] if side == 1 else [280.0, 365.0, 445.0]
	if kind == "generator":
		positions = [1000.0] if side == 1 else [280.0]
	for x in positions:
		if model.place_structure(side, kind, float(x)):
			structure_cursor += 1
			break
	structure_timer = 0.0

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
