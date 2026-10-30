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
const MAX_ACTIVE_UNITS := 256
## Each side's share of the field: one side filling it never stops the other from fielding units.
const SIDE_UNIT_LIMIT := MAX_ACTIVE_UNITS / 2
## The first time a unit falls to half health it is thrown back this far, once: a losing front gets
## room to recover, so fights swing back and forth instead of grinding in place.
const KNOCKBACK_FRACTION := 0.5
const KNOCKBACK_DISTANCE := 100.0
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
## Endless defense: the wave side has no base to destroy; its units come forever until the defender falls.
var invulnerable_bases: Array = [false, false]
## How far each side's units march: side 0 never past advance_limit[0], side 1 never before advance_limit[1].
## Endless defense holds the defenders short of the wave side's spawn point.
var advance_limit: Array = [FIELD_RIGHT, FIELD_LEFT]
## How far past its advance_limit a side's units may go after an enemy that stands there (0: never). Without
## it enemy archers stopping just beyond the line could shoot a melee army that is not allowed to reach them.
## Units past the line with no such enemy walk back to it.
var advance_chase: Array = [0.0, 0.0]
## Per tick: each side's living units sorted by x (ties by their place in `units`), and the x of each side's
## curses. Targeting looks them up by binary search instead of scanning every unit for every unit, which made
## a tick quadratic in the unit count. Only valid while `_indexed` (inside tick); otherwise the scans run.
var _lanes: Array = [{}, {}]
var _curse_xs: Array = [PackedFloat64Array(), PackedFloat64Array()]
var _indexed := false
## Tests turn the index off to check that it picks exactly what the scans pick.
static var targeting_index := true
## Per tick: each side's most advanced living non-support unit (supports follow it), and the living allies a
## support can still buff (below the stack cap), in field order. Stacks only grow, so that list changes only
## when units appear, fall, or reach the cap: with every ally maxed, supports have nothing to look at.
var _fronts: Array = [null, null]
var _needy: Array = [[], []]
## Units that already made their first attack (for the "first_strike" modifier).
var first_struck: Dictionary = {}
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
	if not field_limit_error(units, side, kind).is_empty():
		return false
	var stats: Dictionary = UNIT_STATS[kind]
	var stat_scale := float(campaign_bonuses(int(campaign_levels[side])).stat_scale)
	var cost := unit_cost(side, kind)
	if resources[side] < cost or float(spawn_cooldowns[side].get(kind, 0.0)) > 0.0:
		return false
	resources[side] -= cost
	battle_report[side].resources_spent += cost
	battle_report[side].units[kind].purchased += 1
	spawn_cooldowns[side][kind] = 0.35
	_create_unit(side, kind, stats, stat_scale * unit_modifier(side, kind, "hp"), stat_scale * unit_modifier(side, kind, "damage"), FIELD_LEFT + 35.0 if side == 0 else FIELD_RIGHT - 35.0)
	return true

func _create_unit(side: int, kind: String, stats: Dictionary, hp_scale: float, damage_scale: float, x: float) -> void:
	units.append({"id": next_unit_id, "side": side, "kind": kind,
		"x": clampf(x, FIELD_LEFT, FIELD_RIGHT),
		"hp": stats.hp * hp_scale, "max_hp": stats.hp * hp_scale, "damage": stats.damage * damage_scale,
		"heal": stats.get("heal", 0.0) * damage_scale, "interval": stats.interval,
		"cooldown": 0.0 if kind == "healer" else max(MIN_ATTACK_INTERVAL, float(stats.interval)),
		"support_stacks": 0,
		"speed": stats.speed, "range": float(stats.range) + (float(modifier(side, "range:ranged", 0.0)) if unit_scope(kind) == "ranged" else 0.0)})
	if kind == "necromancer":
		summon_timers[next_unit_id] = SUMMON_INTERVAL
		units.back()["summon_remaining"] = SUMMON_INTERVAL
	if trait_value(kind, "skill_cooldown") != null:
		units.back()["skill_remaining"] = float(trait_value(kind, "skill_cooldown"))
	if trait_value(kind, "soul_max") != null:
		units.back()["souls"] = 0
	next_unit_id += 1

