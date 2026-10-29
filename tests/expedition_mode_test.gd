extends SceneTree
## Expedition: maps, battles with carried base health, rewards, rest, shop, deck rules, acts, saving and
## resuming, records, and the screen flow from the menu through a battle to the reward.

const ExpeditionRun = preload("res://scripts/run/ExpeditionRun.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")
const RunRecords = preload("res://scripts/run/RunRecords.gd")
const ExpeditionFlow = preload("res://scripts/screens/ExpeditionFlow.gd")
const UNITS := ["shield", "archer", "healer", "swordsman"]
const TACTICS := ["wall", "turret", "generator", "swamp"]
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func node_index(run: Dictionary, kind: String) -> int:
	var nodes := ExpeditionRun.current_nodes(run)
	for i in nodes.size():
		if String(nodes[i].type) == kind:
			return i
	return -1

func run() -> void:
	# Maps.
	var map := ExpeditionRun.generate_act(77, 1)
	check(map.size() == ExpeditionRun.LAYERS, "an act has seven layers")
	check(map[0].all(func(node): return node.type == "battle") and map.back().size() == 1 and map.back()[0].type == "boss", "acts open with battles and end with the boss")
	check(map[ExpeditionRun.LAYERS - 2].map(func(node): return node.type) == ["rest", "shop"], "a rest or a shop comes before the boss")
	check(not map[1].any(func(node): return node.type == "elite"), "no elites on the second layer")
	check(map == ExpeditionRun.generate_act(77, 1) and map != ExpeditionRun.generate_act(78, 1), "maps follow the seed")
	for layer in map:
		check(layer.any(func(node): return node.type in ["battle", "elite", "boss"]) or layer.all(func(node): return node.type in ["rest", "shop"]), "mixed layers always offer a fight")
	check(ExpeditionRun.generate_act(77, 3).back()[0].enemy.units.has("demon_lord"), "the last boss is the demon king")
	var relics := ExpeditionRun.starting_relics(77, UNITS, TACTICS)
	check(relics.size() == 3 and relics.all(func(id): return RunBoons.relevant(id, UNITS, TACTICS)), "three starting relics that suit the deck")

	# A battle.
	var trip := ExpeditionRun.create(77, UNITS, TACTICS, "steel_plate")
	check(trip.relics == ["steel_plate"] and float(trip.base_hp) == ExpeditionRun.BASE_MAX and trip.status == "map", "a new run")
	check(not ExpeditionRun.choose_node(trip, 9), "only nodes of the current layer")
	check(ExpeditionRun.choose_node(trip, 0) and trip.status == "battle", "entering a battle node")
	trip.base_hp = 320.0
	trip.stars["archer"] = 1
	var battle := ExpeditionRun.build_battle(trip)
	var model: BattleModel = battle.model
	check(model.base_hp[0] == 320.0 and model.base_max_hp[0] == ExpeditionRun.BASE_MAX, "the battle starts with the carried base health")
	check(model.modifiers[0].has("hp:melee") and int(model.modifiers[0].stars.archer) == 1, "relics and stars apply")
	check(model.unit_decks[1] == trip.node.enemy.units and battle.ai is ServerAI, "the node's enemy fights")
	check(is_equal_approx(float(model.modifiers[1].get("hp:all", 1.0)), ExpeditionRun.REGULAR_SCALE), "regular battles are softened")
	var gold_before := int(trip.gold)
	ExpeditionRun.finish_battle(trip, true, 250.0)
	check(trip.status == "reward" and float(trip.base_hp) == 250.0 and int(trip.gold) > gold_before, "a win keeps the base left and pays gold")
	check(trip.reward.cards.size() == 3 and trip.reward.cards.all(func(kind): return not UNITS.has(kind) and not TACTICS.has(kind)), "three new cards are offered")
	check(trip.reward.relics.is_empty(), "regular battles give no relic")
	var card: String = trip.reward.cards[0]
	ExpeditionRun.take_reward(trip, card)
	check((trip.cards.units.has(card) or trip.cards.structures.has(card)) and trip.layer == 1 and trip.status == "map", "taking a card advances the map")
	check(trip.deck.units == UNITS and trip.deck.structures == TACTICS, "new cards wait outside the deck")

	# Deck rules.
	check(not ExpeditionRun.set_deck(trip, ["shield", "archer", "healer"], TACTICS), "a deck needs four units")
	check(not ExpeditionRun.set_deck(trip, ["shield", "archer", "healer", "demon_lord"] if card != "demon_lord" else ["shield", "archer", "healer", "sniper"], TACTICS), "a deck uses owned cards only")
	if BattleModel.UNIT_STATS.has(card):
		check(ExpeditionRun.set_deck(trip, ["shield", "archer", "healer", card], TACTICS) and trip.deck.units.has(card), "owned cards can join the deck")
	# Rest.
	trip.status = "rest"
	check(ExpeditionRun.rest(trip) and float(trip.base_hp) == 250.0 + ExpeditionRun.BASE_MAX * ExpeditionRun.REST_HEAL, "resting heals 30%")
	trip.status = "rest"
	check(ExpeditionRun.rest(trip, "shield") and int(trip.stars.shield) == 1, "or upgrades a card")
	trip.status = "rest"
	trip.stars["shield"] = 2
	check(not ExpeditionRun.rest(trip, "shield") and trip.status == "rest", "two stars is the most")
	# Shop.
	trip.status = "map"
	trip.layer = ExpeditionRun.LAYERS - 2
	check(ExpeditionRun.choose_node(trip, node_index(trip, "shop")) and trip.status == "shop" and trip.shop.cards.size() == 3, "a shop sells three cards")
	trip.gold = 0
	check(not ExpeditionRun.buy(trip, "card", 0), "nothing without gold")
	trip.gold = 1000
	trip.base_hp = 300.0
	check(ExpeditionRun.buy(trip, "card", 0) and bool(trip.shop.cards[0].sold) and not ExpeditionRun.buy(trip, "card", 0), "a card sells once")
	check(ExpeditionRun.buy(trip, "heal") and float(trip.base_hp) == 300.0 + ExpeditionRun.HEAL_AMOUNT and not ExpeditionRun.buy(trip, "heal"), "one repair per shop")
	check(ExpeditionRun.buy(trip, "upgrade", -1, "archer") and int(trip.stars.archer) == 2, "upgrades for gold")
	check(not ExpeditionRun.buy(trip, "remove", -1, "wall"), "deck cards cannot be thrown away")
	var spare: String = String(trip.shop.cards[0].kind)
	check(ExpeditionRun.buy(trip, "remove", -1, spare) and not trip.cards.units.has(spare) and not trip.cards.structures.has(spare), "a spare card can be thrown away")
	var saved_shop := ExpeditionRun.to_saved(trip)
	var reloaded := ExpeditionRun.from_saved(JSON.parse_string(JSON.stringify(saved_shop)))
	check(reloaded.status == "shop" and bool(reloaded.shop.cards[0].sold) and bool(reloaded.shop.healed) and bool(reloaded.shop.removed), "a resumed shop remembers what was bought")
	ExpeditionRun.leave_shop(trip)
	check(trip.layer == ExpeditionRun.LAYERS - 1 and trip.status == "map", "leaving the shop advances")
	# Boss and the next act.
	check(ExpeditionRun.choose_node(trip, 0) and trip.node.type == "boss", "the boss")
	trip.base_hp = 200.0
	ExpeditionRun.finish_battle(trip, true, 200.0)
	check(int(trip.reward.gold) == ExpeditionRun.GOLD_BOSS and trip.reward.relics.size() == 1, "bosses pay more and give a relic")
	var reward_relic: String = trip.reward.relics[0]
	var resumed_reward := ExpeditionRun.from_saved(JSON.parse_string(JSON.stringify(ExpeditionRun.to_saved(trip))))
	check(resumed_reward.status == "reward" and resumed_reward.reward == trip.reward, "a resumed reward is the same reward")
	ExpeditionRun.take_reward(trip, "")
	check(trip.relics.has(reward_relic) and trip.act == 2 and trip.layer == 0 and float(trip.base_hp) == 200.0 + ExpeditionRun.BASE_MAX * ExpeditionRun.ACT_HEAL, "the next act begins with some repairs")
	check(ExpeditionRun.choose_node(trip, 0) and ExpeditionRun.build_battle(trip).enemy.stage >= 4, "act two fights stronger stages")
	# The last boss wins the run.
	trip.act = ExpeditionRun.ACTS
	trip.layer = ExpeditionRun.LAYERS - 1
	trip.map = ExpeditionRun.generate_act(int(trip.seed), ExpeditionRun.ACTS)
	trip.status = "map"
	ExpeditionRun.choose_node(trip, 0)
	ExpeditionRun.finish_battle(trip, true, 100.0)
	ExpeditionRun.take_reward(trip, "")
	check(trip.status == "won" and ExpeditionRun.progress(trip) == ExpeditionRun.ACTS * ExpeditionRun.LAYERS, "beating the last boss wins the run")
	var lost := ExpeditionRun.create(5, UNITS, TACTICS, "granary")
	ExpeditionRun.choose_node(lost, 0)
	ExpeditionRun.finish_battle(lost, false, 0.0)
	check(lost.status == "lost", "a lost battle ends the run")

	# Saved runs from files.
	var fresh := ExpeditionRun.create(9, UNITS, TACTICS, "granary")
	var round_trip := ExpeditionRun.from_saved(JSON.parse_string(JSON.stringify(ExpeditionRun.to_saved(fresh))))
	check(round_trip.map == fresh.map and round_trip.deck == fresh.deck and round_trip.relics == fresh.relics, "a saved run comes back the same")
	var bad := ExpeditionRun.to_saved(fresh)
	bad.deck = {"units": ["shield", "shield", "archer", "healer"], "structures": TACTICS}
	check(ExpeditionRun.from_saved(bad).is_empty(), "a broken deck drops the save")
	bad = ExpeditionRun.to_saved(fresh)
	bad.status = "battle"
	bad.node_index = 7
	check(ExpeditionRun.from_saved(bad).is_empty(), "a node outside the map drops the save")
	bad = ExpeditionRun.to_saved(fresh)
	bad.relics = ["granary", "made_up"]
	bad.stars = {"shield": 5, "archer": 1}
	var cleaned := ExpeditionRun.from_saved(bad)
	check(cleaned.relics == ["granary"] and cleaned.stars == {"archer": 1}, "unknown relics and impossible stars are dropped")
	var profile := SaveData.default_data()
	RunRecords.expedition(profile).saved = ExpeditionRun.to_saved(fresh)
	var loaded := SaveData.sanitize(JSON.parse_string(JSON.stringify(profile)))
	check(int(loaded.runs.expedition.saved.seed) == 9, "the profile keeps the expedition")
	check(RunRecords.record_expedition(profile, trip) and int(profile.runs.expedition.clears) == 1 and profile.runs.expedition.saved.is_empty(), "a won run is recorded")

	# Screens.
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main._build_solo_screen()
	await process_frame
	main.find_child("ExpeditionButton", true, false).pressed.emit()
	await process_frame
	main.find_child("ExpeditionStart", true, false).pressed.emit()
	await process_frame
	var relic_cards: Array = main.find_children("ExpeditionRelic_*", "Button", true, false)
	check(relic_cards.size() == 3, "three starting relics to pick")
	relic_cards[0].pressed.emit()
	await process_frame
	check(ExpeditionFlow.active(main) and main.find_child("ExpeditionMap", true, false) != null, "the map opens")
	check(not RunRecords.expedition(main.save_data).saved.is_empty(), "the run is saved from the start")
	var node_button: Button = main.find_child("ExpeditionNode_0_0", true, false)
	check(node_button != null and not node_button.disabled and main.find_child("ExpeditionNode_1_0", true, false).disabled, "only the current layer can be picked")
	node_button.pressed.emit()
	await process_frame
	check(main.local_ai_mode and main.battle_active and main.find_child("ExpeditionSpeedButton", true, false) != null, "the battle starts with expedition controls")
	main.set_process(false)
	main.find_child("ExpeditionSpeedButton", true, false).pressed.emit()
	var before: float = main.local_model.elapsed
	main._process(0.1)
	check(main.local_model.elapsed - before > 0.15, "2x speed works in expedition battles")
	main.local_model.base_hp[0] = 410.0
	main.local_model.base_hp[1] = 0.0
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	main._show_result(0)
	await process_frame
	check(main.expedition_run.status == "reward" and float(main.expedition_run.base_hp) == 410.0, "the win is settled with the base left")
	check(main.save_data.stats.ai_matches == 0, "expedition battles stay out of the AI record")
	var go_on: Array = main.result_overlay.find_children("*", "Button", true, false).filter(func(button): return button.text == "계속")
	check(not go_on.is_empty(), "the result offers to continue")
	go_on[0].pressed.emit()
	await process_frame
	var reward_cards: Array = main.find_children("ExpeditionRewardCard_*", "Button", true, false)
	check(reward_cards.size() == 3, "the reward screen offers three cards")
	reward_cards[0].pressed.emit()
	await process_frame
	check(main.expedition_run.layer == 1 and main.find_child("ExpeditionMap", true, false) != null, "back on the map, one layer further")
	main.find_child("ExpeditionDeck", true, false).pressed.emit()
	await process_frame
	check(main.find_child("ExpeditionDeckSave", true, false) != null and main.find_children("ExpeditionCard_*", "Button", true, false).size() == 9, "the deck screen lists the collection")
	main.find_child("ExpeditionDeckBack", true, false).pressed.emit()
	await process_frame
	main.find_child("ExpeditionMenu", true, false).pressed.emit()
	await process_frame
	check(main.expedition_run.is_empty() and String((main.find_child("ExpeditionButton", true, false).find_child("Caption", true, false) as Label).text).contains("진행 중"), "leaving keeps the run for later")
	main.find_child("ExpeditionButton", true, false).pressed.emit()
	await process_frame
	main.find_child("ExpeditionResume", true, false).pressed.emit()
	await process_frame
	check(main.expedition_run.layer == 1 and float(main.expedition_run.base_hp) == 410.0, "resuming continues where it stopped")
	main.find_child("ExpeditionAbandon", true, false).pressed.emit()
	await process_frame
	main.find_child("ConfirmAbandon", true, false).pressed.emit()
	await process_frame
	var record := RunRecords.expedition(main.save_data)
	check(main.find_child("ExpeditionAgain", true, false) != null and int(record.runs) == 1 and record.saved.is_empty(), "abandoning ends and records the run")
	main.find_child("ExpeditionEndMenu", true, false).pressed.emit()
	await process_frame
	main._start_local_ai_battle(1)
	await process_frame
	check(main.expedition_run.is_empty() and main.find_child("ExpeditionSpeedButton", true, false) == null, "a practice battle afterwards is plain")
	print("expedition_mode_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
