class_name BattleModel
extends RefCounted

const Localization = preload("res://scripts/Localization.gd")
const Report = preload("res://scripts/BattleReport.gd")
const GameData = preload("res://scripts/data/GameData.gd")

const WORLD_SCALE := 1.15
const WORLD_WIDTH := 1280.0 * WORLD_SCALE
const FIELD_LEFT := 90.0 * WORLD_SCALE
const FIELD_RIGHT := 1190.0 * WORLD_SCALE
const START_RESOURCE := 70.0
const MAX_RESOURCE := 180.0
const RESOURCE_RATE := 8.0
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
const SUPPORT_INCREMENT := 0.05
const SUPPORT_MAX_STACKS := 10
const SUPPORT_COOLDOWN := 4.0
const SUPPORT_FOLLOW_DISTANCE := 65.0
const CURSE_RADIUS := 45.0
const CURSE_DURATION := 5.0
# Cursed enemies (units, mages and turrets) recover their attacks this much slower.
const CURSE_SPEED_SCALE := 0.7
const SUMMON_INTERVAL := 5.0
# Live skeletons one necromancer may keep; a full summoner skips that cycle.
const MAX_SKELETONS_PER_NECROMANCER := 3
const RAGE_HP_FRACTION := 0.5
const RAGE_SPEED_MULTIPLIER := 1.5
const MAX_ACTIVE_UNITS := 4096 # both sides together: what one online snapshot carries (NetworkProtocol.MAX_SNAPSHOT_UNITS)
## Each side's share of the field: one side filling it never stops the other from fielding units.
const SIDE_UNIT_LIMIT := MAX_ACTIVE_UNITS / 2
## The first time a unit falls to half health it is thrown back this far, once: a losing front gets
## room to recover, so fights swing back and forth instead of grinding in place.
const KNOCKBACK_FRACTION := 0.5
const KNOCKBACK_DISTANCE := 100.0
## Each castle shoots the nearest enemy unit this close to it (a little past an archer's reach, short of a
## sniper's), harder the more health the castle has lost: a side that is being pushed back gets help at home.
const CASTLE_RANGE := 300.0
const CASTLE_INTERVAL := 1.5
const CASTLE_DAMAGE := 8.0
## Damage multiplier at zero castle health (1 at full health, linear in between).
const CASTLE_DESPERATION := 2.5
# Unit/structure numbers live in res://data/**.tres (see scripts/data/GameData.gd).
static var UNIT_STATS: Dictionary = GameData.unit_stats()
static var SUMMON_STATS: Dictionary = GameData.summon_stats()
static var STRUCTURE_STATS: Dictionary = GameData.structure_stats()
static var UNIT_NAMES: Dictionary = GameData.unit_names()
static var STRUCTURE_NAMES: Dictionary = GameData.structure_names()
## Cards per deck: this many units and this many tactic cards (structures and spells).
const DECK_SIZE := 4
## Replays recorded before decks grew to four cards still play.
const REPLAY_DECK_SIZES := [3, 4]
const DEFAULT_UNIT_DECK := ["shield", "swordsman", "archer", "healer"]
const DEFAULT_STRUCTURE_DECK := ["wall", "swamp", "turret", "generator"]

var resources: Array = [START_RESOURCE, START_RESOURCE]
var base_hp: Array = [BASE_MAX_HP, BASE_MAX_HP]
var base_max_hp: Array = [BASE_MAX_HP, BASE_MAX_HP]
## The living (and downed) units. With the native engine (native/, BattleCore) the units live there and this
## property hands out dictionaries on demand; changes made through them are read back before the next tick.
var units: Array:
	get:
		return _core.get_units() if _core != null else _units_store
	set(value):
		if _core != null:
			_core.set_units(value)
		else:
			_units_store = value
var _units_store: Array = []
## BattleCore (native battle engine) when available and built from these exact rules, else null (GDScript).
var _core = null
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
var curses: Array = []
var summon_timers: Dictionary = {}
var summon_owners: Dictionary = {}
# Units that already spent their one revive (trait "revive_delay" in data).
var revive_used: Dictionary = {}
## Units that already took their one knockback (id -> true).
var knocked_back: Dictionary = {}
## Spells (tactic cards with "spell" data): casts waiting to land, per-side cooldowns and uses, and the
## allies each side lost (newest last) that a resurrection can bring back.
var spell_casts: Array = []
var spell_cooldowns: Array = [{}, {}]
var spell_uses: Array = [{}, {}]
var fallen: Array = [[], []]
var next_cast_id := 1
## Cards each side may not use this battle (ranked bans: the opponent removed them before the match).
var banned: Array = [[], []]
## Run modifiers for each side (expedition relics, endless-defense boons): empty in every other mode. Keys are
## documented at modifier(); RunBoons.combine builds them. Part of a battle's setup, like campaign_levels.
var modifiers: Array = [{}, {}]
## Card upgrades (stars): units and structures gain this much health (units also damage) per star, spells
## recover this much faster per star, and two-star units cost this fraction of their price.
const STAR_STEP := 0.2
const STAR_SPELL_STEP := 0.15
const STAR_COST_SCALE := 0.9
const MODIFIER_KEYS := ["hp:", "damage:", "range:ranged", "cost:units", "spell_cooldown", "structure_hp", "knockback",
	"skill_cooldown:", "income", "capacity", "start", "skeleton_cap", "first_strike"]
## Units this close to the enemy a unit would hit count as the same spot: a tank among them is hit first.
const GUARD_SPOT := 20.0
## Endless defense: the wave side has no base to destroy; its units come forever until the defender falls.
var invulnerable_bases: Array = [false, false]
## How far each side's units march: side 0 never past advance_limit[0], side 1 never before advance_limit[1].
## Endless defense holds the defenders short of the wave side's spawn point.
var advance_limit: Array = [FIELD_RIGHT, FIELD_LEFT]
## Endless defense's spawn zone: this deep from its own edge a side's units can neither be targeted nor attack.
## Waves gather there out of reach, then march out together.
var shelter: Array = [0.0, 0.0]
## Formation: a side's units stop short of its advance_limit by role (tanks in front, other melee just behind
## them, ranged at a distance) instead of all standing on the same line.
var formation: Array = [false, false]
const FORMATION_MELEE := 35.0
## Mustering units wait this far inside the spawn zone's edge.
const MUSTER_INSET := 10.0
const FORMATION_RANGED_MIN := 60.0
const FORMATION_RANGED_MAX := 160.0
## The battle rules live only in the native engine (native/src, class BattleCore). A library is used only when
## it was built from the engine source this game data expects: its rules_hash() equals BattleRulesHash.HASH (a
## hash of that source, tools/update_rules_hash.py). Rule changes ship as a new library the updater downloads
## (ContentUpdater, user://native/<hash>/), so no app reinstall is needed; the copy shipped with the app is
## used while it still matches. The Linux server's updater puts its copy next to it (CATWAR_NATIVE_LIB).
const NATIVE_EXTENSION := "res://native/battle_native.gdextension"
const RulesHash = preload("res://scripts/BattleRulesHash.gd")
static var _native_ok := false