static func unit_stat_summary(kind: String, growth_level: int = 0) -> String:
	if not UNIT_STATS.has(kind) and not SUMMON_STATS.has(kind):
		return ""
	var stats: Dictionary = UNIT_STATS.get(kind, SUMMON_STATS.get(kind, {}))
	var interval: float = max(float(stats.interval), MIN_ATTACK_INTERVAL)
	var stat_scale := float(campaign_bonuses(growth_level).stat_scale)
	var output := Localization.text("비용 %d  ·  체력 %d\n") % [int(stats.cost), int(stats.hp * stat_scale)]
	if kind == "skeleton":
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
		"shield": return Localization.text("방어")
		"swordsman": return Localization.text("근접 공격")
		"berserker": return Localization.text("체력 %d%% 이하: 광폭화") % roundi(RAGE_HP_FRACTION * 100.0)
		"warlock": return Localization.text("적 공속 -%d%% 장판") % roundi((1.0 - CURSE_SPEED_SCALE) * 100.0)
		"paladin": return Localization.text("%d초 십자가 강타") % int(trait_value(kind, "skill_cooldown"))
		"sniper": return Localization.text("맨 뒤의 적 저격")
		"zombie": return Localization.text("체력 %d%%로 1회 부활") % roundi(float(trait_value(kind, "revive_hp_fraction", 0.5)) * 100.0)
		"necromancer": return Localization.text("%d초 해골 소환·최대 %d") % [int(SUMMON_INTERVAL), MAX_SKELETONS_PER_NECROMANCER]
		"demon_lord": return Localization.text("영혼 수확·%d초 포효·1기") % int(trait_value(kind, "skill_cooldown"))
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
	var structures_line := Localization.text("구조물  ·  방벽 %d/체력 %d  ·  늪 %d/체력 %d/%d%% 감속/%d초\n포탑 %d/체력 %d/공격 %d/사거리 %d  ·  발전기 %d/체력 %d/+%d 자원") % [
		int(wall.cost), int(wall.hp), int(swamp.cost), int(swamp.hp), roundi((1.0 - float(swamp.speed_scale)) * 100.0), int(swamp.lifetime),
		int(turret.cost), int(turret.hp), int(turret.damage), int(turret.range), int(generator.cost), int(generator.hp), int(generator.income)]
	var support_line := Localization.text("마법사  ·  피해·회복 없음/공속 +%d%% 영구 누적/범위 %d/쿨 %d초/상한 +%d%%") % [roundi(SUPPORT_INCREMENT * 100.0), int(healer.range), int(healer.interval), roundi(SUPPORT_INCREMENT * SUPPORT_MAX_STACKS * 100.0)]
	var field_line := Localization.text("전장  ·  길이 +%d%%  ·  기지 체력 %d  ·  자원 +%.0f/초  ·  최대 %.0f  ·  구조물 진영당 %d개  ·  시간 제한 없음") % [roundi((WORLD_SCALE - 1.0) * 100.0), int(BASE_MAX_HP), RESOURCE_RATE, MAX_RESOURCE, STRUCTURE_LIMIT]
	return structures_line + "\n" + support_line + "\n" + field_line

## Shared by authoritative placement, online previews and purchase cards.
## Destroyed structures can remain in a snapshot until the next cleanup tick.
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

## Lands every cast that is due, in cast order.
func _land_spells() -> void:
	var due: Array = spell_casts.filter(func(cast): return float(cast.lands_at) <= elapsed + 0.000001)
	if due.is_empty():
		return
	spell_casts = spell_casts.filter(func(cast): return float(cast.lands_at) > elapsed + 0.000001)
	for cast in due:
		_land_spell(cast)

func _land_spell(cast: Dictionary) -> void:
	var side := int(cast.side)
	var kind := String(cast.kind)
	var x := float(cast.x)
	var stats: Dictionary = STRUCTURE_STATS[kind]
	var radius := float(stats.get("radius", 0.0))
	var caster := {"id": 0, "side": side, "kind": kind, "x": x}
	var targets: Array = []
	match String(stats.get("effect", kind)):
		"strike":
			# The healthiest enemy unit in the radius takes the whole hit.
			var strongest = null
			for enemy in units:
				if int(enemy.side) != side and float(enemy.hp) > 0.0 and absf(float(enemy.x) - x) <= radius:
					if strongest == null or float(enemy.hp) > float(strongest.hp):
						strongest = enemy
			if strongest != null:
				x = float(strongest.x)
				targets.append(strongest.id)
				_damage_target(caster, strongest, float(stats.damage), false)
		"blast":
			for enemy in units:
				if int(enemy.side) != side and float(enemy.hp) > 0.0 and absf(float(enemy.x) - x) <= radius:
					targets.append(enemy.id)
					_damage_target(caster, enemy, float(stats.damage), false)
		"freeze":
			for enemy in units:
				if int(enemy.side) != side and float(enemy.hp) > 0.0 and absf(float(enemy.x) - x) <= radius:
					targets.append(enemy.id)
					enemy["frozen_remaining"] = float(stats.duration)
		"bless":
			for ally in units:
				if int(ally.side) == side and float(ally.hp) > 0.0 and absf(float(ally.x) - x) <= radius:
					targets.append(ally.id)
					ally["blessed_remaining"] = float(stats.duration)
					ally.hp = minf(float(ally.max_hp), float(ally.hp) + float(ally.max_hp) * float(stats.get("heal_fraction", 0.0)))
		"resurrect":
			var count := mini(int(stats.revive_count), fallen[side].size())
			var raised: Array = fallen[side].slice(fallen[side].size() - count)
			fallen[side] = fallen[side].slice(0, fallen[side].size() - count)
			var fraction := float(stats.revive_fraction)
			for index in raised.size():
				if side_full(side):
					break
				var entry: Dictionary = raised[index]
				var spread := (float(index) - float(raised.size() - 1) * 0.5) * 14.0
				_create_unit(side, String(entry.kind), UNIT_STATS[String(entry.kind)], float(entry.hp_scale) * fraction, float(entry.damage_scale) * fraction, x + spread)
				var unit: Dictionary = units.back()
				unit["revived"] = true
				revive_used[unit.id] = true
				targets.append(unit.id)
	combat_events.append({"type": "SPELL_LAND", "side": side, "kind": kind, "x": x, "radius": radius, "targets": targets})

