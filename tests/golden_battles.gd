extends RefCounted
## A fixed corpus of battles for checking that optimizations leave the battle rules bit-for-bit unchanged. Each
## scenario runs from fixed seeds and folds, every tick, the full snapshot (17 significant digits, sorted keys)
## and that tick's combat events into one SHA-256 digest. determinism_golden_test.gd compares the digests with
## tests/golden/battle_digests.json, recorded from the code before any optimization.

const AutoPlayer = preload("res://scripts/AutoPlayer.gd")
const WaveDirector = preload("res://scripts/run/WaveDirector.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")

const DT := 1.0 / 30.0

## name -> description; run(name) plays it.
static func scenarios() -> Array:
	return [
		{"name": "melee_mix", "a": ["shield", "swordsman", "berserker", "paladin"], "b": ["zombie", "necromancer", "warlock", "demon_lord"], "ta": ["wall", "turret", "generator", "swamp"], "tb": ["lightning", "fireball", "frost", "blessing"], "seconds": 150.0, "boost": 0.0, "seed": 11},
		{"name": "ranged_mix", "a": ["archer", "sniper", "healer", "shield"], "b": ["archer", "warlock", "healer", "berserker"], "ta": ["seraph", "turret", "swamp", "fireball"], "tb": ["wall", "generator", "frost", "lightning"], "seconds": 150.0, "boost": 0.0, "seed": 23},
		{"name": "undead", "a": ["necromancer", "zombie", "demon_lord", "healer"], "b": ["paladin", "shield", "sniper", "swordsman"], "ta": ["blessing", "swamp", "wall", "seraph"], "tb": ["turret", "fireball", "generator", "lightning"], "seconds": 150.0, "boost": 0.0, "seed": 37},
		{"name": "crowd_boosted", "a": ["shield", "archer", "swordsman", "healer"], "b": ["berserker", "zombie", "archer", "paladin"], "ta": ["wall", "turret", "swamp", "lightning"], "tb": ["fireball", "frost", "generator", "blessing"], "seconds": 120.0, "boost": 3.0, "seed": 41},
		{"name": "crowd_uncapped", "a": ["swordsman", "archer", "shield", "healer"], "b": ["swordsman", "zombie", "shield", "warlock"], "ta": ["wall", "swamp", "turret", "fireball"], "tb": ["frost", "seraph", "wall", "lightning"], "seconds": 45.0, "boost": 40.0, "uncapped": true, "seed": 53},
		{"name": "campaign_3", "ai_stage": 3, "a": ["shield", "archer", "healer", "swordsman"], "ta": ["wall", "turret", "generator", "fireball"], "seconds": 180.0, "seed": 61},
		{"name": "campaign_8", "ai_stage": 8, "a": ["paladin", "sniper", "demon_lord", "healer"], "ta": ["blessing", "seraph", "swamp", "lightning"], "seconds": 180.0, "seed": 67, "growth": 4},
		{"name": "endless", "endless": true, "a": ["shield", "paladin", "archer", "healer"], "ta": ["wall", "turret", "lightning", "frost"], "seconds": 300.0, "seed": 71},
		{"name": "endless_boons", "endless": true, "boons": ["steel_plate", "eagle_eye", "recruiter", "bone_urn", "war_drum", "aegis"], "a": ["necromancer", "demon_lord", "sniper", "swordsman"], "ta": ["swamp", "fireball", "seraph", "generator"], "seconds": 240.0, "seed": 79},
	]

static func run(scenario: Dictionary) -> String:
	var model := BattleModel.new()
	var players: Array = []
	var ai: ServerAI = null
	var director = null
	model.configure_deck(0, scenario.a, scenario.ta)
	if scenario.has("growth"):
		model.configure_campaign_growth(0, int(scenario.growth))
	if scenario.has("ai_stage"):
		var stage := int(scenario.ai_stage)
		model.configure_deck(1, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
		model.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(stage) * 10.0)
		model.configure_base_health(1, 300.0 + float(stage) * 20.0)
		ai = ServerAI.new(1, stage)
	elif bool(scenario.get("endless", false)):
		var boons: Array = scenario.get("boons", [])
		director = WaveDirector.new(int(scenario.seed), 1, boons)
		director.setup(model)
		if not boons.is_empty():
			model.modifiers[0] = RunBoons.combine(boons)
	else:
		model.configure_deck(1, scenario.b, scenario.tb)
		players.append(AutoPlayer.new(1, "weighted", int(scenario.seed) + 1, scenario.b))
	players.push_front(AutoPlayer.new(0, "weighted" if int(scenario.seed) % 2 == 1 else "cycle", int(scenario.seed), scenario.a))
	if bool(scenario.get("uncapped", false)):
		for side in 2:
			model.cheats[side]["army_cap"] = true
			model.cheats[side]["no_cap"] = true
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	var ticks := int(float(scenario.seconds) / DT)
	for step in ticks:
		for player in players:
			player.update(model, DT)
		if ai != null:
			ai.update(model, DT)
		if director != null:
			if director.awaiting_choice:
				director.choose(model, String(director.offers[0]) if director.offers[0] is String else String(director.offers[0].id))
			director.update(model, DT)
		var boost := float(scenario.get("boost", 0.0))
		if boost > 0.0:
			for side in 2:
				model.resources[side] = minf(model.resource_capacity(side), float(model.resources[side]) + boost)
			if bool(scenario.get("uncapped", false)):
				# Flood the field: every card as often as the rules allow.
				for side in 2:
					model.spawn_cooldowns[side].clear()
					for kind in model.unit_decks[side]:
						model.spawn_unit(side, String(kind))
		model.tick(DT)
		var data := model.snapshot()
		hashing.update(JSON.stringify(data, "", true, true).to_utf8_buffer())
		hashing.update(JSON.stringify(model.drain_combat_events(), "", true, true).to_utf8_buffer())
		if model.winner != -1:
			break
	return hashing.finish().hex_encode()