## This platform's library target ("android.arm64", "windows.x86_64", ...), or "" where there is none.
static func native_target() -> String:
	match OS.get_name():
		"Android": return "android.arm64" if OS.has_feature("arm64") else "android.arm32"
		"Windows": return "windows.x86_64"
		"Linux": return "linux.x86_64"
	return ""

static func native_library_file(target: String) -> String:
	return "libbattle_native.%s.%s" % [target, "dll" if target.begins_with("windows") else "so"]

## Where the updater keeps the library for these rules.
static func downloaded_native_path(target: String = native_target()) -> String:
	return "user://native/%s/%s" % [RulesHash.HASH, native_library_file(target)]

static func _native_matches() -> bool:
	return ClassDB.class_exists("BattleCore") and String(ClassDB.instantiate("BattleCore").rules_hash()) == RulesHash.HASH

static func _load_native_file(path: String, target: String) -> void:
	var config := "user://battle_native_%s.gdextension" % target
	var file := FileAccess.open(config, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("[configuration]\nentry_symbol = \"battle_native_init\"\ncompatibility_minimum = \"4.5\"\n\n[libraries]\n%s = \"%s\"\n" % [target, path.c_escape()])
	file.close()
	GDExtensionManager.load_extension(config)

static func native_available() -> bool:
	if _native_ok:
		return true
	var target := native_target()
	var downloaded := downloaded_native_path(target)
	var server_copy := OS.get_environment("CATWAR_NATIVE_LIB")
	if not ClassDB.class_exists("BattleCore") and FileAccess.file_exists(NATIVE_EXTENSION):
		GDExtensionManager.load_extension(NATIVE_EXTENSION)
	if not _native_matches() and (FileAccess.file_exists(downloaded) or (not server_copy.is_empty() and FileAccess.file_exists(server_copy))):
		# The app's own copy (loaded at start) is from older rules: swap in the downloaded one.
		for loaded in GDExtensionManager.get_loaded_extensions():
			GDExtensionManager.unload_extension(loaded)
		_load_native_file(ProjectSettings.globalize_path(downloaded) if FileAccess.file_exists(downloaded) else server_copy, target)
	_native_ok = _native_matches()
	return _native_ok

func _init() -> void:
	if native_available():
		_core = ClassDB.instantiate("BattleCore")
		if not _core.configure(UNIT_STATS, SUMMON_STATS, STRUCTURE_STATS, Report.KINDS, native_constants()):
			push_error("BattleModel: the battle engine rejected this game data")
			_core = null

## The constants the engine's rules use, handed over at run time: changing their values (balance) needs no new
## engine.
static func native_constants() -> Dictionary:
	return {
		"FIELD_LEFT": FIELD_LEFT,
		"FIELD_RIGHT": FIELD_RIGHT,
		"MIN_ATTACK_INTERVAL": MIN_ATTACK_INTERVAL,
		"SUPPORT_INCREMENT": SUPPORT_INCREMENT,
		"SUPPORT_COOLDOWN": SUPPORT_COOLDOWN,
		"SUPPORT_FOLLOW_DISTANCE": SUPPORT_FOLLOW_DISTANCE,
		"CURSE_RADIUS": CURSE_RADIUS,
		"CURSE_DURATION": CURSE_DURATION,
		"CURSE_SPEED_SCALE": CURSE_SPEED_SCALE,
		"SUMMON_INTERVAL": SUMMON_INTERVAL,
		"RAGE_HP_FRACTION": RAGE_HP_FRACTION,
		"RAGE_SPEED_MULTIPLIER": RAGE_SPEED_MULTIPLIER,
		"KNOCKBACK_FRACTION": KNOCKBACK_FRACTION,
		"KNOCKBACK_DISTANCE": KNOCKBACK_DISTANCE,
		"CASTLE_RANGE": CASTLE_RANGE,
		"CASTLE_INTERVAL": CASTLE_INTERVAL,
		"CASTLE_DAMAGE": CASTLE_DAMAGE,
		"CASTLE_DESPERATION": CASTLE_DESPERATION,
		"GUARD_SPOT": GUARD_SPOT,
		"FORMATION_MELEE": FORMATION_MELEE,
		"MUSTER_INSET": MUSTER_INSET,
		"FORMATION_RANGED_MIN": FORMATION_RANGED_MIN,
		"FORMATION_RANGED_MAX": FORMATION_RANGED_MAX,
		"SUPPORT_MAX_STACKS": SUPPORT_MAX_STACKS,
		"MAX_SKELETONS_PER_NECROMANCER": MAX_SKELETONS_PER_NECROMANCER,
		"SIDE_UNIT_LIMIT": SIDE_UNIT_LIMIT,
		"MAX_FALLEN": MAX_FALLEN,
	}

## Whether this battle runs on the native engine.
func is_native() -> bool:
	return _core != null
## Units that already made their first attack (for the "first_strike" modifier).
var first_struck: Dictionary = {}
## Cheats switched on per side (super accounts; see Cheats.gd): "resources", "cooldowns", "castle".
var cheats: Array = [{}, {}]
## Stats a cheat toggle replaced (unit id -> {"damage" | "speed": original}), restored when it is switched off.
var cheat_saved: Dictionary = {}
## Seconds until each castle may shoot again.
var castle_cooldowns: Array = [CASTLE_INTERVAL, CASTLE_INTERVAL]
const MAX_FALLEN := 40
var battle_report: Array = [Report.empty_side(),Report.empty_side()]

## What one cleared campaign stage adds (first clear only).
const CAMPAIGN_STAT_STEP := 0.03
const CAMPAIGN_INCOME_STEP := 0.5
const CAMPAIGN_CAPACITY_STEP := 10.0
const CAMPAIGN_START_STEP := 5.0

static func campaign_bonuses(cleared_stages: int) -> Dictionary:
	var levels := clampi(cleared_stages, 0, 8)
	return {"levels": levels, "stat_scale": 1.0 + levels * CAMPAIGN_STAT_STEP,
		"income": RESOURCE_RATE + levels * CAMPAIGN_INCOME_STEP, "capacity": MAX_RESOURCE + levels * CAMPAIGN_CAPACITY_STEP,
		"starting_resources": START_RESOURCE + levels * CAMPAIGN_START_STEP}

static func campaign_reward_text() -> String:
	return Localization.text("첫 클리어 보상 · 병력 +%d%% · 자원 +%s/초 · 보유 +%d · 시작 +%d") % [roundi(CAMPAIGN_STAT_STEP * 100.0), str(CAMPAIGN_INCOME_STEP), int(CAMPAIGN_CAPACITY_STEP), int(CAMPAIGN_START_STEP)]

func configure_campaign_growth(side: int, cleared_stages: int) -> void:
	if side < 0 or side > 1:
		return
	campaign_levels[side] = clampi(cleared_stages, 0, 8)
	resources[side] = starting_resources(side)

func resource_capacity(side: int) -> float:
	return float(campaign_bonuses(int(campaign_levels[side])).capacity) + float(modifier(side, "capacity", 0.0))

func resource_income(side: int) -> float:
	return float(campaign_bonuses(int(campaign_levels[side])).income) + float(modifier(side, "income", 0.0))

func starting_resources(side: int) -> float:
	return minf(resource_capacity(side), float(campaign_bonuses(int(campaign_levels[side])).starting_resources) + float(modifier(side, "start", 0.0)))

## Applies run modifiers to `side` and refreshes its starting resources.
func configure_modifiers(side: int, values: Dictionary) -> void:
	if side < 0 or side > 1:
		return
	modifiers[side] = values.duplicate(true)
	resources[side] = starting_resources(side)

## A run modifier of `side`. Multipliers default to 1, additions to 0:
##   "hp:<scope>", "damage:<scope>"  unit health/damage multiplier; scope "all", "melee", "ranged" or a unit kind
##   "range:ranged"                  extra range for ranged units
##   "cost:units"                    unit cost multiplier
##   "spell_cooldown", "structure_hp", "knockback", "skill_cooldown:<kind>"   multipliers
##   "income", "capacity", "start", "skeleton_cap"                             additions
##   "first_strike"                  > 0: each unit's first attack deals double damage
##   "stars": {kind: level}          card upgrades: units +20% health and damage per level (cost -10% at 2),
##                                   structures +20% health per level, spells -15% cooldown per level
func modifier(side: int, key: String, fallback = 1.0):
	return modifiers[side].get(key, fallback) if side >= 0 and side < 2 else fallback

## Whether `values` is a well-formed modifier set (replays and saved runs come from files).
static func valid_modifiers(values: Variant) -> bool:
	if not values is Dictionary or values.size() > 64:
		return false
	for key in values:
		if not key is String:
			return false
		var value = values[key]
		if key == "stars":
			if not value is Dictionary or value.size() > 32:
				return false
			for kind in value:
				if not kind is String or not (UNIT_STATS.has(kind) or STRUCTURE_STATS.has(kind)):
					return false
				if not (value[kind] is int or value[kind] is float) or float(value[kind]) < 0.0 or float(value[kind]) > 2.0 or float(value[kind]) != floorf(float(value[kind])):
					return false
			continue
		if not MODIFIER_KEYS.any(func(prefix): return key == prefix or (prefix.ends_with(":") and key.begins_with(prefix))):
			return false
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < -1000.0 or float(value) > 1000.0:
			return false
		if not key in ["income", "capacity", "start", "skeleton_cap", "range:ranged"] and float(value) < 0.0:
			return false
	return true

func card_level(side: int, kind: String) -> int:
	var stars = modifier(side, "stars", {})
	return clampi(int(stars.get(kind, 0)), 0, 2) if stars is Dictionary else 0

## Melee: reach up to 60. Ranged: 200 and more. Support and summoners are neither.
static func unit_scope(kind: String) -> String:
	var reach := float(UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {})).get("range", 0.0))
	return "melee" if reach <= 60.0 else ("ranged" if reach >= 200.0 else "")