## Remembers a fallen ally for resurrection: bought units only (no summons, nothing already raised,
## no unit limited to one on the field).
func _remember_fallen(unit: Dictionary) -> void:
	var kind := String(unit.kind)
	if not UNIT_STATS.has(kind) or unit.get("revived", false) or field_limit(kind) > 0:
		return
	var stats: Dictionary = UNIT_STATS[kind]
	var side := int(unit.side)
	var damage_scale := float(unit.damage) / float(stats.damage) if float(stats.damage) > 0.0 else 1.0
	fallen[side].append({"kind": kind, "hp_scale": float(unit.max_hp) / maxf(0.01, float(stats.hp)), "damage_scale": damage_scale})
	if fallen[side].size() > MAX_FALLEN:
		fallen[side].pop_front()

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
	var structure_hp := float(stats.hp) * float(modifier(side, "structure_hp")) * (1.0 + STAR_STEP * card_level(side, kind))
	structures.append({"id": next_structure_id, "side": side, "kind": kind, "x": x, "hp": structure_hp, "max_hp": structure_hp})
	if kind == "turret":
		structure_cooldowns[next_structure_id] = float(stats.interval)
	if kind == "swamp":
		structure_expirations[next_structure_id] = elapsed + float(stats.lifetime)
		structures.back()["expires_at"] = structure_expirations[next_structure_id]
	combat_events.append({"type": "STRUCTURE_PLACED", "structure_id": next_structure_id, "kind": kind, "x": x})
	next_structure_id += 1
	return true

