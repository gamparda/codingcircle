class_name ServerAI
extends RefCounted

var side: int
var spawn_timer := 0.0
var structure_timer := 0.0
var unit_cursor := 0
var structure_cursor := 0

const ATTACK_ORDER := ["swordsman", "archer", "shield", "healer"]
const STRUCTURE_ORDER := ["wall", "swamp", "jump_pad"]

func _init(ai_side: int = 1) -> void:
	side = clampi(ai_side, 0, 1)

func update(model: BattleModel, delta: float) -> void:
	if model.winner != -1:
		return
	spawn_timer -= delta
	structure_timer += delta
	if spawn_timer <= 0.0:
		_try_spawn(model)
	if structure_timer >= 5.0:
		_try_place_structure(model)

func _try_spawn(model: BattleModel) -> void:
	var enemy_side := 1 - side
	var own_count := 0
	var enemy_count := 0
	for unit in model.units:
		if int(unit.side) == side:
			own_count += 1
		elif int(unit.side) == enemy_side:
			enemy_count += 1

	var preferred := String(ATTACK_ORDER[unit_cursor % ATTACK_ORDER.size()])
	if enemy_count >= own_count + 2:
		preferred = "shield"
	elif enemy_count > own_count:
		preferred = "archer"

	var spawned := model.spawn_unit(side, preferred)
	if spawned:
		unit_cursor += 1
		spawn_timer = 0.9
	else:
		spawn_timer = 0.25

func _try_place_structure(model: BattleModel) -> void:
	var kind := String(STRUCTURE_ORDER[structure_cursor % STRUCTURE_ORDER.size()])
	var positions := [920.0, 1000.0, 840.0] if side == 1 else [360.0, 280.0, 440.0]
	var x := float(positions[structure_cursor % positions.size()])
	if model.place_structure(side, kind, x):
		structure_cursor += 1
	structure_timer = 0.0
