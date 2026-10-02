class_name BattleModel
extends RefCounted

const Localization = preload("res://scripts/Localization.gd")

const WORLD_SCALE := 1.15
const WORLD_WIDTH := 1280.0 * WORLD_SCALE
const FIELD_LEFT := 90.0 * WORLD_SCALE
const FIELD_RIGHT := 1190.0 * WORLD_SCALE
const START_RESOURCE := 70.0
const MAX_RESOURCE := 180.0
const RESOURCE_RATE := 9.0
const BASE_MAX_HP := 500.0
const STRUCTURE_LIMIT := 3
const STRUCTURE_MIN_SPACING := 75.0
const MIN_ATTACK_INTERVAL := 1.2
const BLUE_BUILD_MIN := 180.0 * WORLD_SCALE
const BLUE_BUILD_MAX := 610.0 * WORLD_SCALE
const RED_BUILD_MIN := 670.0 * WORLD_SCALE
const RED_BUILD_MAX := 1100.0 * WORLD_SCALE
const BLUE_REAR_MAX := 350.0 * WORLD_SCALE
const RED_REAR_MIN := 930.0 * WORLD_SCALE
const SUPPORT_ATTACK_SPEED := 1.20
const SUPPORT_DURATION := 5.0
const SUPPORT_COOLDOWN := 7.0
const SUPPORT_FOLLOW_DISTANCE := 12.0

const UNIT_STATS := {
	"shield": {"cost": 35.0, "hp": 400.0, "damage": 2.0, "interval": 1.5, "speed": 48.0, "range": 34.0},
	"swordsman": {"cost": 30.0, "hp": 82.0, "damage": 10.0, "interval": 1.4, "speed": 44.0, "range": 40.0},
	"archer": {"cost": 45.0, "hp": 58.0, "damage": 15.0, "interval": 1.5, "speed": 34.0, "range": 280.0},
	"healer": {"cost": 45.0, "hp": 60.0, "damage": 0.0, "heal": 0.0, "interval": SUPPORT_COOLDOWN, "speed": 34.0, "range": 15.0},
}
const STRUCTURE_STATS := {
	"wall": {"cost": 35.0, "hp": 230.0, "max_count": 2},
	"swamp": {"cost": 30.0, "hp": 100.0, "speed_scale": 0.20, "radius": 95.0, "lifetime": 5.0},
	"turret": {"cost": 50.0, "hp": 115.0, "damage": 8.0, "interval": 1.5, "range": 240.0, "max_count": 1},
	"generator": {"cost": 50.0, "hp": 90.0, "income": 1.0, "max_count": 1},
}
const DEFAULT_UNIT_DECK := ["shield", "swordsman", "archer"]
const DEFAULT_STRUCTURE_DECK := ["wall", "swamp", "turret"]

var resources: Array = [START_RESOURCE, START_RESOURCE]
var base_hp: Array = [BASE_MAX_HP, BASE_MAX_HP]
var units: Array = []
var structures: Array = []
var winner := -1
var elapsed := 0.0
var next_unit_id := 1
var next_structure_id := 1
var spawn_cooldowns: Array = [{}, {}]

var unit_decks: Array = [DEFAULT_UNIT_DECK.duplicate(), DEFAULT_UNIT_DECK.duplicate()]
var structure_decks: Array = [DEFAULT_STRUCTURE_DECK.duplicate(), DEFAULT_STRUCTURE_DECK.duplicate()]
var combat_events: Array = []
var structure_cooldowns: Dictionary = {}
var announced_deaths: Dictionary = {}
var announced_structure_deaths: Dictionary = {}
var structure_expirations: Dictionary = {}
var campaign_levels: Array = [0, 0]

static func campaign_bonuses(cleared_stages: int) -> Dictionary:
	var levels := clampi(cleared_stages, 0, 10)
	return {"levels": levels, "stat_scale": 1.0 + levels * 0.03,
		"income": RESOURCE_RATE + levels * 0.5, "capacity": MAX_RESOURCE + levels * 10.0,
		"starting_resources": START_RESOURCE + levels * 5.0}

func configure_campaign_growth(side: int, cleared_stages: int) -> void:
	if side < 0 or side > 1:
		return
	campaign_levels[side] = clampi(cleared_stages, 0, 10)
	resources[side] = campaign_bonuses(int(campaign_levels[side])).starting_resources

