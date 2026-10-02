extends SceneTree
var server
var host
var guest
var observer
var late_observer
var snapshots:Dictionary={}
var errors:Array=[]
var listing:Dictionary={}
var checks:=0
var failures:=0
func _initialize()->void:
	Engine.max_fps=20;call_deferred("run")
func make_controller(label:String):
	var holder:=Node.new();holder.name=label;get_root().add_child(holder)
	set_multiplayer(SceneMultiplayer.new(),holder.get_path())
	var bootstrap:=Node.new();bootstrap.name="Bootstrap";holder.add_child(bootstrap)
	var main:=Node.new();main.name="Main";bootstrap.add_child(main)
	var controller:=NetworkController.new();controller.name="NetworkController";main.add_child(controller)
	controller.set_room_request("session");controller.client_nickname=label
	return controller
func wait_until(predicate:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+6000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	return predicate.call()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func require(predicate:Callable,message:String)->bool:
	var okay:bool=await wait_until(predicate);check(okay,message)
	if not okay:await finish(1)
	return okay
func finish(code:int)->void:
	if is_instance_valid(server):server.set_process(false)
	for controller in [host,guest,observer,late_observer]:
		if is_instance_valid(controller):
			controller.disconnect_from_server();await create_timer(0.2).timeout
	await create_timer(0.15).timeout
	if is_instance_valid(server):server.multiplayer.multiplayer_peer.close()
	quit(code)
func run()->void:
	create_timer(50.0).timeout.connect(func():printerr("Persistent room wire watchdog");finish(1))
	var production:=OS.get_cmdline_user_args().has("--production")
	var port:=7777 if production else 27985
	if not production:
		server=make_controller("RoomServer")
		if not server.start_dedicated_server(port):await finish(1);return
	host=make_controller("방장");guest=make_controller("참가자");observer=make_controller("관전자");late_observer=make_controller("후발관전자")
	guest.session_error.connect(func(text):errors.append(text))
	guest.room_list_received.connect(func(data):listing=data)
	var clients:Array=[host,guest,observer,late_observer]
	for index in clients.size():
		var control=clients[index]
		control.snapshot_received.connect(func(data):snapshots[index]=data)
		control.connect_to_server("127.0.0.1",port)
	if not await require(func():return clients.all(func(control):return control.client_connection_state=="lobby"),"four clients enter lobby"):return
	check(host.create_session_room("대기실 기능 검증","room-test-726"),"host creates password room")
	if not await require(func():return not host.client_session.is_empty(),"host receives session state"):return
	var code:String=host.client_session.code
	if not await require(func():
		for row in listing.get("rooms",[]):
			if row.code==code:return row.get("locked",false) and row.players==1
		return false,"room listing advertises lock but not secret"):return
	check(not JSON.stringify(listing).contains("room-test-726") and not JSON.stringify(host.client_session).contains("secret"),"public packets do not disclose passwords")
	guest.join_session_room(code,"wrong-room-key")
	if not await require(func():return errors.size()==1 and guest.client_connection_state=="lobby","wrong password fails without disconnecting client"):return
	guest.join_session_room(code,"room-test-726")
	if not await require(func():return host.client_session.members.size()==2 and guest.client_connection_state=="session","correct password joins persistent waiting room"):return
	check(not host.client_in_match and not guest.client_in_match,"joining does not automatically start combat")
	observer.join_session_room(code,"room-test-726",true)
	if not await require(func():return observer.client_is_spectator and host.client_session.members.size()==3,"spectator joins waiting room"):return
	guest.request_session_start.rpc_id(1)
	if not await require(func():return errors.size()==2,"non-owner start rejected"):return
	guest.request_session_ready.rpc_id(1,true)
	if not await require(func():return host.client_session.members.any(func(member):return member.nickname=="참가자" and member.ready),"ready state reaches host"):return
	host.request_session_start.rpc_id(1)
	if not await require(func():return host.client_in_match and guest.client_in_match and observer.client_in_match,"owner starts players and spectator together"):return
	late_observer.join_session_room(code,"room-test-726",true)
	if not await require(func():return late_observer.client_in_match and snapshots.has(3),"late spectator receives the live authoritative snapshot"):return
	host.send_spawn("swordsman")
	if not await require(func():return snapshots.size()==4 and snapshots.values().all(func(data):return data.units.size()>0),"authoritative purchase synchronized across four clients"):return
	check(not host.client_is_spectator and observer.client_is_spectator,"player and spectator roles remain distinct")
	observer.request_spawn.rpc_id(1,"swordsman")
	await create_timer(0.2).timeout
	if not production:check(server.registry.get_match_id(observer.multiplayer.get_unique_id())==0 and server.models.values()[0].units.size()==1,"forged spectator purchase rejected by server")
	observer.request_session_chat.rpc_id(1,"[b]관전 채팅[/b]")
	if not await require(func():return clients.all(func(control):return control.client_session.messages.any(func(message):return message.text=="[b]관전 채팅[/b]")),"room chat reaches players and spectators during combat"):return
	if not production:
		var mid:int=server.sessions.rooms[code].match_id
		server.models[mid].winner=0
		if not await require(func():return host.client_session.phase=="finished","battle result preserves room membership"):return
		host.request_session_return.rpc_id(1);guest.request_session_return.rpc_id(1)
		if not await require(func():return host.client_session.phase=="waiting" and guest.client_connection_state=="session" and observer.client_connection_state=="session","players return to same room with spectators"):return
		check(not server.models.has(mid) and server.registry.matches.is_empty(),"completed match cleaned after both players return")
		host.request_session_ready.rpc_id(1,true);guest.request_session_ready.rpc_id(1,true)
		if not await require(func():return host.client_session.members.filter(func(member):return member.role=="player").all(func(member):return member.ready),"both players ready for second match"):return
		host.request_session_start.rpc_id(1)
		if not await require(func():return host.client_in_match and guest.client_in_match and observer.client_in_match,"same room starts second match"):return
	host.request_session_leave.rpc_id(1)
	if not await require(func():return host.client_connection_state=="lobby" and guest.client_session.phase=="waiting" and guest.client_session.owner==guest.multiplayer.get_unique_id(),"host leaves to lobby and remaining player becomes owner"):return
	check(guest.client_connection_state=="session" and observer.client_connection_state=="session","interrupted match returns survivors to waiting room without transport loss")
	guest.request_session_leave.rpc_id(1)
	if not await require(func():return guest.client_connection_state=="lobby" and observer.client_connection_state=="lobby" and late_observer.client_connection_state=="lobby","last player leave closes spectator room and returns everyone to lobby"):return
	if not production:check(server.sessions.rooms.is_empty() and server.session_matches.is_empty() and server.models.is_empty(),"server cleans every persistent-room and match reference")
	if failures==0:print("PASS: %d real ENet persistent-room, password, readiness, replay, chat and spectator checks"%checks)
	await finish(0 if failures==0 else 1)