func tick(delta: float) -> void:
	if winner != -1:
		return
	elapsed += delta
	curses = curses.filter(func(curse): return float(curse.expires_at) > elapsed)
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
		for kind in spell_cooldowns[side].keys():
			spell_cooldowns[side][kind] = maxf(0.0, float(spell_cooldowns[side][kind]) - delta)
			if float(spell_cooldowns[side][kind]) <= 0.0:
				spell_cooldowns[side].erase(kind)
	for unit in units:
		for key in ["frozen_remaining", "blessed_remaining"]:
			if unit.has(key):
				unit[key] = float(unit[key]) - delta
				if float(unit[key]) <= 0.000001:
					unit.erase(key)

	_tick_revives(delta)
	_land_spells()
	_index_curses()
	_index_lanes()
	_index_fronts()

	# All combatants choose from the same positions/health. Applying an attack
	# while choosing the next one gave earlier array entries a free lethal hit.
	var pending_attacks: Array = []
	var pending_base_hits: Array = []
	var pending_moves: Array = []
	_tick_turrets(delta, pending_attacks)
	var pending_summons: Array = []
	var live_skeletons := {}
	for unit in units:
		if unit.kind == "skeleton" and float(unit.hp) > 0.0 and summon_owners.has(unit.id):
			live_skeletons[summon_owners[unit.id]] = int(live_skeletons.get(summon_owners[unit.id], 0)) + 1
	for unit in units:
		if unit.has("frozen_remaining"):
			continue
		unit.cooldown = max(0.0, float(unit.cooldown) - delta * support_attack_speed(unit))
		if unit.hp <= 0.0:
			continue
		if unit.kind == "necromancer":
			summon_timers[unit.id] = float(summon_timers.get(unit.id, SUMMON_INTERVAL)) - delta
			if float(summon_timers[unit.id]) <= 0.000001:
				if int(live_skeletons.get(unit.id, 0)) < MAX_SKELETONS_PER_NECROMANCER + int(modifier(int(unit.side), "skeleton_cap", 0)):
					pending_summons.append(unit)
				summon_timers[unit.id] = SUMMON_INTERVAL
			unit["summon_remaining"] = maxf(0.0, float(summon_timers[unit.id]))
		if unit.has("skill_remaining"):
			unit.skill_remaining = maxf(0.0, float(unit.skill_remaining) - delta)
		if unit.kind == "healer":
			_tick_support(unit, delta)
			continue
	_index_lanes() # supports moved
	var pending_skills: Array = []
	for unit in units:
		if float(unit.hp) <= 0.0 or unit.kind == "healer" or unit.has("frozen_remaining"):
			continue
		var target = _find_target(unit)
		if target != null:
			if unit.has("skill_remaining") and float(unit.skill_remaining) <= 0.0:
				pending_skills.append({"caster": unit, "x": float(target.x)})
				unit.skill_remaining = float(trait_value(String(unit.kind), "skill_cooldown")) * float(modifier(int(unit.side), "skill_cooldown:" + String(unit.kind)))
			if unit.cooldown <= 0.0:
				pending_attacks.append({"attacker":unit, "target":target, "damage":_strike_damage(unit)})
				unit.cooldown = unit.interval
			continue

		var enemy_base_x := FIELD_RIGHT if unit.side == 0 else FIELD_LEFT
		var blocking_wall = _blocking_wall(unit, enemy_base_x)
		if blocking_wall != null and abs(float(blocking_wall.x) - float(unit.x)) <= float(unit.range) + 12.0:
			if unit.cooldown <= 0.0:
				pending_attacks.append({"attacker":unit, "target":blocking_wall, "damage":_strike_damage(unit)})
				unit.cooldown = unit.interval
			continue
		if abs(float(unit.x) - enemy_base_x) <= float(unit.range):
			if unit.cooldown <= 0.0:
				pending_base_hits.append({"attacker":unit, "damage":_strike_damage(unit), "x":enemy_base_x})
				unit.cooldown = unit.interval
			continue
		var direction := 1.0 if unit.side == 0 else -1.0
		var stride := clampf(float(unit.x) + direction * float(unit.speed) * _swamp_scale(unit) * delta, FIELD_LEFT, FIELD_RIGHT)
		stride = _held_stride(unit, stride, direction, delta)
		pending_moves.append({"unit":unit, "x":stride})

	_indexed = false # from here on attacks change health and positions
	for skill in pending_skills:
		_cast_skill(skill.caster, float(skill.x))
	for attack in pending_attacks:
		if attack.attacker.has("speed"):
			_damage_target(attack.attacker, attack.target, attack.damage)
		else:
			var before := maxf(0.0, float(attack.target.hp))
			var effective := minf(before, float(attack.damage))
			_record_damage(int(attack.attacker.side), "turret", effective, attack.target.has("speed") and before > 0.0 and effective >= before)
			attack.target.hp = maxf(0.0, before - float(attack.damage))
			combat_events.append({"type":"ATTACK", "attacker_id":attack.attacker.id, "target_id":attack.target.id, "attack_kind":"turret", "x":attack.attacker.x})
			combat_events.append({"type":"DAMAGE", "target_id":attack.target.id, "amount":attack.damage, "x":attack.target.x})
	for hit in pending_base_hits:
		var enemy_side := 1 - int(hit.attacker.side)
		_record_damage(int(hit.attacker.side), String(hit.attacker.kind), minf(float(hit.damage), float(base_hp[enemy_side])), false)
		if not bool(invulnerable_bases[enemy_side]):
			base_hp[enemy_side] = maxf(0.0, float(base_hp[enemy_side]) - float(hit.damage))
			combat_events.append({"type":"BASE_HIT", "side":enemy_side, "amount":hit.damage, "x":hit.x})
		if hit.attacker.kind == "warlock": _install_curse(hit.attacker, hit.x)
	for move in pending_moves:
		move.unit.x = move.x
	if base_hp[0] <= 0.0 or base_hp[1] <= 0.0:
		winner = 2 if base_hp[0] <= 0.0 and base_hp[1] <= 0.0 else 1 if base_hp[0] <= 0.0 else 0

	_down_revivable_units()
	_emit_death_events()
	units = units.filter(func(unit): return unit.hp > 0.0 or unit.has("revive_remaining"))
	structures = structures.filter(func(structure): return structure.hp > 0.0)
	for owner in pending_summons:
		if winner != -1 or float(owner.hp) <= 0.0 or side_full(int(owner.side)):
			continue
		var hp_scale := float(owner.max_hp) / float(UNIT_STATS.necromancer.hp)
		var damage_scale := float(owner.damage) / float(UNIT_STATS.necromancer.damage)
		battle_report[int(owner.side)].units.necromancer.summoned += 1
		_create_unit(int(owner.side), "skeleton", SUMMON_STATS.skeleton, hp_scale, damage_scale, float(owner.x) + (22.0 if int(owner.side) == 0 else -22.0))
		summon_owners[units.back().id] = owner.id
		combat_events.append({"type": "SUMMON", "source_id": owner.id, "unit_id": units.back().id, "x": units.back().x})
	var live_ids := {}
	for unit in units:
		live_ids[unit.id] = true
	for id in summon_timers.keys():
		if not live_ids.has(id):
			summon_timers.erase(id)
	for id in summon_owners.keys():
		if not live_ids.has(id):
			summon_owners.erase(id)
	for id in revive_used.keys():
		if not live_ids.has(id):
			revive_used.erase(id)
	for id in knocked_back.keys():
		if not live_ids.has(id):
			knocked_back.erase(id)
	for id in structure_expirations.keys():
		if not structures.any(func(structure): return structure.id == id):
			structure_expirations.erase(id)

func support_attack_speed(unit: Dictionary) -> float:
	if float(unit.hp) <= 0.0:
		return 1.0
	var curse := curse_speed_scale(int(unit.side), float(unit.x))
	if unit.kind == "healer":
		return curse
	var multiplier := 1.0 + mini(SUPPORT_MAX_STACKS, maxi(0, int(unit.get("support_stacks", 0)))) * SUPPORT_INCREMENT
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
	return side_count(units, side) >= SIDE_UNIT_LIMIT

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

