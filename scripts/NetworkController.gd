class_name NetworkController
extends Node

const Localization = preload("res://scripts/Localization.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")
const Protocol = preload("res://scripts/NetworkProtocol.gd")
const PeerAdmission = preload("res://scripts/PeerAdmission.gd")
const ServerReplays = preload("res://scripts/ServerReplays.gd")
const ServerBattle = preload("res://scripts/ServerBattle.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerDailyBoard = preload("res://scripts/ServerDailyBoard.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const ServerReplayShelf = preload("res://scripts/ServerReplayShelf.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const QuickQueue = preload("res://scripts/QuickQueue.gd")
const SessionFlow = preload("res://scripts/net/SessionFlow.gd")
const ReconnectFlow = preload("res://scripts/net/ReconnectFlow.gd")
const ClientSessionFlow = preload("res://scripts/net/ClientSessionFlow.gd")

signal connection_status(text: String)
signal server_ready
signal meta_stats_received(data: Dictionary)
signal daily_board_received(data: Dictionary)
signal replay_code_received(code: String)
signal shared_replay_received(code: String, text: String)
signal recent_replays_received(list: Array)
signal match_found(side: int)
signal snapshot_received(data: Dictionary)
signal combat_events_received(events: Array)
signal opponent_disconnected
signal structure_placement_result(success: bool, error: String)
signal room_created(code: String)
signal room_list_received(data: Dictionary)
signal session_changed(data: Dictionary)
signal session_error(text: String)
signal session_chat(message: Dictionary)
signal spectate_started
signal session_closed(text: String)
signal room_join_failed(error: String)
signal latency_updated(milliseconds: int)
signal recovery_changed(data: Dictionary) # {paused, reconnect_remaining}
signal reconnect_status(active: bool, remaining: float)
signal quick_match_status(state: String) # "queued" | "cancelled" | "timeout"

const RECONNECT_GRACE := Protocol.RECONNECT_GRACE
var client_reconnect_token := ""
var client_reconnect_code := ""
var client_reconnecting := false
var client_reconnect_deadline := 0
var client_latency_ms := -1
var latency_ms: int:
	get: return client_latency_ms
var ping_elapsed := 0.0
var ping_sequence := 0
var pending_ping: Dictionary = {}

const DEFAULT_PORT := 7777
const TICK_RATE := ServerBattle.TICK_RATE
const SNAPSHOT_RATE := ServerBattle.SNAPSHOT_RATE
const MAX_REQUESTS_PER_SECOND := PeerAdmission.MAX_REQUESTS_PER_SECOND
const MAX_SNAPSHOT_UNITS := Protocol.MAX_SNAPSHOT_UNITS
const MAX_SNAPSHOT_STRUCTURES := Protocol.MAX_SNAPSHOT_STRUCTURES
const TRANSPORT_MAX_PEERS := Protocol.TRANSPORT_MAX_PEERS
const VALID_UNIT_KINDS := Protocol.VALID_UNIT_KINDS
const VALID_STRUCTURE_KINDS := Protocol.VALID_STRUCTURE_KINDS
const ROOM_LIST_PAGE_SIZE := Protocol.ROOM_LIST_PAGE_SIZE
const ROOM_NAME_LENGTH := Protocol.ROOM_NAME_LENGTH
const ROOM_CODE_LENGTH := Protocol.ROOM_CODE_LENGTH
const ROOM_CODE_ALPHABET := Protocol.ROOM_CODE_ALPHABET
const CONNECTION_TIMEOUT := 4.0
const ROOM_REQUEST_TIMEOUT := 8.0

var registry := MatchRegistry.new()
var battle := ServerBattle.new()
var models: Dictionary:
	get: return battle.models
var replays: ServerReplays:
	get: return battle.replays
var quick_queue := QuickQueue.new()
var stats := ServerStats.new()
var daily_board := ServerDailyBoard.new()
var report_counts: Dictionary = {}
var shelf := ServerReplayShelf.new()
var upload_counts: Dictionary = {}
const MAX_UPLOADS_PER_CONNECTION := 10
const MAX_REPORTS_PER_CONNECTION := 40
var rematch_ready: Dictionary:
	get: return battle.rematch_ready
var server_mode := false
var allow_test_room_codes := false
var client_in_match := false
var accepting_players := true
var admission := PeerAdmission.new()
var request_windows: Dictionary:
	get: return admission.request_windows
var peer_addresses: Dictionary:
	get: return admission.peer_addresses
var address_connection_counts: Dictionary:
	get: return admission.address_connection_counts
var peer_decks: Dictionary = {}
var client_unit_deck: Array = BattleModel.DEFAULT_UNIT_DECK.duplicate()
var client_structure_deck: Array = BattleModel.DEFAULT_STRUCTURE_DECK.duplicate()
var client_connection_state := "idle"
var client_connection_candidates: Array = []
var client_connection_index := -1
var client_connection_port := DEFAULT_PORT
var client_room_mode := "create"
var client_room_code := ""
var client_room_name := ""
var lobby_pages: Dictionary = {}
var lobby_dirty := false
var lobby_refresh_elapsed := 0.0
var sessions = SessionStore.new()
var session_matches: Dictionary = {}
var join_challenges: Dictionary = {}
var chat_times: Dictionary = {}
var client_session: Dictionary = {}
var client_is_spectator := false
var client_nickname := "플레이어"
var pending_room_password := ""
var client_connection_generation := 0
var client_phase_elapsed := 0.0

func _ready() -> void:
	replays.stats = stats
	replays.shelf = shelf
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

static func disconnect_message_for_state(state: String) -> String:
	return Localization.text("서버 연결 실패") if state == "connecting" else Localization.text("서버와 연결이 끊어졌습니다")

static func connection_candidates(primary_address: String, fallback_address: String = "") -> Array:
	var candidates: Array = []
	for address in [primary_address.strip_edges(), fallback_address.strip_edges()]:
		if not address.is_empty() and not candidates.has(address):
			candidates.append(address)
	return candidates

func _on_connected_to_server() -> void:
	client_connection_state = "connected"
	client_phase_elapsed = 0.0
	connection_status.emit(Localization.text("서버에 연결됨 · 덱 검증 중..."))
	request_submit_deck.rpc_id(1, client_unit_deck, client_structure_deck)
	server_ready.emit()

static func validate_deck_payload(unit_deck: Array, structure_deck: Array) -> bool:
	return Protocol.validate_deck_payload(unit_deck, structure_deck)

func set_client_deck(unit_deck: Array, structure_deck: Array) -> bool:
	if not validate_deck_payload(unit_deck, structure_deck):
		return false
	client_unit_deck = unit_deck.duplicate()
	client_structure_deck = structure_deck.duplicate()
	return true

func set_room_request(mode: String, code: String = "") -> bool:
	if not ["create", "join", "enter", "lobby", "session"].has(mode):
		return false
	var normalized := code.strip_edges().to_upper()
	if mode in ["join", "enter"] and not is_valid_room_code(normalized):
		return false
	client_room_mode = mode
	client_room_code = normalized
	return true

func _on_connection_failed() -> void:
	if client_reconnecting:
		_schedule_reconnect(); return
	if _retry_next_connection_candidate():
		return
	client_connection_state = "idle"
	connection_status.emit(Localization.text("서버 연결 실패"))

func _on_server_disconnected() -> void:
	if client_connection_state == "idle":
		return
	var previous_state := client_connection_state
	if not client_reconnect_token.is_empty():
		if not client_reconnecting:
			client_reconnecting = true
			client_reconnect_deadline = Time.get_ticks_msec() + int(RECONNECT_GRACE*1000)
		_schedule_reconnect(); return
	if previous_state == "connecting" and _retry_next_connection_candidate():
		return
	client_connection_state = "idle"
	pending_room_password = ""
	client_session.clear()
	join_challenges.clear()
	connection_status.emit(disconnect_message_for_state(previous_state))
	if client_in_match:
		client_in_match = false
		opponent_disconnected.emit()

func start_dedicated_server(port: int = DEFAULT_PORT) -> bool:
	allow_test_room_codes = OS.get_cmdline_user_args().has("--allow-test-room-codes")
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, TRANSPORT_MAX_PEERS)
	if error != OK:
		printerr(Localization.text("서버 시작 실패: %s") % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	server_mode = true
	print("DEDICATED_SERVER_READY port=%d" % port)
	return true

func connect_to_server(address: String, port: int = DEFAULT_PORT, fallback_address: String = "") -> bool:
	return connect_to_candidates(connection_candidates(address, fallback_address), port)

func connect_to_candidates(candidates: Array, port: int = DEFAULT_PORT) -> bool:
	disconnect_from_server()
	client_connection_candidates = []
	for candidate in candidates:
		var address := String(candidate).strip_edges()
		if not address.is_empty() and not client_connection_candidates.has(address):
			client_connection_candidates.append(address)
	client_connection_index = 0
	client_connection_port = port
	if client_connection_candidates.is_empty():
		connection_status.emit(Localization.text("서버 주소가 비어 있습니다"))
		return false
	return _start_client_attempt(String(client_connection_candidates[0]))

func _start_client_attempt(address: String) -> bool:
	connection_status.emit(Localization.text("%s:%d 연결 중...") % [address, client_connection_port])
	client_connection_state = "connecting"
	client_phase_elapsed = 0.0
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, client_connection_port)
	if error != OK:
		if _retry_next_connection_candidate():
			return true
		client_connection_state = "idle"
		connection_status.emit(Localization.text("연결 설정 실패: %s") % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _retry_next_connection_candidate() -> bool:
	if client_connection_index + 1 >= client_connection_candidates.size():
		return false
	client_connection_index += 1
	var fallback := String(client_connection_candidates[client_connection_index])
	connection_status.emit(Localization.text("연결이 지연되어 다른 서버 주소로 재시도합니다."))
	print("CLIENT_CONNECTION_FALLBACK address=%s" % fallback)
	_start_fallback_if_current.call_deferred(fallback, client_connection_generation)
	return true

func _start_fallback_if_current(address: String, generation: int) -> void:
	if generation == client_connection_generation and client_connection_state == "connecting":
		_start_client_attempt(address)

func disconnect_from_server() -> void:
	var notify_leave := not client_session.is_empty() and client_connection_state not in ["idle","connecting"] and not client_reconnecting
	if notify_leave and multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		request_session_leave.rpc_id(1)
	client_reconnect_token = ""; client_reconnect_code = ""; client_reconnecting = false
	client_latency_ms = -1; pending_ping.clear()
	client_connection_generation += 1
	client_in_match = false
	client_is_spectator = false
	client_session.clear()
	pending_room_password = ""
	client_connection_state = "idle"
	client_phase_elapsed = 0.0
	client_connection_candidates.clear()
	client_connection_index = -1
	if notify_leave:
		_close_explicit_transport.call_deferred(client_connection_generation,multiplayer.multiplayer_peer)
	else:
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer: multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func _close_explicit_transport(generation: int, leaving_peer: MultiplayerPeer) -> void:
	await get_tree().create_timer(0.15).timeout
	if generation != client_connection_generation or multiplayer.multiplayer_peer != leaving_peer: return
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer: multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func set_accepting_players(value: bool) -> void:
	if accepting_players == value:
		return
	accepting_players = value
	if not accepting_players:
		for peer_id in multiplayer.get_peers():
			if peer_should_disconnect_for_drain(int(peer_id)):
				_disconnect_peer(int(peer_id))

func peer_should_disconnect_for_drain(peer_id: int) -> bool:
	var session := sessions.room_for(peer_id)
	if not session.is_empty() and session.phase == "playing": return false
	var match_id := registry.get_match_id(peer_id)
	if match_id <= 0 or not models.has(match_id):
		return true
	var model: BattleModel = models[match_id]
	return model.winner != -1

func can_accept_room_request() -> bool:
	return accepting_players

func can_accept_rematch(model: BattleModel) -> bool:
	return accepting_players and model.winner != -1

func can_process_request(peer_id: int, now_msec: int = -1) -> bool:
	return admission.can_process_request(peer_id, now_msec)

func register_peer_address(peer_id: int, address: String) -> bool:
	return admission.register_peer_address(peer_id, address)

func release_peer_address(peer_id: int) -> void:
	admission.release_peer_address(peer_id)

func can_create_match() -> bool:
	return true # No application-level match quota.

func can_admit_deck(peer_id: int) -> bool:
	# Admission must be checked when the deck arrives, not just on connection.
	return accepting_players and peer_addresses.has(peer_id)

func _remote_address(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var packet_peer := enet.get_peer(peer_id)
	return "" if packet_peer == null else packet_peer.get_remote_address()

func _peer_is_connected(peer_id: int) -> bool:
	if not multiplayer.get_peers().has(peer_id): return false
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		var peer: ENetPacketPeer = (multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(peer_id)
		return peer != null and peer.get_state() == ENetPacketPeer.STATE_CONNECTED
	return false

func _disconnect_orphaned_peer(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and _peer_is_connected(peer_id):
		_disconnect_peer(peer_id)

static func is_safe_command_text(value: String) -> bool:
	return Protocol.is_safe_command_text(value)

static func is_valid_room_code(value: String) -> bool:
	return Protocol.is_valid_room_code(value)

static func is_safe_position(value: float) -> bool:
	return Protocol.is_safe_position(value)

static func is_valid_match_side(side: int) -> bool:
	return Protocol.is_valid_match_side(side)

static func _is_finite_number(value: Variant) -> bool:
	return Protocol._is_finite_number(value)

static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	return Protocol._has_exact_keys(value, expected)

static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return Protocol._number_in_range(value, minimum, maximum)

static func is_valid_snapshot(data: Dictionary) -> bool:
	return Protocol.is_valid_snapshot(data)

static func _has_required_optional_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	return Protocol._has_required_optional_keys(value, required, optional)

func _process(delta: float) -> void:
	if not server_mode:
		_advance_client_connection(delta)
		_advance_ping(delta)
		return
	_expire_recovery()
	for id in join_challenges.keys():
		if Time.get_ticks_msec()>int(join_challenges[id].deadline): join_challenges.erase(id)
	for waiting_peer in quick_queue.expire(Time.get_ticks_msec()):
		if _peer_is_connected(int(waiting_peer)):
			receive_quick_status.rpc_id(int(waiting_peer),"timeout"); request_room_list_for(int(waiting_peer))
	lobby_refresh_elapsed += delta
	if lobby_dirty and lobby_refresh_elapsed >= 0.25:
		lobby_dirty = false
		lobby_refresh_elapsed = 0.0
		var listing := _all_room_listings()
		for peer_id in lobby_pages.keys():
			if registry.has_match(int(peer_id)) or not peer_addresses.has(peer_id):
				lobby_pages.erase(peer_id)
			elif _peer_is_connected(int(peer_id)):
				_send_room_listing(int(peer_id), int(lobby_pages[peer_id]), listing)
	var step := battle.advance(delta, _match_paused)
	for tick in step.ticks:
		var match_id: int = tick.match_id
		if tick.finished and session_matches.has(match_id):
			var code: String = session_matches[match_id]
			if sessions.rooms.has(code) and sessions.rooms[code].phase == "playing":
				sessions.finish(code)
				_push_session(code)
				lobby_dirty = true
		if not tick.events.is_empty():
			_broadcast_combat_events(match_id, tick.events)
	if step.snapshot_due:
		for match_id in models.keys():
			_broadcast_snapshot(int(match_id))

func _advance_client_connection(delta: float) -> void:
	if client_reconnecting:
		var remaining := maxf(0.0,(client_reconnect_deadline-Time.get_ticks_msec())/1000.0)
		reconnect_status.emit(true,remaining)
		if remaining <= 0.0:
			_end_reconnect(); return
		client_phase_elapsed += delta
		if client_phase_elapsed >= CONNECTION_TIMEOUT: _schedule_reconnect()
		return
	if client_connection_state not in ["connecting", "connected", "room_request", "leaving"]:
		return
	client_phase_elapsed += delta
	if client_connection_state == "connecting" and client_phase_elapsed >= CONNECTION_TIMEOUT:
		client_phase_elapsed = 0.0
		if _retry_next_connection_candidate():
			return
		disconnect_from_server()
		connection_status.emit(Localization.text("서버 연결 실패"))
	elif client_connection_state in ["connected", "room_request", "leaving"] and client_phase_elapsed >= ROOM_REQUEST_TIMEOUT:
		if client_room_mode == "session" and client_connection_state == "room_request":
			receive_session_error("방 요청 시간이 초과되었습니다. 다시 시도하세요."); return
		disconnect_from_server()
		connection_status.emit(Localization.text("서버 응답 시간이 초과되었습니다. 다시 시도하세요."))

func _on_peer_connected(peer_id: int) -> void:
	if not server_mode:
		return
	if not accepting_players:
		print("PLAYER_REJECTED_UPDATE peer=%d" % peer_id)
		_disconnect_peer(peer_id)
		return
	if not register_peer_address(peer_id, _remote_address(peer_id)):
		print("PLAYER_REJECTED_INVALID_PEER peer=%d" % peer_id)
		_disconnect_peer(peer_id)
		return
	print("PLAYER_CONNECTED peer=%d" % peer_id)
	# Matching starts only after the authoritative server validates a 3+3 deck.

func _start_paired_match(paired: Dictionary) -> void:
	if paired.size() != 2:
		return
	var peer_id := int(paired.keys()[0])
	var match_id := registry.get_match_id(peer_id)
	var model := BattleModel.new()
	for player_id in paired.keys():
		var deck: Dictionary = peer_decks[int(player_id)]
		model.configure_deck(int(paired[player_id]), deck.units, deck.structures)
	models[match_id] = model
	replays.begin(match_id, model, {"mode": "room"})
	rematch_ready[match_id] = {}
	for player_id in paired.keys():
		match_started.rpc_id(int(player_id), int(paired[player_id]))
	_broadcast_snapshot(match_id)
	print("MATCH_CREATED id=%d players=%s" % [match_id, paired.keys()])

func _generate_room_code() -> String:
	var crypto := Crypto.new()
	for _attempt in 64:
		var random_bytes := crypto.generate_random_bytes(ROOM_CODE_LENGTH)
		if random_bytes.size() != ROOM_CODE_LENGTH:
			return ""
		var code := ""
		for index in ROOM_CODE_LENGTH:
			code += ROOM_CODE_ALPHABET[int(random_bytes[index]) % ROOM_CODE_ALPHABET.length()]
		if not registry.rooms.has(code) and not sessions.rooms.has(code):
			return code
	return ""

func _on_peer_disconnected(peer_id: int) -> void:
	if not server_mode:
		return
	quick_queue.cancel(peer_id)
	report_counts.erase(peer_id)
	upload_counts.erase(peer_id)
	var session_peer: bool = sessions.peer_to_room.has(peer_id)
	if session_peer and sessions.suspend(peer_id,Time.get_ticks_msec()+int(RECONNECT_GRACE*1000)):
		_push_session(sessions.peer_to_room[peer_id])
		lobby_pages.erase(peer_id); join_challenges.erase(peer_id); chat_times.erase(peer_id)
		request_windows.erase(peer_id); release_peer_address(peer_id)
		lobby_dirty = true
		return
	if session_peer: _leave_session(peer_id,true)
	join_challenges.erase(peer_id)
	chat_times.erase(peer_id)
	var match_id := registry.get_match_id(peer_id)
	var players := registry.remove_player(peer_id)
	lobby_pages.erase(peer_id)
	lobby_dirty = true
	for player_id in players:
		if int(player_id) != peer_id and _peer_is_connected(int(player_id)):
			_disconnect_orphaned_peer.call_deferred(int(player_id))
	models.erase(match_id)
	replays.drop(match_id)
	rematch_ready.erase(match_id)
	peer_decks.erase(peer_id)
	request_windows.erase(peer_id)
	release_peer_address(peer_id)
	print("PLAYER_DISCONNECTED peer=%d" % peer_id)

@rpc("any_peer", "call_remote", "reliable")
func request_submit_deck(unit_deck: Array, structure_deck: Array) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if peer_decks.has(sender) or not can_process_request(sender):
		return
	if not can_admit_deck(sender):
		_disconnect_peer(sender)
		return
	if not validate_deck_payload(unit_deck, structure_deck):
		print("PLAYER_REJECTED_DECK peer=%d" % sender)
		_disconnect_peer(sender)
		return
	peer_decks[sender] = {"units": unit_deck.duplicate(), "structures": structure_deck.duplicate()}
	print("PLAYER_DECK_ACCEPTED peer=%d" % sender)
	receive_deck_accepted.rpc_id(sender)

@rpc("any_peer", "call_remote", "reliable")
func request_create_room(title: String = "") -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sessions.peer_to_room.has(sender): return
	if not can_accept_room_request():
		receive_room_join_failed.rpc_id(sender, Localization.text("서버가 업데이트 준비 중입니다. 잠시 후 다시 시도하세요."))
		return
	if not can_process_request(sender) or not peer_decks.has(sender) or registry.peer_to_room.has(sender) or registry.has_match(sender):
		receive_room_join_failed.rpc_id(sender, Localization.text("지금은 방을 만들 수 없습니다. 잠시 후 다시 시도하세요."))
		return
	if not title.is_empty() and not is_valid_room_name(title):
		receive_room_join_failed.rpc_id(sender, "방 이름은 24자 이내로 입력하세요.")
		return
	var code := _generate_room_code()
	if code.is_empty() or not registry.create_room(sender, code, title.strip_edges()):
		receive_room_join_failed.rpc_id(sender, Localization.text("방을 만들지 못했습니다."))
		return
	lobby_dirty = true
	print("ROOM_CREATED peer=%d" % sender)
	receive_room_created.rpc_id(sender, code)

@rpc("any_peer", "call_remote", "reliable")
func request_join_room(code: String, create_if_missing: bool = false) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sessions.peer_to_room.has(sender): return
	var normalized := code.strip_edges().to_upper()
	if not can_accept_room_request():
		receive_room_join_failed.rpc_id(sender, Localization.text("서버가 업데이트 준비 중입니다. 잠시 후 다시 시도하세요."))
		return
	if not can_process_request(sender) or not peer_decks.has(sender) or not is_valid_room_code(normalized):
		receive_room_join_failed.rpc_id(sender, Localization.text("올바른 방 코드를 입력하세요."))
		return
	if create_if_missing and allow_test_room_codes and not registry.rooms.has(normalized):
		if registry.create_room(sender, normalized):
			print("ROOM_CREATED peer=%d smoke=true" % sender)
			receive_room_created.rpc_id(sender, normalized)
			return
	var paired := registry.join_room(sender, normalized)
	if paired.is_empty():
		receive_room_join_failed.rpc_id(sender, Localization.text("방을 찾을 수 없거나 이미 시작된 방입니다."))
		return
	print("ROOM_JOINED peer=%d" % sender)
	lobby_dirty = true
	_start_paired_match(paired)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn(kind: String) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender):
		return
	if not is_safe_command_text(kind):
		return
	var match_id := registry.get_match_id(sender)
	if models.has(match_id) and not _match_paused(match_id):
		var side := registry.get_side(sender)
		if models[match_id].unit_decks[side].has(kind) and models[match_id].spawn_unit(side, kind):
			replays.on_spawn(match_id, side, kind)

@rpc("any_peer", "call_remote", "reliable")
func request_place_structure(kind: String, x: float) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender):
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("요청이 너무 빠릅니다."))
		return
	if not is_safe_command_text(kind) or not is_safe_position(x):
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("잘못된 설치 요청입니다."))
		return
	var match_id := registry.get_match_id(sender)
	if not models.has(match_id) or _match_paused(match_id):
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("진행 중인 경기가 없습니다."))
		return
	var side := registry.get_side(sender)
	var model: BattleModel = models[match_id]
	var error := model.structure_placement_error(side, kind, clamp(x, 0.0, BattleModel.WORLD_WIDTH))
	var placed_x: float = clamp(x, 0.0, BattleModel.WORLD_WIDTH)
	var success := error.is_empty() and model.place_structure(side, kind, placed_x)
	if success:
		replays.on_place(match_id, side, kind, placed_x)
	if not success and error.is_empty():
		error = Localization.text("구조물을 설치하지 못했습니다.")
	receive_structure_placement_result.rpc_id(sender, success, error)

