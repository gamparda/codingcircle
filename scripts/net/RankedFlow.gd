extends RefCounted
## Ranked games and player reports on the server. Ranked is quick match for signed-in accounts only: the
## pair plays under their account nicknames and the result moves both Elo ratings once (a player who leaves
## an unfinished ranked game loses it). After any online match a signed-in player can report the opponent.

const Rating = preload("res://scripts/accounts/Rating.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

const LEADERBOARD_SIZE := 20
const PROFILE_KEYS := ["rating", "wins", "losses", "draws", "rank", "leaderboard"]
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
		for entry in found:
			main.lobby_pages.erase(int(entry.peer)); main._issue_reconnect(int(entry.peer))
		print("RANKED_MATCH room=%s" % code)
		main._push_session(code); main.lobby_dirty = true
		main._begin_session_match(int(first.peer), "ranked")

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
	for side in 2:
		var score := 0.5 if winner == 2 else (1.0 if winner == side else 0.0)
		var outcome := "draws" if winner == 2 else ("wins" if winner == side else "losses")
		var rating: int = Rating.updated(int(before[side]), int(before[1 - side]), score, int(games[side]))
		main.accounts.record_ranked(String(accounts[side]), rating, outcome)
		for peer in main.peer_accounts:
			if String(main.peer_accounts[peer]) == String(accounts[side]) and main._peer_is_connected(int(peer)):
				main.receive_ranked_result.rpc_id(int(peer), {"rating": rating, "delta": rating - int(before[side]), "outcome": outcome})
	main.accounts.flush()
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
	var data := {"rating": 0, "wins": 0, "losses": 0, "draws": 0, "rank": 0, "leaderboard": board}
	if not id.is_empty():
		var profile: Dictionary = main.accounts.profile(id)
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
	for key in ["rating", "wins", "losses", "draws", "rank"]:
		if not data[key] is int or int(data[key]) < 0:
			return false
	for row in data.leaderboard:
		if not row is Dictionary or not row.get("nickname") is String or not SessionStore.safe_text(String(row.nickname), SessionStore.MAX_NICKNAME):
			return false
		for key in ["rating", "wins", "losses", "draws"]:
			if not row.get(key) is int:
				return false
	return true

static func valid_result(data: Variant) -> bool:
	return data is Dictionary and data.size() == RESULT_KEYS.size() and data.has_all(RESULT_KEYS) and data.rating is int and data.delta is int and String(data.outcome) in ["wins", "losses", "draws"]
