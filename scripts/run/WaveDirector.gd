extends RefCounted
## Endless defense opponent: sends ever larger waves at the player until their base falls. It plays the
## opponent's part in the local battle loop (update(model, delta), like ServerAI). The wave side has no base
## (BattleModel.invulnerable_bases) and pays nothing for its units: each wave has a budget in unit costs.
## Between waves the director waits for the player to pick one of three boons (awaiting_choice); the
## battle loop pauses meanwhile and calls choose().

const RunBoons = preload("res://scripts/run/RunBoons.gd")

const WAVE_SIDE := 1
## Wave budget: BUDGET_BASE + BUDGET_STEP * n + BUDGET_CURVE * n² (static so balance tools can try values).
## Tuned so an automatic player (random or greedy boon picks) falls around wave 6-9: people play much better
## than the bot, so the bot must clearly lose.
static var BUDGET_BASE := 60.0
static var BUDGET_STEP := 40.0
static var BUDGET_CURVE := 4.0
## Units of one wave arrive spread over this many seconds.
const SPAWN_WINDOW := 25.0
## A wave that is still alive this long after it began no longer holds back the next one.
const PRESSURE_SECONDS := 45.0
## Defenders hold this far from the wave side's edge, out of reach (even with range boons) of where waves
## appear, so every wave walks into the fight instead of being caught as it spawns.
const HOLD_DISTANCE := 600.0
## The same boon can be taken this many times.
const MAX_BOON_STACK := 3
const CLEAR_BONUS := 40.0
const BOSS_BONUS := 80.0
const BOSS_EVERY := 5
const INTERMISSION := 3.0
## From wave GROWTH_FROM on, wave units grow this much stronger every five waves.
static var GROWTH_STEP := 0.20
static var GROWTH_FROM := 5

const TIERS := [
	{"from": 1, "units": ["swordsman", "archer", "shield", "zombie", "berserker"]},
	{"from": 5, "units": ["warlock", "paladin", "sniper", "healer", "necromancer"]},
	{"from": 10, "units": ["demon_lord"]},
]

var rng := RandomNumberGenerator.new()
var seed_value := 0
## The wave in progress (0 before the first).
var wave := 0
var wave_started_at := 0.0
## {"t": seconds after the wave began, "kind"} not yet on the field, oldest first.
var queue: Array = []
var intermission := 0.0
var awaiting_choice := false
var offers: Array = []
var boons: Array = []
## Waves whose clear has not been rewarded yet.
var unrewarded := 0
var resources_awarded := 0.0

func _init(run_seed: int, start_wave: int = 1, owned_boons: Array = []) -> void:
	seed_value = run_seed
	rng.seed = run_seed
	wave = maxi(0, start_wave - 1)
	boons = owned_boons.duplicate()
	intermission = INTERMISSION

## Prepares `model` for endless defense: the wave side has no base and the defender owns `boons`.
func setup(model: BattleModel) -> void:
	model.invulnerable_bases[WAVE_SIDE] = true
	model.advance_limit[1 - WAVE_SIDE] = BattleModel.FIELD_RIGHT - HOLD_DISTANCE
	model.unit_decks[WAVE_SIDE] = []
	model.structure_decks[WAVE_SIDE] = []
	model.resources[WAVE_SIDE] = 0.0
	var start := float(model.resources[1 - WAVE_SIDE])
	model.configure_modifiers(1 - WAVE_SIDE, RunBoons.combine(boons))
	model.resources[1 - WAVE_SIDE] = maxf(start, model.resources[1 - WAVE_SIDE])

static func is_boss_wave(number: int) -> bool:
	return number > 0 and number % BOSS_EVERY == 0

static func budget(number: int) -> float:
	return BUDGET_BASE + BUDGET_STEP * float(number) + BUDGET_CURVE * float(number * number)

## Wave units' health and damage multiplier.
static func growth(number: int) -> float:
	return pow(1.0 + GROWTH_STEP, float((number - GROWTH_FROM) / 5 + 1)) if number >= GROWTH_FROM else 1.0

static func pool(number: int) -> Array:
	var kinds: Array = []
	for tier in TIERS:
		if number >= int(tier.from):
			kinds.append_array(tier.units)
	return kinds