@rpc("any_peer", "call_remote", "reliable")
func request_rematch() -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if sessions.peer_to_room.has(sender): return
	if not can_process_request(sender):
		return
	var match_id := registry.get_match_id(sender)
	if not models.has(match_id):
		return
	if not can_accept_rematch(models[match_id]):
		return
	if not rematch_ready.has(match_id):
		rematch_ready[match_id] = {}
	rematch_ready[match_id][sender] = true
	if rematch_ready[match_id].size() >= 2:
		models[match_id].reset()
		replays.begin(match_id, models[match_id], {"mode": "rematch"})
		rematch_ready[match_id] = {}
		_broadcast_snapshot(match_id)

func send_spawn(kind: String) -> void:
	if client_is_spectator: return
	if multiplayer.has_multiplayer_peer():
		request_spawn.rpc_id(1, kind)

func send_structure(kind: String, x: float) -> void:
	if client_is_spectator: return
	if multiplayer.has_multiplayer_peer():
		request_place_structure.rpc_id(1, kind, x)

func send_rematch() -> void:
	if client_is_spectator: return
	if multiplayer.has_multiplayer_peer():
		request_rematch.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func receive_deck_accepted() -> void:
	if client_reconnecting:
		request_reconnect.rpc_id(1,client_reconnect_code,client_reconnect_token); return
	if client_room_mode in ["lobby","session"]:
		request_room_list.rpc_id(1,0)
	elif client_room_mode == "join" or client_room_mode == "enter":
		request_join_room.rpc_id(1, client_room_code, client_room_mode == "enter")
	else:
		request_create_room.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func receive_room_created(code: String) -> void:
	if is_valid_room_code(code):
		client_connection_state = "waiting"
		client_phase_elapsed = 0.0
		room_created.emit(code)

