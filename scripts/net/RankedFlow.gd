extends RefCounted
## Ranked games and player reports on the server. Ranked is quick match for signed-in accounts only: the
## pair plays under their account nicknames and the result moves both Elo ratings once (a player who leaves
## an unfinished ranked game loses it). Before the battle each player sees the other's deck and bans one of
## its cards for that match (BAN_SECONDS; no choice means no ban). After any online match a signed-in
## player can report the opponent.

const Rating = preload("res://scripts/accounts/Rating.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")
const RankedStats = preload("res://scripts/accounts/RankedStats.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")

const LEADERBOARD_SIZE := 20
const BAN_SECONDS := 15.0
const PROFILE_KEYS := ["rating", "wins", "losses", "draws", "rank", "leaderboard", "season", "best", "history", "cards", "card_matches"]
## Past seasons sent with a profile.
const PROFILE_HISTORY := 6
const HISTORY_KEYS := ["season", "rating", "best", "wins", "losses", "draws"]
const CARD_KEYS := ["kind", "picks", "bans", "wins", "draws"]
const RESULT_KEYS := ["rating", "delta", "outcome"]

static func now() -> int:
	return int(Time.get_unix_time_from_system())

static func _account(main, peer: int) -> String:
	return String(main.peer_accounts.get(peer, ""))

# ---------- queue ----------

static func request_match(main) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var id := _account(main, sender)
	if id.is_empty():
		main.receive_session_error.rpc_id(sender, "랭크 대전은 로그인한 계정만 참여할 수 있습니다."); return
	if not main.can_create_match():
		main.receive_session_error.rpc_id(sender, main.match_admission_error()); return
	if not main._can_enter_session(sender):
		main.receive_session_error.rpc_id(sender, "지금은 랭크 대전을 시작할 수 없습니다."); return
	if not main.ranked_queue.enqueue(sender, String(main.accounts.profile(id).nickname), Time.get_ticks_msec()):
		main.receive_session_error.rpc_id(sender, "대기열에 들어갈 수 없습니다. 잠시 후 다시 시도하세요."); return
	main.lobby_pages.erase(sender)
	main.receive_quick_status.rpc_id(sender, "queued")
	pair(main)

static func request_cancel(main) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if main.ranked_queue.cancel(sender):
		main.receive_quick_status.rpc_id(sender, "cancelled"); main.request_room_list_for(sender)

static func pair(main) -> void:
	if not main.can_create_match(): return
	while true:
		var eligible := func(peer: int) -> bool:
			return main.accepting_players and main._peer_is_connected(peer) and main.peer_decks.has(peer) and not _account(main, peer).is_empty() and not main.sessions.peer_to_room.has(peer) and not main.registry.has_match(peer)
		var found: Array = main.ranked_queue.take_pair(eligible)
		if found.is_empty(): return
		var first: Dictionary = found[0]; var second: Dictionary = found[1]
		var accounts := [_account(main, int(first.peer)), _account(main, int(second.peer))]
		if accounts[0] == accounts[1]:
			# One account on two devices: keep the earlier one waiting.
			main.ranked_queue.entries.push_front(first)
			main.receive_session_error.rpc_id(int(second.peer), "같은 계정끼리는 랭크 대전을 할 수 없습니다.")
			continue
		var code: String = main._generate_room_code()
		if code.is_empty() or not main.sessions.create(int(first.peer), code, "랭크 대전", String(first.nickname), "", "", main.peer_decks[int(first.peer)]) \
				or not main.sessions.join(int(second.peer), code, String(second.nickname), "player", main.peer_decks[int(second.peer)]).is_empty():
			if main.sessions.rooms.has(code): main._leave_session(int(first.peer))
			for entry in found:
				if main._peer_is_connected(int(entry.peer)): main.receive_session_error.rpc_id(int(entry.peer), "랭크 대전 방을 만들지 못했습니다. 다시 시도하세요.")
			continue
		main.sessions.set_ready(int(second.peer), true)
		# Both players wear their titles in the room.
		for index in 2:
			main.sessions.rooms[code].members[int(found[index].peer)]["title"] = main.accounts.worn_title(String(accounts[index]))
		for entry in found:
			main.lobby_pages.erase(int(entry.peer))
		print("RANKED_MATCH room=%s" % code)
		_start_bans(main, code, [int(first.peer), int(second.peer)])

# ---------- bans ----------

static func _start_bans(main, code: String, peers: Array) -> void:
	main.ranked_bans[code] = {"peers": peers, "bans": {}, "deadline": Time.get_ticks_msec() + int(BAN_SECONDS * 1000.0)}
	for index in 2:
		var opponent_deck: Dictionary = main.peer_decks[int(peers[1 - index])]
		main.receive_ban_phase.rpc_id(int(peers[index]), {"units": opponent_deck.units.duplicate(), "structures": opponent_deck.structures.duplicate(), "seconds": BAN_SECONDS})