func _down_revivable_units() -> void:
	for unit in units:
		if float(unit.hp) > 0.0 or unit.has("revive_remaining") or revive_used.has(unit.id) or not can_revive(String(unit.kind)):
			continue
		revive_used[unit.id] = true
		unit["revive_remaining"] = float(trait_value(String(unit.kind), "revive_delay"))
		unit.support_stacks = 0
		combat_events.append({"type": "DOWNED", "unit_id": unit.id, "x": unit.x})

func _tick_revives(delta: float) -> void:
	for unit in units:
		if not unit.has("revive_remaining"):
			continue
		unit.revive_remaining = maxf(0.0, float(unit.revive_remaining) - delta)
		if float(unit.revive_remaining) > 0.000001:
			continue
		unit.erase("revive_remaining")
		unit.hp = float(unit.max_hp) * float(trait_value(String(unit.kind), "revive_hp_fraction", 0.5))
		unit.cooldown = max(MIN_ATTACK_INTERVAL, float(unit.interval))
		combat_events.append({"type": "REVIVE", "unit_id": unit.id, "x": unit.x})

static func is_enraged(unit: Dictionary) -> bool:
	return unit.kind == "berserker" and float(unit.hp) > 0.0 and float(unit.hp) <= float(unit.max_hp) * RAGE_HP_FRACTION

func unit_attack_damage(unit: Dictionary) -> float:
	return float(unit.damage) * (1.0 + int(unit.get("souls", 0)) * float(trait_value(String(unit.kind), "soul_damage_step", 0.0)))

## The damage of an attack `unit` makes now; the "first_strike" modifier doubles each unit's first one.
func _strike_damage(unit: Dictionary) -> float:
	var damage := unit_attack_damage(unit)
	if float(modifier(int(unit.side), "first_strike", 0.0)) > 0.0 and not first_struck.has(int(unit.id)):
		first_struck[int(unit.id)] = true
		damage *= 2.0
	return damage

func curse_speed_scale(side: int, x: float) -> float:
	if _indexed:
		# Curses of the other side, sorted by x: is the nearest one within the radius?
		var xs: PackedFloat64Array = _curse_xs[1 - side]
		var at := xs.bsearch(x, true)
		if (at < xs.size() and absf(xs[at] - x) <= CURSE_RADIUS) or (at > 0 and absf(xs[at - 1] - x) <= CURSE_RADIUS):
			return CURSE_SPEED_SCALE
		return 1.0
	for curse in curses:
		if int(curse.side) != side and float(curse.expires_at) > elapsed and absf(float(curse.x) - x) <= CURSE_RADIUS:
			return CURSE_SPEED_SCALE
	return 1.0

func _install_curse(caster: Dictionary, x: float) -> void:
	curses = curses.filter(func(curse): return int(curse.source_id) != int(caster.id))
	curses.append({"source_id": caster.id, "side": caster.side, "x": x, "expires_at": elapsed + CURSE_DURATION})
	combat_events.append({"type": "CURSE", "source_id": caster.id, "x": x})

func _tick_support(unit: Dictionary, delta: float) -> void:
	if float(unit.cooldown) <= 0.0:
		var cast := false
		for ally in (_needy[int(unit.side)] if _indexed else units):
			if ally.side == unit.side and ally.kind != "healer" and float(ally.hp) > 0.0 and abs(float(ally.x) - float(unit.x)) <= float(unit.range):
				var stacks := int(ally.get("support_stacks", 0))
				if stacks < SUPPORT_MAX_STACKS:
					ally.support_stacks = stacks + 1
					combat_events.append({"type": "SUPPORT_BUFF", "source_id": unit.id, "target_id": ally.id, "stacks": ally.support_stacks, "x": ally.x})
					cast = true
		if cast:
			unit.cooldown = SUPPORT_COOLDOWN
	var direction := 1.0 if int(unit.side) == 0 else -1.0
	var frontline = _fronts[int(unit.side)] if _indexed else null
	if not _indexed:
		for ally in units:
			if ally.side == unit.side and ally.kind != "healer" and float(ally.hp) > 0.0:
				if frontline == null or direction * float(ally.x) > direction * float(frontline.x):
					frontline = ally
	if frontline != null and direction * (float(frontline.x) - float(unit.x)) <= SUPPORT_FOLLOW_DISTANCE:
		return
	# Support units never attack units, buildings or bases, even with no wounded ally.
	var step := float(unit.speed) * _swamp_scale(unit) * delta
	var enemy_ahead: bool = _enemy_ahead_indexed(unit, max(float(unit.range), step)) if _indexed else units.any(func(enemy): return enemy.side != unit.side and float(enemy.hp) > 0.0 and direction * (float(enemy.x) - float(unit.x)) >= 0.0 and abs(float(enemy.x) - float(unit.x)) <= max(float(unit.range), step))
	if enemy_ahead or _blocking_wall(unit, float(unit.x) + direction * step) != null or _find_target(unit) != null:
		return
	var enemy_base_x := FIELD_RIGHT if int(unit.side) == 0 else FIELD_LEFT
	if abs(float(unit.x) - enemy_base_x) <= float(unit.range):
		return
	var destination := float(unit.x) + direction * step
	if frontline != null:
		var follow_x := float(frontline.x) - direction * SUPPORT_FOLLOW_DISTANCE
		destination = min(destination, follow_x) if direction > 0.0 else max(destination, follow_x)
	unit.x = clamp(destination, FIELD_LEFT, FIELD_RIGHT)


