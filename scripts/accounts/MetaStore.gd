extends RefCounted
## The progression part of a server account record ("meta"): gold, verified battle time per mode, today's quests,
## the week's quest, the season pass, owned and worn cosmetics, unit mastery and recently counted battles.
## AccountStore keeps the records; these functions clean, change and summarise one record's meta.

const Progression = preload("res://scripts/accounts/Progression.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")

const MAX_GOLD := 1_000_000_000
## The most battle seconds one event may count, and one UTC day.
const EVENT_SECONDS_MAX := 3 * 3600
const DAILY_SECONDS_MAX := 14 * 3600
## Solo battles run at up to 8x: battle time counted since the last counted battle is at most this many
## times the real time that passed (plus a minute), so a made-up pile of battles cannot add hours at once.
const WALL_FACTOR := 8.0
## Recently counted battle logs (by hash) so one log is never paid twice.
const SEEN_MAX := 64
const MAX_OWNED := 400

static func fresh() -> Dictionary:
	var equipped: Dictionary = Progression.DEFAULT_EQUIPPED.duplicate(true)
	return {"gold": 0, "day": "", "day_gold": 0, "day_seconds": 0, "seconds": 0, "last_credit": 0, "modes": {},
		"quests": {"day": "", "progress": {}, "done": []}, "weekly": {"week": "", "progress": 0, "done": false},
		"pass": {"season": "", "xp": 0, "tier": 0}, "owned": [], "equipped": equipped, "mastery": {}, "seen": []}

static func _number(value: Variant, low: int = 0, high: int = MAX_GOLD) -> int:
	if not ((value is int or value is float) and is_finite(float(value))):
		return low
	return clampi(int(value), low, high)

static func clean(raw: Variant) -> Dictionary:
	var meta := fresh()
	if not raw is Dictionary:
		return meta
	for key in ["gold", "day_gold", "day_seconds", "seconds", "last_credit"]:
		meta[key] = _number(raw.get(key), 0, 2_000_000_000)
	meta.gold = mini(int(meta.gold), MAX_GOLD)
	meta.day = String(raw.get("day", "")) if raw.get("day") is String and String(raw.day).length() == 8 else ""
	if raw.get("modes") is Dictionary:
		for mode in raw.modes:
			if String(mode) in Progression.MODES and raw.modes[mode] is Dictionary:
				var row: Dictionary = raw.modes[mode]
				meta.modes[String(mode)] = {"battles": _number(row.get("battles"), 0, 2_000_000_000), "wins": _number(row.get("wins"), 0, 2_000_000_000), "seconds": _number(row.get("seconds"), 0, 2_000_000_000)}
	if raw.get("quests") is Dictionary:
		var quests: Dictionary = raw.quests
		meta.quests.day = String(quests.get("day", "")) if quests.get("day") is String and String(quests.day).length() == 8 else ""
		if quests.get("progress") is Dictionary:
			for id in quests.progress:
				if String(id).length() <= 40 and meta.quests.progress.size() < 8:
					meta.quests.progress[String(id)] = _number(quests.progress[id], 0, 2_000_000_000)
		if quests.get("done") is Array:
			for id in quests.done:
				if id is String and String(id).length() <= 40 and meta.quests.done.size() < 8 and not meta.quests.done.has(id):
					meta.quests.done.append(String(id))
	if raw.get("weekly") is Dictionary:
		var weekly: Dictionary = raw.weekly
		meta.weekly = {"week": String(weekly.get("week", "")) if weekly.get("week") is String and String(weekly.week).length() == 8 else "", "progress": _number(weekly.get("progress"), 0, 2_000_000_000), "done": weekly.get("done") is bool and bool(weekly.done)}
	if raw.get("pass") is Dictionary:
		var pass_data: Dictionary = raw.pass
		var season := String(pass_data.get("season", ""))
		meta.pass = {"season": season if season.length() == 7 else "", "xp": _number(pass_data.get("xp"), 0, 1_000_000), "tier": _number(pass_data.get("tier"), 0, Progression.PASS_TIERS)}
	if raw.get("owned") is Array:
		for id in raw.owned:
			if Progression.valid_cosmetic(id) and not meta.owned.has(id) and meta.owned.size() < MAX_OWNED:
				meta.owned.append(String(id))
	if raw.get("equipped") is Dictionary:
		for slot in ["palette", "frame", "banner", "castle"]:
			var id = raw.equipped.get(slot)
			if id is String and owns(meta, String(id)) and String(Progression.cosmetic(String(id)).get("slot", "")) == slot:
				meta.equipped[slot] = String(id)
		var emotes = raw.equipped.get("emotes")
		if emotes is Array and emotes.size() == Progression.EMOTE_SLOTS and emotes.all(func(id): return id is String and owns(meta, String(id)) and String(Progression.cosmetic(String(id)).get("slot", "")) == "emote"):
			var unique := {}
			for id in emotes: unique[id] = true
			if unique.size() == emotes.size():
				meta.equipped.emotes = emotes.map(func(id): return String(id))
	if raw.get("mastery") is Dictionary:
		for kind in raw.mastery:
			if BattleModel.UNIT_STATS.has(kind) and raw.mastery[kind] is Dictionary:
				meta.mastery[String(kind)] = {"spawned": _number(raw.mastery[kind].get("spawned"), 0, 2_000_000_000), "kills": _number(raw.mastery[kind].get("kills"), 0, 2_000_000_000)}
	if raw.get("seen") is Array:
		for value in raw.seen:
			if value is String and String(value).length() == 64 and meta.seen.size() < SEEN_MAX:
				meta.seen.append(String(value))
	return meta