static func request_ban(main, kind: String) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var code: String = String(main.sessions.peer_to_room.get(sender, ""))
	var phase: Dictionary = main.ranked_bans.get(code, {})
	if phase.is_empty() or phase.bans.has(sender): return
	var opponent: int = int(phase.peers[1]) if int(phase.peers[0]) == sender else int(phase.peers[0])
	var deck: Dictionary = main.peer_decks.get(opponent, {})
	if not deck.get("units", []).has(kind) and not deck.get("structures", []).has(kind): return
	phase.bans[sender] = kind
	if phase.bans.size() == 2:
		_finish_bans(main, code)

## Each tick: start the battle when the time is up, or call it off when a player left.
static func advance(main) -> void:
	for code in main.ranked_bans.keys():
		var phase: Dictionary = main.ranked_bans[code]
		if not phase.peers.all(func(peer): return main._peer_is_connected(int(peer))):
			main.ranked_bans.erase(code)
			for peer in phase.peers:
				if main._peer_is_connected(int(peer)):
					main._leave_session(int(peer))
					main.receive_session_error.rpc_id(int(peer), "상대가 나가서 랭크 대전이 취소되었습니다.")
					main.receive_quick_status.rpc_id(int(peer), "cancelled")
			continue
		if Time.get_ticks_msec() >= int(phase.deadline):
			_finish_bans(main, code)

static func _finish_bans(main, code: String) -> void:
	var phase: Dictionary = main.ranked_bans.get(code, {})
	main.ranked_bans.erase(code)
	if phase.is_empty() or not main.sessions.rooms.has(code):
		return
	main.pending_bans[code] = phase.bans
	for peer in phase.peers:
		main._issue_reconnect(int(peer))
	main._push_session(code); main.lobby_dirty = true
	main._begin_session_match(int(phase.peers[0]), "ranked")
	main.pending_bans.erase(code)

# ---------- match bookkeeping ----------

## Called when any session match starts: remembers who played whom (for reports) and, for ranked, the accounts.
static func on_match_begin(main, match_id: int, ids: Array, room: Dictionary, mode: String) -> void:
	var accounts := []
	var nicknames := []
	for side in 2:
		accounts.append(_account(main, int(ids[side])))
		nicknames.append(String(room.members[ids[side]].nickname))
	var key := "%s-%d" % [String(room.code), match_id]
	for side in 2:
		if not String(accounts[side]).is_empty():
			main.last_opponents[accounts[side]] = {"match": key, "account": accounts[1 - side], "nickname": nicknames[1 - side]}
	if mode == "ranked":
		main.ranked_matches[match_id] = {"accounts": accounts, "settled": false}
		# A player's ban removes that card from the opponent's side for this battle.
		var bans: Dictionary = main.pending_bans.get(String(room.code), {})
		var model = main.models.get(match_id)
		for side in 2:
			var chosen = bans.get(int(ids[1 - side]))
			if model != null and chosen != null:
				model.banned[side] = [String(chosen)]

## Settles a finished ranked match once: winner side, 2 for a draw.
static func settle(main, match_id: int, winner: int) -> void:
	var entry: Dictionary = main.ranked_matches.get(match_id, {})
	if entry.is_empty() or bool(entry.settled) or winner < 0:
		return
	entry.settled = true
	main.ranked_matches.erase(match_id)
	var accounts: Array = entry.accounts
	var before := []
	var games := []
	for side in 2:
		var profile: Dictionary = main.accounts.profile(String(accounts[side]))
		before.append(int(profile.get("rating", main.accounts.START_RATING)))
		var ranked: Dictionary = profile.get("ranked", {})
		games.append(int(ranked.get("wins", 0)) + int(ranked.get("losses", 0)) + int(ranked.get("draws", 0)))
	var model = main.models.get(match_id)
	for side in 2:
		var score := 0.5 if winner == 2 else (1.0 if winner == side else 0.0)
		var outcome := "draws" if winner == 2 else ("wins" if winner == side else "losses")
		var rating: int = Rating.updated(int(before[side]), int(before[1 - side]), score, int(games[side]))
		main.accounts.record_ranked(String(accounts[side]), rating, outcome)
		if model != null:
			main.accounts.record_summons(String(accounts[side]), int(model.battle_report[side].units.necromancer.summoned))
		for peer in main.peer_accounts:
			if String(main.peer_accounts[peer]) == String(accounts[side]) and main._peer_is_connected(int(peer)):
				main.receive_ranked_result.rpc_id(int(peer), {"rating": rating, "delta": rating - int(before[side]), "outcome": outcome})
	main.accounts.flush()
	if model != null:
		main.ranked_stats.record(model, winner, main.accounts.current_season())
		main.ranked_stats.flush()
	print("RANKED_RESULT winner=%d" % winner)