## Combined health or damage multiplier of `side`'s modifiers for `kind` (stat: "hp" or "damage").
func unit_modifier(side: int, kind: String, stat: String) -> float:
	var value := float(modifier(side, stat + ":all")) * float(modifier(side, stat + ":" + kind))
	var scope := unit_scope(kind)
	if not scope.is_empty():
		value *= float(modifier(side, stat + ":" + scope))
	return value * (1.0 + STAR_STEP * card_level(side, kind))

func unit_cost(side: int, kind: String) -> float:
	var cost := float(UNIT_STATS[kind].cost) * float(modifier(side, "cost:units"))
	if card_level(side, kind) >= 2:
		cost *= STAR_COST_SCALE
	return roundf(cost)

func configure_base_health(side: int, maximum: float) -> void:
	if side < 0 or side > 1 or not is_finite(maximum) or maximum <= 0.0:
		return
	base_max_hp[side] = minf(BASE_MAX_HP, maximum)
	base_hp[side] = base_max_hp[side]

func reset() -> void:
	resources = [starting_resources(0), starting_resources(1)]
	base_hp = base_max_hp.duplicate()
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
	curses.clear()
	summon_timers.clear()
	summon_owners.clear()
	revive_used.clear()
	knocked_back.clear()
	first_struck.clear()
	spell_casts.clear()
	spell_cooldowns = [{}, {}]
	spell_uses = [{}, {}]
	fallen = [[], []]
	next_cast_id = 1
	banned = [[], []]
	battle_report = [Report.empty_side(),Report.empty_side()]

static func _valid_deck(values: Array, allowed: Dictionary, sizes: Array = [DECK_SIZE]) -> bool:
	if not sizes.has(values.size()):
		return false
	var unique := {}
	for value in values:
		var kind := String(value)
		if not allowed.has(kind) or unique.has(kind):
			return false
		unique[kind] = true
	return true

func configure_deck(side: int, selected_units: Array, selected_structures: Array) -> bool:
	if side < 0 or side > 1 or not _valid_deck(selected_units, UNIT_STATS, REPLAY_DECK_SIZES) or not _valid_deck(selected_structures, STRUCTURE_STATS, REPLAY_DECK_SIZES):
		return false
	unit_decks[side] = selected_units.duplicate()
	structure_decks[side] = selected_structures.duplicate()
	return true

func spawn_unit(side: int, kind: String) -> bool:
	if winner != -1 or side < 0 or side > 1 or side_full(side) or not UNIT_STATS.has(kind) or not unit_decks[side].has(kind) or banned[side].has(kind):
		return false
	if field_limit(kind) > 0 and (_core.fielded(side, kind) if _core != null else _fielded(units, side, kind)) >= field_limit(kind) and not cheats[side].has("no_cap"):
		return false
	var stats: Dictionary = UNIT_STATS[kind]
	var stat_scale := float(campaign_bonuses(int(campaign_levels[side])).stat_scale)
	var cost := unit_cost(side, kind)
	if resources[side] < cost or float(spawn_cooldowns[side].get(kind, 0.0)) > 0.0:
		return false
	resources[side] -= cost
	battle_report[side].resources_spent += cost
	battle_report[side].units[kind].purchased += 1
	spawn_cooldowns[side][kind] = float(trait_value(kind, "card_cooldown", 0.35))
	var hp_scale := stat_scale * unit_modifier(side, kind, "hp")
	var damage_scale := stat_scale * unit_modifier(side, kind, "damage")
	var spawn_x := FIELD_LEFT + 35.0 if side == 0 else FIELD_RIGHT - 35.0
	var arrival = trait_value(kind, "arrival_stall")
	if arrival != null:
		# Arrives in front of the enemy's foremost structure (the one nearest this side), if it has any.
		var direction := 1.0 if side == 0 else -1.0
		var front = null
		for structure in structures:
			if int(structure.side) != side and float(structure.hp) > 0.0 and (front == null or direction * float(structure.x) < direction * float(front.x)):
				front = structure
		if front != null:
			spawn_x = float(front.x) - direction * 30.0
	_create_unit(side, kind, stats, hp_scale, damage_scale, spawn_x)
	if arrival != null:
		var arrived: Dictionary = last_unit()
		arrived["stall_remaining"] = float(arrival)
		combat_events.append({"type": "ARRIVAL", "unit_id": arrived.id, "x": arrived.x})
	var escort = trait_value(kind, "escort_kind")
	if escort != null:
		# A leader arrives with its escort: summons that march with it (see "leaderless_damage").
		var leader: Dictionary = last_unit()
		var direction := 1.0 if side == 0 else -1.0
		for index in int(trait_value(kind, "escort_count", 0)):
			if side_full(side):
				break
			_create_unit(side, String(escort), SUMMON_STATS[String(escort)], hp_scale, damage_scale, spawn_x + direction * (16.0 + 14.0 * index))
			summon_owners[last_unit().id] = leader.id
			battle_report[side].units[kind].summoned += 1
		combat_events.append({"type": "ESCORT", "source_id": leader.id, "x": leader.x})
	return true

