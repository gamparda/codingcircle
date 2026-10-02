extends SceneTree
var server
var host
var guest
var listing:Dictionary={}
var snapshots:Dictionary={}
func _initialize()->void:
	Engine.max_fps=20
	call_deferred("run")
func make_controller(label:String):
	var holder:=Node.new();holder.name=label;get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(),holder.get_path())
	var bootstrap:=Node.new();bootstrap.name="Bootstrap";holder.add_child(bootstrap)
	var main:=Node.new();main.name="Main";bootstrap.add_child(main)
	var controller:=NetworkController.new();controller.name="NetworkController";main.add_child(controller)
	return controller
func wait_until(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+6000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	return predicate.call()
func finish(code:int)->void:
	for controller in [host,guest,server]:
		if is_instance_valid(controller):controller.multiplayer.multiplayer_peer.close()
	quit(code)
func run()->void:
	create_timer(35.0).timeout.connect(func():printerr("Room browser wire smoke watchdog");finish(1))
	var production:=OS.get_cmdline_user_args().has("--production")
	host=make_controller("BrowserHost")
	guest=make_controller("BrowserGuest")
	var port:=7777 if production else 27983
	if not production:
		server=make_controller("BrowserServer")
		if not server.start_dedicated_server(port):finish(1);return
	host.set_room_request("lobby");guest.set_room_request("lobby")
	guest.room_list_received.connect(func(data):listing=data)
	host.snapshot_received.connect(func(data):snapshots[0]=data)
	guest.snapshot_received.connect(func(data):snapshots[1]=data)
	host.connect_to_server("127.0.0.1",port);guest.connect_to_server("127.0.0.1",port)
	if not await wait_until(func():return host.client_connection_state=="lobby" and guest.client_connection_state=="lobby"):
		printerr("Browser clients could not enter lobby");finish(1);return
	var room_code:Dictionary={"value":""}
	host.room_created.connect(func(code):room_code.value=code)
	if not host.create_lobby_room("방 목록 연동 확인"):
		printerr("Create action was rejected locally");finish(1);return
	if not await wait_until(func():
		for item in listing.get("rooms",[]):
			if item.code==room_code.value:return true
		return false):
		printerr("Guest did not receive the host's actual room listing");finish(1);return
	print("REAL_LOBBY_ROOM_ADVERTISED ",room_code.value)
	if not guest.join_lobby_room(room_code.value):finish(1);return
	if not await wait_until(func():return host.client_connection_state=="in_match" and guest.client_connection_state=="in_match"):
		printerr("List join did not create a two-player match");finish(1);return
	host.send_spawn("swordsman")
	if not await wait_until(func():return snapshots.has(0) and snapshots.has(1) and snapshots[0].units.size()>0 and snapshots[1].units.size()>0):
		printerr("Both clients did not receive the authoritative purchase");finish(1);return
	print("PASS: real room listing -> join -> two-client match -> synchronized authoritative purchase")
	if is_instance_valid(server): server.set_process(false)
	host.disconnect_from_server()
	await create_timer(0.2).timeout
	guest.disconnect_from_server()
	await create_timer(0.3).timeout
	finish(0)
