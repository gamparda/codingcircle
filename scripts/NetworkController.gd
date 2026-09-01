class_name NetworkController
extends Node

signal connection_status(text: String)
signal match_found(side: int)
signal snapshot_received(data: Dictionary)
signal combat_events_received(events: Array)
signal opponent_disconnected
signal structure_placement_result(success: bool, error: String)
signal room_created(code: String)
signal room_join_failed(error: String)

const DEFAULT_PORT := 7777
const TICK_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 12.0
const MAX_REQUESTS_PER_SECOND := 24
const MAX_SNAPSHOT_UNITS := 256
const MAX_SNAPSHOT_STRUCTURES := 16
const MAX_CONNECTIONS_PER_ADDRESS := 4
const MAX_ACTIVE_MATCHES := 32
const EARLY_DISCONNECT_LIMIT := 3
const EARLY_DISCONNECT_WINDOW_MSEC := 60000
const QUICK_DISCONNECT_MSEC := 15000
const ABUSE_BLOCK_MSEC := 120000
const VALID_UNIT_KINDS := ["shield", "swordsman", "archer", "healer"]
const VALID_STRUCTURE_KINDS := ["wall", "swamp", "turret", "generator"]
const ROOM_CODE_LENGTH := 6
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

var registry := MatchRegistry.new()
var models: Dictionary = {}
var rematch_ready: Dictionary = {}
var server_mode := false
var allow_test_room_codes := false
var client_in_match := false
var accepting_players := true
var tick_accumulator := 0.0
var snapshot_accumulator := 0.0
var request_windows: Dictionary = {}
var peer_addresses: Dictionary = {}
var address_connection_counts: Dictionary = {}
var peer_connected_msec: Dictionary = {}
var early_disconnect_events: Dictionary = {}
var address_blocked_until: Dictionary = {}
var server_forced_disconnects: Dictionary = {}
var peer_decks: Dictionary = {}
var client_unit_deck: Array = BattleModel.DEFAULT_UNIT_DECK.duplicate()
var client_structure_deck: Array = BattleModel.DEFAULT_STRUCTURE_DECK.duplicate()
var client_connection_state := "idle"
var client_connection_candidates: Array = []
var client_connection_index := -1
var client_connection_port := DEFAULT_PORT
var client_room_mode := "create"
var client_room_code := ""

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

static func disconnect_message_for_state(state: String) -> String:
	return "서버 연결 실패" if state == "connecting" else "서버와 연결이 끊어졌습니다"

static func connection_candidates(primary_address: String, fallback_address: String = "") -> Array:
	var candidates: Array = []
	for address in [primary_address.strip_edges(), fallback_address.strip_edges()]:
		if not address.is_empty() and not candidates.has(address):
			candidates.append(address)
	return candidates

func _on_connected_to_server() -> void:
	client_connection_state = "connected"
	connection_status.emit("서버에 연결됨 · 덱 검증 중...")
	request_submit_deck.rpc_id(1, client_unit_deck, client_structure_deck)

static func validate_deck_payload(unit_deck: Array, structure_deck: Array) -> bool:
	return BattleModel._valid_deck(unit_deck, BattleModel.UNIT_STATS) and BattleModel._valid_deck(structure_deck, BattleModel.STRUCTURE_STATS)

func set_client_deck(unit_deck: Array, structure_deck: Array) -> bool:
	if not validate_deck_payload(unit_deck, structure_deck):
		return false
	client_unit_deck = unit_deck.duplicate()
	client_structure_deck = structure_deck.duplicate()
	return true

func set_room_request(mode: String, code: String = "") -> bool:
	if not ["create", "join", "enter"].has(mode):
		return false
	var normalized := code.strip_edges().to_upper()
	if mode != "create" and not is_valid_room_code(normalized):
		return false
	client_room_mode = mode
	client_room_code = normalized
	return true

func _on_connection_failed() -> void:
	if _retry_next_connection_candidate():
		return
	client_connection_state = "idle"
	connection_status.emit("서버 연결 실패")

func _on_server_disconnected() -> void:
	if client_connection_state == "idle":
		return
	var previous_state := client_connection_state
	if previous_state == "connecting" and _retry_next_connection_candidate():
		return
	client_connection_state = "idle"
	connection_status.emit(disconnect_message_for_state(previous_state))
	if client_in_match:
		client_in_match = false
		opponent_disconnected.emit()