## Ground slam around `x` (or the caster): every living enemy unit in the radius takes the
## skill damage, and survivors are pushed back toward their own base when the skill knocks back.
func _cast_skill(caster: Dictionary, x: float) -> void:
	var kind := String(caster.kind)
	if trait_value(kind, "skill_on_self", false):
		x = float(caster.x)
	var growth := float(caster.damage) / maxf(0.01, float(UNIT_STATS[kind].damage))
	var radius := float(trait_value(kind, "skill_radius", 0.0))
	var knockback := float(trait_value(kind, "skill_knockback", 0.0)) * (1.0 if int(caster.side) == 0 else -1.0)
	combat_events.append({"type": "SKILL", "source_id": caster.id, "kind": kind, "x": x, "radius": radius})
	for enemy in units:
		if int(enemy.side) != int(caster.side) and float(enemy.hp) > 0.0 and absf(float(enemy.x) - x) <= radius:
			_damage_target(caster, enemy, float(trait_value(kind, "skill_damage", 0.0)) * growth, false)
			if knockback != 0.0 and float(enemy.hp) > 0.0:
				enemy.x = clampf(float(enemy.x) + knockback, FIELD_LEFT, FIELD_RIGHT)

func _damage_target(attacker: Dictionary, target: Dictionary, damage: float, show_attack: bool = true) -> void:
	var undead_bonus = trait_value(String(attacker.kind), "undead_bonus")
	var smites_undead: bool = undead_bonus != null and target.has("speed") and smite_tags(String(attacker.kind)).any(func(tag): return has_tag(String(target.kind), tag))
	if smites_undead:
		damage *= float(undead_bonus)
	var before := maxf(0.0,float(target.hp))
	var effective := minf(before,maxf(0.0,damage))
	_record_damage(int(attacker.side),String(attacker.kind),effective,target.has("speed") and before>0.0 and effective>=before)
	target.hp = max(0.0, float(target.hp) - damage)
	# Undead struck down by holy damage stay down (no zombie revive).
	if smites_undead and float(target.hp) <= 0.0:
		revive_used[target.id] = true
	if show_attack:
		combat_events.append({"type": "ATTACK", "attacker_id": attacker.id, "target_id": target.id, "attack_kind": attacker.kind, "x": attacker.x})
	combat_events.append({"type": "DAMAGE", "target_id": target.id, "amount": damage, "x": target.x})
	if target.has("speed") and float(target.hp) > 0.0 and float(target.hp) <= float(target.max_hp) * KNOCKBACK_FRACTION and not knocked_back.has(target.id):
		knocked_back[target.id] = true
		var away := -1.0 if int(target.side) == 0 else 1.0
		target.x = clampf(float(target.x) + away * KNOCKBACK_DISTANCE * float(modifier(int(target.side), "knockback")), FIELD_LEFT, FIELD_RIGHT)
		combat_events.append({"type": "KNOCKBACK", "target_id": target.id, "x": target.x})
	if attacker.kind == "warlock":
		_install_curse(attacker, float(target.x))

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

func _index_fronts() -> void:
	_fronts = [null, null]
	_needy = [[], []]
	for unit in units:
		if unit.kind == "healer" or float(unit.hp) <= 0.0:
			continue
		var side := int(unit.side)
		if int(unit.get("support_stacks", 0)) < SUPPORT_MAX_STACKS:
			_needy[side].append(unit)
		var direction := 1.0 if side == 0 else -1.0
		if _fronts[side] == null or direction * float(unit.x) > direction * float(_fronts[side].x):
			_fronts[side] = unit

func _index_curses() -> void:
	for side in 2:
		var xs := PackedFloat64Array()
		for curse in curses:
			if int(curse.side) == side and float(curse.expires_at) > elapsed:
				xs.append(float(curse.x))
		xs.sort()
		_curse_xs[side] = xs

func _index_lanes() -> void:
	var keyed: Array = [[], []]
	for index in units.size():
		var unit: Dictionary = units[index]
		if float(unit.hp) > 0.0:
			keyed[int(unit.side)].append([float(unit.x), index])
	for side in 2:
		var entries: Array = keyed[side]
		entries.sort() # by x, then by place in `units`
		var xs := PackedFloat64Array()
		var order := PackedInt32Array()
		var refs: Array = []
		xs.resize(entries.size())
		order.resize(entries.size())
		refs.resize(entries.size())
		for i in entries.size():
			xs[i] = entries[i][0]
			order[i] = entries[i][1]
			refs[i] = units[entries[i][1]]
		_lanes[side] = {"xs": xs, "order": order, "units": refs}
	_indexed = targeting_index