## A player leaving an unfinished ranked match loses it.
static func forfeit(main, peer: int) -> void:
	var match_id: int = main.registry.get_match_id(peer)
	if not main.ranked_matches.has(match_id) or not main.models.has(match_id) or main.models[match_id].winner != -1:
		return
	var side: int = main.registry.get_side(peer)
	if side == 0 or side == 1:
		settle(main, match_id, 1 - side)

# ---------- profile and reports ----------

static func request_profile(main) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var board: Array = main.accounts.leaderboard(LEADERBOARD_SIZE)
	var id := _account(main, sender)
	var season: String = main.accounts.current_season()
	var stats_current: bool = main.ranked_stats.season == season
	var data := {"rating": 0, "wins": 0, "losses": 0, "draws": 0, "rank": 0, "leaderboard": board, "season": season, "best": 0, "history": [],
		"cards": main.ranked_stats.summary() if stats_current else [], "card_matches": int(main.ranked_stats.data.matches) if stats_current else 0}
	if not id.is_empty():
		var profile: Dictionary = main.accounts.profile(id)
		data.best = int(profile.best)
		var seasons: Array = profile.history.keys()
		seasons.sort()
		seasons.reverse()
		for past in seasons.slice(0, PROFILE_HISTORY):
			var entry: Dictionary = profile.history[past]
			data.history.append({"season": String(past), "rating": int(entry.rating), "best": int(entry.best), "wins": int(entry.wins), "losses": int(entry.losses), "draws": int(entry.draws)})
		data.rating = int(profile.rating)
		data.wins = int(profile.ranked.wins); data.losses = int(profile.ranked.losses); data.draws = int(profile.ranked.draws)
		for index in board.size():
			if String(board[index].nickname) == String(profile.nickname):
				data.rank = index + 1
	main.receive_ranked_profile.rpc_id(sender, data)

static func request_report(main, reason: String) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var id := _account(main, sender)
	var last: Dictionary = main.last_opponents.get(id, {})
	var error: String = "not_signed_in" if id.is_empty() else ("no_match" if last.is_empty() else String(main.reports.add(id, last, String(last.match), reason, now())))
	main.receive_report_result.rpc_id(sender, error)

# ---------- client-side checks ----------

static func valid_profile(data: Variant) -> bool:
	if not data is Dictionary or data.size() != PROFILE_KEYS.size() or not data.has_all(PROFILE_KEYS) or not data.leaderboard is Array or data.leaderboard.size() > LEADERBOARD_SIZE:
		return false
	for key in ["rating", "wins", "losses", "draws", "rank", "best", "card_matches"]:
		if not data[key] is int or int(data[key]) < 0:
			return false
	if not data.season is String or String(data.season).length() > 7 or not data.history is Array or data.history.size() > PROFILE_HISTORY or not data.cards is Array or data.cards.size() > BattleModel.UNIT_STATS.size() + BattleModel.STRUCTURE_STATS.size():
		return false
	for row in data.history:
		if not row is Dictionary or row.size() != HISTORY_KEYS.size() or not row.has_all(HISTORY_KEYS) or not row.season is String or String(row.season).length() > 7:
			return false
		for key in HISTORY_KEYS.slice(1):
			if not row[key] is int or int(row[key]) < 0:
				return false
	for row in data.cards:
		if not row is Dictionary or row.size() != CARD_KEYS.size() or not row.has_all(CARD_KEYS) or not RankedStats.valid_kind(row.kind):
			return false
		for key in CARD_KEYS.slice(1):
			if not row[key] is int or int(row[key]) < 0:
				return false
	for row in data.leaderboard:
		if not row is Dictionary or not row.get("nickname") is String or not SessionStore.safe_text(String(row.nickname), SessionStore.MAX_NICKNAME):
			return false
		for key in ["rating", "wins", "losses", "draws"]:
			if not row.get(key) is int:
				return false
		if not row.get("title", "") is String or not (String(row.get("title", "")).is_empty() or Titles.valid_id(row.title)):
			return false
	return true

static func valid_ban_phase(data: Variant) -> bool:
	if not data is Dictionary or data.size() != 3 or not data.has_all(["units", "structures", "seconds"]) or not (data.seconds is float or data.seconds is int):
		return false
	return data.units is Array and data.structures is Array and BattleModel._valid_deck(data.units, BattleModel.UNIT_STATS) and BattleModel._valid_deck(data.structures, BattleModel.STRUCTURE_STATS)

static func valid_result(data: Variant) -> bool:
	return data is Dictionary and data.size() == RESULT_KEYS.size() and data.has_all(RESULT_KEYS) and data.rating is int and data.delta is int and String(data.outcome) in ["wins", "losses", "draws"]
