extends RefCounted
## 원정 (expedition): a roguelite run of three acts. Each act is a map of seven layers; the player picks one
## node per layer (battle, elite, rest, shop) and fights the act's boss at the end. The base's health carries
## over between battles, and cards, card upgrades (stars), relics and gold collected on the way make the
## run stronger. The run is plain data (saved in the profile under runs.expedition.saved); these functions
## are its rules. Everything random is drawn from the run's seed, so leaving and resuming changes nothing.

const RunBoons = preload("res://scripts/run/RunBoons.gd")

const ACTS := 3
const LAYERS := 7
const BASE_MAX := 500.0
const REST_HEAL := 0.3
const ACT_HEAL := 0.25
const GOLD_BATTLE := [20, 30]
const GOLD_ELITE := 50
const GOLD_BOSS := 100
const CARD_PRICE := [60, 90]
const RELIC_PRICE := [120, 160]
const UPGRADE_PRICE := 50
const HEAL_PRICE := 40
const HEAL_AMOUNT := 100.0
const REMOVE_PRICE := 30
const MAX_STARS := 2

## Stages of the regular battles of each act, by layer.
const ACT_STAGES := [[1, 1, 2, 2, 3, 3, 3], [4, 4, 5, 5, 6, 6, 6], [6, 7, 7, 8, 8, 8, 8]]
const ELITES := {
	"turtle": {"name": "거북 진형", "units": ["shield", "paladin", "healer", "archer"], "structures": ["wall", "turret", "generator", "blessing"]},
	"wraiths": {"name": "망령 부대", "units": ["zombie", "necromancer", "warlock", "swordsman"], "structures": ["swamp", "frost", "generator", "wall"]},
	"assassins": {"name": "암살대", "units": ["sniper", "berserker", "archer", "swordsman"], "structures": ["lightning", "fireball", "generator", "swamp"]},
}
const BOSSES := [
	{"id": "swamp_shaman", "name": "늪지기 주술사", "units": ["warlock", "zombie", "healer", "shield"], "structures": ["swamp", "frost", "generator", "wall"], "stage": 3, "base": 450.0, "scale": 1.0},
	{"id": "undead_lord", "name": "언데드 군주", "units": ["necromancer", "zombie", "paladin", "warlock"], "structures": ["seraph", "swamp", "generator", "wall"], "stage": 6, "base": 500.0, "scale": 1.15},
	{"id": "demon_king", "name": "마왕", "units": ["demon_lord", "sniper", "shield", "healer"], "structures": ["seraph", "lightning", "turret", "generator"], "stage": 8, "base": 500.0, "scale": 1.2},
]
## Enemy health and damage in expedition battles, relative to the same AI stage in the campaign. A run asks for
## some twenty wins in a row, so regular battles are easier than their campaign stage. Tuned with an automatic
## player (random rewards, elites half the time): about a quarter to a third of its runs clear all three acts.
static var REGULAR_SCALE := 0.8
static var ELITE_SCALE := 0.95
static var BOSS_SCALE := 0.95

static func rng_for(run: Dictionary, tag: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([int(run.seed), int(run.act), int(run.layer), tag])
	return rng

## A fresh run with the starter deck (four units and four tactics) and one starting relic.
static func create(run_seed: int, units: Array, structures: Array, relic: String) -> Dictionary:
	var run := {"seed": run_seed, "act": 1, "layer": 0, "map": [], "cards": {"units": units.duplicate(), "structures": structures.duplicate()},
		"deck": {"units": units.duplicate(), "structures": structures.duplicate()}, "stars": {}, "relics": [relic] if RunBoons.RELICS.has(relic) else [],
		"gold": 0, "base_hp": BASE_MAX, "status": "map", "node_index": -1, "node": {}, "reward": {}, "shop": {}, "won_battles": 0}
	run.map = generate_act(run_seed, 1)
	return run

## Three starting relics to pick from.
static func starting_relics(run_seed: int, units: Array, structures: Array) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, "start"])
	return RunBoons.draw(rng, 3, [], false, units, structures)