## The first entry of the run of equal x that `at` belongs to: the earliest of them in `units`.
static func _run_start(xs: PackedFloat64Array, at: int) -> int:
	return xs.bsearch(xs[at], true)

## Nearest living enemy of `unit` within its range (ties: earliest in `units`), from the lane index.
func _nearest_enemy_indexed(unit: Dictionary):
	var lane: Dictionary = _lanes[1 - int(unit.side)]
	var xs: PackedFloat64Array = lane.xs
	if xs.is_empty():
		return null
	var x := float(unit.x)
	var reach := float(unit.range)
	var best = null
	var best_distance := INF
	var best_order := 1 << 30
	var right := xs.bsearch(x, true)
	if right < xs.size() and absf(xs[right] - x) <= reach:
		best = lane.units[right]
		best_distance = absf(xs[right] - x)
		best_order = lane.order[right]
	if right > 0:
		var left := _run_start(xs, right - 1)
		var distance := absf(xs[left] - x)
		if distance <= reach and (distance < best_distance or (distance == best_distance and lane.order[left] < best_order)):
			best = lane.units[left]
	return best

## Farthest living enemy of `unit` within its range (ties: earliest in `units`), from the lane index.
func _rearmost_enemy_indexed(unit: Dictionary):
	var lane: Dictionary = _lanes[1 - int(unit.side)]
	var xs: PackedFloat64Array = lane.xs
	var x := float(unit.x)
	var reach := float(unit.range)
	var low := xs.bsearch(x - reach, true)
	while low < xs.size() and absf(xs[low] - x) > reach and xs[low] < x:
		low += 1
	var high := xs.bsearch(x + reach, false) - 1
	while high >= 0 and absf(xs[high] - x) > reach and xs[high] > x:
		high -= 1
	if low >= xs.size() or high < 0 or low > high:
		return null
	var best = lane.units[low]
	var best_distance := absf(xs[low] - x)
	var best_order: int = lane.order[low]
	var far := _run_start(xs, high)
	var distance := absf(xs[far] - x)
	if distance > best_distance or (distance == best_distance and lane.order[far] < best_order):
		best = lane.units[far]
	return best

## Whether a living enemy of `unit` stands ahead of it (or level) within `reach`, from the lane index.
## Where `unit` may step to (`stride`) given its side's advance limit and chase distance.
func _held_stride(unit: Dictionary, stride: float, direction: float, delta: float) -> float:
	var side := int(unit.side)
	var limit := float(advance_limit[side])
	var x := float(unit.x)
	if direction * (stride - limit) <= 0.0:
		return stride
	var chase := float(advance_chase[side])
	if chase <= 0.0:
		return minf(stride, maxf(x, limit)) if side == 0 else maxf(stride, minf(x, limit))
	var target := _nearest_ahead_x(unit)
	if not is_inf(target) and direction * (target - limit) <= chase:
		return minf(stride, target) if side == 0 else maxf(stride, target)
	if direction * (x - limit) <= 0.0:
		return limit if direction * (x - limit) < 0.0 else x
	# Past the line with nobody to chase: back to the line.
	var back := x - direction * float(unit.speed) * _swamp_scale(unit) * delta
	return maxf(back, limit) if side == 0 else minf(back, limit)

## The x of the nearest living enemy ahead of `unit` (INF / -INF when there is none).
func _nearest_ahead_x(unit: Dictionary) -> float:
	var x := float(unit.x)
	var ahead := 1.0 if int(unit.side) == 0 else -1.0
	if _indexed:
		var xs: PackedFloat64Array = _lanes[1 - int(unit.side)].xs
		if ahead > 0.0:
			var at := xs.bsearch(x, true)
			return xs[at] if at < xs.size() else INF
		var behind := xs.bsearch(x, false) - 1
		return xs[behind] if behind >= 0 else -INF
	var best := ahead * INF
	for enemy in units:
		if int(enemy.side) != int(unit.side) and float(enemy.hp) > 0.0 and ahead * (float(enemy.x) - x) >= 0.0 and ahead * (float(enemy.x) - best) < 0.0:
			best = float(enemy.x)
	return best

func _enemy_ahead_indexed(unit: Dictionary, reach: float) -> bool:
	var xs: PackedFloat64Array = _lanes[1 - int(unit.side)].xs
	var x := float(unit.x)
	if int(unit.side) == 0:
		var at := xs.bsearch(x, true)
		return at < xs.size() and absf(xs[at] - x) <= reach
	var behind := xs.bsearch(x, false) - 1
	return behind >= 0 and absf(xs[behind] - x) <= reach

func _find_target(unit: Dictionary):
	if trait_value(String(unit.kind), "target_rearmost", false):
		var rearmost = _rearmost_enemy_indexed(unit) if _indexed else _rearmost_enemy(unit)
		if rearmost != null:
			return rearmost
	var best_unit = null
	var best_distance := INF
	if _indexed:
		best_unit = _nearest_enemy_indexed(unit)
	else:
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