func resource_capacity(side: int) -> float:
	return float(campaign_bonuses(int(campaign_levels[side])).capacity)

func resource_income(side: int) -> float:
	return float(campaign_bonuses(int(campaign_levels[side])).income)

func reset() -> void:
	resources = [campaign_bonuses(int(campaign_levels[0])).starting_resources, campaign_bonuses(int(campaign_levels[1])).starting_resources]
	base_hp = [BASE_MAX_HP, BASE_MAX_HP]
	units.clear()
	structures.clear()
	winner = -1
	elapsed = 0.0
	next_unit_id = 1
	next_structure_id = 1
	spawn_cooldowns = [{}, {}]

	combat_events.clear()
	structure_cooldowns.clear()
	announced_deaths.clear()
	announced_structure_deaths.clear()
	structure_expirations.clear()

static func _valid_deck(values: Array, allowed: Dictionary) -> bool:
	if values.size() != 3:
		return false
	var unique := {}
	for value in values:
		var kind := String(value)
		if not allowed.has(kind) or unique.has(kind):
			return false
		unique[kind] = true
	return true

func configure_deck(side: int, selected_units: Array, selected_structures: Array) -> bool:
	if side < 0 or side > 1 or not _valid_deck(selected_units, UNIT_STATS) or not _valid_deck(selected_structures, STRUCTURE_STATS):
		return false
	unit_decks[side] = selected_units.duplicate()
	structure_decks[side] = selected_structures.duplicate()
	return true

func spawn_unit(side: int, kind: String) -> bool:
	if winner != -1 or side < 0 or side > 1 or not UNIT_STATS.has(kind) or not unit_decks[side].has(kind):
		return false
	var stats: Dictionary = UNIT_STATS[kind]
	var stat_scale := float(campaign_bonuses(int(campaign_levels[side])).stat_scale)
	if resources[side] < stats.cost or float(spawn_cooldowns[side].get(kind, 0.0)) > 0.0:
		return false
	resources[side] -= stats.cost
	spawn_cooldowns[side][kind] = 0.35
	units.append({"id": next_unit_id, "side": side, "kind": kind,
		"x": FIELD_LEFT + 35.0 if side == 0 else FIELD_RIGHT - 35.0,
		"hp": stats.hp * stat_scale, "max_hp": stats.hp * stat_scale, "damage": stats.damage * stat_scale,
		"heal": stats.get("heal", 0.0) * stat_scale, "interval": stats.interval,
		"cooldown": 0.0 if kind == "healer" else max(MIN_ATTACK_INTERVAL, float(stats.interval)),
		"support_until": 0.0,
		"speed": stats.speed, "range": stats.range})
	next_unit_id += 1
	return true

static func unit_stat_summary(kind: String, growth_level: int = 0) -> String:
	if not UNIT_STATS.has(kind):
		return ""
	var stats: Dictionary = UNIT_STATS[kind]
	var interval: float = max(float(stats.interval), MIN_ATTACK_INTERVAL)
	var stat_scale := float(campaign_bonuses(growth_level).stat_scale)
	var output := Localization.text("비용 %d  ·  체력 %d\n") % [int(stats.cost), int(stats.hp * stat_scale)]
	if kind == "healer":
		return output + Localization.text("피해·회복 없음  ·  공격속도 +20%\n범위 15  ·  유지 5초  ·  쿨 7초 (시전부터)\n중첩 없음  ·  이동 34")
	else:
		output += Localization.text("공격력 %d  ·  DPS %.1f\n") % [int(stats.damage * stat_scale), float(stats.damage) * stat_scale / interval]
	return output + Localization.text("공격 간격 %.2f초  ·  사거리 %d  ·  이동 %d") % [interval, int(stats.range), int(stats.speed)]

static func battle_stat_summary() -> String:
	return Localization.text("구조물  ·  방벽 35/체력 230  ·  늪 30/체력 100/80%% 감속/5초\n포탑 50/체력 115/공격 8/사거리 240  ·  발전기 50/체력 90/+1 자원\n마법사  ·  피해·회복 없음/공격속도 +20%%/범위 15/유지 5초/쿨 7초 (시전부터, 중첩 없음)\n전장  ·  길이 +15%%  ·  기지 체력 %d  ·  자원 +%.0f/초  ·  최대 %.0f  ·  구조물 진영당 %d개  ·  시간 제한 없음") % [int(BASE_MAX_HP), RESOURCE_RATE, MAX_RESOURCE, STRUCTURE_LIMIT]