@rpc("authority", "call_remote", "reliable")
func receive_room_join_failed(error: String) -> void:
	if error.length() <= 100:
		if client_room_mode == "lobby" and client_connection_state == "room_request":
			client_connection_state = "lobby"
			client_phase_elapsed = 0.0
		room_join_failed.emit(error)

func _broadcast_snapshot(match_id: int) -> void:
	if not models.has(match_id):
		return
	var data: Dictionary = models[match_id].snapshot()
	data["network"] = _recovery_state(match_id)
	for player_id in _match_audience(match_id):
		if _peer_is_connected(int(player_id)):
			if int(data.winner)!=-1: receive_completed_snapshot.rpc_id(int(player_id),data)
			else: receive_snapshot.rpc_id(int(player_id), data)

func _broadcast_combat_events(match_id: int, events: Array) -> void:
	for player_id in _match_audience(match_id):
		if _peer_is_connected(int(player_id)):
			receive_combat_events.rpc_id(int(player_id), events)

@rpc("authority", "call_remote", "reliable")
func match_started(side: int) -> void:
	if is_valid_match_side(side):
		client_connection_state = "in_match"
		client_in_match = true
		match_found.emit(side)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(data: Dictionary) -> void:
	if is_valid_snapshot(data):
		if data.has("network"): recovery_changed.emit(data.network)
		snapshot_received.emit(data)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_combat_events(events: Array) -> void:
	if events.size() <= 128:
		combat_events_received.emit(events)