func _create_unit(side: int, kind: String, stats: Dictionary, hp_scale: float, damage_scale: float, x: float) -> void:
	var unit := {"id": next_unit_id, "side": side, "kind": kind,
		"x": clampf(x, FIELD_LEFT, FIELD_RIGHT),
		"hp": stats.hp * hp_scale, "max_hp": stats.hp * hp_scale, "damage": stats.damage * damage_scale,
		"heal": stats.get("heal", 0.0) * damage_scale, "interval": stats.interval,
		"cooldown": 0.0 if kind == "healer" else max(MIN_ATTACK_INTERVAL, float(stats.interval)),
		"support_stacks": 0,
		"speed": stats.speed, "range": float(stats.range) + (float(modifier(side, "range:ranged", 0.0)) if unit_scope(kind) == "ranged" else 0.0)}
	if kind == "necromancer":
		summon_timers[next_unit_id] = SUMMON_INTERVAL
		unit["summon_remaining"] = SUMMON_INTERVAL
	if trait_value(kind, "skill_cooldown") != null:
		unit["skill_remaining"] = float(trait_value(kind, "skill_cooldown"))
	if trait_value(kind, "soul_max") != null:
		unit["souls"] = 0
	if trait_value(kind, "blink_cooldown") != null:
		unit["blink_remaining"] = float(trait_value(kind, "blink_cooldown"))
	if _core != null:
		_core.append_unit(unit)
	else:
		units.append(unit)
	next_unit_id += 1

static func unit_stat_summary(kind: String, growth_level: int = 0) -> String:
	if not UNIT_STATS.has(kind) and not SUMMON_STATS.has(kind):
		return ""
	var stats: Dictionary = UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {}))
	# MIN_ATTACK_INTERVAL only delays a new unit's first attack; afterwards it attacks every `interval`.
	var interval := float(stats.interval)
	var stat_scale := float(campaign_bonuses(growth_level).stat_scale)
	var output := Localization.text("비용 %d  ·  체력 %d\n") % [int(stats.cost), int(stats.hp * stat_scale)]
	if bool(stats.get("summon_only", false)) or SUMMON_STATS.has(kind):
		output = "소환 전용  ·  체력 %d\n" % int(stats.hp * stat_scale)
	var support_step := roundi(SUPPORT_INCREMENT * 100.0)
	var support_cap := roundi(SUPPORT_INCREMENT * SUPPORT_MAX_STACKS * 100.0)
	if kind == "healer":
		return output + Localization.text("피해·회복 없음  ·  공속 +%d%% 영구 누적\n범위 %d  ·  쿨 %d초  ·  상한 +%d%%\n유닛 사망·전투 종료 시 초기화  ·  이동 %d") % [support_step, int(stats.range), int(stats.interval), support_cap, int(stats.speed)]
	else:
		output += Localization.text("공격력 %d  ·  DPS %.1f\n") % [int(stats.damage * stat_scale), float(stats.damage) * stat_scale / interval]
	output += Localization.text("공격 간격 %.2f초  ·  사거리 %d  ·  이동 %d") % [interval, int(stats.range), int(stats.speed)]
	if kind == "berserker":
		output += "\n체력 %d%% 이하: 공속 +%d%% · 공격력 %d" % [roundi(RAGE_HP_FRACTION * 100.0), roundi((RAGE_SPEED_MULTIPLIER - 1.0) * 100.0), int(float(stats.damage) * stat_scale)]
	elif kind == "warlock":
		output += "\n공격 대상에 반경 %d 장판 · 적 공속 -%d%%\n%d초 유지 · 시전자당 1개 · 중첩 없음 · 포탑 포함" % [int(CURSE_RADIUS), roundi((1.0 - CURSE_SPEED_SCALE) * 100.0), int(CURSE_DURATION)]
	elif kind == "necromancer":
		var skeleton: Dictionary = SUMMON_STATS.skeleton
		output += "\n%d초마다 해골 소환 · 최대 %d기 유지 · 추가 자원 없음\n해골 체력 %d · 공격 %d · 사거리 %d" % [int(SUMMON_INTERVAL), MAX_SKELETONS_PER_NECROMANCER, int(float(skeleton.hp) * stat_scale), int(float(skeleton.damage) * stat_scale), int(skeleton.range)]
	if trait_value(kind, "skill_cooldown") != null:
		output += "\n%d초마다 %s · 반경 %d 적 전체 피해 %d" % [int(trait_value(kind, "skill_cooldown")), skill_name(kind), int(trait_value(kind, "skill_radius", 0.0)), int(float(trait_value(kind, "skill_damage", 0.0)) * stat_scale)]
		if trait_value(kind, "skill_knockback") != null:
			output += " · %d만큼 밀쳐냄" % int(trait_value(kind, "skill_knockback"))
	if trait_value(kind, "soul_max") != null:
		output += "\n영혼 수확 · 반경 %d 안의 적이 쓰러질 때마다 체력 %d%% 회복\n영혼 1개당 공격력 +%d%% · 최대 %d개 (+%d%%)" % [int(trait_value(kind, "soul_radius", 0.0)), roundi(float(trait_value(kind, "soul_heal_fraction", 0.0)) * 100.0), roundi(float(trait_value(kind, "soul_damage_step", 0.0)) * 100.0), int(trait_value(kind, "soul_max")), roundi(float(trait_value(kind, "soul_damage_step", 0.0)) * float(trait_value(kind, "soul_max")) * 100.0)]
	if trait_value(kind, "blast_radius") != null:
		output += "\n적·방벽·성에 닿으면 자폭 · 반경 %d 안의 모든 유닛에 공격력만큼 피해 (아군 포함)\n적 구조물과 성에는 %d" % [int(trait_value(kind, "blast_radius")), int(float(trait_value(kind, "blast_structure_damage", 0.0)) * stat_scale)]
	if trait_value(kind, "blink_cooldown") != null:
		output += "\n%d초마다 앞쪽 %d 안의 가장 깊숙한 적 곁으로 순간이동\n이동 직후 %.1f초 멈춤 · 다음 공격 피해 ×%.0f" % [int(trait_value(kind, "blink_cooldown")), int(trait_value(kind, "blink_range", 0.0)), float(trait_value(kind, "blink_stall", 0.0)), float(trait_value(kind, "blink_bonus", 1.0))]
	if trait_value(kind, "control_weakness") != null:
		output += "\n늪·빙결 효과를 %.1f배로 받음 (기마)" % float(trait_value(kind, "control_weakness"))
	if trait_value(kind, "escort_kind") != null:
		var escort := String(trait_value(kind, "escort_kind"))
		var guard: Dictionary = SUMMON_STATS[escort]
		output += "\n소환할 때 %s %d기 동행 · 체력 %d · 공격력 %d\n%s이 쓰러지면 %s 공격력 -%d%%" % [UNIT_NAMES.get(escort, escort), int(trait_value(kind, "escort_count", 0)), int(float(guard.hp) * stat_scale), int(float(guard.damage) * stat_scale), UNIT_NAMES.get(kind, kind), UNIT_NAMES.get(escort, escort), roundi((1.0 - float(guard.get("leaderless_damage", 1.0))) * 100.0)]
	if trait_value(kind, "aura_radius") != null:
		output += "\n반경 %d 안의 아군(자신 포함) 공속 +%d%% · 주인공끼리 중복 없음\n마법사 지원과 합쳐 최대 +%d%%" % [int(trait_value(kind, "aura_radius")), roundi(float(trait_value(kind, "aura_attack_speed", 0.0)) * 100.0), roundi(float(trait_value(kind, "aura_cap", 0.0)) * 100.0)]
	if trait_value(kind, "plunder_fraction") != null:
		output += "\n적 유닛을 처치하면 그 비용의 %d%%(최대 %d)를 상대 자원에서 빼앗음\n약탈 후 %d초 대기 · 소환 유닛은 대상 아님" % [roundi(float(trait_value(kind, "plunder_fraction")) * 100.0), int(trait_value(kind, "plunder_cap", 0.0)), int(trait_value(kind, "plunder_cooldown", 0.0))]
	if trait_value(kind, "gift_kinds") != null:
		output += "\n처치한 적의 능력 하나를 얻음 (마지막 것만 유지)\n%s" % " · ".join(PackedStringArray(Array(trait_value(kind, "gift_kinds")).map(func(gift): return {"berserker": "광전사: 광폭화", "zombie": "좀비: 1회 부활", "paladin": "성기사: 언데드·마족 추가 피해"}.get(gift, gift))))
	if trait_value(kind, "arrival_stall") != null:
		output += "\n적 구조물 중 가장 앞의 것 바로 앞에 등장 (없으면 기지에서 출발)\n등장 후 %.1f초 행동 불가 · 다시 소환까지 %d초" % [float(trait_value(kind, "arrival_stall")), int(trait_value(kind, "card_cooldown", 0.0))]
	if trait_value(kind, "convert_radius") != null:
		output += "\n반경 %d 안에서 쓰러진 비용 %d 이하 적을 아군으로 일으킴 (체력 %d%%)\n동시에 %d기까지 · %d초마다 · 군주·소환 유닛 제외" % [int(trait_value(kind, "convert_radius")), int(trait_value(kind, "convert_max_cost", 0.0)), roundi(float(trait_value(kind, "convert_hp", 0.5)) * 100.0), int(trait_value(kind, "convert_limit", 0)), int(trait_value(kind, "convert_cooldown", 0.0))]
	if field_limit(kind) > 0:
		output += "\n전장에 %d기만 둘 수 있음" % field_limit(kind)
	if trait_value(kind, "undead_bonus") != null:
		output += "\n%s에게 피해 ×%.1f · 처치한 언데드는 부활하지 못함" % ["·".join(PackedStringArray(smite_tags(kind).map(func(tag): return TAG_NAMES.get(tag, tag)))), float(trait_value(kind, "undead_bonus"))]
	if trait_value(kind, "target_rearmost", false):
		output += "\n사거리 안에서 가장 뒤에 있는 적을 노림 · 방벽 너머 저격"
	if can_revive(kind):
		output += "\n첫 사망 시 %.0f초 뒤 체력 %d%%로 1회 부활 · 쓰러진 동안 공격받지 않음" % [float(trait_value(kind, "revive_delay")), roundi(float(trait_value(kind, "revive_hp_fraction", 0.5)) * 100.0)]
	if has_tag(kind, "undead"):
		output += "\n언데드"
	if has_tag(kind, "demon"):
		output += "\n마족"
	return output

