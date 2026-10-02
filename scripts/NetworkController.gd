class_name NetworkController
extends Node

const Localization = preload("res://scripts/Localization.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

signal connection_status(text: String)
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

const DEFAULT_PORT := 7777
const TICK_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 12.0
const MAX_REQUESTS_PER_SECOND := 24
const MAX_SNAPSHOT_UNITS := 256
const MAX_SNAPSHOT_STRUCTURES := 16
const TRANSPORT_MAX_PEERS := 4095 # ENet protocol ceiling, not an application admission quota.
const VALID_UNIT_KINDS := ["shield", "swordsman", "archer", "healer", "berserker", "warlock", "necromancer", "skeleton"]
const VALID_STRUCTURE_KINDS := ["wall", "swamp", "turret", "generator"]
const ROOM_LIST_PAGE_SIZE := 12
const ROOM_NAME_LENGTH := 24
const ROOM_CODE_LENGTH := 6
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CONNECTION_TIMEOUT := 4.0
const ROOM_REQUEST_TIMEOUT := 8.0

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

static func validate_deck_payload(unit_deck: Array, structure_deck: Array) -> bool:
	return BattleModel._valid_deck(unit_deck, BattleModel.UNIT_STATS) and BattleModel._valid_deck(structure_deck, BattleModel.STRUCTURE_STATS)

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
	if _retry_next_connection_candidate():
		return
	client_connection_state = "idle"
	connection_status.emit(Localization.text("서버 연결 실패"))

func _on_server_disconnected() -> void:
	if client_connection_state == "idle":
		return
	var previous_state := client_connection_state
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
	client_connection_generation += 1
	client_in_match = false
	client_is_spectator = false
	client_session.clear()
	pending_room_password = ""
	client_connection_state = "idle"
	client_phase_elapsed = 0.0
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
				multiplayer.disconnect_peer(int(peer_id))

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
	var count := int(address_connection_counts.get(address, 0))
	peer_addresses[peer_id] = address
	address_connection_counts[address] = count + 1
	return true

func release_peer_address(peer_id: int) -> void:
	if not peer_addresses.has(peer_id):
		return
	var address := String(peer_addresses[peer_id])
	peer_addresses.erase(peer_id)
	var count := int(address_connection_counts.get(address, 0)) - 1
	if count <= 0:
		address_connection_counts.erase(address)
	else:
		address_connection_counts[address] = count

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
		multiplayer.disconnect_peer(peer_id)

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
	if not _has_required_optional_keys(data, ["resources", "base_hp", "units", "structures", "winner", "elapsed"], ["curses", "base_max_hp", "spawn_cooldowns", "battle_report"]):
		return false
	if data.has("battle_report") and (int(data.get("winner",-1)) == -1 or not preload("res://scripts/BattleReport.gd").valid(data.battle_report)): return false
	if data.has("spawn_cooldowns"):
		if not data.spawn_cooldowns is Array or data.spawn_cooldowns.size()!=2: return false
		for side in data.spawn_cooldowns:
			if not side is Dictionary or side.size()>BattleModel.UNIT_STATS.size(): return false
			for kind in side:
				if not BattleModel.UNIT_STATS.has(kind) or not _number_in_range(side[kind],0.0,0.35): return false
	var resources = data.resources
	var base_hp = data.base_hp
	var units = data.units
	var structures = data.structures
	if not resources is Array or resources.size() != 2:
		return false
	if not base_hp is Array or base_hp.size() != 2:
		return false
	for value in resources:
		if not _number_in_range(value, 0.0, BattleModel.MAX_RESOURCE):
			return false
	for value in base_hp:
		if not _number_in_range(value, 0.0, 500.0):
			return false
	var maxima = data.get("base_max_hp", [BattleModel.BASE_MAX_HP, BattleModel.BASE_MAX_HP])
	if not maxima is Array or maxima.size() != 2:
		return false
	for index in 2:
		if not _number_in_range(maxima[index], 1.0, BattleModel.BASE_MAX_HP) or float(base_hp[index]) > float(maxima[index]):
			return false
	if not units is Array or units.size() > MAX_SNAPSHOT_UNITS:
		return false
	if not structures is Array or structures.size() > MAX_SNAPSHOT_STRUCTURES:
		return false
	var unit_ids := {}
	for unit in units:
		if not unit is Dictionary or not _has_required_optional_keys(unit, ["id", "side", "kind", "x", "hp", "max_hp", "damage", "heal", "interval", "cooldown", "speed", "range"], ["support_stacks", "summon_remaining"]):
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
		if unit.has("support_stacks") and (not unit.support_stacks is int or int(unit.support_stacks) < 0 or int(unit.support_stacks) > BattleModel.SUPPORT_MAX_STACKS):
			return false
		if unit.has("summon_remaining") and (unit.kind != "necromancer" or not _number_in_range(unit.summon_remaining, 0.0, BattleModel.SUMMON_INTERVAL)):
			return false
	var structure_ids := {}
	for structure in structures:
		if not structure is Dictionary or not _has_required_optional_keys(structure, ["id", "side", "kind", "x", "hp", "max_hp"], ["expires_at"]):
			return false
		var structure_id = structure.id
		var structure_side = structure.side
		if not structure_id is int or int(structure_id) <= 0 or structure_ids.has(structure_id):
			return false
		structure_ids[structure_id] = true
		if not structure_side is int or not is_valid_match_side(structure_side) or not VALID_STRUCTURE_KINDS.has(String(structure.kind)):
			return false
		if not _number_in_range(structure.x, 0.0, BattleModel.WORLD_WIDTH) or not _number_in_range(structure.max_hp, 0.01, 10000.0):
			return false
		if not _number_in_range(structure.hp, 0.0, float(structure.max_hp)):
			return false
		if structure.has("expires_at") and (structure.kind != "swamp" or not _number_in_range(structure.expires_at, 0.0, 1000000000.0)):
			return false
	var winner = data.winner
	var curses = data.get("curses", [])
	if not curses is Array or curses.size() > MAX_SNAPSHOT_UNITS:
		return false
	var sources := {}
	for curse in curses:
		if not curse is Dictionary or not _has_exact_keys(curse, ["source_id", "side", "x", "expires_at"]):
			return false
		if not curse.source_id is int or int(curse.source_id) <= 0 or sources.has(curse.source_id) or not curse.side is int or not is_valid_match_side(int(curse.side)):
			return false
		if not _number_in_range(curse.x, BattleModel.FIELD_LEFT, BattleModel.FIELD_RIGHT) or not _number_in_range(curse.expires_at, 0.0, 1000000000.0):
			return false
		sources[curse.source_id] = true
	if not winner is int or int(winner) < -1 or int(winner) > 2:
		return false
	return _is_finite_number(data.elapsed) and float(data.elapsed) >= 0.0

static func _has_required_optional_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	for key in required:
		if not value.has(key):
			return false
	for key in value:
		if not required.has(key) and not optional.has(key):
			return false
	return true

func _process(delta: float) -> void:
	if not server_mode:
		_advance_client_connection(delta)
		return
	for id in join_challenges.keys():
		if Time.get_ticks_msec()>int(join_challenges[id].deadline): join_challenges.erase(id)
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
	tick_accumulator += delta
	snapshot_accumulator += delta
	while tick_accumulator >= TICK_RATE:
		for match_id in models.keys():
			var model: BattleModel = models[match_id]
			model.tick(TICK_RATE)
			if model.winner != -1 and session_matches.has(match_id):
				var code: String = session_matches[match_id]
				if sessions.rooms.has(code) and sessions.rooms[code].phase == "playing":
					sessions.finish(code)
					_push_session(code)
					lobby_dirty = true
			var events := model.drain_combat_events()
			if not events.is_empty():
				_broadcast_combat_events(int(match_id), events)
		tick_accumulator -= TICK_RATE
	if snapshot_accumulator >= SNAPSHOT_RATE:
		for match_id in models.keys():
			_broadcast_snapshot(int(match_id))
		snapshot_accumulator = 0.0

func _advance_client_connection(delta: float) -> void:
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
		multiplayer.disconnect_peer(peer_id)
		return
	if not register_peer_address(peer_id, _remote_address(peer_id)):
		print("PLAYER_REJECTED_INVALID_PEER peer=%d" % peer_id)
		multiplayer.disconnect_peer(peer_id)
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
		if not registry.rooms.has(code) and not sessions.rooms.has(code):
			return code
	return ""

func _on_peer_disconnected(peer_id: int) -> void:
	if not server_mode:
		return
	var session_peer: bool = sessions.peer_to_room.has(peer_id)
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
		multiplayer.disconnect_peer(sender)
		return
	if not validate_deck_payload(unit_deck, structure_deck):
		print("PLAYER_REJECTED_DECK peer=%d" % sender)
		multiplayer.disconnect_peer(sender)
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
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("요청이 너무 빠릅니다."))
		return
	if not is_safe_command_text(kind) or not is_safe_position(x):
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("잘못된 설치 요청입니다."))
		return
	var match_id := registry.get_match_id(sender)
	if not models.has(match_id):
		receive_structure_placement_result.rpc_id(sender, false, Localization.text("진행 중인 경기가 없습니다."))
		return
	var side := registry.get_side(sender)
	var model: BattleModel = models[match_id]
	var error := model.structure_placement_error(side, kind, clamp(x, 0.0, BattleModel.WORLD_WIDTH))
	var success := error.is_empty() and model.place_structure(side, kind, clamp(x, 0.0, BattleModel.WORLD_WIDTH))
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
	for player_id in _match_audience(match_id):
		if _peer_is_connected(int(player_id)):
			receive_snapshot.rpc_id(int(player_id), data)

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
	var value := title.strip_edges()
	if value.is_empty() or value.length() > ROOM_NAME_LENGTH: return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127: return false
	return true

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
	if not _has_exact_keys(data,["rooms","page","total"]) or not data.rooms is Array: return false
	if not _number_in_range(data.page,0,TRANSPORT_MAX_PEERS) or not _number_in_range(data.total,0,TRANSPORT_MAX_PEERS): return false
	if float(data.page) != floor(float(data.page)) or float(data.total) != floor(float(data.total)) or data.rooms.size() > ROOM_LIST_PAGE_SIZE: return false
	var last_page := maxi(0,(int(data.total)-1)/ROOM_LIST_PAGE_SIZE)
	if int(data.page)>last_page or data.rooms.size()!=mini(ROOM_LIST_PAGE_SIZE,maxi(0,int(data.total)-int(data.page)*ROOM_LIST_PAGE_SIZE)): return false
	var codes: Dictionary = {}
	for item in data.rooms:
		if not item is Dictionary or not _has_required_optional_keys(item,["code","name","players"],["locked","state","spectators"]): return false
		if not item.code is String or not is_valid_room_code(item.code) or codes.has(item.code): return false
		if not item.name is String or not is_valid_room_name(item.name) or not _number_in_range(item.players,1,2) or float(item.players)!=floor(float(item.players)): return false
		if not item.has("state") and int(item.players)!=1: return false
		if item.has("locked") and not item.locked is bool: return false
		if item.has("state") and item.state not in ["waiting","playing","finished"]: return false
		if item.has("spectators") and (not _number_in_range(item.spectators,0,TRANSPORT_MAX_PEERS) or float(item.spectators)!=floor(float(item.spectators))): return false
		codes[item.code] = true
	return true

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
	var state := sessions.public_state(code)
	if state.is_empty(): return
	for member in state.members:
		if _peer_is_connected(int(member.id)): receive_session_state.rpc_id(int(member.id),state)