@rpc("authority", "call_remote", "reliable")
func receive_structure_placement_result(success: bool, error: String) -> void:
	if error.length() <= 100:
		structure_placement_result.emit(success, error)

@rpc("authority", "call_remote", "reliable")
func opponent_left() -> void:
	client_in_match = false
	opponent_disconnected.emit()

static func is_valid_room_name(title: String) -> bool:
	return Protocol.is_valid_room_name(title)

func _send_room_listing(peer_id: int, page: int, listing: Array) -> void:
	var last_page := maxi(0, (listing.size()-1) / ROOM_LIST_PAGE_SIZE)
	page = clampi(page,0,last_page)
	lobby_pages[peer_id] = page
	receive_room_list.rpc_id(peer_id,{"rooms":listing.slice(page*ROOM_LIST_PAGE_SIZE,(page+1)*ROOM_LIST_PAGE_SIZE),"page":page,"total":listing.size()})

@rpc("any_peer", "call_remote", "reliable")
func request_room_list(page: int = 0) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not peer_decks.has(sender) or registry.has_match(sender): return
	_send_room_listing(sender,maxi(0,page),_all_room_listings())

@rpc("any_peer", "call_remote", "reliable")
func request_leave_room() -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if sessions.peer_to_room.has(sender): return
	if not can_process_request(sender) or not peer_decks.has(sender) or registry.has_match(sender): return
	registry.remove_player(sender)
	lobby_dirty = true
	_send_room_listing(sender,0,_all_room_listings())

