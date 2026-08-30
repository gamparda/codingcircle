class_name NetworkController
extends Node

signal connection_status(text: String)
signal match_found(side: int)
signal snapshot_received(data: Dictionary)
signal opponent_disconnected

const DEFAULT_PORT := 7777
const TICK_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 12.0

var registry := MatchRegistry.new()
var models: Dictionary = {}
var rematch_ready: Dictionary = {}
var server_mode := false
var accepting_players := true
var tick_accumulator := 0.0
var snapshot_accumulator := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connection_status.emit("서버에 연결됨 · 상대를 찾는 중..."))
	multiplayer.connection_failed.connect(func(): connection_status.emit("서버 연결 실패"))
	multiplayer.server_disconnected.connect(func(): connection_status.emit("서버와 연결이 끊어졌습니다"))

func start_dedicated_server(port: int = DEFAULT_PORT) -> bool:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_server(port, 128)
	if error != OK:
		printerr("서버 시작 실패: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	server_mode = true
	print("DEDICATED_SERVER_READY port=%d" % port)
	return true

func connect_to_server(address: String, port: int = DEFAULT_PORT) -> bool:
	connection_status.emit("%s:%d 연결 중..." % [address, port])
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		connection_status.emit("연결 설정 실패: %s" % error_string(error))
		return false
	multiplayer.multiplayer_peer = peer
	return true

func set_accepting_players(value: bool) -> void:
	if accepting_players == value:
		return
	accepting_players = value
	if not accepting_players and registry.waiting_peer != 0:
		var waiting_peer := registry.waiting_peer
		registry.remove_player(waiting_peer)
		if multiplayer.get_peers().has(waiting_peer):
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(waiting_peer)

func _process(delta: float) -> void:
	if not server_mode:
		return
	tick_accumulator += delta
	snapshot_accumulator += delta
	while tick_accumulator >= TICK_RATE:
		for model in models.values():
			model.tick(TICK_RATE)
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
	print("PLAYER_CONNECTED peer=%d" % peer_id)
	var paired := registry.add_player(peer_id)
	if paired.is_empty():
		return
	var match_id := registry.get_match_id(peer_id)
	models[match_id] = BattleModel.new()
	rematch_ready[match_id] = {}
	for player_id in paired.keys():
		match_started.rpc_id(int(player_id), int(paired[player_id]))
	_broadcast_snapshot(match_id)
	print("MATCH_CREATED id=%d players=%s" % [match_id, paired.keys()])

func _on_peer_disconnected(peer_id: int) -> void:
	if not server_mode:
		return
	var match_id := registry.get_match_id(peer_id)
	var players := registry.remove_player(peer_id)
	for player_id in players:
		if int(player_id) != peer_id and multiplayer.get_peers().has(int(player_id)):
			opponent_left.rpc_id(int(player_id))
	models.erase(match_id)
	rematch_ready.erase(match_id)
	print("PLAYER_DISCONNECTED peer=%d" % peer_id)

@rpc("any_peer", "call_remote", "reliable")
func request_spawn(kind: String) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	var match_id := registry.get_match_id(sender)
	if models.has(match_id):
		models[match_id].spawn_unit(registry.get_side(sender), kind)

@rpc("any_peer", "call_remote", "reliable")
func request_place_structure(kind: String, x: float) -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	var match_id := registry.get_match_id(sender)
	if models.has(match_id):
		models[match_id].place_structure(registry.get_side(sender), kind, clamp(x, 0.0, 1280.0))

@rpc("any_peer", "call_remote", "reliable")
func request_rematch() -> void:
	if not server_mode:
		return
	var sender := multiplayer.get_remote_sender_id()
	var match_id := registry.get_match_id(sender)
	if not models.has(match_id):
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

func _broadcast_snapshot(match_id: int) -> void:
	if not models.has(match_id):
		return
	var data: Dictionary = models[match_id].snapshot()
	for player_id in registry.matches.get(match_id, []):
		if multiplayer.get_peers().has(int(player_id)):
			receive_snapshot.rpc_id(int(player_id), data)

@rpc("authority", "call_remote", "reliable")
func match_started(side: int) -> void:
	match_found.emit(side)

@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(data: Dictionary) -> void:
	snapshot_received.emit(data)

@rpc("authority", "call_remote", "reliable")
func opponent_left() -> void:
	opponent_disconnected.emit()
