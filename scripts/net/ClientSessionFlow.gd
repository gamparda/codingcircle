extends RefCounted
## ClientSessionFlow: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const SessionStore = preload("res://scripts/RoomSessions.gd")

static func receive_session_state(main, data: Dictionary) -> void:
	if main.client_connection_state == "idle" or not main.valid_session_state(data): return
	var self_member: Dictionary = {}
	for member in data.members:
		if int(member.id) == main.multiplayer.get_unique_id(): self_member = member
	if self_member.is_empty(): return
	main.client_session = data.duplicate(true)
	main.client_is_spectator = self_member.role == "spectator"
	main.pending_room_password = ""
	if data.phase == "waiting" or (data.phase == "finished" and self_member.returned):
		main.client_in_match = false; main.client_connection_state = "session"
	elif main.client_connection_state != "in_match": main.client_connection_state = "session"
	main.client_phase_elapsed = 0.0
	main.session_changed.emit(main.client_session)

static func receive_session_challenge(main, code: String, salt: String, nonce: String) -> void:
	if main.client_connection_state != "room_request" or not main.is_valid_room_code(code) or not main._hex_string(nonce,32) or not (salt.is_empty() or main._hex_string(salt,32)): return
	var secret: String = SessionStore.verifier(main.pending_room_password,salt)
	main.pending_room_password = ""
	main.request_join_session.rpc_id(1,"" if salt.is_empty() else SessionStore.proof(secret,nonce,main.multiplayer.get_unique_id(),code))

static func receive_session_error(main, text: String) -> void:
	if text.length()>100: return
	main.pending_room_password = ""
	if main.client_session.is_empty(): main.client_connection_state = "lobby"
	else: main.client_connection_state = "session" if main.client_session.phase != "playing" else "in_match"
	main.session_error.emit(text)

static func receive_session_closed(main, text: String) -> void:
	if text.length()>100 or main.client_connection_state == "idle": return
	main.client_reconnect_token = ""; main.client_reconnect_code = ""; main.client_reconnecting = false
	main.client_session.clear(); main.client_is_spectator = false; main.client_in_match = false; main.client_connection_state = "lobby"
	main.session_closed.emit(text)
	main.request_room_list.rpc_id(1,0)

static func receive_session_chat(main, message: Dictionary) -> void:
	if main.client_session.is_empty() or not main.valid_chat_message(message): return
	main.client_session.messages.append(message)
	if main.client_session.messages.size()>SessionStore.CHAT_HISTORY: main.client_session.messages.pop_front()
	main.session_chat.emit(message)

static func session_spectate(main) -> void:
	if main.client_session.is_empty() or not main.client_is_spectator: return
	main.client_in_match = true; main.client_connection_state = "in_match"
	main.spectate_started.emit()

static func create_session_room(main, title: String, password: String = "") -> bool:
	if main.client_connection_state != "lobby" or not main.is_valid_room_name(title) or password.length()>32 or not SessionStore.safe_text(main.client_nickname,SessionStore.MAX_NICKNAME): return false
	var salt := "" if password.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	main.client_connection_state = "room_request"; main.client_phase_elapsed = 0.0
	main.request_create_session.rpc_id(1,title.strip_edges(),main.client_nickname,salt,SessionStore.verifier(password,salt))
	return true

static func join_session_room(main, code: String, password: String = "", spectator: bool = false) -> bool:
	if main.client_connection_state != "lobby" or not main.is_valid_room_code(code) or password.length()>32 or not SessionStore.safe_text(main.client_nickname,SessionStore.MAX_NICKNAME): return false
	main.pending_room_password = password
	main.client_connection_state = "room_request"; main.client_phase_elapsed = 0.0
	main.request_session_challenge.rpc_id(1,code,main.client_nickname,"spectator" if spectator else "player")
	return true

static func start_quick_match(main) -> bool:
	if main.client_connection_state != "lobby" or not SessionStore.safe_text(main.client_nickname,SessionStore.MAX_NICKNAME): return false
	main.client_connection_state = "queued"; main.client_phase_elapsed = 0.0
	main.request_quick_match.rpc_id(1,main.client_nickname)
	return true

static func cancel_quick_match(main) -> bool:
	if main.client_connection_state != "queued": return false
	main.request_cancel_quick_match.rpc_id(1)
	return true

static func receive_quick_status(main, state: String) -> void:
	if state not in ["queued","cancelled","timeout"] or main.client_connection_state not in ["lobby","queued"]: return
	main.client_connection_state = "queued" if state == "queued" else "lobby"
	main.client_phase_elapsed = 0.0
	main.quick_match_status.emit(state)