static func is_valid_room_listing(data: Dictionary) -> bool:
	return Protocol.is_valid_room_listing(data)

@rpc("authority", "call_remote", "reliable")
func receive_room_list(data: Dictionary) -> void:
	if not is_valid_room_listing(data) or client_connection_state in ["idle","in_match"]: return
	if client_connection_state in ["connected","leaving"]:
		client_connection_state = "lobby"
		client_phase_elapsed = 0.0
	room_list_received.emit(data)

func browse_rooms(page: int = 0) -> void:
	if client_connection_state == "lobby": request_room_list.rpc_id(1,page)

func create_lobby_room(title: String) -> bool:
	if client_connection_state != "lobby" or not is_valid_room_name(title): return false
	client_room_name = title.strip_edges()
	client_connection_state = "room_request"
	client_phase_elapsed = 0.0
	request_create_room.rpc_id(1,client_room_name)
	return true

func join_lobby_room(code: String) -> bool:
	if client_connection_state != "lobby" or not is_valid_room_code(code): return false
	client_connection_state = "room_request"
	client_phase_elapsed = 0.0
	request_join_room.rpc_id(1,code,false)
	return true

func leave_lobby_room() -> void:
	if client_connection_state != "waiting": return
	client_connection_state = "leaving"
	client_phase_elapsed = 0.0
	request_leave_room.rpc_id(1)