func _cleanup_session_match(match_id: int) -> void:
	if match_id <= 0: return
	for id in registry.matches.get(match_id,[]):
		if registry.get_match_id(int(id)) == match_id:
			registry.peer_to_match.erase(id); registry.peer_to_side.erase(id)
	registry.matches.erase(match_id); models.erase(match_id); rematch_ready.erase(match_id); session_matches.erase(match_id)

func _leave_session(peer_id: int, disconnected: bool = false) -> void:
	var result := sessions.leave(peer_id)
	if result.is_empty(): return
	if result.interrupted: _cleanup_session_match(int(result.match_id))
	if result.closed:
		for id in result.affected:
			if int(id) != peer_id and _peer_is_connected(int(id)):
				receive_session_closed.rpc_id(int(id),"방이 종료되었습니다.")
	else: _push_session(result.code)
	lobby_dirty = true
	if not disconnected and _peer_is_connected(peer_id): receive_session_closed.rpc_id(peer_id,"")

static func _hex_string(value: String, length: int) -> bool:
	if value.length() != length: return false
	for char_value in value:
		if not char_value in "0123456789abcdef": return false
	return true

func _can_enter_session(peer_id: int) -> bool:
	return accepting_players and peer_decks.has(peer_id) and not registry.has_match(peer_id) and not registry.peer_to_room.has(peer_id) and not sessions.peer_to_room.has(peer_id)