## One-line role description shown on deck cards. Numbers come from the rule constants/data.
static func unit_role(kind: String) -> String:
	match kind:
		"healer": return Localization.text("공격속도 지원")
		"archer": return Localization.text("원거리")
		"shield": return Localization.text("방어 · 먼저 맞음")
		"swordsman": return Localization.text("근접 공격")
		"berserker": return Localization.text("%d%% 이하 광폭화") % roundi(RAGE_HP_FRACTION * 100.0)
		"warlock": return Localization.text("공속 -%d%% 장판") % roundi((1.0 - CURSE_SPEED_SCALE) * 100.0)
		"paladin": return Localization.text("%d초 십자가") % int(trait_value(kind, "skill_cooldown"))
		"sniper": return Localization.text("맨 뒤의 적 저격")
		"zombie": return Localization.text("%d%%로 1회 부활") % roundi(float(trait_value(kind, "revive_hp_fraction", 0.5)) * 100.0)
		"necromancer": return Localization.text("%d초 해골 소환 ·%d") % [int(SUMMON_INTERVAL), MAX_SKELETONS_PER_NECROMANCER]
		"demon_lord": return Localization.text("영혼 수확 · %d초 포효") % int(trait_value(kind, "skill_cooldown"))
		"general": return Localization.text("기마 · 빠른 공격")
		"bomber": return Localization.text("닿으면 자폭")
		"joker": return Localization.text("%d초 순간이동 ×%.0f") % [int(trait_value(kind, "blink_cooldown")), float(trait_value(kind, "blink_bonus", 1.0))]
		"king": return Localization.text("근위병 %d기 동행") % int(trait_value(kind, "escort_count", 0))
		"hero": return Localization.text("주변 공속 +%d%%") % roundi(float(trait_value(kind, "aura_attack_speed", 0.0)) * 100.0)
		"raider": return Localization.text("처치 시 자원 약탈")
		"preacher": return Localization.text("적 능력 흡수")
		"psychic": return Localization.text("적 구조물 앞 등장")
		"shaman": return Localization.text("쓰러진 적을 아군으로")
	return ""

## One-line description of a tactic card (structure or spell) for deck and battle cards.
static func tactic_role(kind: String) -> String:
	var stats: Dictionary = STRUCTURE_STATS.get(kind, {})
	match kind:
		"wall": return Localization.text("뒤 대상을 차폐 · 최대 %d") % int(stats.max_count)
		"swamp": return Localization.text("반경 %d · %d%% 감속 · %d초") % [int(stats.radius), roundi((1.0 - float(stats.speed_scale)) * 100.0), int(stats.lifetime)]
		"turret": return Localization.text("사거리 %d · 최대 %d") % [int(stats.range), int(stats.max_count)]
		"generator": return Localization.text("후방 전용 · 초당 +%d") % int(stats.income)
		"lightning": return Localization.text("반경 %d 안 가장 튼튼한 적 1기에 %d 피해") % [int(stats.radius), int(stats.damage)]
		"fireball": return Localization.text("반경 %d 적 전체 %d 피해") % [int(stats.radius), int(stats.damage)]
		"frost": return Localization.text("반경 %d 적 %.1f초 정지") % [int(stats.radius), float(stats.duration)]
		"blessing": return Localization.text("반경 %d 아군 체력 %d%% 회복 · 공속 +%d%% %d초") % [int(stats.radius), roundi(float(stats.get("heal_fraction", 0.0)) * 100.0), roundi((float(stats.attack_speed) - 1.0) * 100.0), int(stats.duration)]
		"seraph": return Localization.text("쓰러진 아군 %d명 %d%%로 부활 · 판당 %d회") % [int(stats.revive_count), roundi(float(stats.revive_fraction) * 100.0), int(stats.max_uses)]
	return ""

