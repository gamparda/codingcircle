extends SceneTree
# One process, isolated SceneMultiplayer roots, real ENet RPC traffic.
var server
var host
var guest
var observer
var attacker
var clients: Array = []
var latest: Dictionary = {}
var checks := 0
var failures := 0
var finishing := false

func _initialize() -> void:
	Engine.max_fps = 20
	call_deferred("run")

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(),holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	return controller

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)

func require(predicate: Callable, message: String) -> bool:
	var deadline := Time.get_ticks_msec()+6000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.025).timeout
	var okay: bool = predicate.call(); check(okay,message)
	if not okay: await finish(1)
	return okay

func finish(code: int) -> void:
	if finishing: return
	finishing = true
	for client in clients:
		client.disconnect_from_server(); await create_timer(0.2).timeout
	server.set_process(false); server.multiplayer.multiplayer_peer.close()
	quit(code)

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("Recovery wire watchdog"); finish(1))
	server = make_controller("RecoveryServer")
	if not server.start_dedicated_server(27986): await finish(1); return
	host = make_controller("방장"); guest = make_controller("참가자"); guest._reconnect_retry_delay = 2.0
	observer = make_controller("관전자"); observer._reconnect_retry_delay = 2.0; attacker = make_controller("외부인")
	clients = [host,guest,observer,attacker]
	host.snapshot_received.connect(func(data): latest = data)
	for client in clients: client.connect_to_server("127.0.0.1",27986)
	if not await require(func(): return clients.all(func(c): return c.client_connection_state == "lobby"),"clients enter lobby"): return
	host.create_session_room("복구 검증")
	if not await require(func(): return not host.client_session.is_empty() and not host.client_reconnect_token.is_empty(),"private credentials issued"): return
	var code: String = host.client_session.code
	guest.join_session_room(code)
	observer.join_session_room(code,"",true)
	if not await require(func(): return host.client_session.members.size()==3 and not guest.client_reconnect_token.is_empty() and not observer.client_reconnect_token.is_empty(),"players and spectator join"): return
	check(not JSON.stringify(host.client_session).contains(host.client_reconnect_token) and not JSON.stringify(server._all_room_listings()).contains("reconnect_hash"),"public room data contains no credential")
	if not await require(func(): return host.latency_ms >= 0,"real ping/pong measures RTT"): return
	var live_id: int = guest.multiplayer.get_unique_id()
	var original_token: String = guest.client_reconnect_token
	attacker.request_reconnect.rpc_id(1,code,original_token)
	await create_timer(0.15).timeout
	check(server.sessions.room_for(live_id).members[live_id].connected and not server.sessions.peer_to_room.has(attacker.multiplayer.get_unique_id()),"even valid token cannot hijack connected player")
	guest.request_session_ready.rpc_id(1,true)
	if not await require(func(): return server.sessions.can_start(host.multiplayer.get_unique_id()),"players ready"): return
	host.request_session_start.rpc_id(1)
	if not await require(func(): return host.client_in_match and guest.client_in_match and observer.client_in_match,"match starts with spectator"): return
	var mid: int = server.sessions.rooms[code].match_id
	observer.request_surrender.rpc_id(1)
	await create_timer(0.15).timeout
	check(server.models[mid].winner == -1 and not observer.send_surrender(),"forged and UI spectator surrender denied")
	host.send_spawn("swordsman")
	if not await require(func(): return server.models[mid].units.size()==1,"authoritative unit exists before recovery"): return
	server.multiplayer.disconnect_peer(live_id)
	server._on_peer_disconnected(live_id) # SceneMultiplayer.disconnect_peer intentionally suppresses its local signal.
	if not await require(func(): return server.sessions.paused(code),"unexpected disconnect pauses match"): return
	var elapsed: float = server.models[mid].elapsed
	var remaining: float = server._recovery_state(mid).reconnect_remaining
	check(remaining>19.0 and remaining<=20.0,"server grants bounded twenty-second grace")
	host.send_spawn("swordsman")
	await create_timer(0.15).timeout
	check(is_equal_approx(server.models[mid].elapsed,elapsed) and server.models[mid].units.size()==1,"ticks and purchases freeze during recovery")
	if not await require(func(): return not guest.client_reconnecting and guest.multiplayer.get_unique_id()!=live_id and server.sessions.peer_to_room.has(guest.multiplayer.get_unique_id()),"client automatically reconnects under new peer ID"): return
	var recovered_id: int = guest.multiplayer.get_unique_id()
	check(server.registry.get_match_id(recovered_id)==mid and server.registry.get_side(recovered_id)==1 and server.sessions.rooms[code].members.size()==3 and not server.registry.peer_to_match.has(live_id),"same room model side and membership rebound without ghost peer")
	check(guest.client_reconnect_token!=original_token and not guest.client_reconnect_token.is_empty(),"single-use token rotated")
	attacker.request_reconnect.rpc_id(1,code,original_token)
	await create_timer(0.15).timeout
	check(not server.sessions.peer_to_room.has(attacker.multiplayer.get_unique_id()),"consumed token replay rejected")
	if not await require(func(): return server.models[mid].elapsed>elapsed and not latest.get("network",{}).get("paused",true),"authoritative simulation resumes"): return
	var observer_old: int = observer.multiplayer.get_unique_id()
	server.multiplayer.disconnect_peer(observer_old)
	server._on_peer_disconnected(observer_old)
	if not await require(func(): return not server.sessions.room_for(observer_old).is_empty() and not server.sessions.room_for(observer_old).members[observer_old].connected,"spectator gets recovery grace"): return
	check(not server.sessions.paused(code),"spectator disconnect does not pause players")
	if not await require(func(): return not observer.client_reconnecting and observer.client_is_spectator and observer.client_in_match and observer.multiplayer.get_unique_id()!=observer_old,"spectator rejoins with unchanged authority"): return
	check(host.send_surrender(),"player surrender API accepts active player")
	if not await require(func(): return latest.get("winner",-1)==1 and host.client_session.phase=="finished","surrender authoritative result preserves room"): return
	host.request_session_return.rpc_id(1); guest.request_session_return.rpc_id(1)
	if not await require(func(): return server.sessions.rooms[code].phase=="waiting" and not server.models.has(mid),"results return cleans model"): return
	host.request_session_ready.rpc_id(1,true); guest.request_session_ready.rpc_id(1,true)
	if not await require(func(): return server.sessions.can_start(host.multiplayer.get_unique_id()),"same room readies again"): return
	host.request_session_start.rpc_id(1)
	if not await require(func(): return host.client_in_match and guest.client_in_match,"second match starts"): return
	mid = server.sessions.rooms[code].match_id
	# Prevent the test client retrying; advance only the server deadline, not simulation time.
	guest.set_process(false)
	var timed_out: int = guest.multiplayer.get_unique_id()
	server.multiplayer.disconnect_peer(timed_out)
	server._on_peer_disconnected(timed_out)
	if not await require(func(): return server.sessions.paused(code),"second disconnect enters grace"): return
	guest.client_reconnecting = false; guest.client_connection_generation += 1
	server.sessions.rooms[code].members[timed_out].reconnect_deadline = Time.get_ticks_msec()-1
	if not await require(func(): return not server.sessions.peer_to_room.has(timed_out) and server.models[mid].winner==0 and host.client_session.phase=="finished","expired grace forfeits match and removes ghost seat"): return
	host.request_session_return.rpc_id(1)
	if not await require(func(): return server.sessions.rooms[code].phase=="waiting" and not server.models.has(mid),"survivor return cleans timed-out model"): return
	host.disconnect_from_server()
	check(host.client_reconnect_token.is_empty() and not host.client_reconnecting,"explicit disconnect immediately clears credentials")
	if not await require(func(): return not server.sessions.rooms.has(code) and observer.client_connection_state=="lobby","explicit last-player leave closes room immediately without grace"): return
	check(server.session_matches.is_empty() and server.registry.matches.is_empty() and server.models.is_empty(),"no stale room or model references")
	if failures==0: print("PASS: %d isolated ENet recovery, surrender and latency checks"%checks)
	await finish(0 if failures==0 else 1)
