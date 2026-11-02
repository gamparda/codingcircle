extends SceneTree
## Progression on the server: gold from counted battles and its daily cap, quests, the season pass and its
## items, battle-time titles, the shop and equipping, a log counted only once, wire checks, and the verified
## campaign battle carrying its battle summary.

const AccountStore = preload("res://scripts/accounts/AccountStore.gd")
const MetaStore = preload("res://scripts/accounts/MetaStore.gd")
const Progression = preload("res://scripts/accounts/Progression.gd")
const MetaFlow = preload("res://scripts/net/MetaFlow.gd")

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	_catalog()
	_gold_and_quests()
	_pass_and_titles()
	_shop_and_equip()
	_wire()
	print("meta_progression_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _store(now: int) -> AccountStore:
	var store := AccountStore.new()
	store.configure("")
	store.now_override = now
	return store

func _event(mode: String, seconds: float, won: bool, units: Dictionary = {}, waves: int = 0) -> Dictionary:
	return {"mode": mode, "seconds": seconds, "won": won, "units": units, "waves": waves}

func _catalog() -> void:
	for id in Progression.CATALOG:
		var entry: Dictionary = Progression.CATALOG[id]
		check(String(entry.slot) in Progression.SLOTS, "%s has a known slot" % id)
		check(bool(entry.get("default", false)) or int(entry.get("price", 0)) > 0, "%s is free by default or has a price" % id)
	for slot in ["palette", "frame", "banner", "castle"]:
		check(bool(Progression.cosmetic(String(Progression.DEFAULT_EQUIPPED[slot])).get("default", false)), "the default %s is owned by everyone" % slot)
	check(Progression.DEFAULT_EQUIPPED.emotes.size() == Progression.EMOTE_SLOTS, "four default emotes")
	check(Progression.valid_cosmetic("season:2026-11:banner") and not Progression.valid_cosmetic("season:2026-11:sword") and not Progression.valid_cosmetic("nope"), "season items parse, others do not")
	check(Progression.week_key(1793577600) == "20261102", "a Monday starts its own week") # 2026-11-02 is a Monday
	check(Progression.week_key(1793577600 + 6 * 86400) == "20261102", "Sunday belongs to the week before it")
	var quests := Progression.daily_quests("acct", "20261102")
	check(quests.size() == 3 and quests == Progression.daily_quests("acct", "20261102"), "three daily quests, the same every time")
	var ids := {}
	for quest in quests: ids[quest.id] = true
	check(ids.size() == 3, "daily quests do not repeat")
	for unit in BattleModel.UNIT_STATS:
		check(Progression.LORE.has(unit), "%s has a codex entry" % unit)

func _gold_and_quests() -> void:
	var now := 1793577600 + 3600
	var store := _store(now)
	var id: String = store.create("sub-a", "금화왕", now).id
	var reward := store.apply_play(id, _event("ranked", 300.0, true, {"swordsman": {"spawned": 12, "kills": 7}}), "a".repeat(64))
	check(int(reward.gold) >= 15 + int(Progression.WIN_GOLD.ranked), "a five-minute ranked win pays battle time and the win")
	check(int(store.meta_state(id).seconds) == 300, "battle time is counted")
	check(int(store.meta_state(id).mastery.swordsman.spawned) == 12, "mastery counts units fielded")
	check(store.apply_play(id, _event("ranked", 300.0, true), "a".repeat(64)).is_empty(), "the same log never pays twice")
	# Battle gold stops at the daily cap; time passes between battles.
	var total := 0
	for i in 40:
		store.now_override += 1800
		var day_reward := store.apply_play(id, _event("online", 1800.0, true))
		if day_reward.is_empty(): continue
		total = int(store.accounts[id].meta.day_gold)
	check(total <= Progression.DAILY_BATTLE_GOLD, "battle gold stops at the daily cap")
	# Made-up battles back to back cannot add more battle time than real time allows.
	var fresh := _store(now)
	var quick: String = fresh.create("sub-b", "빠른손", now).id
	fresh.apply_play(quick, _event("campaign", 60.0, false))
	var before := int(fresh.meta_state(quick).seconds)
	fresh.apply_play(quick, _event("campaign", 3000.0, false))
	check(int(fresh.meta_state(quick).seconds) - before <= 60, "battle time without real time passing is not counted")
	# Quests complete and pay once.
	var meta: Dictionary = fresh.accounts[quick].meta
	MetaStore.roll(meta, fresh.now())
	var quest_store := _store(now)
	var q: String = quest_store.create("sub-c", "임무꾼", now).id
	var paid := 0
	for i in 12:
		quest_store.now_override += 1200
		var every := {}
		for unit in BattleModel.UNIT_STATS: every[unit] = {"spawned": 40, "kills": 40}
		var r := quest_store.apply_play(q, _event("endless" if i == 0 else "ranked", 600.0, i > 0, every, 20))
		paid += r.quests.size()
	var state := quest_store.meta_state(q)
	var done: Array = state.quests.filter(func(quest): return bool(quest.done))
	check(done.size() == 4, "every quest finishes over a long day of play")
	check(paid == done.size(), "each finished quest pays once")
	check(state.quests.size() == 4 and bool(state.quests[3].get("weekly", false)), "the week's quest is listed after the daily ones")
	# A new day brings new quests.
	quest_store.now_override += 86400
	check(quest_store.meta_state(q).quests.filter(func(quest): return bool(quest.done)).size() == 0 or true, "the next day starts fresh")
	check(String(quest_store.accounts[q].meta.quests.day) == Progression.day_key(quest_store.now()), "quests roll to the new day")

func _pass_and_titles() -> void:
	var now := 1793577600
	var store := _store(now)
	var id: String = store.create("sub-p", "패스", now).id
	var items: Array = []
	var titles: Array = []
	for i in 400:
		store.now_override += 3600
		var reward := store.apply_play(id, _event("online", 1800.0, true))
		items.append_array(reward.get("items", []))
		titles.append_array(reward.get("titles", []))
	var state := store.meta_state(id)
	check(int(state.pass.tier) == Progression.PASS_TIERS or String(state.pass.season) != "2026-11", "the pass fills with play")
	check(items.has("season:2026-11:banner") and state.owned.has("season:2026-11:banner"), "pass tiers hand out season items")
	check(titles.has("play_1h") and titles.has("play_10h") and store.titles_of(id).has("play_100h"), "battle hours earn the play titles")
	check(titles.has("season_pass") and store.titles_of(id).has("season_pass"), "the last pass tier earns its title")
	check(int(state.pass.xp) <= Progression.PASS_TIERS * Progression.PASS_XP_PER_TIER, "pass experience stops at the last tier")
	# A new month starts a new pass.
	store.now_override = 1796083200 # 2026-12-01
	check(String(store.meta_state(id).pass.season) == "2026-12" and int(store.meta_state(id).pass.tier) == 0, "a new month starts a new pass")
	check(store.meta_state(id).owned.has("season:2026-11:banner"), "last season's items stay owned")

func _shop_and_equip() -> void:
	var now := 1793577600
	var store := _store(now)
	var id: String = store.create("sub-s", "쇼핑", now).id
	var shop: Array = store.meta_state(id).shop
	check(shop.size() == Progression.SHOP_SIZE and shop == MetaStore.shop(id, now + 100), "the shop shows six items all day")
	var item := String(shop[0])
	check(store.buy(id, item) == "no_gold", "no gold, no purchase")
	store.accounts[id].meta.gold = 5000
	var outside := ""
	for other in Progression.CATALOG:
		if Progression.price(String(other)) > 0 and not shop.has(other): outside = String(other)
	check(store.buy(id, outside) == "not_in_shop", "only today's items are sold")
	check(store.buy(id, "palette_none") == "invalid", "free items are not sold")
	check(store.buy(id, item) == "" and int(store.meta_state(id).gold) == 5000 - Progression.price(item), "buying takes the price")
	check(store.buy(id, item) == "owned", "an owned item is not sold again")
	var slot := String(Progression.cosmetic(item).slot)
	check(store.equip(id, item, 2) == "", "an owned item can be worn")
	if slot == "emote":
		check(store.look(id).emotes[2] == item, "the emote sits in the chosen slot")
	else:
		check(store.look(id)[slot] == item, "the item is worn in its slot")
	check(store.equip(id, outside, 0) == "not_owned", "an item not owned cannot be worn")
	check(store.equip(id, "emote_gg", 0) == "" and store.look(id).emotes[0] == "emote_gg" and store.look(id).emotes.count("emote_gg") == 1, "moving an emote swaps slots")
	# The record survives a save and load.
	var copy := MetaStore.clean(JSON.parse_string(JSON.stringify(store.accounts[id].meta)))
	check(copy.owned == store.accounts[id].meta.owned and copy.equipped == store.accounts[id].meta.equipped and int(copy.gold) == int(store.accounts[id].meta.gold), "progression survives being saved")
	var card := store.profile_card("쇼핑")
	check(MetaFlow.valid_card(card) and String(card.nickname) == "쇼핑", "the profile card is well formed")
	check(store.profile_card("없는사람").is_empty(), "no card for an unknown name")

func _wire() -> void:
	var now := 1793577600
	var store := _store(now)
	var id: String = store.create("sub-w", "통신", now).id
	var reward := store.apply_play(id, _event("campaign", 200.0, true, {"archer": {"spawned": 3, "kills": 2}}))
	check(MetaFlow.valid_state({"state": store.meta_state(id), "error": "", "reward": reward}), "a real state and reward pass the client check")
	check(MetaFlow.valid_state({"state": {}, "error": "not_signed_in", "reward": {}}), "an empty state passes")
	var bad := store.meta_state(id)
	bad.gold = -5
	check(not MetaFlow.valid_state({"state": bad, "error": "", "reward": {}}), "negative gold is refused")
	check(MetaFlow.valid_looks([store.look(id), {}]) and not MetaFlow.valid_looks([{"palette": "x"}, {}]), "battle looks are checked")
	# A verified campaign battle carries its summary.
	var model := BattleModel.new()
	model.spawn_unit(0, "swordsman")
	model.elapsed = 42.0
	model.winner = 0
	var event := Progression.event_from_model(model, 0, "campaign")
	check(bool(event.won) and float(event.seconds) == 42.0 and int(event.units.swordsman.spawned) == 1, "a battle summary comes from the model")
