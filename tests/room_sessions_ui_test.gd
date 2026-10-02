extends SceneTree
var failures:=0
var checks:=0
var main
const Store=preload("res://scripts/RoomSessions.gd")
func _initialize()->void:
	Engine.max_fps=20;call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	var directory:=""
	for value in OS.get_cmdline_user_args():
		if value.begins_with("--capture-dir="):directory=value.trim_prefix("--capture-dir=")
	if directory.is_empty():return
	DirAccess.make_dir_recursive_absolute(directory)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(directory.path_join(name+".png"))
func run()->void:
	create_timer(35.0).timeout.connect(func():printerr("Room session UI watchdog");quit(1))
	var bootstrap:=Node.new();bootstrap.name="Bootstrap";get_root().add_child(bootstrap)
	main=load("res://scenes/Main.tscn").instantiate();main.name="Main";bootstrap.add_child(main);main.updater.enabled=false
	main.save_data=SaveData.default_data();main.network.client_nickname="테스트 방장";main.network.client_connection_state="lobby"
	main.lobby_data={"rooms":[],"page":0,"total":0};main._build_lobby_screen();await process_frame;await process_frame
	check(main.lobby_previous_button.disabled and main.lobby_next_button.disabled,"single page disables navigation")
	check(main.root_background.find_child("NicknameInput",true,false)!=null,"nickname input provided")
	check(main.root_background.find_child("LobbyDeckSelector",true,false)!=null,"browser provides saved deck selector")
	main.lobby_data={"rooms":[{"code":"ABC234","name":"같이 연습해요","players":1,"locked":false,"state":"waiting","spectators":0},{"code":"DEF234","name":"친구들과 대전","players":2,"locked":true,"state":"playing","spectators":3}],"page":0,"total":2};main._render_room_listing(main.lobby_data)
	await process_frame;await process_frame
	var joins:Array=main.lobby_rows.find_children("JoinRoomButton","Button",true,false)
	check(joins.size()==2 and not joins[0].disabled and joins[1].disabled,"playing/full room cannot be joined as player")
	check(main.lobby_rows.find_children("WatchRoomButton","Button",true,false).size()==2,"room cards expose spectator actions")
	await capture("multiplayer-browser")
	main._show_create_room_dialog();await process_frame
	var name_input=main.room_create_dialog.find_child("RoomNameInput",true,false)
	var password_input=main.room_create_dialog.find_child("RoomPasswordInput",true,false)
	check(password_input!=null and password_input.secret,"room password input masks characters")
	name_input.text="";name_input.text_changed.emit("")
	check(main.room_create_dialog.get_ok_button().disabled,"empty room name disables create action")
	main.room_create_dialog.queue_free();await process_frame
	var store:=Store.new();var deck:Dictionary={"units":BattleModel.DEFAULT_UNIT_DECK.duplicate(),"structures":BattleModel.DEFAULT_STRUCTURE_DECK.duplicate()}
	store.create(1,"ABC234","같이 연습해요","테스트 방장","","",deck);store.join(20,"ABC234","참가자","player",deck);store.join(30,"ABC234","관전자","spectator",deck);store.append_chat(30,"안녕하세요. 이번 판은 관전할게요.");store.append_chat(20,"덱을 골랐어요. 준비하겠습니다.")
	main.network.client_session=store.public_state("ABC234");main.network.client_connection_state="session";main._on_session_changed(main.network.client_session);await process_frame;await process_frame
	check(main.multiplayer_screen=="session","session state opens persistent waiting room")
	check(main.session_roster.get_child_count()==2,"waiting room shows both player slots")
	check(main.session_start_button.disabled,"unready guest disables host start")
	check(main.session_chat_log.text.contains("[관전] 관전자"),"spectator messages retain role labels")
	check(not main.session_chat_log.bbcode_enabled,"chat treats formatting and links as plain text")
	store.set_ready(20,true);main.network.client_session=store.public_state("ABC234");main._on_session_changed(main.network.client_session)
	check(not main.session_start_button.disabled,"both ready enables owner start")
	await capture("multiplayer-waiting-room")
	main.network.client_is_spectator=true;main.local_ai_mode=false;main.own_side=0;main.battle_preset=deck;main._build_battle_screen()
	var model:=BattleModel.new();main._on_snapshot(model.snapshot())
	check(main.purchase_buttons.all(func(button):return button.disabled),"spectator purchase controls stay disabled after snapshot")
	check(main.root_background.find_child("BattleChatButton",true,false)!=null,"battle offers toggleable room chat")
	check(main.session_chat_log!=null and not main.session_chat_log.bbcode_enabled,"battle chat remains plain text")
	var before:int=main.save_data.stats.online_completed;main._show_result(0)
	check(main.save_data.stats.online_completed==before,"spectating never changes player win/loss statistics")
	check(main.result_overlay.find_children("*","Button",true,false).any(func(button):return button.text=="대기실로"),"battle result returns to same room")
	if failures==0:print("PASS: %d multiplayer browser, waiting-room, password, chat and spectator UI checks"%checks)
	main.network.disconnect_from_server();quit(0 if failures==0 else 1)