## Second line of a spell's battle card: cooldown, and where it can be used.
static func spell_card_note(kind: String) -> String:
	var stats: Dictionary = STRUCTURE_STATS[kind]
	return Localization.text("쿨 %d초%s") % [int(stats.cooldown), " · 우리 진영" if String(stats.get("zone", "any")) == "own" else ""]

## Short swamp description for battle cards, e.g. "80% 감속 · 5초".
static func swamp_summary() -> String:
	var swamp: Dictionary = STRUCTURE_STATS.swamp
	return Localization.text("%d%% 감속 · %d초") % [roundi((1.0 - float(swamp.speed_scale)) * 100.0), int(swamp.lifetime)]

static func battle_stat_summary() -> String:
	var wall: Dictionary = STRUCTURE_STATS.wall
	var swamp: Dictionary = STRUCTURE_STATS.swamp
	var turret: Dictionary = STRUCTURE_STATS.turret
	var generator: Dictionary = STRUCTURE_STATS.generator
	var healer: Dictionary = UNIT_STATS.healer
	var structures_line := Localization.text("구조물  ·  방벽 %d/체력 %d  ·  늪 %d/%d%% 감속/%d초\n포탑 %d/체력 %d/공격 %d/사거리 %d  ·  발전기 %d/체력 %d/+%d 자원") % [
		int(wall.cost), int(wall.hp), int(swamp.cost), roundi((1.0 - float(swamp.speed_scale)) * 100.0), int(swamp.lifetime),
		int(turret.cost), int(turret.hp), int(turret.damage), int(turret.range), int(generator.cost), int(generator.hp), int(generator.income)]
	var support_line := Localization.text("마법사  ·  피해·회복 없음/공속 +%d%% 영구 누적/범위 %d/쿨 %d초/상한 +%d%%") % [roundi(SUPPORT_INCREMENT * 100.0), int(healer.range), int(healer.interval), roundi(SUPPORT_INCREMENT * SUPPORT_MAX_STACKS * 100.0)]
	var field_line := Localization.text("전장  ·  길이 +%d%%  ·  기지 체력 %d  ·  자원 +%.0f/초  ·  최대 %.0f  ·  구조물 진영당 %d개  ·  시간 제한 없음") % [roundi((WORLD_SCALE - 1.0) * 100.0), int(BASE_MAX_HP), RESOURCE_RATE, MAX_RESOURCE, STRUCTURE_LIMIT]
	return structures_line + "\n" + support_line + "\n" + field_line

## Shared by authoritative placement, online previews and purchase cards.
## Destroyed structures can remain in a snapshot until the next cleanup tick.
## Whether structure `kind` can be attacked (the swamp cannot: it has no health and only expires).
static func has_health(kind: String) -> bool:
	return float(STRUCTURE_STATS.get(kind, {}).get("hp", 0.0)) > 0.0

static func structure_counts(values: Array, side: int) -> Dictionary:
	var counts := {"total": 0, "kinds": {}}
	for structure in values:
		if int(structure.side) != side or float(structure.get("hp", 1.0)) <= 0.0:
			continue
		var kind := String(structure.kind)
		counts.total += 1
		counts.kinds[kind] = int(counts.kinds.get(kind, 0)) + 1
	return counts

static func structure_limit_error(kind: String, counts: Dictionary) -> String:
	if not STRUCTURE_STATS.has(kind):
		return Localization.text("설치할 수 없는 구조물입니다.")
	if int(counts.total) >= STRUCTURE_LIMIT:
		return Localization.text("구조물은 최대 %d개까지 설치할 수 있습니다.") % STRUCTURE_LIMIT
	var max_count := int(STRUCTURE_STATS[kind].get("max_count", STRUCTURE_LIMIT))
	if int(counts.kinds.get(kind, 0)) < max_count:
		return ""
	if kind == "turret":
		return Localization.text("포탑은 %d개만 설치할 수 있습니다.") % max_count
	if kind == "generator":
		return Localization.text("발전기는 %d개만 설치할 수 있습니다.") % max_count
	if kind == "wall":
		return Localization.text("방벽은 %d개만 설치할 수 있습니다.") % max_count
	return Localization.text("같은 종류의 구조물은 %d개까지 설치할 수 있습니다.") % max_count

func _owned_structure_count(side: int, kind: String = "") -> int:
	var count := 0
	for structure in structures:
		if int(structure.side) == side and (kind.is_empty() or String(structure.kind) == kind) and float(structure.hp) > 0.0:
			count += 1
	return count

# ---------- spells ----------

static func is_spell(kind: String) -> bool:
	return bool(STRUCTURE_STATS.get(kind, {}).get("spell", false))

## Where a tactic card may be used: [lower, upper] world x. Spells marked "own" and structures use the
## build zone (generators only its rear); other spells reach the whole field.
static func tactic_zone(side: int, kind: String) -> Array:
	if is_spell(kind) and String(STRUCTURE_STATS[kind].get("zone", "any")) != "own":
		return [FIELD_LEFT, FIELD_RIGHT]
	var lower := BLUE_BUILD_MIN if side == 0 else RED_BUILD_MIN
	var upper := BLUE_BUILD_MAX if side == 0 else RED_BUILD_MAX
	if kind == "generator":
		if side == 0: upper = BLUE_REAR_MAX
		else: lower = RED_REAR_MIN
	return [lower, upper]

## Shared by the model and the battle cards: why spell `kind` cannot be cast now, or "".
## `cooldowns` and `uses` are one side's spell_cooldowns / spell_uses.
static func spell_error(kind: String, cooldowns: Dictionary, uses: Dictionary) -> String:
	var name := String(STRUCTURE_NAMES.get(kind, kind))
	var remaining := float(cooldowns.get(kind, 0.0))
	if remaining > 0.0:
		return Localization.text("%s은(는) %d초 뒤에 다시 쓸 수 있습니다.") % [name, ceili(remaining)]
	var limit := int(STRUCTURE_STATS[kind].get("max_uses", 0))
	if limit > 0 and int(uses.get(kind, 0)) >= limit:
		return Localization.text("%s은(는) 한 전투에 %d번만 쓸 수 있습니다.") % [name, limit]
	return ""

func _cast_spell(side: int, kind: String, x: float) -> void:
	var stats: Dictionary = STRUCTURE_STATS[kind]
	resources[side] -= float(stats.cost)
	battle_report[side].resources_spent += float(stats.cost)
	spell_cooldowns[side][kind] = float(stats.get("cooldown", 0.0)) * float(modifier(side, "spell_cooldown")) * (1.0 - STAR_SPELL_STEP * card_level(side, kind))
	spell_uses[side][kind] = int(spell_uses[side].get(kind, 0)) + 1
	var delay := float(stats.get("delay", 0.0))
	if stats.has("speed"):
		# Thrown from the caster's base: farther targets land later.
		delay += absf(x - (FIELD_LEFT if side == 0 else FIELD_RIGHT)) / float(stats.speed)
	spell_casts.append({"id": next_cast_id, "side": side, "kind": kind, "x": x, "lands_at": elapsed + delay})
	combat_events.append({"type": "SPELL_CAST", "cast_id": next_cast_id, "side": side, "kind": kind, "x": x, "delay": delay})
	next_cast_id += 1

