extends SceneTree
const Bindings=preload("res://scripts/BattleBindings.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func key(code:int)->InputEventKey:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;return event
func _initialize()->void:
	Engine.max_fps=20;call_deferred("run")
func capture()->void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var directory:=arg.trim_prefix("--capture-dir=");DirAccess.make_dir_recursive_absolute(directory)
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(directory.path_join("key-bindings.png"))
func run()->void:
	create_timer(30).timeout.connect(func():printerr("Key binding UI watchdog");quit(1))
	check(Bindings.sanitize(null)==Bindings.DEFAULTS,"legacy profiles receive original keys")
	var custom:=[KEY_J,KEY_K,KEY_L,KEY_U,KEY_I,KEY_O]
	var profile:=SaveData.default_data();profile.settings.battle_keys=custom.duplicate()
	check(SaveData.sanitize(JSON.parse_string(JSON.stringify(profile))).settings.battle_keys==custom,"bindings survive JSON float-number roundtrip")
	check(Bindings.sanitize([KEY_J,KEY_J,KEY_L,KEY_U,KEY_I,KEY_O])==Bindings.DEFAULTS,"malformed duplicate save resets safely")
	check(Bindings.sanitize([KEY_ESCAPE,KEY_K,KEY_L,KEY_U,KEY_I,KEY_O])==Bindings.DEFAULTS,"reserved key never loaded")
	check(Bindings.sanitize([INF,KEY_K,KEY_L,KEY_U,KEY_I,KEY_O])==Bindings.DEFAULTS,"non-finite save rejected")
	var draft:=Bindings.DEFAULTS.duplicate()
	check(not Bindings.assign(draft,0,KEY_Q).is_empty() and draft==Bindings.DEFAULTS,"duplicate assignment keeps draft unchanged")
	check(not Bindings.assign(draft,0,KEY_F11).is_empty(),"fullscreen reserved key rejected")
	check(Bindings.assign(draft,0,KEY_J).is_empty() and draft[0]==KEY_J,"valid physical key assigned")
	var bootstrap:=Control.new();bootstrap.name="Bootstrap";bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(bootstrap)
	var main=load("res://scenes/Main.tscn").instantiate();bootstrap.add_child(main);main.updater.enabled=false;main.set_process(false);main.save_data=SaveData.default_data();main.save_data.tutorial_completed=true
	main._build_settings_screen();check(main.binding_buttons.size()==6,"settings expose six action slots")
	main._begin_binding_capture(0);main._input(key(KEY_J))
	check(main.binding_draft[0]==KEY_J and main.binding_capture_index==-1,"actual key capture updates selected action")
	check(main.save_data.settings.battle_keys==Bindings.DEFAULTS,"unsaved draft leaves profile unchanged")
	main._begin_binding_capture(1);main._input(key(KEY_J))
	check(main.binding_capture_index==1 and main.binding_hint.text.contains("사용 중"),"UI rejects duplicate and continues capture")
	main._input(key(KEY_ESCAPE));check(main.binding_capture_index==-1 and main.binding_draft[1]==KEY_2,"Escape cancels capture without change")
	main.root_background.find_child("ResetBattleBindings",true,false).pressed.emit();check(main.binding_draft==Bindings.DEFAULTS,"restore resets all six draft keys")
	# Test disk persistence using an isolated profile file, not the user's save.
	var temporary:="user://bindings_test_profile.json"
	check(SaveData.save_data(profile,temporary),"profile with changed bindings written")
	var file:=FileAccess.open(temporary,FileAccess.READ);var loaded:=SaveData.sanitize(JSON.parse_string(file.get_as_text()));file.close();DirAccess.remove_absolute(temporary)
	check(loaded.settings.battle_keys==custom,"persisted physical keys reload")
	main.save_data.settings.battle_keys=custom.duplicate();main._build_settings_screen();await process_frame
	var scroll: ScrollContainer = main.root_background.find_child("SettingsScroll",true,false)
	var grid: Control = main.root_background.find_child("BattleKeyBindings",true,false)
	scroll.scroll_vertical = maxi(0,roundi(grid.get_global_rect().position.y-scroll.get_global_rect().position.y)-35)
	await capture()
	main._start_local_ai_battle()
	check(main.purchase_buttons.map(func(button):return button.get_node("PurchaseHotkey").text)==["J","K","L","U","I","O"],"battle cards show saved key names")
	check(not main._handle_battle_hotkey(key(KEY_1)) and main.local_model.units.is_empty(),"old key no longer triggers purchase")
	check(main._handle_battle_hotkey(key(KEY_J)) and main.local_model.units.size()==1,"new unit key performs actual purchase")
	check(main._handle_battle_hotkey(key(KEY_U)) and main.battle_view.selected_structure=="wall","new structure key selects matching slot")
	var input:=LineEdit.new();main.root_background.add_child(input);input.grab_focus();await process_frame
	check(not main._handle_battle_hotkey(key(KEY_K)),"custom keys remain blocked during text input")
	input.release_focus();main.network.client_is_spectator=true
	check(not main._handle_battle_hotkey(key(KEY_K)),"spectator cannot use customized battle keys")
	main.network.disconnect_from_server()
	if failures==0:print("PASS: %d key-binding persistence, validation, capture and gameplay checks"%checks)
	quit(0 if failures==0 else 1)