static func owns(meta: Dictionary, id: String) -> bool:
	return bool(Progression.cosmetic(id).get("default", false)) or meta.owned.has(id)

## Today's shop for an account: SHOP_SIZE items, the same all day.
static func shop(account: String, now: int) -> Array:
	var items: Array = []
	for id in Progression.CATALOG:
		if Progression.price(String(id)) > 0:
			items.append(String(id))
	items.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("keepfall-shop-" + account + "-" + Progression.day_key(now))
	var picked: Array = []
	while picked.size() < Progression.SHOP_SIZE and not items.is_empty():
		picked.append(items.pop_at(rng.randi_range(0, items.size() - 1)))
	return picked

## Starts a new day, week or pass season where one has begun.
static func roll(meta: Dictionary, now: int) -> void:
	var day := Progression.day_key(now)
	if String(meta.day) != day:
		meta.day = day; meta.day_gold = 0; meta.day_seconds = 0
	if String(meta.quests.day) != day:
		meta.quests = {"day": day, "progress": {}, "done": []}
	var week := Progression.week_key(now)
	if String(meta.weekly.week) != week:
		meta.weekly = {"week": week, "progress": 0, "done": false}
	var season := season_of(now)
	if String(meta.pass.season) != season:
		meta.pass = {"season": season, "xp": 0, "tier": 0}

static func season_of(now: int) -> String:
	var date := Time.get_date_dict_from_unix_time(now)
	return "%04d-%02d" % [int(date.year), int(date.month)]