func structure_placement_error(side: int, kind: String, x: float) -> String:
	if winner != -1 or side < 0 or side > 1 or not STRUCTURE_STATS.has(kind):
		return Localization.text("설치할 수 없는 구조물입니다.")
	if not structure_decks[side].has(kind):
		return Localization.text("현재 덱에 없는 구조물입니다.")
	if banned[side].has(kind):
		return Localization.text("이번 경기에서 금지된 카드입니다.")
	if is_spell(kind):
		var zone := tactic_zone(side, kind)
		if not is_finite(x) or x < float(zone[0]) or x > float(zone[1]):
			return Localization.text("자신의 진영에만 쓸 수 있습니다.") if String(STRUCTURE_STATS[kind].get("zone", "any")) == "own" else Localization.text("전장 안에만 쓸 수 있습니다.")
		var spell_problem := spell_error(kind, spell_cooldowns[side], spell_uses[side])
		if not spell_problem.is_empty():
			return spell_problem
		if resources[side] < float(STRUCTURE_STATS[kind].cost):
			return Localization.text("자원이 부족합니다.")
		return ""
	var valid_zone := (side == 0 and x >= BLUE_BUILD_MIN and x <= BLUE_BUILD_MAX) or (side == 1 and x >= RED_BUILD_MIN and x <= RED_BUILD_MAX)
	if not valid_zone:
		return Localization.text("자신의 건설 구역에만 설치할 수 있습니다.")
	if kind == "generator" and not ((side == 0 and x <= BLUE_REAR_MAX) or (side == 1 and x >= RED_REAR_MIN)):
		return Localization.text("발전기는 후방에만 설치할 수 있습니다.")
	for structure in structures:
		if int(structure.side) == side and float(structure.hp) > 0.0 and abs(float(structure.x) - x) < STRUCTURE_MIN_SPACING:
			return Localization.text("구조물이 너무 가깝습니다.")
	var limit_error := structure_limit_error(kind, structure_counts(structures, side))
	if not limit_error.is_empty():
		return limit_error
	if resources[side] < float(STRUCTURE_STATS[kind].cost):
		return Localization.text("자원이 부족합니다.")
	return ""

func place_structure(side: int, kind: String, x: float) -> bool:
	if not structure_placement_error(side, kind, x).is_empty():
		return false
	if is_spell(kind):
		_cast_spell(side, kind, x)
		return true
	var stats: Dictionary = STRUCTURE_STATS[kind]
	resources[side] -= stats.cost
	battle_report[side].resources_spent += float(stats.cost)
	battle_report[side].structures_built += 1
	if kind == "turret": battle_report[side].units.turret.purchased += 1
	# Structures without health (the swamp) keep hp 1 only as "still on the field"; nothing can lower it.
	var structure_hp := float(stats.hp) * float(modifier(side, "structure_hp")) * (1.0 + STAR_STEP * card_level(side, kind)) if has_health(kind) else 1.0
	structures.append({"id": next_structure_id, "side": side, "kind": kind, "x": x, "hp": structure_hp, "max_hp": structure_hp})
	if kind == "turret":
		structure_cooldowns[next_structure_id] = float(stats.interval)
	if kind == "swamp":
		structure_expirations[next_structure_id] = elapsed + float(stats.lifetime)
		structures.back()["expires_at"] = structure_expirations[next_structure_id]
	combat_events.append({"type": "STRUCTURE_PLACED", "structure_id": next_structure_id, "kind": kind, "x": x})
	next_structure_id += 1
	return true

## One step of the battle. The rules live in the native engine (native/src/battle_core.cpp); a model
## without it cannot fight (see native_available()).
func tick(delta: float) -> void:
	if winner != -1:
		return
	if _core == null:
		push_error("BattleModel: the battle engine is not loaded")
		return
	_core.tick(self, delta)

## ---- Single rule steps run by the engine on their own (tests and tools; battles use tick()). ----
func _probe(what: String, args: Array):
	return _core.probe(self, what, args) if _core != null else null

func _unit_by_id(id) -> Variant:
	for unit in units:
		if int(unit.id) == int(id):
			return unit
	return null

## What `unit` would attack now (a unit, a structure, or null).
func _find_target(unit: Dictionary):
	var found = _probe("find_target", [int(unit.id)])
	return _unit_by_id(found) if found is int else found

func _damage_target(attacker: Dictionary, target: Dictionary, damage: float, show_attack: bool = true) -> void:
	_probe("damage", [int(attacker.id), target if not target.has("speed") else int(target.id), damage, show_attack])

func _swamp_scale(unit: Dictionary) -> float:
	return float(_probe("swamp_scale", [int(unit.id)]))

func _strike_damage(unit: Dictionary) -> float:
	return float(_probe("strike", [int(unit.id)]))

func _install_curse(caster: Dictionary, x: float) -> void:
	_probe("curse", [int(caster.id), x])

func _record_damage(side: int, kind: String, amount: float, killed: bool) -> void:
	_probe("record", [side, kind, amount, killed])

func _tick_support(unit: Dictionary, _delta: float = 0.0) -> void:
	_probe("support", [int(unit.id)])

## For display: a unit's attack-speed factor, as the engine computes it in battle.
func support_attack_speed(unit: Dictionary) -> float:
	if float(unit.hp) <= 0.0:
		return 1.0
	var curse := curse_speed_scale(int(unit.side), float(unit.x))
	if unit.kind == "healer":
		return curse
	var multiplier := 1.0 + mini(SUPPORT_MAX_STACKS, maxi(0, int(unit.get("support_stacks", 0)))) * SUPPORT_INCREMENT
	var aura := 0.0
	var cap := 0.0
	for hero in units_view():
		var kind := String(hero.kind)
		if int(hero.side) == int(unit.side) and float(hero.hp) > 0.0 and absf(float(hero.x) - float(unit.x)) <= float(trait_value(kind, "aura_radius", 0.0)) and float(trait_value(kind, "aura_attack_speed", 0.0)) > aura:
			aura = float(trait_value(kind, "aura_attack_speed", 0.0))
			cap = float(trait_value(kind, "aura_cap", 0.0))
	if aura > 0.0:
		multiplier = minf(multiplier + aura, 1.0 + cap)
	if unit.has("blessed_remaining"):
		multiplier *= float(STRUCTURE_STATS.blessing.attack_speed)
	return multiplier * (RAGE_SPEED_MULTIPLIER if is_enraged(unit) else 1.0) * curse

## Data tags (e.g. "undead") let traits and future counters target groups of units.
static func unit_tags(kind: String) -> Array:
	return Array(UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {})).get("tags", []))

static func has_tag(kind: String, tag: String) -> bool:
	return unit_tags(kind).has(tag)

const TAG_NAMES := {"undead": "언데드", "demon": "마족"}

## Tags a holy attacker's bonus applies to (data "smite_tags"; undead by default).
static func smite_tags(kind: String) -> Array:
	return Array(trait_value(kind, "smite_tags", ["undead"]))

static func skill_name(kind: String) -> String:
	return "공포의 포효" if trait_value(kind, "skill_knockback") != null else "심판의 십자가"

