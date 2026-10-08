extends RefCounted
## Runs an action that needs the game server and connects first when there is no connection yet, without
## opening the multiplayer screen. Used by the replay codes, the community statistics and the leaderboards so
## the player never has to "go online" by hand.

const LobbyFlow = preload("res://scripts/screens/LobbyFlow.gd")

const COOLDOWN_MSEC := 30000 # after a failed attempt, passive requests stay quiet this long
const POLL_SECONDS := 0.25

## `action` is called once the connection is up (right away when it already is). `on_status(text)` receives
## progress and failure messages. `force` false is for background requests: they do not retry for a while after a
## failure, so an offline player is not made to wait on every screen.
static func run(main, action: Callable, on_status: Callable = Callable(), force: bool = true) -> void:
	var network = main.network
	if network.client_is_online():
		action.call()
		return
	if not main.link_enabled:
		_say(on_status, "서버에 접속할 수 없습니다.")
		return
	if not force and Time.get_ticks_msec() - int(main.server_link_failed_at) < COOLDOWN_MSEC:
		_say(on_status, "서버에 접속할 수 없습니다.")
		return
	_say(on_status, "서버에 접속 중...")
	var context := {"done": false, "elapsed": 0.0}
	var ready := func():
		if bool(context.done):
			return
		context.done = true
		main.quiet_connection = false
		action.call()
	network.server_ready.connect(ready, CONNECT_ONE_SHOT)
	if network.client_connection_state != "connecting":
		_start(main)
	_poll(main, context, ready, on_status)

static func _start(main) -> void:
	main.quiet_connection = true
	var preset = main._active_preset()
	main.network.set_room_request("session")
	main.network.set_client_deck(preset.units, preset.structures)
	var port: int = int(main.link_port) if int(main.link_port) > 0 else LobbyFlow.OFFICIAL_SERVER_PORT
	main.network.connect_to_candidates(main.official_connection_candidates(IP.get_local_addresses()), port)

static func _poll(main, context: Dictionary, ready: Callable, on_status: Callable) -> void:
	if not is_instance_valid(main) or not main.is_inside_tree():
		return
	main.get_tree().create_timer(POLL_SECONDS).timeout.connect(func():
		if bool(context.done):
			return
		context.elapsed = float(context.elapsed) + POLL_SECONDS
		var state: String = main.network.client_connection_state
		if state == "idle" or float(context.elapsed) >= float(main.link_timeout):
			context.done = true
			main.quiet_connection = false
			main.server_link_failed_at = Time.get_ticks_msec()
			if main.network.server_ready.is_connected(ready):
				main.network.server_ready.disconnect(ready)
			if state == "connecting":
				main.network.disconnect_from_server()
			_say(on_status, "서버에 접속하지 못했습니다. 인터넷 연결을 확인해 주세요.")
		else:
			_poll(main, context, ready, on_status))

static func _say(on_status: Callable, text: String) -> void:
	if on_status.is_valid():
		on_status.call(text)