## Layers of act `act`: two opening battles, three layers of mixed nodes, a rest-or-shop layer, the boss.
static func generate_act(run_seed: int, act: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, act, "map"])
	var layers: Array = []
	for layer in LAYERS:
		var nodes: Array = []
		if layer == LAYERS - 1:
			nodes.append({"type": "boss"})
		elif layer == LAYERS - 2:
			nodes = [{"type": "rest"}, {"type": "shop"}]
		elif layer == 0:
			nodes = [{"type": "battle"}, {"type": "battle"}]
		else:
			var kinds := ["battle", "battle", "elite", "rest", "shop"] if layer >= 2 else ["battle", "battle", "rest", "shop"]
			var count := 3
			var picked := {}
			while nodes.size() < count:
				var kind: String = kinds[rng.randi_range(0, kinds.size() - 1)]
				if kind != "battle" and picked.has(kind):
					continue
				picked[kind] = true
				nodes.append({"type": kind})
			if not nodes.any(func(node): return node.type == "battle" or node.type == "elite"):
				nodes[0] = {"type": "battle"}
		for node in nodes:
			if node.type in ["battle", "elite", "boss"]:
				node["enemy"] = _enemy(rng, act, layer, String(node.type))
		layers.append(nodes)
	return layers

static func _enemy(rng: RandomNumberGenerator, act: int, layer: int, kind: String) -> Dictionary:
	var stage: int = ACT_STAGES[act - 1][layer]
	match kind:
		"boss":
			var boss: Dictionary = BOSSES[act - 1]
			return {"name": boss.name, "units": boss.units.duplicate(), "structures": boss.structures.duplicate(), "stage": int(boss.stage),
				"base": float(boss.base), "mods": _scaled(float(boss.scale) * BOSS_SCALE)}
		"elite":
			var ids := ELITES.keys()
			ids.sort()
			var id: String = ids[rng.randi_range(0, ids.size() - 1)]
			var elite: Dictionary = ELITES[id]
			return {"name": elite.name, "units": elite.units.duplicate(), "structures": elite.structures.duplicate(), "stage": stage,
				"base": 300.0 + stage * 25.0, "mods": _scaled(ELITE_SCALE)}
	return {"name": ServerAI.stage_name(stage), "units": ServerAI.stage_unit_deck(stage), "structures": ServerAI.stage_structure_deck(stage),
		"stage": stage, "base": 300.0 + stage * 20.0, "mods": _scaled(REGULAR_SCALE)}

static func _scaled(scale: float) -> Dictionary:
	return {} if is_equal_approx(scale, 1.0) else {"hp:all": scale, "damage:all": scale}

static func current_nodes(run: Dictionary) -> Array:
	return run.map[int(run.layer)] if int(run.layer) < run.map.size() else []

static func modifiers(run: Dictionary) -> Dictionary:
	return RunBoons.combine(run.relics, run.stars)

## Enters node `index` of the current layer.
static func choose_node(run: Dictionary, index: int) -> bool:
	var nodes := current_nodes(run)
	if String(run.status) != "map" or index < 0 or index >= nodes.size():
		return false
	run.node_index = index
	run.node = nodes[index].duplicate(true)
	match String(run.node.type):
		"rest":
			run.status = "rest"
		"shop":
			run.status = "shop"
			run.shop = _stock(run)
		_:
			run.status = "battle"
	return true

## The battle of the current node: {"model", "ai", "enemy"}.
static func build_battle(run: Dictionary) -> Dictionary:
	var enemy: Dictionary = run.node.enemy
	var model := BattleModel.new()
	model.configure_deck(0, run.deck.units, run.deck.structures)
	model.configure_deck(1, enemy.units, enemy.structures)
	# The same growth a campaign player has at this stage; relics and stars come on top.
	model.configure_campaign_growth(0, int(enemy.stage) - 1)
	model.configure_modifiers(0, modifiers(run))
	model.base_hp[0] = clampf(float(run.base_hp), 1.0, BASE_MAX)
	model.configure_base_health(1, float(enemy.base))
	model.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(enemy.stage) * 10.0)
	model.modifiers[1] = enemy.mods.duplicate()
	return {"model": model, "ai": ServerAI.new(1, int(enemy.stage)), "enemy": enemy}