## The units of wave `number` with their arrival times, drawn with `random`.
static func plan(number: int, random: RandomNumberGenerator) -> Array:
	var entries: Array = []
	var left := budget(number)
	var kinds := pool(number)
	if is_boss_wave(number):
		for index in 1 + number / 15:
			entries.append({"t": 1.0 + 2.0 * index, "kind": "demon_lord" if number >= 10 or index > 0 else "paladin"})
			left -= float(BattleModel.UNIT_STATS["demon_lord" if number >= 10 else "paladin"].cost)
		left = maxf(left, budget(number) * 0.4)
	var cheapest := 1000.0
	for kind in kinds:
		cheapest = minf(cheapest, float(BattleModel.UNIT_STATS[kind].cost))
	while left >= cheapest and entries.size() < 60:
		var kind: String = kinds[random.randi_range(0, kinds.size() - 1)]
		var cost := float(BattleModel.UNIT_STATS[kind].cost)
		if cost > left:
			continue
		left -= cost
		entries.append({"t": random.randf_range(0.0, SPAWN_WINDOW), "kind": kind})
	entries.sort_custom(func(a, b): return float(a.t) < float(b.t))
	return entries

func update(model: BattleModel, delta: float) -> void:
	if model.winner != -1 or awaiting_choice:
		return
	if wave == 0 or (queue.is_empty() and _enemies(model) == 0):
		if wave > 0 and unrewarded > 0:
			_reward(model)
			return
		intermission -= delta
		if intermission <= 0.0:
			_begin_wave(model)
		return
	# A wave that is still alive (or still waiting to come in) after PRESSURE_SECONDS lets the next one in.
	if model.elapsed - wave_started_at >= PRESSURE_SECONDS:
		_begin_wave(model)
	_spawn_due(model)

func _begin_wave(model: BattleModel) -> void:
	wave += 1
	unrewarded += 1
	wave_started_at = model.elapsed
	intermission = INTERMISSION
	# Units an earlier wave could not field yet come first.
	var leftover: Array = queue.map(func(entry): return {"t": 0.0, "kind": entry.kind})
	queue = leftover + plan(wave, rng)
	var scale := growth(wave)
	var mods := {}
	if not is_equal_approx(scale, 1.0):
		mods = {"hp:all": scale, "damage:all": scale}
	if is_boss_wave(wave):
		mods["hp:demon_lord"] = 1.5
		mods["hp:paladin"] = 1.5
	model.modifiers[WAVE_SIDE] = mods
	model.unit_decks[WAVE_SIDE] = pool(wave) + (["paladin"] if is_boss_wave(wave) and wave < 10 else [])
	model.combat_events.append({"type": "WAVE", "wave": wave, "boss": is_boss_wave(wave)})

func _spawn_due(model: BattleModel) -> void:
	var elapsed := model.elapsed - wave_started_at
	var waiting: Array = []
	for entry in queue:
		if float(entry.t) > elapsed:
			waiting.append(entry)
			continue
		model.resources[WAVE_SIDE] = 1000.0
		if not model.spawn_unit(WAVE_SIDE, String(entry.kind)):
			waiting.append(entry) # cooldown or field limit: try again next tick
	model.resources[WAVE_SIDE] = 0.0
	queue = waiting

func _enemies(model: BattleModel) -> int:
	var count := 0
	for unit in model.units:
		if int(unit.side) == WAVE_SIDE and (float(unit.hp) > 0.0 or unit.has("revive_remaining")):
			count += 1
	return count

func _reward(model: BattleModel) -> void:
	var side := 1 - WAVE_SIDE
	var bonus := (BOSS_BONUS if is_boss_wave(wave) else CLEAR_BONUS)
	model.resources[side] = minf(model.resource_capacity(side), model.resources[side] + bonus)
	resources_awarded += bonus
	unrewarded = 0
	# Boons stack up to MAX_BOON_STACK copies (one that does nothing twice, only once).
	offers = RunBoons.draw(rng, 3, maxed_boons(), is_boss_wave(wave), model.unit_decks[side], model.structure_decks[side])
	awaiting_choice = not offers.is_empty()

## Boons that cannot be offered again: taken MAX_BOON_STACK times, or one whose second copy does nothing.
func maxed_boons() -> Array:
	var maxed: Array = []
	for id in boons:
		if not maxed.has(id) and (boons.count(id) >= MAX_BOON_STACK or id == "ambush"):
			maxed.append(id)
	return maxed

## The player picked `id` from offers (or skipped with ""): the boon applies to the next units at once.
func choose(model: BattleModel, id: String) -> void:
	if not awaiting_choice:
		return
	if offers.has(id):
		boons.append(id)
		model.modifiers[1 - WAVE_SIDE] = RunBoons.combine(boons)
	offers = []
	awaiting_choice = false
	intermission = INTERMISSION

## Waves survived: every wave before the one in progress, whether it was cleared or the next one pushed in
## on top of it.
func waves_cleared() -> int:
	return maxi(0, wave - mini(unrewarded, 1))