## Snipers fire over walls at the in-range enemy unit farthest behind the enemy line.
func _rearmost_enemy(unit: Dictionary):
	var best = null
	var best_distance := -1.0
	for enemy in units:
		if enemy.side == unit.side or float(enemy.hp) <= 0.0:
			continue
		var distance: float = absf(float(enemy.x) - float(unit.x))
		if distance <= float(unit.range) and distance > best_distance:
			best = enemy
			best_distance = distance
	return best

func _tick_turrets(delta: float, pending_attacks: Array) -> void:
	for structure in structures:
		if String(structure.kind) != "turret" or float(structure.hp) <= 0.0:
			continue
		var id := int(structure.id)
		structure_cooldowns[id] = max(0.0, float(structure_cooldowns.get(id, STRUCTURE_STATS.turret.interval)) - delta * curse_speed_scale(int(structure.side), float(structure.x)))
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
			var damage := float(STRUCTURE_STATS.turret.damage)
			pending_attacks.append({"attacker":structure, "target":target, "damage":damage})
			structure_cooldowns[id] = float(STRUCTURE_STATS.turret.interval)

func _swamp_scale(unit: Dictionary) -> float:
	for structure in structures:
		if structure.kind == "swamp" and structure.side != unit.side and structure.hp > 0.0 and abs(float(structure.x) - float(unit.x)) <= float(STRUCTURE_STATS.swamp.radius):
			return float(STRUCTURE_STATS.swamp.speed_scale)
	return 1.0


func _emit_death_events() -> void:
	for unit in units:
		if float(unit.hp) <= 0.0 and not unit.has("revive_remaining") and not announced_deaths.has(unit.id):
			announced_deaths[unit.id] = true
			combat_events.append({"type": "DEATH", "unit_id": unit.id, "x": unit.x})
			_harvest_soul(unit)
			_remember_fallen(unit)
	for structure in structures:
		if float(structure.hp) <= 0.0 and not announced_structure_deaths.has(structure.id):
			announced_structure_deaths[structure.id] = true
			combat_events.append({"type": "STRUCTURE_DESTROYED", "structure_id": structure.id, "kind": structure.kind, "x": structure.x})

## A living soul harvester near a fallen enemy heals and gains one soul (up to its maximum).
func _harvest_soul(fallen: Dictionary) -> void:
	for lord in units:
		if int(lord.side) == int(fallen.side) or float(lord.hp) <= 0.0 or not lord.has("souls"):
			continue
		var kind := String(lord.kind)
		if absf(float(lord.x) - float(fallen.x)) > float(trait_value(kind, "soul_radius", 0.0)):
			continue
		lord.souls = mini(int(trait_value(kind, "soul_max", 0)), int(lord.souls) + 1)
		var healed := minf(float(lord.max_hp) - float(lord.hp), float(lord.max_hp) * float(trait_value(kind, "soul_heal_fraction", 0.0)))
		lord.hp = float(lord.hp) + healed
		combat_events.append({"type": "SOUL", "source_id": lord.id, "unit_id": fallen.id, "x": lord.x, "from_x": fallen.x, "souls": lord.souls})
		if healed > 0.0:
			combat_events.append({"type": "HEAL", "target_id": lord.id, "amount": healed, "x": lord.x})

func drain_combat_events() -> Array:
	var result := combat_events.duplicate(true)
	combat_events.clear()
	return result

func _record_damage(side: int, kind: String, amount: float, killed: bool) -> void:
	kind = Report.credit_kind(kind)
	if side<0 or side>1 or not battle_report[side].units.has(kind): return
	battle_report[side].damage += amount
	battle_report[side].units[kind].damage += amount
	if killed:
		battle_report[side].kills += 1; battle_report[side].units[kind].kills += 1

## Fingerprint of the full simulation state; replays use it to prove determinism.
func state_hash() -> String:
	var data := snapshot()
	data.erase("battle_report")
	data.erase("banned") # a ranked ban only removes commands; a replay of the battle needs no copy of it
	return JSON.stringify(data, "", true).sha256_text()

func snapshot() -> Dictionary:
	var data := {"resources": resources.duplicate(), "base_hp": base_hp.duplicate(), "base_max_hp": base_max_hp.duplicate(), "units": units.duplicate(true), "structures": structures.duplicate(true), "curses": curses.duplicate(true), "winner": winner, "elapsed": elapsed,
		"spawn_cooldowns":spawn_cooldowns.duplicate(true), "spells": spell_casts.duplicate(true), "spell_cooldowns": spell_cooldowns.duplicate(true), "spell_uses": spell_uses.duplicate(true)}
	if not banned[0].is_empty() or not banned[1].is_empty(): data["banned"] = banned.duplicate(true)
	# Per-unit report is authoritative but sent only after the result, not at every live tick.
	if winner != -1: data["battle_report"] = battle_report.duplicate(true)
	return data