## Counts one battle. `event` = {"mode", "seconds", "won", "units": {kind: {"spawned", "kills"}}, "waves"?}, built by
## the server. `log_hash` (64 hex) keeps a log from paying twice. Returns what it gave:
## {"gold", "xp", "seconds", "quests": [text], "tiers": [int], "items": [id], "titles": [id]} (empty when skipped).
static func apply_play(meta: Dictionary, account: String, event: Dictionary, now: int, log_hash: String = "") -> Dictionary:
	if not String(event.get("mode", "")) in Progression.MODES:
		return {}
	if not log_hash.is_empty():
		if meta.seen.has(log_hash):
			return {}
		meta.seen.append(log_hash)
		while meta.seen.size() > SEEN_MAX:
			meta.seen.pop_front()
	roll(meta, now)
	var mode := String(event.mode)
	var won := bool(event.get("won", false))
	var seconds := clampi(int(float(event.get("seconds", 0.0))), 0, EVENT_SECONDS_MAX)
	if int(meta.last_credit) > 0:
		seconds = mini(seconds, int(float(maxi(0, now - int(meta.last_credit))) * WALL_FACTOR) + 60)
	seconds = mini(seconds, maxi(0, DAILY_SECONDS_MAX - int(meta.day_seconds)))
	meta.last_credit = now
	meta.day_seconds = int(meta.day_seconds) + seconds
	var hours_before := int(meta.seconds) / 3600
	meta.seconds = mini(int(meta.seconds) + seconds, 2_000_000_000)
	var row: Dictionary = meta.modes.get(mode, {"battles": 0, "wins": 0, "seconds": 0})
	row.battles = int(row.battles) + 1
	row.wins = int(row.wins) + (1 if won else 0)
	row.seconds = int(row.seconds) + seconds
	meta.modes[mode] = row
	var units := {}
	if event.get("units") is Dictionary:
		for kind in event.units:
			if BattleModel.UNIT_STATS.has(kind) and event.units[kind] is Dictionary:
				units[String(kind)] = {"spawned": _number(event.units[kind].get("spawned"), 0, 100000), "kills": _number(event.units[kind].get("kills"), 0, 100000)}
	for kind in units:
		var mastery: Dictionary = meta.mastery.get(kind, {"spawned": 0, "kills": 0})
		mastery.spawned = int(mastery.spawned) + int(units[kind].spawned)
		mastery.kills = int(mastery.kills) + int(units[kind].kills)
		meta.mastery[kind] = mastery
	var counted := {"mode": mode, "won": won, "seconds": seconds, "units": units, "waves": _number(event.get("waves"), 0, 10000)}
	var reward := {"gold": 0, "xp": 0, "seconds": seconds, "quests": [], "tiers": [], "items": [], "titles": []}
	var battle_gold := mini(Progression.battle_gold(counted), maxi(0, Progression.DAILY_BATTLE_GOLD - int(meta.day_gold)))
	meta.day_gold = int(meta.day_gold) + battle_gold
	reward.gold += battle_gold
	var xp := int(float(seconds) / Progression.PASS_SECONDS_PER_XP) + (Progression.PASS_WIN_XP if won else 0)
	# Quests.
	for quest in Progression.daily_quests(account, String(meta.quests.day)):
		if meta.quests.done.has(quest.id):
			continue
		var amount := Progression.metric_amount(String(quest.metric), counted) if String(quest.metric) != "endless_waves" else 0
		var progress := int(meta.quests.progress.get(quest.id, 0)) + amount
		if String(quest.metric) == "endless_waves" and mode == "endless":
			progress = maxi(progress, int(counted.waves))
		meta.quests.progress[quest.id] = mini(progress, int(quest.goal))
		if progress >= int(quest.goal):
			meta.quests.done.append(quest.id)
			reward.gold += int(quest.reward)
			xp += Progression.PASS_QUEST_XP
			reward.quests.append(String(quest.text))
	var weekly := Progression.weekly_quest(account, String(meta.weekly.week))
	if not bool(meta.weekly.done):
		var progress := int(meta.weekly.progress)
		if String(weekly.metric) == "endless_waves":
			progress = maxi(progress, int(counted.waves) if mode == "endless" else 0)
		else:
			progress += Progression.metric_amount(String(weekly.metric), counted)
		meta.weekly.progress = mini(progress, int(weekly.goal))
		if progress >= int(weekly.goal):
			meta.weekly.done = true
			reward.gold += int(weekly.reward)
			xp += Progression.PASS_QUEST_XP * 2
			reward.quests.append(String(weekly.text))
	# Season pass: each tier pays gold, some tiers a season item; the last tier a title.
	reward.xp = xp
	meta.pass.xp = mini(int(meta.pass.xp) + xp, Progression.PASS_TIERS * Progression.PASS_XP_PER_TIER)
	var tier := mini(Progression.PASS_TIERS, int(meta.pass.xp) / Progression.PASS_XP_PER_TIER)
	while int(meta.pass.tier) < tier:
		meta.pass.tier = int(meta.pass.tier) + 1
		var reached := int(meta.pass.tier)
		reward.tiers.append(reached)
		reward.gold += Progression.PASS_TIER_GOLD
		var slot := String(Progression.PASS_ITEMS.get(reached, ""))
		if slot == "title":
			reward.titles.append("season_pass")
		elif not slot.is_empty():
			var item := "season:%s:%s" % [String(meta.pass.season), slot]
			if not meta.owned.has(item) and meta.owned.size() < MAX_OWNED:
				meta.owned.append(item)
				reward.items.append(item)
	meta.gold = mini(int(meta.gold) + int(reward.gold), MAX_GOLD)
	# Battle-time titles.
	var hours := int(meta.seconds) / 3600
	if hours > hours_before:
		for step in Titles.PLAY_TIERS:
			if hours >= int(step[0]):
				reward.titles.append(String(step[1]))
	return reward

