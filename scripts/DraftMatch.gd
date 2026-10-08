extends RefCounted
## Draft mode: the player and an AI take turns picking units from one shared pool, each unit only once, so a
## good pick also denies it to the opponent. The drafted decks then fight a normal AI battle.

const PICKS_PER_SIDE := 3
const MIN_STAGE := 1
## Roles that make a deck balanced; the AI likes to cover each of them once.
const GROUPS := {"shield": "tank", "swordsman": "melee", "berserker": "melee", "archer": "ranged", "healer": "support", "warlock": "support", "necromancer": "support"}

static func pool() -> Array:
	return BattleModel.UNIT_STATS.keys()

## Raw durability-and-damage per cost; used only for the AI's taste, not for any game rule.
static func efficiency(kind: String) -> float:
	var stats: Dictionary = BattleModel.UNIT_STATS[kind]
	var damage_rate := float(stats.damage) / maxf(0.1, float(stats.interval))
	return float(stats.hp) * (damage_rate + 1.0) / maxf(1.0, float(stats.cost))

class Draft extends RefCounted:
	var stage := 3
	var available: Array = []
	var mine: Array = []
	var theirs: Array = []
	var rng := RandomNumberGenerator.new()

	func _init(difficulty: int = 3, seed_value: int = -1) -> void:
		stage = clampi(difficulty, 1, ServerAI.MAX_STAGE)
		available = preload("res://scripts/DraftMatch.gd").pool()
		if seed_value >= 0:
			rng.seed = seed_value
		else:
			rng.randomize()

	func done() -> bool:
		return mine.size() >= preload("res://scripts/DraftMatch.gd").PICKS_PER_SIDE and theirs.size() >= preload("res://scripts/DraftMatch.gd").PICKS_PER_SIDE

	## The player picks, then the AI answers at once (the screen animates the reply). Returns the AI's pick or "".
	func human_pick(kind: String) -> String:
		if not available.has(kind) or mine.size() >= preload("res://scripts/DraftMatch.gd").PICKS_PER_SIDE:
			return ""
		available.erase(kind)
		mine.append(kind)
		return ai_pick() if available.size() > 0 and theirs.size() < preload("res://scripts/DraftMatch.gd").PICKS_PER_SIDE else ""

	func ai_pick() -> String:
		var choice := preload("res://scripts/DraftMatch.gd").choose(available, theirs, mine, stage, rng)
		if choice.is_empty():
			return ""
		available.erase(choice)
		theirs.append(choice)
		return choice

## The AI's choice from `options`. Weaker stages are noisier, so low stages draft sloppily.
static func choose(options: Array, own: Array, rival: Array, difficulty: int, rng: RandomNumberGenerator) -> String:
	if options.is_empty():
		return ""
	var lowest := INF
	var highest := -INF
	for kind in pool():
		lowest = minf(lowest, efficiency(String(kind)))
		highest = maxf(highest, efficiency(String(kind)))
	var held := {}
	for kind in own:
		held[String(GROUPS.get(kind, ""))] = true
	var noise := maxf(0.08, 0.5 - 0.06 * float(difficulty))
	var best := ""
	var best_score := -INF
	for kind in options:
		var score := (efficiency(String(kind)) - lowest) / maxf(0.001, highest - lowest)
		var group := String(GROUPS.get(kind, ""))
		score += -0.3 if held.has(group) else 0.15
		if String(kind) == "shield" and not held.has("tank"):
			score += 0.1
		if String(kind) == "healer" and rival.has("archer"):
			score -= 0.05
		score += rng.randf_range(-noise, noise)
		if score > best_score:
			best_score = score
			best = String(kind)
	return best

## {"model", "ai", "stage"} for the fight: the same setup as an AI practice battle at that stage, with the drafted decks.
static func build(my_units: Array, my_structures: Array, enemy_units: Array, enemy_structures: Array, difficulty: int) -> Dictionary:
	var stage := clampi(difficulty, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
	var model := BattleModel.new()
	model.configure_campaign_growth(0, stage - 1)
	model.configure_deck(0, my_units, my_structures)
	model.configure_deck(1, enemy_units, enemy_structures)
	model.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(stage) * 10.0)
	model.configure_base_health(1, 300.0 + float(stage) * 20.0)
	return {"model": model, "ai": ServerAI.new(1, stage), "stage": stage}