func _all_room_listings() -> Array:
	return sessions.listing() + registry.room_listing()

func _match_audience(match_id: int) -> Array:
	if session_matches.has(match_id):
		var room: Dictionary = sessions.rooms.get(session_matches[match_id],{})
		if not room.is_empty(): return room.members.keys()
	return registry.matches.get(match_id,[])

func _push_session(code: String) -> void:
	SessionFlow._push_session(self, code)

func _cleanup_session_match(match_id: int) -> void:
	SessionFlow._cleanup_session_match(self, match_id)

func _leave_session(peer_id: int, disconnected: bool = false, preserve_result: bool = false) -> void:
	SessionFlow._leave_session(self, peer_id, disconnected, preserve_result)

static func _hex_string(value: String, length: int) -> bool:
	return Protocol._hex_string(value, length)

func _can_enter_session(peer_id: int) -> bool:
	return SessionFlow._can_enter_session(self, peer_id)

@rpc("any_peer", "call_remote", "reliable")
func request_create_session(title: String, nickname: String, salt: String, secret: String) -> void:
	SessionFlow.request_create_session(self, title, nickname, salt, secret)

@rpc("any_peer", "call_remote", "reliable")
func request_session_challenge(code: String, nickname: String, role: String) -> void:
	SessionFlow.request_session_challenge(self, code, nickname, role)

@rpc("any_peer", "call_remote", "reliable")
func request_join_session(response: String) -> void:
	SessionFlow.request_join_session(self, response)

@rpc("any_peer", "call_remote", "reliable")
func request_session_ready(ready: bool) -> void:
	SessionFlow.request_session_ready(self, ready)

@rpc("any_peer", "call_remote", "reliable")
func request_session_deck(units: Array, structures: Array) -> void:
	SessionFlow.request_session_deck(self, units, structures)

@rpc("any_peer", "call_remote", "reliable")
func request_session_start() -> void:
	SessionFlow.request_session_start(self)

func _begin_session_match(owner_id: int, mode: String) -> void:
	SessionFlow._begin_session_match(self, owner_id, mode)

@rpc("any_peer", "call_remote", "reliable")
func request_quick_match(nickname: String) -> void:
	SessionFlow.request_quick_match(self, nickname)

@rpc("any_peer", "call_remote", "reliable")
func request_cancel_quick_match() -> void:
	SessionFlow.request_cancel_quick_match(self)

func request_room_list_for(peer_id: int) -> void:
	SessionFlow.request_room_list_for(self, peer_id)

## Turns every waiting pair into a started session match (both players start ready).
func _pair_quick_queue() -> void:
	SessionFlow._pair_quick_queue(self)

@rpc("any_peer", "call_remote", "reliable")
func request_session_return() -> void:
	SessionFlow.request_session_return(self)

@rpc("any_peer", "call_remote", "reliable")
func request_session_leave() -> void:
	SessionFlow.request_session_leave(self)

@rpc("any_peer", "call_remote", "reliable")
func request_session_chat(text: String) -> void:
	SessionFlow.request_session_chat(self, text)

static func valid_session_state(data: Dictionary) -> bool:
	return Protocol.valid_session_state(data)

static func valid_chat_message(message: Variant) -> bool:
	return Protocol.valid_chat_message(message)

@rpc("authority", "call_remote", "reliable")
func receive_session_state(data: Dictionary) -> void:
	ClientSessionFlow.receive_session_state(self, data)

@rpc("authority", "call_remote", "reliable")
func receive_session_challenge(code: String, salt: String, nonce: String) -> void:
	ClientSessionFlow.receive_session_challenge(self, code, salt, nonce)

@rpc("authority", "call_remote", "reliable")
func receive_session_error(text: String) -> void:
	ClientSessionFlow.receive_session_error(self, text)

@rpc("authority", "call_remote", "reliable")
func receive_session_closed(text: String) -> void:
	ClientSessionFlow.receive_session_closed(self, text)

