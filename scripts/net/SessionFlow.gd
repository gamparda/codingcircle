extends RefCounted
## SessionFlow: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const SessionStore = preload("res://scripts/RoomSessions.gd")

static func request_create_session(main, title: String, nickname: String, salt: String, secret: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if not main._can_enter_session(sender) or not main.is_valid_room_name(title) or not SessionStore.safe_text(nickname,SessionStore.MAX_NICKNAME):
		main.receive_session_error.rpc_id(sender,"지금은 방을 만들 수 없습니다."); return
	if not ((salt.is_empty() and secret.is_empty()) or (main._hex_string(salt,32) and main._hex_string(secret,64))):
		main.receive_session_error.rpc_id(sender,"잘못된 비밀번호 설정입니다."); return
	var code = main._generate_room_code()
	if code.is_empty(): main.receive_session_error.rpc_id(sender,"방 코드를 생성하지 못했습니다. 다시 시도하세요."); return
	if not main.sessions.create(sender,code,title.strip_edges(),nickname.strip_edges(),salt,secret,main.peer_decks[sender]):
		main.receive_session_error.rpc_id(sender,"방을 만들지 못했습니다."); return
	main.lobby_pages.erase(sender)
	main.lobby_dirty = true; main._issue_reconnect(sender); main._push_session(code)

static func request_session_challenge(main, code: String, nickname: String, role: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if not main._can_enter_session(sender) or not main.sessions.rooms.has(code) or role not in ["player","spectator"] or not SessionStore.safe_text(nickname,SessionStore.MAX_NICKNAME):
		main.receive_session_error.rpc_id(sender,"참가할 수 없는 방입니다."); return
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	main.join_challenges[sender] = {"code":code,"nickname":nickname.strip_edges(),"role":role,"nonce":nonce,"deadline":Time.get_ticks_msec()+10000}
	main.receive_session_challenge.rpc_id(sender,code,main.sessions.rooms[code].salt,nonce)

static func request_join_session(main, response: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender) or not main.join_challenges.has(sender): return
	var challenge: Dictionary = main.join_challenges[sender]; main.join_challenges.erase(sender)
	if not main._can_enter_session(sender) or Time.get_ticks_msec() > challenge.deadline or not main.sessions.rooms.has(challenge.code):
		main.receive_session_error.rpc_id(sender,"방이 종료되었거나 참가 시간이 초과되었습니다."); return
	var room: Dictionary = main.sessions.rooms[challenge.code]
	var expected := "" if room.secret.is_empty() else SessionStore.proof(room.secret,challenge.nonce,sender,challenge.code)
	if not SessionStore.equal_secret(expected,response):
		main.receive_session_error.rpc_id(sender,"비밀번호가 맞지 않습니다."); return
	var error: String = main.sessions.join(sender,challenge.code,challenge.nickname,challenge.role,main.peer_decks[sender])
	if not error.is_empty(): main.receive_session_error.rpc_id(sender,error); return
	main.lobby_pages.erase(sender)
	main.lobby_dirty = true; main._issue_reconnect(sender); main._push_session(challenge.code)
	if room.phase in ["playing","finished"] and challenge.role == "spectator":
		main.session_spectate.rpc_id(sender)
		if main.models.has(room.match_id): main._broadcast_snapshot(int(room.match_id))

static func request_session_ready(main, ready: bool) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if main.sessions.set_ready(sender,ready): main._push_session(main.sessions.peer_to_room[sender])

static func request_session_deck(main, units: Array, structures: Array) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender) or not main.validate_deck_payload(units,structures): return
	if main.sessions.set_deck(sender,{"units":units,"structures":structures}):
		main.peer_decks[sender] = {"units":units.duplicate(),"structures":structures.duplicate()}
		main._push_session(main.sessions.peer_to_room[sender])

static func request_session_start(main) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if not main.accepting_players or not main.sessions.can_start(sender):
		main.receive_session_error.rpc_id(sender,"두 플레이어가 준비해야 시작할 수 있습니다."); return
	main._begin_session_match(sender, "session")

static func _begin_session_match(main, owner_id: int, mode: String) -> void:
	var match_id = main.registry.next_match_id; main.registry.next_match_id += 1
	var ids: Array = main.sessions.start(owner_id,match_id)
	var room: Dictionary = main.sessions.room_for(owner_id)
	var model := BattleModel.new()
	main.registry.matches[match_id] = ids.duplicate()
	for side in 2:
		var id: int = ids[side]; main.registry.peer_to_match[id] = match_id; main.registry.peer_to_side[id] = side
		var deck: Dictionary = room.members[id].deck
		model.configure_deck(side,deck.units,deck.structures)
	main.models[match_id] = model; main.session_matches[match_id] = room.code
	main.replays.begin(match_id, model, {"mode": mode})
	main._push_session(room.code); main.lobby_dirty = true
	for side in 2: main.match_started.rpc_id(int(ids[side]),side)
	for id in room.members:
		if room.members[id].role == "spectator" and main._peer_is_connected(int(id)): main.session_spectate.rpc_id(int(id))
	main._broadcast_snapshot(match_id)

static func request_quick_match(main, nickname: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if not main._can_enter_session(sender) or not SessionStore.safe_text(nickname,SessionStore.MAX_NICKNAME):
		main.receive_session_error.rpc_id(sender,"지금은 빠른 대전을 시작할 수 없습니다."); return
	if not main.quick_queue.enqueue(sender,nickname.strip_edges(),Time.get_ticks_msec()):
		main.receive_session_error.rpc_id(sender,"대기열에 들어갈 수 없습니다. 잠시 후 다시 시도하세요."); return
	main.lobby_pages.erase(sender)
	main.receive_quick_status.rpc_id(sender,"queued")
	main._pair_quick_queue()

static func request_cancel_quick_match(main) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if main.quick_queue.cancel(sender):
		main.receive_quick_status.rpc_id(sender,"cancelled"); main.request_room_list_for(sender)

static func request_room_list_for(main, peer_id: int) -> void:
	main.lobby_pages[peer_id] = 0; main.lobby_dirty = true

static func _pair_quick_queue(main) -> void:
	while true:
		var pair = main.quick_queue.take_pair(func(id): return main.accepting_players and main._peer_is_connected(id) and main.peer_decks.has(id) and not main.sessions.peer_to_room.has(id) and not main.registry.has_match(id))
		if pair.is_empty(): return
		var code = main._generate_room_code()
		var first: Dictionary = pair[0]; var second: Dictionary = pair[1]
		if code.is_empty() or not main.sessions.create(int(first.peer),code,"빠른 대전",String(first.nickname),"","",main.peer_decks[int(first.peer)]) 				or not main.sessions.join(int(second.peer),code,String(second.nickname),"player",main.peer_decks[int(second.peer)]).is_empty():
			if main.sessions.rooms.has(code): main._leave_session(int(first.peer))
			for entry in pair:
				if main._peer_is_connected(int(entry.peer)): main.receive_session_error.rpc_id(int(entry.peer),"빠른 대전 방을 만들지 못했습니다. 다시 시도하세요.")
			continue
		main.sessions.set_ready(int(second.peer),true)
		for entry in pair:
			main.lobby_pages.erase(int(entry.peer)); main._issue_reconnect(int(entry.peer))
		print("QUICK_MATCH room=%s waited_ms=%d" % [code, Time.get_ticks_msec()-int(first.since)])
		main._push_session(code); main.lobby_dirty = true
		main._begin_session_match(int(first.peer), "quick")

static func request_session_return(main) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	if main.sessions.return_from_battle(sender):
		var room: Dictionary = main.sessions.room_for(sender)
		if room.phase == "waiting": main._cleanup_session_match(int(room.match_id)); room.match_id = 0; main.lobby_dirty = true
		main._push_session(room.code)

static func request_session_leave(main) -> void:
	if main.server_mode and main.can_process_request(main.multiplayer.get_remote_sender_id()): main._leave_session(main.multiplayer.get_remote_sender_id())

static func request_session_chat(main, text: String) -> void:
	if not main.server_mode: return
	var sender = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender) or not main.sessions.peer_to_room.has(sender) or not SessionStore.safe_text(text,SessionStore.MAX_CHAT): return
	var now := Time.get_ticks_msec()
	if now-int(main.chat_times.get(sender,-1000)) < 750: return
	main.chat_times[sender] = now
	var message: Dictionary = main.sessions.append_chat(sender,text)
	if message.is_empty(): return
	for id in main.sessions.room_for(sender).members:
		if main._peer_is_connected(int(id)): main.receive_session_chat.rpc_id(int(id),message)

static func _push_session(main, code: String) -> void:
	var state = main.sessions.public_state(code)
	if state.is_empty(): return
	for member in state.members:
		if main._peer_is_connected(int(member.id)): main.receive_session_state.rpc_id(int(member.id),state)

static func _cleanup_session_match(main, match_id: int) -> void:
	if match_id <= 0: return
	for id in main.registry.matches.get(match_id,[]):
		if main.registry.get_match_id(int(id)) == match_id:
			main.registry.peer_to_match.erase(id); main.registry.peer_to_side.erase(id)
	main.registry.matches.erase(match_id); main.models.erase(match_id); main.replays.drop(match_id); main.rematch_ready.erase(match_id); main.session_matches.erase(match_id)

static func _leave_session(main, peer_id: int, disconnected: bool = false, preserve_result: bool = false) -> void:
	var result = main.sessions.leave(peer_id,preserve_result)
	if result.is_empty(): return
	if result.interrupted or result.closed: main._cleanup_session_match(int(result.match_id))
	if preserve_result:
		var mid = main.registry.get_match_id(peer_id)
		main.registry.peer_to_match.erase(peer_id); main.registry.peer_to_side.erase(peer_id)
		if main.registry.matches.has(mid): main.registry.matches[mid].erase(peer_id)
	if disconnected: main.peer_decks.erase(peer_id)
	if result.closed:
		for id in result.affected:
			if int(id) != peer_id and main._peer_is_connected(int(id)):
				main.receive_session_closed.rpc_id(int(id),"방이 종료되었습니다.")
	else: main._push_session(result.code)
	main.lobby_dirty = true
	if not disconnected and main._peer_is_connected(peer_id): main.receive_session_closed.rpc_id(peer_id,"")

static func _can_enter_session(main, peer_id: int) -> bool:
	return main.accepting_players and main.peer_decks.has(peer_id) and not main.registry.has_match(peer_id) and not main.registry.peer_to_room.has(peer_id) and not main.sessions.peer_to_room.has(peer_id) and not main.quick_queue.has(peer_id)