func _owned_structure_count(side: int, kind: String = "") -> int:
	var count := 0
	for structure in structures:
		if int(structure.side) == side and (kind.is_empty() or String(structure.kind) == kind) and float(structure.hp) > 0.0:
			count += 1
	return count

func structure_placement_error(side: int, kind: String, x: float) -> String:
	if winner != -1 or side < 0 or side > 1 or not STRUCTURE_STATS.has(kind):
		return Localization.text("설치할 수 없는 구조물입니다.")
	if not structure_decks[side].has(kind):
		return Localization.text("현재 덱에 없는 구조물입니다.")
	var valid_zone := (side == 0 and x >= BLUE_BUILD_MIN and x <= BLUE_BUILD_MAX) or (side == 1 and x >= RED_BUILD_MIN and x <= RED_BUILD_MAX)
	if not valid_zone:
		return Localization.text("자신의 건설 구역에만 설치할 수 있습니다.")
	if kind == "generator" and not ((side == 0 and x <= BLUE_REAR_MAX) or (side == 1 and x >= RED_REAR_MIN)):
		return Localization.text("발전기는 후방에만 설치할 수 있습니다.")
	for structure in structures:
		if int(structure.side) == side and float(structure.hp) > 0.0 and abs(float(structure.x) - x) < STRUCTURE_MIN_SPACING:
			return Localization.text("구조물이 너무 가깝습니다.")
	if _owned_structure_count(side) >= STRUCTURE_LIMIT:
		return Localization.text("구조물은 최대 3개까지 설치할 수 있습니다.")
	var max_count := int(STRUCTURE_STATS[kind].get("max_count", STRUCTURE_LIMIT))
	if _owned_structure_count(side, kind) >= max_count:
		if kind == "turret":
			return Localization.text("포탑은 1개만 설치할 수 있습니다.")
		if kind == "generator":
			return Localization.text("발전기는 1개만 설치할 수 있습니다.")
		return Localization.text("방벽은 2개만 설치할 수 있습니다.")
	if resources[side] < float(STRUCTURE_STATS[kind].cost):
		return Localization.text("자원이 부족합니다.")
	return ""

func place_structure(side: int, kind: String, x: float) -> bool:
	if not structure_placement_error(side, kind, x).is_empty():
		return false
	var stats: Dictionary = STRUCTURE_STATS[kind]
	resources[side] -= stats.cost
	structures.append({"id": next_structure_id, "side": side, "kind": kind, "x": x, "hp": stats.hp, "max_hp": stats.hp})
	if kind == "turret":
		structure_cooldowns[next_structure_id] = float(stats.interval)
	if kind == "swamp":
		structure_expirations[next_structure_id] = elapsed + float(stats.lifetime)
	combat_events.append({"type": "STRUCTURE_PLACED", "structure_id": next_structure_id, "kind": kind, "x": x})
	next_structure_id += 1
	return true

