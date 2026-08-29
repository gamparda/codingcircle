class_name BattleModel
extends RefCounted

const FIELD_LEFT := 90.0
const FIELD_RIGHT := 1190.0
const START_RESOURCE := 60.0
const MAX_RESOURCE := 150.0
const RESOURCE_RATE := 8.0
const BASE_MAX_HP := 500.0
const STRUCTURE_LIMIT := 3
const MATCH_LIMIT := 300.0

const UNIT_STATS := {
	"shield": {"cost": 40.0, "hp": 180.0, "damage": 12.0, "interval": 1.1, "speed": 34.0, "range": 34.0},
	"swordsman": {"cost": 25.0, "hp": 95.0, "damage": 18.0, "interval": 0.8, "speed": 48.0, "range": 34.0},
	"archer": {"cost": 45.0, "hp": 60.0, "damage": 22.0, "interval": 1.25, "speed": 37.0, "range": 150.0},
	"healer": {"cost": 45.0, "hp": 62.0, "damage": 0.0, "heal": 20.0, "interval": 1.2, "speed": 36.0, "range": 125.0},
}

const STRUCTURE_STATS := {
	"wall": {"cost": 35.0, "hp": 170.0},
	"jump_pad": {"cost": 30.0, "hp": 90.0},
	"swamp": {"cost": 30.0, "hp": 90.0},
}

var resources: Array = [START_RESOURCE, START_RESOURCE]
var base_hp: Array = [BASE_MAX_HP, BASE_MAX_HP]
var units: Array = []
var structures: Array = []
var winner := -1
var elapsed := 0.0
var next_unit_id := 1
var next_structure_id := 1
var spawn_cooldowns: Array = [{}, {}]
var jumped: Dictionary = {}

func reset() -> void:
	resources = [START_RESOURCE, START_RESOURCE]
	base_hp = [BASE_MAX_HP, BASE_MAX_HP]
	units.clear()
	structures.clear()
	winner = -1
	elapsed = 0.0
	next_unit_id = 1
	next_structure_id = 1
	spawn_cooldowns = [{}, {}]
	jumped.clear()

func spawn_unit(side: int, kind: String) -> bool:
	if winner != -1 or side < 0 or side > 1 or not UNIT_STATS.has(kind):
		return false
	var stats: Dictionary = UNIT_STATS[kind]
	if resources[side] < stats.cost or float(spawn_cooldowns[side].get(kind, 0.0)) > 0.0:
		return false
	resources[side] -= stats.cost
	spawn_cooldowns[side][kind] = 0.35
	units.append({
		"id": next_unit_id,
		"side": side,
		"kind": kind,
		"x": FIELD_LEFT + 35.0 if side == 0 else FIELD_RIGHT - 35.0,
		"hp": stats.hp,
		"max_hp": stats.hp,
		"damage": stats.damage,
		"heal": stats.get("heal", 0.0),
		"interval": stats.interval,
		"cooldown": 0.0,
		"speed": stats.speed,
		"range": stats.range,
	})
	next_unit_id += 1
	return true

func place_structure(side: int, kind: String, x: float) -> bool:
	if winner != -1 or side < 0 or side > 1 or not STRUCTURE_STATS.has(kind):
		return false
	var valid_zone := (side == 0 and x >= 180.0 and x <= 600.0) or (side == 1 and x >= 680.0 and x <= 1100.0)
	if not valid_zone:
		return false
	var owned := 0
	for structure in structures:
		if structure.side == side:
			owned += 1
	if owned >= STRUCTURE_LIMIT:
		return false
	var stats: Dictionary = STRUCTURE_STATS[kind]
	if resources[side] < stats.cost:
		return false
	resources[side] -= stats.cost
	structures.append({
		"id": next_structure_id,
		"side": side,
		"kind": kind,
		"x": x,
		"hp": stats.hp,
		"max_hp": stats.hp,
	})
	next_structure_id += 1
	return true

