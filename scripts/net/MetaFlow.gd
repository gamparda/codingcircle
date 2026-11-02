extends RefCounted
## Gold, quests, the season pass, the shop, cosmetics, profile cards and battle emotes over the game connection.
## The server counts finished online matches itself and verified solo battles (TitleFlow); the client only asks
## for its state, buys, wears, looks up a profile card and sends an emote from its worn set.

const Progression = preload("res://scripts/accounts/Progression.gd")
const MetaStore = preload("res://scripts/accounts/MetaStore.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

const ERRORS := ["", "not_signed_in", "invalid", "owned", "not_in_shop", "no_gold", "not_owned"]
const STATE_KEYS := ["gold", "seconds", "modes", "quests", "pass", "owned", "equipped", "shop", "mastery", "day_gold"]
## Seconds between two emotes from one player.
const EMOTE_GAP_MSEC := 1500
const LOOK_KEYS := ["palette", "frame", "banner", "castle", "emotes"]

static func _account(main, peer: int) -> String:
	return String(main.peer_accounts.get(peer, ""))

static func _peers_of(main, account: String) -> Array:
	var peers: Array = []
	for peer in main.peer_accounts:
		if String(main.peer_accounts[peer]) == account and main._peer_is_connected(int(peer)):
			peers.append(int(peer))
	return peers

# ---------- server ----------

## Sends `peer` its progression; `reward` is what the battle just counted gave ({} for none).
static func send_state(main, peer: int, error: String = "", reward: Dictionary = {}) -> void:
	if not main._peer_is_connected(peer):
		return
	var id := _account(main, peer)
	var data: Dictionary = main.accounts.meta_state(id) if not id.is_empty() else {}
	main.receive_meta_state.rpc_id(peer, {"state": data, "error": error, "reward": reward})

## Counts a battle for `account` and tells its connected devices.
static func credit(main, account: String, event: Dictionary, log_hash: String = "") -> Dictionary:
	if account.is_empty():
		return {}
	var reward: Dictionary = main.accounts.apply_play(account, event, log_hash)
	if reward.is_empty():
		return reward
	main.accounts.flush()
	for peer in _peers_of(main, account):
		send_state(main, peer, "", reward)
		if not reward.titles.is_empty():
			main.TitleFlow.send_state(main, peer, "", reward.titles)
	return reward

static func request_state(main) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	send_state(main, sender, "" if not _account(main, sender).is_empty() else "not_signed_in")

static func request_buy(main, item: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	var error: String = "not_signed_in" if id.is_empty() else main.accounts.buy(id, item if item.length() <= 40 else "")
	if error.is_empty():
		main.accounts.flush()
		print("META_BUY item=%s" % item)
	send_state(main, sender, error)

static func request_equip(main, item: String, index: int) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	var error: String = "not_signed_in" if id.is_empty() else main.accounts.equip(id, item if item.length() <= 40 else "", index)
	if error.is_empty():
		main.accounts.flush()
	send_state(main, sender, error)

static func request_profile_card(main, nickname: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var card: Dictionary = main.accounts.profile_card(nickname) if SessionStore.safe_text(nickname, SessionStore.MAX_NICKNAME) else {}
	main.receive_profile_card.rpc_id(sender, card)

## A session match began: remembers who plays which side and shows both players each side's cosmetics.
static func on_match_begin(main, match_id: int, ids: Array, mode: String) -> void:
	var accounts: Array = []
	var looks: Array = []
	for side in 2:
		var account := _account(main, int(ids[side]))
		accounts.append(account)
		looks.append(main.accounts.look(account) if not account.is_empty() else {})
	main.meta_matches[match_id] = {"accounts": accounts, "mode": "ranked" if mode == "ranked" else "online"}
	for side in 2:
		if main._peer_is_connected(int(ids[side])):
			main.receive_match_looks.rpc_id(int(ids[side]), looks)

## A session match ended: each signed-in player's battle counts (not when a cheat was used in it).
static func on_match_finished(main, match_id: int) -> void:
	var entry: Dictionary = main.meta_matches.get(match_id, {})
	main.meta_matches.erase(match_id)
	var model = main.models.get(match_id)
	if entry.is_empty() or model == null or model.winner == -1 or main.cheated_matches.has(match_id):
		return
	for side in 2:
		var account := String(entry.accounts[side])
		if not account.is_empty():
			credit(main, account, Progression.event_from_model(model, side, String(entry.mode)))

## Relays an emote to everyone in the sender's battle, if it is one the sender wears.
static func request_emote(main, emote: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var match_id: int = main.registry.get_match_id(sender)
	var side: int = main.registry.get_side(sender)
	if side < 0 or side > 1 or not main.models.has(match_id):
		return
	var id := _account(main, sender)
	var worn: Array = main.accounts.look(id).get("emotes", []) if not id.is_empty() else Progression.DEFAULT_EQUIPPED.emotes
	if not worn.has(emote):
		return
	var now: int = Time.get_ticks_msec()
	if now - int(main.emote_times.get(sender, -EMOTE_GAP_MSEC)) < EMOTE_GAP_MSEC:
		return
	main.emote_times[sender] = now
	for peer in main.registry.get_players_for_peer(sender):
		if main._peer_is_connected(int(peer)):
			main.receive_emote.rpc_id(int(peer), side, emote)

# ---------- client checks ----------

static func valid_look(look: Variant) -> bool:
	if not look is Dictionary:
		return false
	if look.is_empty():
		return true
	if look.size() != LOOK_KEYS.size() or not look.has_all(LOOK_KEYS):
		return false
	for slot in ["palette", "frame", "banner", "castle"]:
		if not Progression.valid_cosmetic(look[slot]) or String(Progression.cosmetic(String(look[slot])).slot) != slot:
			return false
	return look.emotes is Array and look.emotes.size() == Progression.EMOTE_SLOTS and look.emotes.all(func(id): return Progression.valid_cosmetic(id) and String(Progression.cosmetic(String(id)).slot) == "emote")

static func valid_looks(data: Variant) -> bool:
	return data is Array and data.size() == 2 and data.all(func(look): return valid_look(look))

static func _count(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 2_000_000_000.0

static func valid_reward(reward: Variant) -> bool:
	if not reward is Dictionary:
		return false
	if reward.is_empty():
		return true
	if not reward.has_all(["gold", "xp", "seconds", "quests", "tiers", "items", "titles"]) or reward.size() != 7:
		return false
	if not _count(reward.gold) or not _count(reward.xp) or not _count(reward.seconds):
		return false
	if not reward.quests is Array or reward.quests.size() > 8 or not reward.quests.all(func(text): return text is String and String(text).length() <= 80):
		return false
	if not reward.tiers is Array or reward.tiers.size() > Progression.PASS_TIERS or not reward.tiers.all(func(tier): return _count(tier)):
		return false
	if not reward.items is Array or reward.items.size() > 8 or not reward.items.all(func(id): return Progression.valid_cosmetic(id)):
		return false
	return reward.titles is Array and reward.titles.size() <= Titles.CATALOG.size() and reward.titles.all(func(id): return Titles.valid_id(id))

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or not data.has_all(["state", "error", "reward"]) or data.size() != 3:
		return false
	if not data.error is String or not String(data.error) in ERRORS or not valid_reward(data.reward):
		return false
	var state = data.state
	if not state is Dictionary:
		return false
	if state.is_empty():
		return true
	if state.size() != STATE_KEYS.size() or not state.has_all(STATE_KEYS):
		return false
	if not _count(state.gold) or not _count(state.seconds) or not _count(state.day_gold):
		return false
	if not state.modes is Dictionary or not state.modes.keys().all(func(mode): return String(mode) in Progression.MODES and state.modes[mode] is Dictionary and ["battles", "wins", "seconds"].all(func(key): return _count(state.modes[mode].get(key)))):
		return false
	if not state.quests is Array or state.quests.size() > 6:
		return false
	for quest in state.quests:
		if not quest is Dictionary or not quest.get("text") is String or String(quest.text).length() > 80 or not quest.get("id") is String or not _count(quest.get("goal")) or not _count(quest.get("progress")) or not quest.get("done") is bool or not _count(quest.get("reward")):
			return false
	if not state.pass is Dictionary or not state.pass.get("season") is String or not _count(state.pass.get("xp")) or not _count(state.pass.get("tier")):
		return false
	if not state.owned is Array or state.owned.size() > MetaStore.MAX_OWNED or not state.owned.all(func(id): return Progression.valid_cosmetic(id)):
		return false
	if not valid_look(state.equipped) or state.equipped.is_empty():
		return false
	if not state.shop is Array or state.shop.size() > Progression.SHOP_SIZE or not state.shop.all(func(id): return Progression.CATALOG.has(id)):
		return false
	return state.mastery is Dictionary and state.mastery.keys().all(func(kind): return BattleModel.UNIT_STATS.has(kind) and state.mastery[kind] is Dictionary and _count(state.mastery[kind].get("spawned")) and _count(state.mastery[kind].get("kills")))

static func valid_card(card: Variant) -> bool:
	if not card is Dictionary:
		return false
	if card.is_empty():
		return true
	var keys := ["nickname", "title", "banner", "frame", "rating", "best", "ranked_games", "seconds", "battles", "wins", "titles", "pass_tier", "units", "since"]
	if card.size() != keys.size() or not card.has_all(keys):
		return false
	if not card.nickname is String or not SessionStore.safe_text(card.nickname, SessionStore.MAX_NICKNAME):
		return false
	if not card.title is String or not (String(card.title).is_empty() or Titles.valid_id(card.title)):
		return false
	if not Progression.valid_cosmetic(card.banner) or not Progression.valid_cosmetic(card.frame):
		return false
	for key in ["rating", "best", "ranked_games", "seconds", "battles", "wins", "titles", "pass_tier", "since"]:
		if not _count(card[key]):
			return false
	return card.units is Array and card.units.size() <= 3 and card.units.all(func(row): return row is Dictionary and BattleModel.UNIT_STATS.has(row.get("kind")) and _count(row.get("spawned")) and _count(row.get("kills")))