## After the battle of the current node. A win keeps the remaining base health and offers rewards.
static func finish_battle(run: Dictionary, won: bool, base_left: float) -> void:
	if String(run.status) != "battle":
		return
	if not won:
		run.status = "lost"
		run.base_hp = 0.0
		return
	run.base_hp = clampf(base_left, 1.0, BASE_MAX)
	run.won_battles = int(run.won_battles) + 1
	run.reward = _reward(run)
	run.gold = int(run.gold) + int(run.reward.gold)
	run.status = "reward"

## The reward of the current node's battle (drawn from the seed, so a resumed run shows the same one).
static func _reward(run: Dictionary) -> Dictionary:
	var rng := rng_for(run, "reward")
	var kind := String(run.node.type)
	var gold := rng.randi_range(GOLD_BATTLE[0], GOLD_BATTLE[1]) if kind == "battle" else (GOLD_ELITE if kind == "elite" else GOLD_BOSS)
	var relics: Array = []
	if kind != "battle":
		relics = RunBoons.draw(rng, 1, run.relics, kind == "boss", run.cards.units, run.cards.structures)
	return {"gold": gold, "cards": card_offers(run, rng, 3), "relics": relics}

## Up to `count` cards the run does not own yet, mixing units and tactics.
static func card_offers(run: Dictionary, rng: RandomNumberGenerator, count: int) -> Array:
	var pool: Array = []
	for kind in BattleModel.UNIT_STATS:
		if not run.cards.units.has(kind):
			pool.append(String(kind))
	for kind in BattleModel.STRUCTURE_STATS:
		if not run.cards.structures.has(kind):
			pool.append(String(kind))
	pool.sort()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked

static func add_card(run: Dictionary, kind: String) -> bool:
	var group := "units" if BattleModel.UNIT_STATS.has(kind) else ("structures" if BattleModel.STRUCTURE_STATS.has(kind) else "")
	if group.is_empty() or run.cards[group].has(kind):
		return false
	run.cards[group].append(kind)
	return true

## Takes the reward card `kind` ("" skips it) and the reward relic, then returns to the map.
static func take_reward(run: Dictionary, kind: String) -> void:
	if String(run.status) != "reward":
		return
	if not kind.is_empty() and run.reward.cards.has(kind):
		add_card(run, kind)
	for relic in run.reward.relics:
		if not run.relics.has(relic):
			run.relics.append(relic)
	run.reward = {}
	_advance(run)

static func can_upgrade(run: Dictionary, kind: String) -> bool:
	return (run.deck.units.has(kind) or run.deck.structures.has(kind)) and int(run.stars.get(kind, 0)) < MAX_STARS

static func upgrade(run: Dictionary, kind: String) -> bool:
	if not can_upgrade(run, kind):
		return false
	run.stars[kind] = int(run.stars.get(kind, 0)) + 1
	return true

## Rest: heal 30% of the base, or upgrade one card of the deck.
static func rest(run: Dictionary, upgrade_kind: String = "") -> bool:
	if String(run.status) != "rest":
		return false
	if upgrade_kind.is_empty():
		run.base_hp = minf(BASE_MAX, float(run.base_hp) + BASE_MAX * REST_HEAL)
	elif not upgrade(run, upgrade_kind):
		return false
	_advance(run)
	return true

static func _stock(run: Dictionary) -> Dictionary:
	var rng := rng_for(run, "shop")
	var cards: Array = []
	for kind in card_offers(run, rng, 3):
		cards.append({"kind": kind, "price": rng.randi_range(CARD_PRICE[0], CARD_PRICE[1]), "sold": false})
	var relics: Array = []
	for id in RunBoons.draw(rng, 1, run.relics, false, run.cards.units, run.cards.structures):
		relics.append({"id": id, "price": rng.randi_range(RELIC_PRICE[0], RELIC_PRICE[1]), "sold": false})
	return {"cards": cards, "relics": relics, "healed": false, "removed": false}