func start_dedicated_server(port: int = DEFAULT_PORT) -> bool:
	allow_test_room_codes = OS.get_cmdline_user_args().has("--allow-test-room-codes")
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 128)
	if error != OK:
		printerr("서버 시작 실패: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	server_mode = true
	print("DEDICATED_SERVER_READY port=%d" % port)
	return true

func connect_to_server(address: String, port: int = DEFAULT_PORT, fallback_address: String = "") -> bool:
	return connect_to_candidates(connection_candidates(address, fallback_address), port)

func connect_to_candidates(candidates: Array, port: int = DEFAULT_PORT) -> bool:
	client_connection_candidates = []
	for candidate in candidates:
		var address := String(candidate).strip_edges()
		if not address.is_empty() and not client_connection_candidates.has(address):
			client_connection_candidates.append(address)
	client_connection_index = 0
	client_connection_port = port
	if client_connection_candidates.is_empty():
		connection_status.emit("서버 주소가 비어 있습니다")
		return false
	return _start_client_attempt(String(client_connection_candidates[0]))

func _start_client_attempt(address: String) -> bool:
	connection_status.emit("%s:%d 연결 중..." % [address, client_connection_port])
	client_connection_state = "connecting"
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, client_connection_port)
	if error != OK:
		if _retry_next_connection_candidate():
			return true
		client_connection_state = "idle"
		connection_status.emit("연결 설정 실패: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	return true

func _retry_next_connection_candidate() -> bool:
	if client_connection_index + 1 >= client_connection_candidates.size():
		return false
	client_connection_index += 1
	var fallback := String(client_connection_candidates[client_connection_index])
	connection_status.emit("DNS 응답 실패 · 공식 서버 우회 주소로 다시 연결 중...")
	print("CLIENT_CONNECTION_FALLBACK address=%s" % fallback)
	_start_client_attempt.call_deferred(fallback)
	return true

func disconnect_from_server() -> void:
	client_in_match = false
	client_connection_state = "idle"
	client_connection_candidates.clear()
	client_connection_index = -1
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

func set_accepting_players(value: bool) -> void:
	if accepting_players == value:
		return
	accepting_players = value
	if not accepting_players:
		for peer_id in multiplayer.get_peers():
			if peer_should_disconnect_for_drain(int(peer_id)):
				mark_server_forced_disconnect(int(peer_id))
				registry.remove_player(int(peer_id))
				(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(int(peer_id))

func peer_should_disconnect_for_drain(peer_id: int) -> bool:
	var match_id := registry.get_match_id(peer_id)
	if match_id <= 0 or not models.has(match_id):
		return true
	var model: BattleModel = models[match_id]
	return model.winner != -1

func can_accept_room_request() -> bool:
	return accepting_players and can_create_match()

func can_accept_rematch(model: BattleModel) -> bool:
	return accepting_players and model.winner != -1

func can_process_request(peer_id: int, now_msec: int = -1) -> bool:
	if peer_id <= 0:
		return false
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var window: Dictionary = request_windows.get(peer_id, {"started": now, "count": 0})
	if now - int(window.started) >= 1000:
		window = {"started": now, "count": 0}
	if int(window.count) >= MAX_REQUESTS_PER_SECOND:
		request_windows[peer_id] = window
		return false
	window.count = int(window.count) + 1
	request_windows[peer_id] = window
	return true

func register_peer_address(peer_id: int, address: String) -> bool:
	if peer_id <= 0 or address.is_empty() or peer_addresses.has(peer_id):
		return false
	if is_address_temporarily_blocked(address):
		return false
	var count := int(address_connection_counts.get(address, 0))
	if count >= MAX_CONNECTIONS_PER_ADDRESS:
		return false
	peer_addresses[peer_id] = address
	peer_connected_msec[peer_id] = Time.get_ticks_msec()
	address_connection_counts[address] = count + 1
	return true

func record_early_disconnect(address: String, now_msec: int = -1) -> void:
	if address.is_empty():
		return
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var recent: Array = []
	for event_time in early_disconnect_events.get(address, []):
		if now - int(event_time) <= EARLY_DISCONNECT_WINDOW_MSEC:
			recent.append(int(event_time))
	recent.append(now)
	early_disconnect_events[address] = recent
	if recent.size() >= EARLY_DISCONNECT_LIMIT:
		address_blocked_until[address] = now + ABUSE_BLOCK_MSEC

func is_address_temporarily_blocked(address: String, now_msec: int = -1) -> bool:
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	return now < int(address_blocked_until.get(address, 0))

func release_peer_address(peer_id: int) -> void:
	if not peer_addresses.has(peer_id):
		return
	var address := String(peer_addresses[peer_id])
	peer_addresses.erase(peer_id)
	peer_connected_msec.erase(peer_id)
	var count := int(address_connection_counts.get(address, 0)) - 1
	if count <= 0:
		address_connection_counts.erase(address)
	else:
		address_connection_counts[address] = count

func mark_server_forced_disconnect(peer_id: int) -> void:
	if peer_id > 0:
		server_forced_disconnects[peer_id] = true

func should_penalize_disconnect(peer_id: int, connected_at: int, now: int) -> bool:
	if server_forced_disconnects.erase(peer_id):
		return false
	return now - connected_at < QUICK_DISCONNECT_MSEC

func can_create_match() -> bool:
	return models.size() < MAX_ACTIVE_MATCHES

func _remote_address(peer_id: int) -> String:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return ""
	var packet_peer := enet.get_peer(peer_id)
	return "" if packet_peer == null else packet_peer.get_remote_address()

func _peer_is_connected(peer_id: int) -> bool:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null or not multiplayer.get_peers().has(peer_id):
		return false
	var packet_peer := enet.get_peer(peer_id)
	return packet_peer != null and packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED

func _disconnect_orphaned_peer(peer_id: int) -> void:
	var enet := multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet != null and _peer_is_connected(peer_id):
		mark_server_forced_disconnect(peer_id)
		enet.disconnect_peer(peer_id, true)

static func is_safe_command_text(value: String) -> bool:
	return not value.is_empty() and value.length() <= 32 and value == value.to_lower() and value.is_valid_identifier()

static func is_valid_room_code(value: String) -> bool:
	if value.length() != ROOM_CODE_LENGTH:
		return false
	for character in value:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true

static func is_safe_position(value: float) -> bool:
	return is_finite(value)

static func is_valid_match_side(side: int) -> bool:
	return side == 0 or side == 1

static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return _is_finite_number(value) and float(value) >= minimum and float(value) <= maximum

static func is_valid_snapshot(data: Dictionary) -> bool:
	if not _has_exact_keys(data, ["resources", "base_hp", "units", "structures", "winner", "elapsed"]):
		return false
	var resources = data.resources
	var base_hp = data.base_hp
	var units = data.units
	var structures = data.structures
	if not resources is Array or resources.size() != 2:
		return false
	if not base_hp is Array or base_hp.size() != 2:
		return false
	for value in resources:
		if not _number_in_range(value, 0.0, 150.0):
			return false
	for value in base_hp:
		if not _number_in_range(value, 0.0, 500.0):
			return false
	if not units is Array or units.size() > MAX_SNAPSHOT_UNITS:
		return false
	if not structures is Array or structures.size() > MAX_SNAPSHOT_STRUCTURES:
		return false
	var unit_ids := {}
	for unit in units:
		if not unit is Dictionary or not _has_exact_keys(unit, ["id", "side", "kind", "x", "hp", "max_hp", "damage", "heal", "interval", "cooldown", "speed", "range"]):
			return false
		var unit_id = unit.id
		var unit_side = unit.side
		if not unit_id is int or int(unit_id) <= 0 or unit_ids.has(unit_id):
			return false
		unit_ids[unit_id] = true
		if not unit_side is int or not is_valid_match_side(unit_side) or not VALID_UNIT_KINDS.has(String(unit.kind)):
			return false
		if not _number_in_range(unit.x, -256.0, 1536.0) or not _number_in_range(unit.max_hp, 0.01, 10000.0):
			return false
		if not _number_in_range(unit.hp, 0.0, float(unit.max_hp)):
			return false
		for key in ["damage", "heal", "interval", "cooldown", "speed", "range"]:
			if not _number_in_range(unit[key], 0.0, 10000.0):
				return false
	var structure_ids := {}
	for structure in structures:
		if not structure is Dictionary or not _has_exact_keys(structure, ["id", "side", "kind", "x", "hp", "max_hp"]):
			return false
		var structure_id = structure.id
		var structure_side = structure.side
		if not structure_id is int or int(structure_id) <= 0 or structure_ids.has(structure_id):
			return false
		structure_ids[structure_id] = true
		if not structure_side is int or not is_valid_match_side(structure_side) or not VALID_STRUCTURE_KINDS.has(String(structure.kind)):
			return false
		if not _number_in_range(structure.x, 0.0, 1280.0) or not _number_in_range(structure.max_hp, 0.01, 10000.0):
			return false
		if not _number_in_range(structure.hp, 0.0, float(structure.max_hp)):
			return false
	var winner = data.winner
	if not winner is int or int(winner) < -1 or int(winner) > 2:
		return false
	return _is_finite_number(data.elapsed) and float(data.elapsed) >= 0.0

func _process(delta: float) -> void:
	if not server_mode:
		return
	tick_accumulator += delta
	snapshot_accumulator += delta
	while tick_accumulator >= TICK_RATE:
		for match_id in models.keys():
			var model: BattleModel = models[match_id]
			model.tick(TICK_RATE)
			var events := model.drain_combat_events()
			if not events.is_empty():
				_broadcast_combat_events(int(match_id), events)
		tick_accumulator -= TICK_RATE
	if snapshot_accumulator >= SNAPSHOT_RATE:
		for match_id in models.keys():
			_broadcast_snapshot(int(match_id))
		snapshot_accumulator = 0.0

func _on_peer_connected(peer_id: int) -> void:
	if not server_mode:
		return
	if not accepting_players:
		print("PLAYER_REJECTED_UPDATE peer=%d" % peer_id)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
		return
	if not can_create_match() or not register_peer_address(peer_id, _remote_address(peer_id)):
		print("PLAYER_REJECTED_CAPACITY peer=%d" % peer_id)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer_id)
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
		if not registry.rooms.has(code):
			return code
	return ""

func _on_peer_disconnected(peer_id: int) -> void:
	if not server_mode:
		return
	var match_id := registry.get_match_id(peer_id)
	var players := registry.remove_player(peer_id)
	for player_id in players:
		if int(player_id) != peer_id and _peer_is_connected(int(player_id)):
			_disconnect_orphaned_peer.call_deferred(int(player_id))
	var now := Time.get_ticks_msec()
	var connected_at := int(peer_connected_msec.get(peer_id, now))
	var address := String(peer_addresses.get(peer_id, ""))
	if should_penalize_disconnect(peer_id, connected_at, now):
		record_early_disconnect(address, now)
	models.erase(match_id)
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
	if not validate_deck_payload(unit_deck, structure_deck):
		print("PLAYER_REJECTED_DECK peer=%d" % sender)
		mark_server_forced_disconnect(sender)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(sender)
		return
	peer_decks[sender] = {"units": unit_deck.duplicate(), "structures": structure_deck.duplicate()}
	print("PLAYER_DECK_ACCEPTED peer=%d" % sender)
	receive_deck_accepted.rpc_id(sender)

@rpc("any_peer", "call_remote", "reliable")
func request_create_room() -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not can_accept_room_request():
		receive_room_join_failed.rpc_id(sender, "서버가 업데이트 준비 중이거나 대전 수용량이 가득 찼습니다.")
		return
	if not can_process_request(sender) or not peer_decks.has(sender) or registry.peer_to_room.has(sender) or registry.has_match(sender):
		receive_room_join_failed.rpc_id(sender, "지금은 방을 만들 수 없습니다. 잠시 후 다시 시도하세요.")
		return
	var code := _generate_room_code()
	if code.is_empty() or not registry.create_room(sender, code):
		receive_room_join_failed.rpc_id(sender, "방을 만들지 못했습니다.")
		return
	print("ROOM_CREATED peer=%d" % sender)
	receive_room_created.rpc_id(sender, code)

@rpc("any_peer", "call_remote", "reliable")
func request_join_room(code: String, create_if_missing: bool = false) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	var normalized := code.strip_edges().to_upper()
	if not can_accept_room_request():
		receive_room_join_failed.rpc_id(sender, "서버가 업데이트 준비 중이거나 대전 수용량이 가득 찼습니다.")
		return
	if not can_process_request(sender) or not peer_decks.has(sender) or not is_valid_room_code(normalized):
		receive_room_join_failed.rpc_id(sender, "올바른 방 코드를 입력하세요.")
		return
	if create_if_missing and allow_test_room_codes and not registry.rooms.has(normalized):
		if registry.create_room(sender, normalized):
			print("ROOM_CREATED peer=%d smoke=true" % sender)
			receive_room_created.rpc_id(sender, normalized)
			return
	var paired := registry.join_room(sender, normalized)
	if paired.is_empty():
		receive_room_join_failed.rpc_id(sender, "방을 찾을 수 없거나 이미 시작된 방입니다.")
		return
	print("ROOM_JOINED peer=%d" % sender)
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
	if models.has(match_id):
		var side := registry.get_side(sender)
		if models[match_id].unit_decks[side].has(kind):
			models[match_id].spawn_unit(side, kind)

@rpc("any_peer", "call_remote", "reliable")
func request_place_structure(kind: String, x: float) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender):
		receive_structure_placement_result.rpc_id(sender, false, "요청이 너무 빠릅니다.")
		return
	if not is_safe_command_text(kind) or not is_safe_position(x):
		receive_structure_placement_result.rpc_id(sender, false, "잘못된 설치 요청입니다.")
		return
	var match_id := registry.get_match_id(sender)
	if not models.has(match_id):
		receive_structure_placement_result.rpc_id(sender, false, "진행 중인 경기가 없습니다.")
		return
	var side := registry.get_side(sender)
	var model: BattleModel = models[match_id]
	var error := model.structure_placement_error(side, kind, clamp(x, 0.0, 1280.0))
	var success := error.is_empty() and model.place_structure(side, kind, clamp(x, 0.0, 1280.0))
	if not success and error.is_empty():
		error = "구조물을 설치하지 못했습니다."
	receive_structure_placement_result.rpc_id(sender, success, error)