## Buys `id` from today's shop. Returns an error code or "".
static func buy(meta: Dictionary, account: String, id: String, now: int) -> String:
	if not Progression.CATALOG.has(id) or Progression.price(id) <= 0:
		return "invalid"
	if owns(meta, id):
		return "owned"
	if not shop(account, now).has(id):
		return "not_in_shop"
	if int(meta.gold) < Progression.price(id):
		return "no_gold"
	if meta.owned.size() >= MAX_OWNED:
		return "invalid"
	meta.gold = int(meta.gold) - Progression.price(id)
	meta.owned.append(id)
	return ""

## Wears `id` in its slot; for emotes `id` goes into emote slot `index` (0..3), swapping if it was elsewhere.
static func equip(meta: Dictionary, id: String, index: int = 0) -> String:
	if not Progression.valid_cosmetic(id) or not owns(meta, id):
		return "not_owned"
	var slot := String(Progression.cosmetic(id).slot)
	if slot == "emote":
		if index < 0 or index >= Progression.EMOTE_SLOTS:
			return "invalid"
		var emotes: Array = meta.equipped.emotes
		var at := emotes.find(id)
		if at >= 0:
			emotes[at] = emotes[index]
		emotes[index] = id
		return ""
	meta.equipped[slot] = id
	return ""

## What other players see of an account: cosmetics worn in battle and on the profile card.
static func look(meta: Dictionary) -> Dictionary:
	return {"palette": String(meta.equipped.palette), "frame": String(meta.equipped.frame), "banner": String(meta.equipped.banner), "castle": String(meta.equipped.castle), "emotes": meta.equipped.emotes.duplicate()}

static func total_battles(meta: Dictionary) -> Dictionary:
	var totals := {"battles": 0, "wins": 0}
	for mode in meta.modes:
		totals.battles += int(meta.modes[mode].battles)
		totals.wins += int(meta.modes[mode].wins)
	return totals

## The three units fielded most, with their mastery.
static func top_units(meta: Dictionary, count: int = 3) -> Array:
	var rows: Array = []
	for kind in meta.mastery:
		rows.append({"kind": String(kind), "spawned": int(meta.mastery[kind].spawned), "kills": int(meta.mastery[kind].kills)})
	rows.sort_custom(func(a, b): return int(a.spawned) > int(b.spawned) or (int(a.spawned) == int(b.spawned) and String(a.kind) < String(b.kind)))
	return rows.slice(0, count)

## The state the owner sees (MetaFlow).
static func state(meta: Dictionary, account: String, now: int) -> Dictionary:
	roll(meta, now)
	var quests: Array = []
	for quest in Progression.daily_quests(account, String(meta.quests.day)):
		quests.append({"id": String(quest.id), "text": String(quest.text), "goal": int(quest.goal), "progress": mini(int(meta.quests.progress.get(quest.id, 0)), int(quest.goal)), "done": meta.quests.done.has(quest.id), "reward": int(quest.reward)})
	var weekly := Progression.weekly_quest(account, String(meta.weekly.week))
	quests.append({"id": String(weekly.id), "text": String(weekly.text), "goal": int(weekly.goal), "progress": mini(int(meta.weekly.progress), int(weekly.goal)), "done": bool(meta.weekly.done), "reward": int(weekly.reward), "weekly": true})
	var modes := {}
	for mode in meta.modes:
		modes[mode] = meta.modes[mode].duplicate()
	var mastery := {}
	for kind in meta.mastery:
		mastery[kind] = meta.mastery[kind].duplicate()
	return {"gold": int(meta.gold), "seconds": int(meta.seconds), "modes": modes, "quests": quests,
		"pass": {"season": String(meta.pass.season), "xp": int(meta.pass.xp), "tier": int(meta.pass.tier)},
		"owned": meta.owned.duplicate(), "equipped": look(meta), "shop": shop(account, now), "mastery": mastery,
		"day_gold": int(meta.day_gold)}
