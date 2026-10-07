extends RefCounted
## ReconnectFlow: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.


static func _issue_reconnect(main, peer_id: int) -> void:
	var token: String = main.sessions.issue_reconnect_token(peer_id)
	if not token.is_empty(): main.receive_reconnect_credentials.rpc_id(peer_id,String(main.sessions.peer_to_room[peer_id]),token)

static func request_reconnect(main, code: String, token: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender) or not main.peer_decks.has(sender): return
	if not main.is_valid_room_code(code) or not main._hex_string(token,64) or main.registry.has_match(sender) or main.registry.peer_to_room.has(sender):
		main.receive_reconnect_result.rpc_id(sender,false); return
	# Never rebind a live member. Identity comes exclusively from the random token.
	var old_peer: int = main.sessions.resume(code,token,sender,Time.get_ticks_msec())
	if old_peer == 0:
		main.receive_reconnect_result.rpc_id(sender,false); return
	var mid = main.registry.get_match_id(old_peer)
	var side = main.registry.get_side(old_peer)
	if mid > 0:
		main.registry.peer_to_match.erase(old_peer); main.registry.peer_to_side.erase(old_peer)
		main.registry.peer_to_match[sender] = mid; main.registry.peer_to_side[sender] = side
		var ids: Array = main.registry.matches.get(mid,[])
		var index := ids.find(old_peer)
		if index >= 0: ids[index] = sender
		if main.rematch_ready.has(mid) and main.rematch_ready[mid].has(old_peer):
			main.rematch_ready[mid].erase(old_peer); main.rematch_ready[mid][sender] = true
	main.peer_decks.erase(old_peer)
	var room: Dictionary = main.sessions.room_for(sender)
	main.peer_decks[sender] = room.members[sender].deck.duplicate(true)
	main.lobby_pages.erase(sender); main._issue_reconnect(sender)
	main.receive_reconnect_result.rpc_id(sender,true)
	main._push_session(code)
	if room.phase in ["playing","finished"] and not room.members[sender].returned:
		if room.members[sender].role == "spectator": main.session_spectate.rpc_id(sender)
		elif main.is_valid_match_side(side): main.match_started.rpc_id(sender,side)
		main._broadcast_snapshot(int(room.match_id))
	main.lobby_dirty = true

static func _expire_recovery(main) -> void:
	var now := Time.get_ticks_msec()
	for code in main.sessions.rooms.keys():
		if not main.sessions.rooms.has(code): continue
		var room: Dictionary = main.sessions.rooms[code]
		for id in room.members.keys():
			if not main.sessions.peer_to_room.has(id): continue
			var member: Dictionary = room.members[id]
			if member.connected or int(member.reconnect_deadline)>now: continue
			var mid = main.registry.get_match_id(int(id))
			if member.role == "player" and room.phase == "playing":
				var winner = 1-main.registry.get_side(int(id))
				for other in main.sessions.players(room):
					if int(other) != int(id) and not room.members[other].connected: winner = 2
				main._finish_match(mid,winner)
			main._leave_session(int(id),true,room.phase == "finished")
			main.peer_decks.erase(id); main.request_windows.erase(id)
			if main.sessions.rooms.has(code) and room.phase == "finished":
				var remaining_players: Array = main.sessions.players(room)
				if remaining_players.all(func(peer): return room.members[peer].returned):
					main.sessions.return_from_battle(int(remaining_players[0]))
					main._cleanup_session_match(int(room.match_id)); room.match_id = 0
					main._push_session(String(code)); main.lobby_dirty = true