func tick(delta: float) -> void:
	if winner != -1:
		return
	elapsed += delta
	for structure in structures:
		if structure_expirations.has(structure.id) and elapsed >= float(structure_expirations[structure.id]):
			structure.hp = 0.0
			structure_expirations.erase(structure.id)
	for side in 2:
		var income := resource_income(side)
		for structure in structures:
			if int(structure.side) == side and String(structure.kind) == "generator" and float(structure.hp) > 0.0:
				income += float(STRUCTURE_STATS.generator.income)
		resources[side] = min(resource_capacity(side), float(resources[side]) + income * delta)
		for kind in spawn_cooldowns[side].keys():
			spawn_cooldowns[side][kind] = max(0.0, float(spawn_cooldowns[side][kind]) - delta)

	_tick_turrets(delta)
	for unit in units:
		unit.cooldown = max(0.0, float(unit.cooldown) - delta * support_attack_speed(unit))
		if unit.hp <= 0.0:
			continue
		if unit.kind == "healer":
			_tick_support(unit, delta)
			continue
		var target = _find_target(unit)
		if target != null:
			if unit.cooldown <= 0.0:
				_damage_target(unit, target, float(unit.damage))
				unit.cooldown = unit.interval
			continue

		var enemy_base_x := FIELD_RIGHT if unit.side == 0 else FIELD_LEFT
		var blocking_wall = _blocking_wall(unit, enemy_base_x)
		if blocking_wall != null and abs(float(blocking_wall.x) - float(unit.x)) <= float(unit.range) + 12.0:
			if unit.cooldown <= 0.0:
				_damage_target(unit, blocking_wall, float(unit.damage))
				unit.cooldown = unit.interval
			continue
		if abs(float(unit.x) - enemy_base_x) <= float(unit.range):
			if unit.cooldown <= 0.0:
				var enemy_side: int = 1 - int(unit.side)
				base_hp[enemy_side] = max(0.0, float(base_hp[enemy_side]) - float(unit.damage))
				combat_events.append({"type": "BASE_HIT", "side": enemy_side, "amount": unit.damage, "x": enemy_base_x})
				unit.cooldown = unit.interval
				if base_hp[enemy_side] <= 0.0:
					winner = int(unit.side)
			continue
		var direction := 1.0 if unit.side == 0 else -1.0
		unit.x = clamp(float(unit.x) + direction * float(unit.speed) * _swamp_scale(unit) * delta, FIELD_LEFT, FIELD_RIGHT)

	_emit_death_events()
	units = units.filter(func(unit): return unit.hp > 0.0)
	structures = structures.filter(func(structure): return structure.hp > 0.0)
	for id in structure_expirations.keys():
		if not structures.any(func(structure): return structure.id == id):
			structure_expirations.erase(id)

func support_attack_speed(unit: Dictionary) -> float:
	if unit.kind == "healer" or float(unit.hp) <= 0.0:
		return 1.0
	return SUPPORT_ATTACK_SPEED if elapsed < float(unit.get("support_until", 0.0)) else 1.0

func _tick_support(unit: Dictionary, delta: float) -> void:
	if float(unit.cooldown) <= 0.0:
		var cast := false
		for ally in units:
			if ally.side == unit.side and ally.kind != "healer" and float(ally.hp) > 0.0 and abs(float(ally.x) - float(unit.x)) <= float(unit.range):
				ally.support_until = elapsed + SUPPORT_DURATION
				combat_events.append({"type": "SUPPORT_BUFF", "source_id": unit.id, "target_id": ally.id, "x": ally.x})
				cast = true
		if cast:
			unit.cooldown = SUPPORT_COOLDOWN
	var direction := 1.0 if int(unit.side) == 0 else -1.0
	var frontline = null
	for ally in units:
		if ally.side == unit.side and ally.kind != "healer" and float(ally.hp) > 0.0:
			if frontline == null or direction * float(ally.x) > direction * float(frontline.x):
				frontline = ally
	if frontline != null and direction * (float(frontline.x) - float(unit.x)) <= SUPPORT_FOLLOW_DISTANCE:
		return
	# Support units never attack units, buildings or bases, even with no wounded ally.
	var step := float(unit.speed) * _swamp_scale(unit) * delta
	if units.any(func(enemy): return enemy.side != unit.side and float(enemy.hp) > 0.0 and direction * (float(enemy.x) - float(unit.x)) >= 0.0 and abs(float(enemy.x) - float(unit.x)) <= max(float(unit.range), step)) or _blocking_wall(unit, float(unit.x) + direction * step) != null or _find_target(unit) != null:
		return
	var enemy_base_x := FIELD_RIGHT if int(unit.side) == 0 else FIELD_LEFT
	if abs(float(unit.x) - enemy_base_x) <= float(unit.range):
		return
	var destination := float(unit.x) + direction * step
	if frontline != null:
		var follow_x := float(frontline.x) - direction * SUPPORT_FOLLOW_DISTANCE
		destination = min(destination, follow_x) if direction > 0.0 else max(destination, follow_x)
	unit.x = clamp(destination, FIELD_LEFT, FIELD_RIGHT)


func _damage_target(attacker: Dictionary, target: Dictionary, damage: float) -> void:
	target.hp = max(0.0, float(target.hp) - damage)
	combat_events.append({"type": "ATTACK", "attacker_id": attacker.id, "target_id": target.id, "attack_kind": attacker.kind, "x": attacker.x})
	combat_events.append({"type": "DAMAGE", "target_id": target.id, "amount": damage, "x": target.x})