@rpc("authority", "call_remote", "reliable")
func receive_session_chat(message: Dictionary) -> void:
	ClientSessionFlow.receive_session_chat(self, message)

@rpc("authority", "call_remote", "reliable")
func session_spectate() -> void:
	ClientSessionFlow.session_spectate(self)

func create_session_room(title: String, password: String = "") -> bool:
	return ClientSessionFlow.create_session_room(self, title, password)

func start_quick_match() -> bool:
	return ClientSessionFlow.start_quick_match(self)

func cancel_quick_match() -> bool:
	return ClientSessionFlow.cancel_quick_match(self)

@rpc("authority", "call_remote", "reliable")
func receive_quick_status(state: String) -> void:
	ClientSessionFlow.receive_quick_status(self, state)

func join_session_room(code: String, password: String = "", spectator: bool = false) -> bool:
	return ClientSessionFlow.join_session_room(self, code, password, spectator)

func _match_paused(match_id: int) -> bool:
	return session_matches.has(match_id) and sessions.paused(String(session_matches[match_id]))

func _recovery_state(match_id: int) -> Dictionary:
	var remaining := 0.0
	if session_matches.has(match_id):
		var room: Dictionary = sessions.rooms.get(session_matches[match_id],{})
		if not room.is_empty() and room.phase == "playing":
			for id in sessions.players(room):
				var member: Dictionary = room.members[id]
				if not member.connected: remaining = maxf(remaining,maxf(0.0,(int(member.reconnect_deadline)-Time.get_ticks_msec())/1000.0))
	return {"paused":_match_paused(match_id),"reconnect_remaining":remaining}

static func valid_recovery_state(data: Variant) -> bool:
	return Protocol.valid_recovery_state(data)

func _finish_match(match_id: int, winner: int) -> void:
	if not models.has(match_id) or models[match_id].winner != -1: return
	models[match_id].winner = winner
	replays.settle(match_id, models[match_id])
	if session_matches.has(match_id):
		sessions.finish(String(session_matches[match_id])); _push_session(String(session_matches[match_id]))
	_broadcast_snapshot(match_id); lobby_dirty = true

func send_surrender() -> bool:
	if client_is_spectator or not client_in_match or client_reconnecting: return false
	request_surrender.rpc_id(1)
	return true

@rpc("any_peer", "call_remote", "reliable")
func request_surrender() -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	var mid := registry.get_match_id(sender)
	var side := registry.get_side(sender)
	if not is_valid_match_side(side) or not models.has(mid): return
	_finish_match(mid,1-side)

func _issue_reconnect(peer_id: int) -> void:
	ReconnectFlow._issue_reconnect(self, peer_id)

@rpc("authority", "call_remote", "reliable")
func receive_reconnect_credentials(code: String, token: String) -> void:
	if client_connection_state == "idle" or not is_valid_room_code(code) or not _hex_string(token,64): return
	client_reconnect_code = code; client_reconnect_token = token

@rpc("any_peer", "call_remote", "reliable")
func request_reconnect(code: String, token: String) -> void:
	ReconnectFlow.request_reconnect(self, code, token)

@rpc("authority", "call_remote", "reliable")
func receive_reconnect_result(success: bool) -> void:
	if not client_reconnecting: return
	if not success: _end_reconnect(); return
	client_reconnecting = false; client_phase_elapsed = 0.0
	reconnect_status.emit(false,0.0)

func _schedule_reconnect() -> void:
	if not client_reconnecting: return
	client_connection_generation += 1
	client_connection_state = "recovering"; client_phase_elapsed = 0.0
	_retry_reconnect_after_delay.call_deferred(client_connection_generation)

var _reconnect_retry_delay := 0.5

func _retry_reconnect_after_delay(generation: int) -> void:
	await get_tree().create_timer(_reconnect_retry_delay).timeout
	if generation != client_connection_generation or not client_reconnecting: return
	if Time.get_ticks_msec() >= client_reconnect_deadline or client_connection_candidates.is_empty():
		_end_reconnect(); return
	client_connection_index = (client_connection_index+1)%client_connection_candidates.size()
	_start_client_attempt(String(client_connection_candidates[client_connection_index]))

func _end_reconnect() -> void:
	disconnect_from_server()
	reconnect_status.emit(false,0.0)
	connection_status.emit("재접속 시간이 초과되었습니다.")
	opponent_disconnected.emit()

func _expire_recovery() -> void:
	ReconnectFlow._expire_recovery(self)

func _advance_ping(delta: float) -> void:
	if client_connection_state in ["idle","connecting","recovering"] or client_reconnecting: return
	ping_elapsed += delta
	if ping_elapsed < 2.0: return
	ping_elapsed = 0.0
	ping_sequence = (ping_sequence+1)%2147483647
	pending_ping = {"sequence":ping_sequence,"sent":Time.get_ticks_msec()}
	request_ping.rpc_id(1,ping_sequence)

@rpc("any_peer", "call_remote", "unreliable")
func request_ping(sequence: int) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if sequence < 0 or not peer_addresses.has(sender) or not can_process_request(sender): return
	receive_pong.rpc_id(sender,sequence)

@rpc("authority", "call_remote", "unreliable")
func receive_pong(sequence: int) -> void:
	if pending_ping.is_empty() or int(pending_ping.sequence) != sequence: return
	client_latency_ms = maxi(0,Time.get_ticks_msec()-int(pending_ping.sent))
	pending_ping.clear(); latency_updated.emit(client_latency_ms)

@rpc("any_peer", "call_remote", "reliable")
func request_lobby_deck(units: Array, structures: Array) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not _can_enter_session(sender) or not validate_deck_payload(units,structures): return
	peer_decks[sender] = {"units":units.duplicate(),"structures":structures.duplicate()}