@rpc("any_peer", "call_remote", "reliable")
func request_create_session(title: String, nickname: String, salt: String, secret: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if not _can_enter_session(sender) or not is_valid_room_name(title) or not SessionStore.safe_text(nickname,SessionStore.MAX_NICKNAME):
		receive_session_error.rpc_id(sender,"지금은 방을 만들 수 없습니다."); return
	if not ((salt.is_empty() and secret.is_empty()) or (_hex_string(salt,32) and _hex_string(secret,64))):
		receive_session_error.rpc_id(sender,"잘못된 비밀번호 설정입니다."); return
	var code := _generate_room_code()
	if code.is_empty(): receive_session_error.rpc_id(sender,"방 코드를 생성하지 못했습니다. 다시 시도하세요."); return
	if not sessions.create(sender,code,title.strip_edges(),nickname.strip_edges(),salt,secret,peer_decks[sender]):
		receive_session_error.rpc_id(sender,"방을 만들지 못했습니다."); return
	lobby_pages.erase(sender)
	lobby_dirty = true; _push_session(code)

@rpc("any_peer", "call_remote", "reliable")
func request_session_challenge(code: String, nickname: String, role: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if not _can_enter_session(sender) or not sessions.rooms.has(code) or role not in ["player","spectator"] or not SessionStore.safe_text(nickname,SessionStore.MAX_NICKNAME):
		receive_session_error.rpc_id(sender,"참가할 수 없는 방입니다."); return
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	join_challenges[sender] = {"code":code,"nickname":nickname.strip_edges(),"role":role,"nonce":nonce,"deadline":Time.get_ticks_msec()+10000}
	receive_session_challenge.rpc_id(sender,code,sessions.rooms[code].salt,nonce)

@rpc("any_peer", "call_remote", "reliable")
func request_join_session(response: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not join_challenges.has(sender): return
	var challenge: Dictionary = join_challenges[sender]; join_challenges.erase(sender)
	if not _can_enter_session(sender) or Time.get_ticks_msec() > challenge.deadline or not sessions.rooms.has(challenge.code):
		receive_session_error.rpc_id(sender,"방이 종료되었거나 참가 시간이 초과되었습니다."); return
	var room: Dictionary = sessions.rooms[challenge.code]
	var expected := "" if room.secret.is_empty() else SessionStore.proof(room.secret,challenge.nonce,sender,challenge.code)
	if not SessionStore.equal_secret(expected,response):
		receive_session_error.rpc_id(sender,"비밀번호가 맞지 않습니다."); return
	var error: String = sessions.join(sender,challenge.code,challenge.nickname,challenge.role,peer_decks[sender])
	if not error.is_empty(): receive_session_error.rpc_id(sender,error); return
	lobby_pages.erase(sender)
	lobby_dirty = true; _push_session(challenge.code)
	if room.phase in ["playing","finished"] and challenge.role == "spectator":
		session_spectate.rpc_id(sender)
		if models.has(room.match_id): receive_snapshot.rpc_id(sender,models[room.match_id].snapshot())

@rpc("any_peer", "call_remote", "reliable")
func request_session_ready(ready: bool) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if sessions.set_ready(sender,ready): _push_session(sessions.peer_to_room[sender])

@rpc("any_peer", "call_remote", "reliable")
func request_session_deck(units: Array, structures: Array) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not validate_deck_payload(units,structures): return
	if sessions.set_deck(sender,{"units":units,"structures":structures}):
		peer_decks[sender] = {"units":units.duplicate(),"structures":structures.duplicate()}
		_push_session(sessions.peer_to_room[sender])

@rpc("any_peer", "call_remote", "reliable")
func request_session_start() -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if not accepting_players or not sessions.can_start(sender):
		receive_session_error.rpc_id(sender,"두 플레이어가 준비해야 시작할 수 있습니다."); return
	var match_id := registry.next_match_id; registry.next_match_id += 1
	var ids: Array = sessions.start(sender,match_id)
	var room: Dictionary = sessions.room_for(sender)
	var model := BattleModel.new()
	registry.matches[match_id] = ids.duplicate()
	for side in 2:
		var id: int = ids[side]; registry.peer_to_match[id] = match_id; registry.peer_to_side[id] = side
		var deck: Dictionary = room.members[id].deck
		model.configure_deck(side,deck.units,deck.structures)
	models[match_id] = model; session_matches[match_id] = room.code
	_push_session(room.code); lobby_dirty = true
	for side in 2: match_started.rpc_id(int(ids[side]),side)
	for id in room.members:
		if room.members[id].role == "spectator": session_spectate.rpc_id(int(id))
	_broadcast_snapshot(match_id)

@rpc("any_peer", "call_remote", "reliable")
func request_session_return() -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender): return
	if sessions.return_from_battle(sender):
		var room: Dictionary = sessions.room_for(sender)
		if room.phase == "waiting": _cleanup_session_match(int(room.match_id)); room.match_id = 0; lobby_dirty = true
		_push_session(room.code)

@rpc("any_peer", "call_remote", "reliable")
func request_session_leave() -> void:
	if server_mode and can_process_request(multiplayer.get_remote_sender_id()): _leave_session(multiplayer.get_remote_sender_id())

@rpc("any_peer", "call_remote", "reliable")
func request_session_chat(text: String) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not sessions.peer_to_room.has(sender) or not SessionStore.safe_text(text,SessionStore.MAX_CHAT): return
	var now := Time.get_ticks_msec()
	if now-int(chat_times.get(sender,-1000)) < 750: return
	chat_times[sender] = now
	var message: Dictionary = sessions.append_chat(sender,text)
	if message.is_empty(): return
	for id in sessions.room_for(sender).members:
		if _peer_is_connected(int(id)): receive_session_chat.rpc_id(int(id),message)

static func valid_session_state(data: Dictionary) -> bool:
	if not _has_exact_keys(data,["code","name","owner","phase","locked","members","messages"]): return false
	if not data.code is String or not is_valid_room_code(data.code) or not data.name is String or not is_valid_room_name(data.name): return false
	if not data.locked is bool or data.phase not in ["waiting","playing","finished"] or not data.members is Array or not data.messages is Array: return false
	if data.members.size()<1 or data.members.size()>TRANSPORT_MAX_PEERS or data.messages.size()>SessionStore.CHAT_HISTORY: return false
	var players := 0; var ids: Dictionary = {}
	for member in data.members:
		if not member is Dictionary or not _has_exact_keys(member,["id","nickname","role","ready","returned","deck"]): return false
		if not _number_in_range(member.id,1,2147483647) or float(member.id)!=floor(float(member.id)) or ids.has(int(member.id)): return false
		if not member.nickname is String or not SessionStore.safe_text(member.nickname,SessionStore.MAX_NICKNAME) or member.role not in ["player","spectator"] or not member.ready is bool or not member.returned is bool: return false
		if not member.deck is Dictionary or not _has_exact_keys(member.deck,["units","structures"]) or not member.deck.units is Array or not member.deck.structures is Array or not validate_deck_payload(member.deck.units,member.deck.structures): return false
		ids[int(member.id)] = true
		if member.role == "player": players += 1
	if players<1 or players>2 or not _number_in_range(data.owner,1,2147483647) or float(data.owner)!=floor(float(data.owner)) or not ids.has(int(data.owner)): return false
	for message in data.messages:
		if not valid_chat_message(message): return false
	return true

static func valid_chat_message(message: Variant) -> bool:
	return message is Dictionary and _has_exact_keys(message,["id","nickname","role","text"]) and _number_in_range(message.id,1,1e9) and message.nickname is String and SessionStore.safe_text(message.nickname,SessionStore.MAX_NICKNAME) and message.role in ["player","spectator"] and message.text is String and SessionStore.safe_text(message.text,SessionStore.MAX_CHAT)

@rpc("authority", "call_remote", "reliable")
func receive_session_state(data: Dictionary) -> void:
	if client_connection_state == "idle" or not valid_session_state(data): return
	var self_member: Dictionary = {}
	for member in data.members:
		if int(member.id) == multiplayer.get_unique_id(): self_member = member
	if self_member.is_empty(): return
	client_session = data.duplicate(true)
	client_is_spectator = self_member.role == "spectator"
	pending_room_password = ""
	if data.phase == "waiting" or (data.phase == "finished" and self_member.returned):
		client_in_match = false; client_connection_state = "session"
	elif client_connection_state != "in_match": client_connection_state = "session"
	client_phase_elapsed = 0.0
	session_changed.emit(client_session)

@rpc("authority", "call_remote", "reliable")
func receive_session_challenge(code: String, salt: String, nonce: String) -> void:
	if client_connection_state != "room_request" or not is_valid_room_code(code) or not _hex_string(nonce,32) or not (salt.is_empty() or _hex_string(salt,32)): return
	var secret: String = SessionStore.verifier(pending_room_password,salt)
	pending_room_password = ""
	request_join_session.rpc_id(1,"" if salt.is_empty() else SessionStore.proof(secret,nonce,multiplayer.get_unique_id(),code))

@rpc("authority", "call_remote", "reliable")
func receive_session_error(text: String) -> void:
	if text.length()>100: return
	pending_room_password = ""
	if client_session.is_empty(): client_connection_state = "lobby"
	else: client_connection_state = "session" if client_session.phase != "playing" else "in_match"
	session_error.emit(text)

@rpc("authority", "call_remote", "reliable")
func receive_session_closed(text: String) -> void:
	if text.length()>100: return
	client_session.clear(); client_is_spectator = false; client_in_match = false; client_connection_state = "lobby"
	session_closed.emit(text)
	request_room_list.rpc_id(1,0)

@rpc("authority", "call_remote", "reliable")
func receive_session_chat(message: Dictionary) -> void:
	if client_session.is_empty() or not valid_chat_message(message): return
	client_session.messages.append(message)
	if client_session.messages.size()>SessionStore.CHAT_HISTORY: client_session.messages.pop_front()
	session_chat.emit(message)

@rpc("authority", "call_remote", "reliable")
func session_spectate() -> void:
	if client_session.is_empty() or not client_is_spectator: return
	client_in_match = true; client_connection_state = "in_match"
	spectate_started.emit()

func create_session_room(title: String, password: String = "") -> bool:
	if client_connection_state != "lobby" or not is_valid_room_name(title) or password.length()>32 or not SessionStore.safe_text(client_nickname,SessionStore.MAX_NICKNAME): return false
	var salt := "" if password.is_empty() else Crypto.new().generate_random_bytes(16).hex_encode()
	client_connection_state = "room_request"; client_phase_elapsed = 0.0
	request_create_session.rpc_id(1,title.strip_edges(),client_nickname,salt,SessionStore.verifier(password,salt))
	return true

func join_session_room(code: String, password: String = "", spectator: bool = false) -> bool:
	if client_connection_state != "lobby" or not is_valid_room_code(code) or password.length()>32 or not SessionStore.safe_text(client_nickname,SessionStore.MAX_NICKNAME): return false
	pending_room_password = password
	client_connection_state = "room_request"; client_phase_elapsed = 0.0
	request_session_challenge.rpc_id(1,code,client_nickname,"spectator" if spectator else "player")
	return true

@rpc("any_peer", "call_remote", "reliable")
func request_lobby_deck(units: Array, structures: Array) -> void:
	if not server_mode: return
	var sender := multiplayer.get_remote_sender_id()
	if not can_process_request(sender) or not _can_enter_session(sender) or not validate_deck_payload(units,structures): return
	peer_decks[sender] = {"units":units.duplicate(),"structures":structures.duplicate()}
