extends SceneTree
var checks:=0
var failures:=0
func check(value: bool, message: String) -> void:
	checks+=1
	if not value: failures+=1;printerr("FAIL: ",message)
func _initialize() -> void:
	var registry:=MatchRegistry.new()
	check(registry.create_room(10,"ABC234","처음 하는 분 환영"),"named room created")
	var rooms:=registry.room_listing()
	check(rooms.size()==1 and rooms[0].name=="처음 하는 분 환영" and rooms[0].players==1,"listing contains a real waiting room")
	check(not registry.create_room(10,"DEF234","중복"),"one host cannot occupy two rooms")
	var paired:=registry.join_room(20,"ABC234")
	check(paired.size()==2 and registry.room_listing().is_empty() and registry.room_names.is_empty(),"joining starts a match and removes room from browser")
	registry.remove_player(10)
	check(registry.create_room(10,"DEF234","다시 만들기"),"host can create after cleanup")
	registry.remove_player(10)
	check(registry.rooms.is_empty() and registry.room_names.is_empty(),"leaving deletes the advertised room and title")
	check(NetworkController.is_valid_room_name("둘이 대전해요"),"Korean room title accepted")
	check(not NetworkController.is_valid_room_name(" ") and not NetworkController.is_valid_room_name("가".repeat(25)) and not NetworkController.is_valid_room_name("a\nb"),"empty, oversized and control-character names rejected")
	check(NetworkController.is_valid_room_listing({"rooms":[],"page":0,"total":0}),"empty browser response accepted")
	var data:Dictionary={"rooms":[{"code":"ABC234","name":"연습방","players":1}],"page":0,"total":1}
	check(NetworkController.is_valid_room_listing(data),"normal named room response accepted")
	var bad:=data.duplicate(true);bad.rooms[0].players=2
	check(not NetworkController.is_valid_room_listing(bad),"started/full room is not advertised as joinable")
	bad=data.duplicate(true);bad.total=0
	check(not NetworkController.is_valid_room_listing(bad),"list total must match enumerated page")
	bad=data.duplicate(true);bad.page=0.5
	check(not NetworkController.is_valid_room_listing(bad),"fractional page rejected")
	var controller:=NetworkController.new()
	check(controller.set_room_request("lobby"),"browser mode does not need a room code")
	controller.client_connection_state="connected"
	controller.receive_room_list(data)
	check(controller.client_connection_state=="lobby","server list completes the initial connection without creating a room")
	controller._advance_client_connection(30.0)
	check(controller.client_connection_state=="lobby","browsing does not hit the room-response timeout")
	controller.client_connection_state="waiting"
	controller.receive_room_list(data)
	check(controller.client_connection_state=="waiting","list pushes do not eject a waiting host")
	controller.client_connection_state="leaving"
	controller.receive_room_list(data)
	check(controller.client_connection_state=="lobby","leave acknowledgement returns to browser")
	controller.client_connection_state="room_request";controller.client_room_mode="lobby"
	controller.receive_room_join_failed("방이 이미 시작됐습니다.")
	check(controller.client_connection_state=="lobby","joining a stale room preserves the connection for another selection")
	controller.free()
	if failures==0:print("PASS: %d room-browser lifecycle and protocol checks"%checks)
	quit(0 if failures==0 else 1)
