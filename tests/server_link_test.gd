extends SceneTree
## Features that need the server connect on their own: success, already online, failure and the retry cooldown.

const ServerLink = preload("res://scripts/ServerLink.gd")
var server
var client
var checks := 0
var failures := 0

class FakeMain extends Node:
	var network
	var link_enabled := true
	var link_port := 0
	var link_timeout := 8.0
	var server_link_failed_at := -1000000
	var quiet_connection := false
	func _active_preset() -> Dictionary:
		return {"units": BattleModel.DEFAULT_UNIT_DECK.duplicate(), "structures": BattleModel.DEFAULT_STRUCTURE_DECK.duplicate()}
	func official_connection_candidates(_local: Variant) -> Array:
		return ["127.0.0.1"]

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	Engine.max_fps = 20
	call_deferred("run")

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	return controller

func wait_until(predicate: Callable, seconds: float = 6.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	return predicate.call()

func finish(code: int) -> void:
	if is_instance_valid(client):
		client.disconnect_from_server(); await create_timer(0.2).timeout
	await create_timer(0.15).timeout
	if is_instance_valid(server): server.multiplayer.multiplayer_peer.close()
	print("server_link_test checks=%d failures=%d" % [checks, failures])
	quit(code)

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("server link watchdog"); finish(1))
	var port := 27990
	server = make_controller("LinkServer")
	if not server.start_dedicated_server(port):
		await finish(1); return
	client = make_controller("클라")
	var fake := FakeMain.new()
	fake.network = client
	fake.link_port = port
	fake.link_timeout = 1.5
	get_root().add_child(fake)

	var called := []
	var messages := []
	ServerLink.run(fake, func(): called.append(1), func(text): messages.append(text))
	check(messages == ["서버에 접속 중..."] and fake.quiet_connection, "starting says it is connecting and keeps connection messages quiet")
	check(await wait_until(func(): return called.size() == 1), "the action runs once the connection is up")
	check(client.client_is_online() and not fake.quiet_connection and messages.size() == 1, "online afterwards, quiet mode is over, no failure reported")

	ServerLink.run(fake, func(): called.append(2), func(text): messages.append(text))
	check(called == [1, 2] and messages.size() == 1, "when already online the action runs right away")

	# Failure: nothing listens on this port.
	client.disconnect_from_server()
	fake.link_port = 27999
	var failed := []
	var failure_calls := []
	ServerLink.run(fake, func(): failure_calls.append(1), func(text): failed.append(text))
	check(await wait_until(func(): return failed.size() == 2, 8.0), "an unreachable server is reported")
	check(failed.size() == 2 and failed[1].begins_with("서버에 접속하지 못했습니다") and failure_calls.is_empty() and not fake.quiet_connection, "the failure message arrives and the action never runs")
	check(client.client_connection_state == "idle" and fake.server_link_failed_at > 0, "the client is idle again and the failure is remembered")

	# Passive requests stay quiet for a while after a failure; deliberate ones try again.
	var passive := []
	ServerLink.run(fake, func(): passive.append(1), func(text): passive.append(text), false)
	check(passive == ["서버에 접속할 수 없습니다."] and client.client_connection_state == "idle", "background requests do not retry right after a failure")
	var disabled := FakeMain.new()
	disabled.network = client
	disabled.link_enabled = false
	get_root().add_child(disabled)
	var off := []
	ServerLink.run(disabled, func(): off.append(1), func(text): off.append(text))
	check(off == ["서버에 접속할 수 없습니다."] and client.client_connection_state == "idle", "with linking switched off nothing is dialled")
	await finish(0 if failures == 0 else 1)