func tick(delta: float) -> void:
	if winner != -1:
		return
	elapsed += delta
	for side in 2:
		resources[side] = min(MAX_RESOURCE, resources[side] + RESOURCE_RATE * delta)
		for kind in spawn_cooldowns[side].keys():
			spawn_cooldowns[side][kind] = max(0.0, float(spawn_cooldowns[side][kind]) - delta)

	for unit in units:
		unit.cooldown = max(0.0, float(unit.cooldown) - delta)
		if unit.hp <= 0.0:
			continue
		_apply_jump_pad(unit)
		if unit.kind == "healer":
			var heal_target = _find_heal_target(unit)
			if heal_target != null:
				if unit.cooldown <= 0.0:
					heal_target.hp = min(heal_target.max_hp, heal_target.hp + unit.heal)
					unit.cooldown = unit.interval
				continue
			var healer_direction := 1.0 if unit.side == 0 else -1.0
			unit.x = clamp(float(unit.x) + healer_direction * unit.speed * _swamp_scale(unit) * delta, FIELD_LEFT, FIELD_RIGHT)
			continue
		var target = _find_target(unit)
		if target != null:
			if unit.cooldown <= 0.0:
				target.hp -= unit.damage
				unit.cooldown = unit.interval
			continue
		var enemy_base_x := FIELD_RIGHT if unit.side == 0 else FIELD_LEFT
		if abs(unit.x - enemy_base_x) <= unit.range:
			if unit.cooldown <= 0.0:
				base_hp[1 - unit.side] -= unit.damage
				unit.cooldown = unit.interval
				if base_hp[1 - unit.side] <= 0.0:
					base_hp[1 - unit.side] = 0.0
					winner = unit.side
			continue
		var speed_scale := _swamp_scale(unit)
		var direction := 1.0 if unit.side == 0 else -1.0
		unit.x = clamp(float(unit.x) + direction * unit.speed * speed_scale * delta, FIELD_LEFT, FIELD_RIGHT)

	units = units.filter(func(unit): return unit.hp > 0.0)
	structures = structures.filter(func(structure): return structure.hp > 0.0)
	if elapsed >= MATCH_LIMIT and winner == -1:
		winner = 0 if base_hp[0] > base_hp[1] else 1 if base_hp[1] > base_hp[0] else 2

func _find_target(unit: Dictionary):
	var best = null
	var best_distance := INF
	for enemy in units:
		if enemy.side == unit.side or enemy.hp <= 0.0:
			continue
		var distance: float = abs(float(enemy.x) - float(unit.x))
		if distance <= unit.range and distance < best_distance:
			best = enemy
			best_distance = distance
	for structure in structures:
		if structure.side == unit.side or structure.kind != "wall" or structure.hp <= 0.0:
			continue
		var ahead := float(structure.x) >= float(unit.x) if unit.side == 0 else float(structure.x) <= float(unit.x)
		var distance: float = abs(float(structure.x) - float(unit.x))
		if ahead and distance <= unit.range + 12.0 and distance < best_distance:
			best = structure
			best_distance = distance
	return best

func _find_heal_target(unit: Dictionary):
	var best = null
	var lowest_ratio := 1.0
	for ally in units:
		if ally.id == unit.id or ally.side != unit.side or ally.hp <= 0.0 or ally.hp >= ally.max_hp:
			continue
		if abs(float(ally.x) - float(unit.x)) > unit.range:
			continue
		var ratio: float = float(ally.hp) / max(float(ally.max_hp), 1.0)
		if ratio < lowest_ratio:
			best = ally
			lowest_ratio = ratio
	return best

func _swamp_scale(unit: Dictionary) -> float:
	for structure in structures:
		if structure.kind == "swamp" and structure.side != unit.side and abs(float(structure.x) - float(unit.x)) <= 90.0:
			return 0.45
	return 1.0

func _apply_jump_pad(unit: Dictionary) -> void:
	for structure in structures:
		if structure.kind != "jump_pad" or structure.side != unit.side:
			continue
		var key := "%s:%s" % [unit.id, structure.id]
		if not jumped.has(key) and abs(float(structure.x) - float(unit.x)) <= 24.0:
			unit.x += 125.0 if unit.side == 0 else -125.0
			jumped[key] = true

func snapshot() -> Dictionary:
	return {
		"resources": resources.duplicate(),
		"base_hp": base_hp.duplicate(),
		"units": units.duplicate(true),
		"structures": structures.duplicate(true),
		"winner": winner,
		"elapsed": elapsed,
	}
