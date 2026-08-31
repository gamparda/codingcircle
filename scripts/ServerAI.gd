class_name ServerAI
extends RefCounted

const MIN_STAGE := 1
const MAX_STAGE := 10
const STAGE_NAMES := [
	"입문", "견습", "전진", "수비", "전술",
	"공세", "정예", "맹공", "지휘관", "최종전",
]
const ATTACK_ORDER := ["swordsman", "shield", "archer", "healer"]
const STRUCTURE_ORDER := ["wall", "swamp", "jump_pad"]

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
	return String(STAGE_NAMES[index])

static func stage_summary(difficulty_stage: int) -> String:
	var value := clampi(difficulty_stage, MIN_STAGE, MAX_STAGE)
	if value <= 2:
		return "느린 기본 병력"
	if value <= 4:
		return "원거리와 방벽 해금"
	if value <= 6:
		return "회복과 지형 전술"
	if value <= 8:
		return "강화 병력과 빠른 공세"
	return "최대 전력·자원 보너스"

func update(model: BattleModel, delta: float) -> void:
	if model.winner != -1:
		return
	if stage > 1:
		var bonus_income := float(stage - 1) * 0.40 * delta
		model.resources[side] = min(BattleModel.MAX_RESOURCE, float(model.resources[side]) + bonus_income)
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

	var unlocked_count := 1
	if stage >= 2:
		unlocked_count = 2
	if stage >= 3:
		unlocked_count = 3
	if stage >= 5:
		unlocked_count = 4
	var preferred := String(ATTACK_ORDER[unit_cursor % unlocked_count])
	if stage >= 2 and enemy_count >= own_count + 2:
		preferred = "shield"
	elif stage >= 3 and enemy_count > own_count:
		preferred = "archer"
	elif stage >= 5 and own_count >= 2 and own_healers == 0:
		preferred = "healer"

	if model.spawn_unit(side, preferred):
		_apply_stage_unit_bonus(model.units.back())
		unit_cursor += 1
		spawn_timer = _spawn_interval()
	else:
		spawn_timer = 0.25

func _apply_stage_unit_bonus(unit: Dictionary) -> void:
	var hp_scale := 0.84 + float(stage) * 0.04
	var damage_scale := 0.80 + float(stage) * 0.04
	unit.max_hp = float(unit.max_hp) * hp_scale
	unit.hp = float(unit.max_hp)
	unit.damage = float(unit.damage) * damage_scale
	if String(unit.kind) == "healer":
		unit.heal = float(unit.heal) * damage_scale

func _try_place_structure(model: BattleModel) -> void:
	var unlocked_count := 1
	if stage >= 5:
		unlocked_count = 2
	if stage >= 7:
		unlocked_count = 3
	var kind := String(STRUCTURE_ORDER[structure_cursor % unlocked_count])
	var positions := [920.0, 1000.0, 840.0] if side == 1 else [360.0, 280.0, 440.0]
	var x := float(positions[structure_cursor % positions.size()])
	if model.place_structure(side, kind, x):
		structure_cursor += 1
	structure_timer = 0.0

func _spawn_interval() -> float:
	return 1.85 - float(stage - 1) * 0.115

func _structure_interval() -> float:
	return 9.0 - float(stage - 1) * 0.5
