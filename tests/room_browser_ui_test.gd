extends SceneTree
var checks:=0
var failures:=0
var capture_dir:=""
func check(value:bool,message:String)->void:
	checks+=1
	if not value: failures+=1;printerr("FAIL: ",message)
func _initialize()->void:
	Engine.max_fps=20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):capture_dir=arg.trim_prefix("--capture-dir=")
	call_deferred("run")
func run()->void:
	create_timer(45.0).timeout.connect(func():printerr("Room browser UI watchdog");quit(1))
	var bootstrap:=Control.new();bootstrap.name="Bootstrap";bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);get_root().add_child(bootstrap)
	var scene:PackedScene=load("res://scenes/Main.tscn")
	var main=scene.instantiate();bootstrap.add_child(main)
	main.updater.enabled=false
	await process_frame
	check(main.find_child("MultiplayerButton",true,false)!=null,"main menu offers multiplayer navigation")
	check(main.find_child("RoomCodeInput",true,false)==null,"main menu is no longer the code/create form")
	main._build_lobby_screen()
	main.network.client_room_mode="lobby";main.network.client_connection_state="lobby"
	main._on_room_list({"rooms":[],"page":0,"total":0})
	await process_frame
	check(main.find_child("NoRoomsLabel",true,false)!=null,"empty browser is explicit")
	check(not main.connect_button_ref.disabled,"connected browser enables room creation")
	var quick:Button=main.find_child("QuickMatchButton",true,false)
	check(quick!=null and not quick.disabled and quick.text.contains("빠른 대전"),"lobby offers a one-button quick match")
	main.network.client_connection_state="queued";main._on_quick_match_status("queued")
	check(quick.text.contains("취소") and not quick.disabled and main.connect_button_ref.disabled,"queued state turns the button into cancel and locks room creation")
	main.network.client_connection_state="lobby";main._on_quick_match_status("cancelled")
	check(quick.text.contains("빠른 대전") and not main.connect_button_ref.disabled,"cancel restores the lobby")
	var data:Dictionary={"rooms":[{"code":"ABC234","name":"처음 하는 분 환영","players":1},{"code":"DEF234","name":"한 판 같이 해요","players":1}],"page":0,"total":2}
	main._on_room_list(data)
	await process_frame
	check(main.lobby_rows.get_child_count()==2,"room list renders exactly the advertised rows")
	check(main.lobby_rows.find_children("JoinRoomButton","Button",true,false).size()==2,"every waiting room has a join action")
	check(main.lobby_page_label.text.contains("2개"),"total agrees with visible rooms")
	main._show_create_room_dialog()
	await process_frame
	check(is_instance_valid(main.room_create_dialog) and main.room_create_dialog.visible,"create opens a real dialog")
	check(main.room_create_dialog.find_child("RoomNameInput",true,false).max_length==24,"dialog supplies a bounded room-name field")
	main.room_create_dialog.canceled.emit()
	await process_frame
	main.network.client_room_name="처음 하는 분 환영";main.network.client_connection_state="waiting"
	main._on_room_created("ABC234")
	await process_frame
	check(main.find_child("WaitingRoomPanel",true,false)!=null,"creation enters a waiting room")
	check(main.find_child("LeaveRoomButton",true,false)!=null,"waiting host can leave")
	main.network.client_connection_state="lobby";main._on_room_list(data)
	await process_frame
	check(main.find_child("RoomBrowserPanel",true,false)!=null,"leave acknowledgement returns to the room browser")
	if not capture_dir.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_dir.path_join("room-browser.png"))
	main.network.disconnect_from_server()
	main.queue_free();await process_frame
	if failures==0:print("PASS: %d room-browser UI navigation checks"%checks)
	quit(0 if failures==0 else 1)