func _blocking_wall(attacker: Dictionary, target_x: float):
	var best = null
	var best_distance := INF
	var origin := float(attacker.x)
	for structure in structures:
		if int(structure.side) == int(attacker.side) or String(structure.kind) != "wall" or float(structure.hp) <= 0.0:
			continue
		var wall_x := float(structure.x)
		var between := (origin < wall_x and wall_x < target_x) or (target_x < wall_x and wall_x < origin)
		var distance: float = abs(wall_x - origin)
		if between and distance < best_distance:
			best = structure
			best_distance = distance
	return best

func _find_target(unit: Dictionary):
	var best_unit = null
	var best_distance := INF
	for enemy in units:
		if enemy.side == unit.side or enemy.hp <= 0.0:
			continue
		var distance: float = abs(float(enemy.x) - float(unit.x))
		if distance <= float(unit.range) and distance < best_distance:
			best_unit = enemy
			best_distance = distance
	if best_unit != null:
		var wall = _blocking_wall(unit, float(best_unit.x))
		if wall != null:
			return wall if abs(float(wall.x) - float(unit.x)) <= float(unit.range) + 12.0 else null
		return best_unit
	var best_structure = null
	best_distance = INF
	for structure in structures:
		if structure.side == unit.side or structure.hp <= 0.0:
			continue
		var distance: float = abs(float(structure.x) - float(unit.x))
		if distance <= float(unit.range) + 12.0 and distance < best_distance:
			var wall = _blocking_wall(unit, float(structure.x))
			best_structure = wall if wall != null else structure
			best_distance = abs(float(best_structure.x) - float(unit.x))
	return best_structure


func _tick_turrets(delta: float) -> void:
	for structure in structures:
		if String(structure.kind) != "turret" or float(structure.hp) <= 0.0:
			continue
		var id := int(structure.id)
		structure_cooldowns[id] = max(0.0, float(structure_cooldowns.get(id, STRUCTURE_STATS.turret.interval)) - delta)
		if structure_cooldowns[id] > 0.0:
			continue
		var target = null
		var nearest := INF
		for enemy in units:
			if int(enemy.side) == int(structure.side) or float(enemy.hp) <= 0.0:
				continue
			var enemy_distance: float = abs(float(enemy.x) - float(structure.x))
			if enemy_distance > float(STRUCTURE_STATS.turret.range):
				continue
			var wall = _blocking_wall(structure, float(enemy.x))
			var candidate = wall if wall != null else enemy
			var candidate_distance: float = abs(float(candidate.x) - float(structure.x))
			if candidate_distance < nearest:
				target = candidate
				nearest = candidate_distance
		if target != null:
			target.hp = max(0.0, float(target.hp) - float(STRUCTURE_STATS.turret.damage))
			combat_events.append({"type": "ATTACK", "attacker_id": id, "target_id": target.id, "attack_kind": "turret", "x": structure.x})
			combat_events.append({"type": "DAMAGE", "target_id": target.id, "amount": STRUCTURE_STATS.turret.damage, "x": target.x})
			structure_cooldowns[id] = float(STRUCTURE_STATS.turret.interval)

func _swamp_scale(unit: Dictionary) -> float:
	for structure in structures:
		if structure.kind == "swamp" and structure.side != unit.side and structure.hp > 0.0 and abs(float(structure.x) - float(unit.x)) <= float(STRUCTURE_STATS.swamp.radius):
			return float(STRUCTURE_STATS.swamp.speed_scale)
	return 1.0


func _emit_death_events() -> void:
	for unit in units:
		if float(unit.hp) <= 0.0 and not announced_deaths.has(unit.id):
			announced_deaths[unit.id] = true
			combat_events.append({"type": "DEATH", "unit_id": unit.id, "x": unit.x})
	for structure in structures:
		if float(structure.hp) <= 0.0 and not announced_structure_deaths.has(structure.id):
			announced_structure_deaths[structure.id] = true
			combat_events.append({"type": "STRUCTURE_DESTROYED", "structure_id": structure.id, "kind": structure.kind, "x": structure.x})

func drain_combat_events() -> Array:
	var result := combat_events.duplicate(true)
	combat_events.clear()
	return result

func snapshot() -> Dictionary:
	return {"resources": resources.duplicate(), "base_hp": base_hp.duplicate(), "units": units.duplicate(true), "structures": structures.duplicate(true), "winner": winner, "elapsed": elapsed}
