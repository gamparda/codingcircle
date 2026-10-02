extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ",message)
func _initialize() -> void:
	var controller := NetworkController.new()
	controller.server_mode=true
	for attempt in 30:
		var id := 1000+attempt
		check(controller.register_peer_address(id,"198.51.100.7"),"repeat reconnect admitted immediately")
		controller._on_peer_disconnected(id)
		check(controller.peer_addresses.is_empty() and controller.address_connection_counts.is_empty(),"disconnect fully releases admission slot")
	for index in 12:
		check(controller.register_peer_address(2000+index,"198.51.100.7"),"normal simultaneous peer admitted")
	check(controller.register_peer_address(3000,"198.51.100.7"),"same-IP connection admitted above former simultaneous cap")
	controller._on_peer_disconnected(2000)
	check(controller.register_peer_address(3001,"198.51.100.7"),"released simultaneous slot is immediately reusable")
	check(not controller.register_peer_address(3000,"198.51.100.7"),"duplicate identifier rejected")
	check(not controller.register_peer_address(0,"198.51.100.7"),"invalid identifier rejected")
	check(not controller.register_peer_address(4000,""),"missing address rejected")
	controller.accepting_players=false
	check(not controller.can_admit_deck(3000),"update admission gate preserved")
	controller.accepting_players=true
	for index in 40: controller.models[index]=BattleModel.new()
	check(controller.can_create_match(),"matches above former global cap do not block admission")
	check(controller.can_admit_deck(3000) and controller.can_accept_room_request(),"existing matches do not block deck submission or room requests")
	controller.free()
	if failures==0: print("PASS: %d reconnect-without-IP-ban and uncapped-admission checks" % checks)
	quit(0 if failures==0 else 1)