## Shop purchases. `what`: "card", "relic" (with the item index), "heal", "upgrade" or "remove" (with a card kind).
static func buy(run: Dictionary, what: String, index: int = -1, kind: String = "") -> bool:
	if String(run.status) != "shop":
		return false
	var shop: Dictionary = run.shop
	match what:
		"card", "relic":
			var items: Array = shop.cards if what == "card" else shop.relics
			if index < 0 or index >= items.size() or bool(items[index].sold) or int(run.gold) < int(items[index].price):
				return false
			if what == "card":
				add_card(run, String(items[index].kind))
			else:
				run.relics.append(String(items[index].id))
			run.gold = int(run.gold) - int(items[index].price)
			items[index].sold = true
		"heal":
			if bool(shop.healed) or int(run.gold) < HEAL_PRICE or float(run.base_hp) >= BASE_MAX:
				return false
			run.gold = int(run.gold) - HEAL_PRICE
			run.base_hp = minf(BASE_MAX, float(run.base_hp) + HEAL_AMOUNT)
			shop.healed = true
		"upgrade":
			if int(run.gold) < UPGRADE_PRICE or not upgrade(run, kind):
				return false
			run.gold = int(run.gold) - UPGRADE_PRICE
		"remove":
			if bool(shop.removed) or int(run.gold) < REMOVE_PRICE or not can_remove(run, kind):
				return false
			var group := "units" if run.cards.units.has(kind) else "structures"
			run.cards[group].erase(kind)
			run.stars.erase(kind)
			run.gold = int(run.gold) - REMOVE_PRICE
			shop.removed = true
		_:
			return false
	return true

## A card can go when it is not in the battle deck (the deck always keeps four of each).
static func can_remove(run: Dictionary, kind: String) -> bool:
	return (run.cards.units.has(kind) or run.cards.structures.has(kind)) and not run.deck.units.has(kind) and not run.deck.structures.has(kind)

static func leave_shop(run: Dictionary) -> void:
	if String(run.status) == "shop":
		run.shop = {}
		_advance(run)

## Sets the battle deck: four units and four tactics from the collection.
static func set_deck(run: Dictionary, units: Array, structures: Array) -> bool:
	if not BattleModel._valid_deck(units, BattleModel.UNIT_STATS) or not BattleModel._valid_deck(structures, BattleModel.STRUCTURE_STATS):
		return false
	if not units.all(func(kind): return run.cards.units.has(kind)) or not structures.all(func(kind): return run.cards.structures.has(kind)):
		return false
	run.deck = {"units": units.duplicate(), "structures": structures.duplicate()}
	return true

static func _advance(run: Dictionary) -> void:
	run.node = {}
	run.node_index = -1
	run.layer = int(run.layer) + 1
	run.status = "map"
	if int(run.layer) < LAYERS:
		return
	if int(run.act) >= ACTS:
		run.status = "won"
		return
	run.act = int(run.act) + 1
	run.layer = 0
	run.map = generate_act(int(run.seed), int(run.act))
	run.base_hp = minf(BASE_MAX, float(run.base_hp) + BASE_MAX * ACT_HEAL)

## How far the run got, for records: nodes cleared over all acts (ACTS * LAYERS for a won run).
static func progress(run: Dictionary) -> int:
	return mini(ACTS * LAYERS, (int(run.act) - 1) * LAYERS + int(run.layer))

## What a run looks like when saved: the derived parts (map, enemies, offers) are rebuilt from the seed on load.
static func to_saved(run: Dictionary) -> Dictionary:
	var shop: Dictionary = run.get("shop", {})
	return {"seed": int(run.seed), "act": int(run.act), "layer": int(run.layer), "cards": run.cards.duplicate(true), "deck": run.deck.duplicate(true),
		"stars": run.stars.duplicate(), "relics": run.relics.duplicate(), "gold": int(run.gold), "base_hp": float(run.base_hp),
		"status": String(run.status), "node_index": int(run.node_index), "won_battles": int(run.won_battles),
		"sold_cards": range(shop.get("cards", []).size()).filter(func(i): return bool(shop.cards[i].sold)),
		"sold_relics": range(shop.get("relics", []).size()).filter(func(i): return bool(shop.relics[i].sold)),
		"healed": bool(shop.get("healed", false)), "removed": bool(shop.get("removed", false))}