func _disconnect_peer(peer_id: int) -> void:
	# Administrative closes do not emit SceneMultiplayer.peer_disconnected.
	# Leave explicitly (no reconnect grace), then clean authoritative indexes.
	if sessions.peer_to_room.has(peer_id): _leave_session(peer_id,true)
	multiplayer.disconnect_peer(peer_id)
	_on_peer_disconnected(peer_id)

@rpc("authority", "call_remote", "reliable")
func receive_completed_snapshot(data: Dictionary) -> void:
	# Final per-kind reports exceed a single datagram; ENet reliable fragmentation
	# avoids sending the only result/report over an oversized unreliable packet.
	receive_snapshot(data)

# ---------- Community statistics and the daily board ----------

func configure_stats(directory: String) -> void:
	stats.configure(directory)
	daily_board.configure(directory)
	shelf.configure(directory)
	replays.stats = stats

func client_is_online() -> bool:
	return not (client_connection_state in ["idle", "connecting", "recovering"]) and not client_reconnecting

func send_stats_request(decks: Array) -> void:
	if client_is_online():
		request_meta_stats.rpc_id(1, decks.slice(0, ServerStats.MAX_LOOKUP))

@rpc("any_peer", "call_remote", "reliable")
func request_meta_stats(decks: Array) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	var clean: Array = []
	for deck in decks.slice(0, ServerStats.MAX_LOOKUP):
		if deck is Array and deck.size() == 3 and deck.all(func(kind): return kind is String and BattleModel.UNIT_STATS.has(kind)):
			clean.append(deck)
	receive_meta_stats.rpc_id(sender, stats.snapshot(clean))

@rpc("authority", "call_remote", "reliable")
func receive_meta_stats(data: Dictionary) -> void:
	if not MetaStats.valid_snapshot(data): return
	MetaStats.store(data)
	meta_stats_received.emit(MetaStats.current())

func send_result_report(units: Array, structures: Array, result: int, mode: String) -> void:
	if client_is_online():
		report_result.rpc_id(1, units, structures, result, mode)

## Results the client reports about its own solo battles. Trusted as sent for now; they are counted
## in a separate "reported" bucket so they can be audited or discarded later.
@rpc("any_peer", "call_remote", "reliable")
func report_result(units: Array, structures: Array, result: int, mode: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not MetaStats.REPORT_MODES.has(mode): return
	if int(report_counts.get(sender, 0)) >= MAX_REPORTS_PER_CONNECTION: return
	if stats.record("reported", units, structures, result):
		report_counts[sender] = int(report_counts.get(sender, 0)) + 1
		stats.flush()

func send_daily_score(date: String, install_id: String, nickname: String, score: int, seconds: float) -> void:
	if client_is_online():
		submit_daily_score.rpc_id(1, date, install_id, nickname, score, seconds)

func send_daily_board_request(date: String, install_id: String) -> void:
	if client_is_online():
		request_daily_board.rpc_id(1, date, install_id)

@rpc("any_peer", "call_remote", "reliable")
func submit_daily_score(date: String, install_id: String, nickname: String, score: int, seconds: float) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if daily_board.submit(date, install_id, nickname, score, seconds):
		receive_daily_board.rpc_id(sender, daily_board.board(date, install_id))

@rpc("any_peer", "call_remote", "reliable")
func request_daily_board(date: String, install_id: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not ServerDailyBoard.accepts_date(date, DailyChallenge.date_key()): return
	receive_daily_board.rpc_id(sender, daily_board.board(date, install_id))

@rpc("authority", "call_remote", "reliable")
func receive_daily_board(data: Dictionary) -> void:
	if not MetaStats.valid_board(data): return
	MetaStats.boards[String(data.date)] = data
	daily_board_received.emit(data)

# ---------- Replay codes and recent online battles ----------

func send_replay_upload(text: String) -> void:
	if client_is_online():
		upload_replay.rpc_id(1, text)

func send_replay_fetch(code: String) -> void:
	if client_is_online():
		fetch_replay.rpc_id(1, code)

func send_recent_request() -> void:
	if client_is_online():
		request_recent_replays.rpc_id(1)

## Shares a replay by code. Answers with the code, or "" when the text was refused.
@rpc("any_peer", "call_remote", "reliable")
func upload_replay(text: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	var code := ""
	if text.length() <= ServerReplayShelf.MAX_TEXT and int(upload_counts.get(sender, 0)) < MAX_UPLOADS_PER_CONNECTION:
		upload_counts[sender] = int(upload_counts.get(sender, 0)) + 1
		code = shelf.add(text, false)
	receive_replay_code.rpc_id(sender, code)

@rpc("any_peer", "call_remote", "reliable")
func fetch_replay(code: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	var normalized := code.strip_edges().to_upper()
	receive_shared_replay.rpc_id(sender, normalized, shelf.text_for(normalized) if is_valid_room_code(normalized) else "")

@rpc("any_peer", "call_remote", "reliable")
func request_recent_replays() -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	receive_recent_replays.rpc_id(sender, shelf.recent())

@rpc("authority", "call_remote", "reliable")
func receive_replay_code(code: String) -> void:
	if code.is_empty() or is_valid_room_code(code):
		replay_code_received.emit(code)

@rpc("authority", "call_remote", "reliable")
func receive_shared_replay(code: String, text: String) -> void:
	if is_valid_room_code(code) and text.length() <= BattleReplay.MAX_SHARE_CHARS:
		shared_replay_received.emit(code, text)

@rpc("authority", "call_remote", "reliable")
func receive_recent_replays(list: Array) -> void:
	var clean: Array = []
	for entry in list.slice(0, ServerReplayShelf.RECENT_LIMIT):
		if entry is Dictionary and entry.get("code") is String and is_valid_room_code(entry.code) and entry.get("units") is Array and entry.units.size() == 2:
			clean.append(entry)
	recent_replays_received.emit(clean)