@rpc("any_peer", "call_remote", "reliable")
func request_rematch() -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
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
		rematch_ready[match_id] = {}
		_broadcast_snapshot(match_id)

func send_spawn(kind: String) -> void:
	if multiplayer.has_multiplayer_peer():
		request_spawn.rpc_id(1, kind)

func send_structure(kind: String, x: float) -> void:
	if multiplayer.has_multiplayer_peer():
		request_place_structure.rpc_id(1, kind, x)

func send_rematch() -> void:
	if multiplayer.has_multiplayer_peer():
		request_rematch.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func receive_deck_accepted() -> void:
	if client_room_mode == "join" or client_room_mode == "enter":
		request_join_room.rpc_id(1, client_room_code, client_room_mode == "enter")
	else:
		request_create_room.rpc_id(1)

@rpc("authority", "call_remote", "reliable")
func receive_room_created(code: String) -> void:
	if is_valid_room_code(code):
		room_created.emit(code)

@rpc("authority", "call_remote", "reliable")
func receive_room_join_failed(error: String) -> void:
	if error.length() <= 100:
		room_join_failed.emit(error)

func _broadcast_snapshot(match_id: int) -> void:
	if not models.has(match_id):
		return
	var data: Dictionary = models[match_id].snapshot()
	for player_id in registry.matches.get(match_id, []):
		if _peer_is_connected(int(player_id)):
			receive_snapshot.rpc_id(int(player_id), data)

func _broadcast_combat_events(match_id: int, events: Array) -> void:
	for player_id in registry.matches.get(match_id, []):
		if _peer_is_connected(int(player_id)):
			receive_combat_events.rpc_id(int(player_id), events)

@rpc("authority", "call_remote", "reliable")
func match_started(side: int) -> void:
	if is_valid_match_side(side):
		client_in_match = true
		match_found.emit(side)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(data: Dictionary) -> void:
	if is_valid_snapshot(data):
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