static func _int(value: Variant, low: int, high: int, fallback: int = -1) -> int:
	if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and float(value) >= low and float(value) <= high:
		return int(value)
	return fallback

static func _kinds(value: Variant, allowed: Dictionary, minimum: int) -> Array:
	if not value is Array or value.size() < minimum or value.size() > allowed.size():
		return []
	var result: Array = []
	for kind in value:
		if not kind is String or not allowed.has(kind) or result.has(kind):
			return []
		result.append(kind)
	return result

## A run from a save file, or {} when it is not a valid run.
static func from_saved(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var run_seed := _int(raw.get("seed"), 0, 2147483647)
	var act := _int(raw.get("act"), 1, ACTS)
	var layer := _int(raw.get("layer"), 0, LAYERS - 1)
	var status := String(raw.get("status", "")) if raw.get("status") is String else ""
	if run_seed < 0 or act < 0 or layer < 0 or not status in ["map", "battle", "reward", "rest", "shop"]:
		return {}
	if not raw.get("cards") is Dictionary or not raw.get("deck") is Dictionary:
		return {}
	var cards := {"units": _kinds(raw.cards.get("units"), BattleModel.UNIT_STATS, BattleModel.DECK_SIZE), "structures": _kinds(raw.cards.get("structures"), BattleModel.STRUCTURE_STATS, BattleModel.DECK_SIZE)}
	if cards.units.is_empty() or cards.structures.is_empty():
		return {}
	var run := {"seed": run_seed, "act": act, "layer": layer, "map": generate_act(run_seed, act), "cards": cards, "deck": {}, "stars": {}, "relics": [],
		"gold": _int(raw.get("gold"), 0, 1000000, 0), "base_hp": 0.0, "status": "map", "node_index": -1, "node": {}, "reward": {}, "shop": {},
		"won_battles": _int(raw.get("won_battles"), 0, 1000, 0)}
	if not set_deck(run, raw.deck.get("units", []) if raw.deck.get("units") is Array else [], raw.deck.get("structures", []) if raw.deck.get("structures") is Array else []):
		return {}
	var base = raw.get("base_hp")
	if not (base is int or base is float) or not is_finite(float(base)) or float(base) <= 0.0:
		return {}
	run.base_hp = minf(float(base), BASE_MAX)
	if raw.get("stars") is Dictionary:
		for kind in raw.stars:
			var level := _int(raw.stars[kind], 1, MAX_STARS)
			if kind is String and level > 0 and (cards.units.has(kind) or cards.structures.has(kind)):
				run.stars[kind] = level
	if raw.get("relics") is Array:
		for id in raw.relics:
			if id is String and RunBoons.RELICS.has(id) and not run.relics.has(id):
				run.relics.append(id)
	if status != "map":
		var index := _int(raw.get("node_index"), 0, current_nodes(run).size() - 1)
		if index < 0:
			return {}
		run.node_index = index
		run.node = current_nodes(run)[index].duplicate(true)
		var expected: String = {"rest": "rest", "shop": "shop"}.get(String(run.node.type), "battle")
		if status != expected and not (status == "reward" and expected == "battle"):
			return {}
		run.status = status
		if status == "reward":
			run.reward = _reward(run)
		elif status == "shop":
			run.shop = _stock(run)
			for key in [["sold_cards", "cards"], ["sold_relics", "relics"]]:
				if raw.get(key[0]) is Array:
					for i in raw[key[0]]:
						var item := _int(i, 0, run.shop[key[1]].size() - 1)
						if item >= 0:
							run.shop[key[1]][item].sold = true
			run.shop.healed = raw.get("healed") == true
			run.shop.removed = raw.get("removed") == true
	return run