## How many of `kind` one side may field at once (data "field_limit"); 0 means no limit.
## Units of `side` on the field, downed ones (still holding their place) included.
static func side_count(values: Array, side: int) -> int:
	var count := 0
	for unit in values:
		if int(unit.side) == side:
			count += 1
	return count

func side_full(side: int) -> bool:
	return (_core.side_count(side) if _core != null else side_count(units, side)) >= side_limit(side)

## Units of `side` holding a field slot of `kind` (alive or downed), as field_limit_error counts them.
static func _fielded(values: Array, side: int, kind: String) -> int:
	var fielded := 0
	for unit in values:
		if int(unit.side) == side and String(unit.kind) == kind and (float(unit.hp) > 0.0 or unit.has("revive_remaining")):
			fielded += 1
	return fielded

# ---------- unit queries that work the same on both engines ----------

## The units for reading only (a copy with the native engine): no write-back, so no cost on the next tick.
func units_view() -> Array:
	return _core.export_units() if _core != null else units

## Units of `side` alive (and downed, with include_downed).
func count_units(side: int, include_downed: bool) -> int:
	if _core != null:
		return _core.count_units(side, include_downed)
	var count := 0
	for unit in units:
		if int(unit.side) == side and (float(unit.hp) > 0.0 or (include_downed and unit.has("revive_remaining"))):
			count += 1
	return count

## Whether a living unit of `side` has left its muster (endless defense: the wave is marching).
func has_marching(side: int) -> bool:
	if _core != null:
		return _core.has_marching(side)
	for unit in units:
		if int(unit.side) == side and float(unit.hp) > 0.0 and not unit.has("muster"):
			return true
	return false

## Lets every unit of `side` leave its muster.
func clear_muster(side: int) -> void:
	if _core != null:
		_core.clear_muster(side)
		return
	for unit in units:
		if int(unit.side) == side:
			unit.erase("muster")

## The newest unit, to adjust right after it appeared (changes are kept).
func last_unit() -> Dictionary:
	return _core.last_unit() if _core != null else units.back()

## Units a side may field: SIDE_UNIT_LIMIT, doubled by the solo-battle cheat "army_cap".
func side_limit(side: int) -> int:
	return SIDE_UNIT_LIMIT * 2 if cheats[side].has("army_cap") else SIDE_UNIT_LIMIT

static func field_limit(kind: String) -> int:
	return int(trait_value(kind, "field_limit", 0))

## Shared by authoritative purchases and the purchase cards. Downed units still hold their slot.
static func field_limit_error(values: Array, side: int, kind: String) -> String:
	var limit := field_limit(kind)
	if limit <= 0:
		return ""
	var fielded := 0
	for unit in values:
		if int(unit.side) == side and String(unit.kind) == kind and (float(unit.hp) > 0.0 or unit.has("revive_remaining")):
			fielded += 1
	if fielded < limit:
		return ""
	return Localization.text("%s은(는) 전장에 %d기만 둘 수 있습니다.") % [String(UNIT_NAMES.get(kind, kind)), limit]

## Optional per-unit trait numbers stored in the unit's data `extra`.
static func trait_value(kind: String, key: String, fallback = null):
	return UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {})).get(key, fallback)

static func can_revive(kind: String) -> bool:
	return trait_value(kind, "revive_delay") != null

static func is_enraged(unit: Dictionary) -> bool:
	return (unit.kind == "berserker" or String(unit.get("gift", "")) == "berserker") and float(unit.hp) > 0.0 and float(unit.hp) <= float(unit.max_hp) * RAGE_HP_FRACTION

func unit_attack_damage(unit: Dictionary) -> float:
	var damage: float = float(unit.damage) * (1.0 + int(unit.get("souls", 0)) * _kind_trait(String(unit.kind), "soul_damage_step", 0.0))
	if unit.has("leaderless"):
		damage *= float(_kind_trait(String(unit.kind), "leaderless_damage", 1.0))
	return damage

## trait_value() cached per kind and key (unit data never changes during a battle).
static var _trait_cache: Dictionary = {}
static func _kind_trait(kind: String, key: String, fallback):
	var cache_key := kind + "|" + key
	if not _trait_cache.has(cache_key):
		_trait_cache[cache_key] = trait_value(kind, key, fallback)
	return _trait_cache[cache_key]

## For display: the attack-speed factor an enemy curse puts on a spot (the engine decides in battle).
func curse_speed_scale(side: int, x: float) -> float:
	for curse in curses:
		if int(curse.side) != side and float(curse.expires_at) > elapsed and absf(float(curse.x) - x) <= CURSE_RADIUS:
			return CURSE_SPEED_SCALE
	return 1.0

## Whether `unit` stands inside its side's spawn zone (see `shelter`).
func sheltered(unit: Dictionary) -> bool:
	var depth := float(shelter[int(unit.side)])
	if depth <= 0.0:
		return false
	return float(unit.x) < FIELD_LEFT + depth if int(unit.side) == 0 else float(unit.x) > FIELD_RIGHT - depth

func targetable(unit: Dictionary) -> bool:
	return not sheltered(unit)

## How far behind its side's advance_limit `unit` stops when its side keeps formation.
static func formation_offset(kind: String) -> float:
	if trait_value(kind, "guard", false):
		return 0.0
	var scope := unit_scope(kind)
	if scope == "ranged":
		return clampf(float(UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {})).get("range", 0.0)) * 0.5, FORMATION_RANGED_MIN, FORMATION_RANGED_MAX)
	return FORMATION_MELEE if scope == "melee" else 0.0

## A castle's shot: CASTLE_DAMAGE at full health, rising to CASTLE_DESPERATION times that as it falls.
func castle_damage(side: int) -> float:
	var lost := 1.0 - clampf(float(base_hp[side]) / maxf(1.0, float(base_max_hp[side])), 0.0, 1.0)
	return CASTLE_DAMAGE * (1.0 + (CASTLE_DESPERATION - 1.0) * lost)

func drain_combat_events() -> Array:
	var result := combat_events.duplicate(true)
	combat_events.clear()
	return result

## Fingerprint of the full simulation state; replays use it to prove determinism.
func state_hash() -> String:
	var data := snapshot()
	data.erase("battle_report")
	data.erase("banned") # a ranked ban only removes commands; a replay of the battle needs no copy of it
	return JSON.stringify(data, "", true).sha256_text()

func snapshot() -> Dictionary:
	var data := {"resources": resources.duplicate(), "base_hp": base_hp.duplicate(), "base_max_hp": base_max_hp.duplicate(), "units": _core.export_units() if _core != null else units.duplicate(true), "structures": structures.duplicate(true), "curses": curses.duplicate(true), "winner": winner, "elapsed": elapsed,
		"spawn_cooldowns":spawn_cooldowns.duplicate(true), "spells": spell_casts.duplicate(true), "spell_cooldowns": spell_cooldowns.duplicate(true), "spell_uses": spell_uses.duplicate(true)}
	if not banned[0].is_empty() or not banned[1].is_empty(): data["banned"] = banned.duplicate(true)
	if float(shelter[0]) > 0.0 or float(shelter[1]) > 0.0: data["shelter"] = shelter.duplicate()
	# Per-unit report is authoritative but sent only after the result, not at every live tick.
	if winner != -1: data["battle_report"] = battle_report.duplicate(true)
	return data
