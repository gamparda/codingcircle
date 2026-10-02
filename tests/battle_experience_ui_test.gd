extends SceneTree
var main
var checks:=0
var failures:=0
func _initialize()->void:
	Engine.max_fps=20;call_deferred("run")
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func key(code:int)->InputEventKey:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=true;return event
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	var directory:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):directory=arg.trim_prefix("--capture-dir=")
	if directory.is_empty():return
	DirAccess.make_dir_recursive_absolute(directory)
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png(directory.path_join(name+".png"))
func run()->void:
	create_timer(40.0).timeout.connect(func():printerr("Battle experience UI watchdog");quit(1))
	var bootstrap:=Control.new();bootstrap.name="Bootstrap";bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);get_root().add_child(bootstrap)
	main=load("res://scenes/Main.tscn").instantiate();bootstrap.add_child(main);main.updater.enabled=false
	main.save_data=SaveData.default_data();main.local_ai_mode=true;main.local_model=BattleModel.new();main.local_ai=ServerAI.new();main.battle_preset=main._active_preset().duplicate(true);main._build_battle_screen();main.set_process(false);main._on_snapshot(main.local_model.snapshot())
	await process_frame;await process_frame
	check(main.purchase_buttons.map(func(button):return button.get_node("PurchaseHotkey").text)==["1","2","3","Q","W","E"],"six purchase cards expose correct hotkeys")
	check(main._handle_battle_hotkey(key(KEY_2)) and main.local_model.units.size()==1,"unit hotkey follows authoritative purchase callback")
	check(main.purchase_buttons[1].disabled and main.purchase_buttons[1].get_node("PurchaseState").text.contains("대기"),"successful purchase displays cooldown and disables repeat")
	var repeated:=key(KEY_2);repeated.echo=true
	check(not main._handle_battle_hotkey(repeated) and main.local_model.units.size()==1,"key-repeat cannot spam purchases")
	var input:=LineEdit.new();main.root_background.add_child(input);input.grab_focus();await process_frame
	check(not main._handle_battle_hotkey(key(KEY_1)) and main.local_model.units.size()==1,"text and chat focus block battle hotkeys")
	input.release_focus();input.queue_free();await process_frame
	main.local_model.resources[0]=180;main.local_model.tick(0.4);main.client_purchase_gates.clear();main._on_snapshot(main.local_model.snapshot())
	check(main._handle_battle_hotkey(key(KEY_Q)) and main.battle_view.selected_structure=="wall","structure hotkey selects structure")
	check(main.cancel_build_button.visible,"mobile-friendly cancel action is visible during placement")
	main._cancel_build_selection()
	check(main.battle_view.selected_structure.is_empty() and not main.cancel_build_button.visible,"cancel action clears preview and toggle state")
	main.network.client_is_spectator=true
	check(not main._handle_battle_hotkey(key(KEY_1)),"spectator hotkeys cannot purchase")
	main.network.client_is_spectator=false
	main.local_model.resources[0]=0;main._on_snapshot(main.local_model.snapshot())
	check(main.purchase_buttons[0].get_node("PurchaseState").text.contains("자원"),"resource shortage differs from cooldown state")
	main.local_model.base_hp[0]=100;main._on_snapshot(main.local_model.snapshot());main._on_snapshot(main.local_model.snapshot())
	check(main.base_warning_label.visible and main.base_warning_fired,"base warning triggers at danger threshold and remains single-shot")
	for index in 120:main.battle_view.push_combat_events([{"type":"DAMAGE","target_id":index,"amount":3,"x":700.0}])
	check(main.battle_view.visual_events.size()==main.battle_view.MAX_VISUAL_EVENTS,"dense effects remain capped")
	check(main.battle_view.visual_events.slice(-4).map(func(event):return event.text_lane)==[0,1,2,3],"damage numbers use separate height lanes")
	await capture("battle-feedback")
	main.local_model._record_damage(0,"swordsman",75.0,true);main.local_model._record_damage(1,"archer",43.0,false);main.local_model.winner=0
	# Keep this presentation fixture from writing local player progress.
	main.result_recorded=true;main._on_snapshot(main.local_model.snapshot())
	check(main.result_overlay.find_child("BattleReportButton",true,false)!=null,"results offer authoritative battle report")
	main._show_battle_report();await process_frame;await process_frame
	check(main.report_overlay!=null and main.report_overlay.find_child("CloseBattleReportButton",true,false)!=null,"report offers two-sided comparison and close action")
	check(not main._handle_battle_hotkey(key(KEY_1)),"result/report overlay suppresses gameplay shortcuts")
	await capture("battle-report")
	main._dismiss_battle_report();main.network.disconnect_from_server()
	if failures==0:print("PASS: %d battle shortcut, purchase-state, danger, bounded-effects and report UI checks"%checks)
	quit(0 if failures==0 else 1)
