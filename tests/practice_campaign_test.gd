extends SceneTree
const Tools = preload("res://scripts/PracticeTools.gd")
const Brief = preload("res://scripts/CampaignBrief.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value: failures+=1; printerr("FAIL: ",message)
func _initialize()->void:
	Engine.max_fps=20;call_deferred("run")
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			var directory:=arg.trim_prefix("--capture-dir=");DirAccess.make_dir_recursive_absolute(directory)
			await process_frame;await process_frame;await RenderingServer.frame_post_draw
			get_root().get_texture().get_image().save_png(directory.path_join(name+".png"))
func run()->void:
	create_timer(40).timeout.connect(func():printerr("Practice UI watchdog");quit(1))
	var tools=Tools.new();var model=BattleModel.new();var ai=ServerAI.new()
	tools.paused=true;tools.advance(model,ai,0.1,0)
	check(model.elapsed==0,"pause freezes simulation and AI")
	tools.paused=false;tools.speed=2.0;tools.advance(model,ai,0.1,0)
	check(is_equal_approx(model.elapsed,0.2),"speed changes simulation time without global Engine time scale")
	tools.unlimited=true;model.resources[0]=0;tools.advance(model,ai,0.1,0)
	check(model.resources[0]==model.resource_capacity(0),"unlimited refills only practice player")
	check(not tools.set_enemy_deck(["swordsman","swordsman","archer"],["wall","swamp","turret"]),"duplicate enemy deck rejected")
	check(tools.set_enemy_deck(["swordsman","berserker","necromancer"],["wall","swamp","turret"]),"custom enemy deck accepted")
	for stage in 8:
		var target:Dictionary=SaveData.CAMPAIGN_TARGETS[stage]
		check(not Brief.goal(stage+1).is_empty() and Brief.conditions(stage+1).contains(str(int(target.time))) and Brief.enemy_deck(stage+1).contains(BattleModel.UNIT_NAMES[ServerAI.stage_unit_deck(stage+1)[0]]),"campaign preview uses real deck/target: %d"%(stage+1))
	var bootstrap:=Control.new();bootstrap.name="Bootstrap";bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);get_root().add_child(bootstrap)
	var main=load("res://scenes/Main.tscn").instantiate();bootstrap.add_child(main);main.updater.enabled=false;main.set_process(false);main.save_data=SaveData.default_data();main.save_data.tutorial_completed=true
	main._build_ai_stage_screen(true);main._show_stage_brief(1)
	check(main.action_overlay.find_child("StartCampaignStage",true,false)!=null,"campaign brief has explicit start")
	await capture("campaign-brief")
	main.action_overlay.find_child("StartCampaignStage",true,false).pressed.emit()
	check(main.campaign_mode and main.battle_active and main.root_background.find_child("PracticeControls",true,false)==null,"practice controls never appear in campaign")
	main._exit_ai_battle();main._build_ai_stage_screen(false);main.practice.unlimited=true;main.practice.set_enemy_deck(["swordsman","berserker","necromancer"],["wall","swamp","turret"]);main._start_local_ai_battle(1)
	check(main.local_model.unit_decks[1]==main.practice.enemy_units and main.local_model.resources[0]==main.local_model.resource_capacity(0),"practice settings applied to real battle")
	check(main.root_background.find_child("PracticeControls",true,false)!=null,"actual scene offers pause/speed/reset")
	main._toggle_practice_pause();var elapsed:float=main.local_model.elapsed;main._process(0.2)
	check(main.local_model.elapsed==elapsed and main.purchase_buttons.all(func(button):return button.disabled),"UI pause blocks simulation and purchases")
	main._toggle_practice_pause();main.practice.speed=4;main.practice_used_tools=true;main._process(0.1)
	check(is_equal_approx(main.local_model.elapsed,elapsed+0.4),"four-times practice actually advances four-times")
	main._restart_practice();check(main.local_model.elapsed==0 and main.local_model.units.is_empty() and not main.practice.paused,"reset clears battle and preserves chosen deck")
	await capture("practice-tools")
	main._show_practice_deck();await capture("practice-enemy-deck");main._dismiss_action_overlay()
	# Do not write a test player profile on disk.
	main.result_recorded=true;main._confirm_surrender();check(main.action_overlay.find_child("ConfirmSurrender",true,false)!=null,"surrender requires confirmation")
	main.action_overlay.find_child("ConfirmSurrender",true,false).pressed.emit();check(main.local_model.winner==1 and main.result_shown,"offline surrender follows actual defeat result")
	check(main.save_data.campaign_records.all(func(record):return not record.cleared),"practice never changes campaign progression")
	main.network.disconnect_from_server()
	if failures==0:print("PASS: %d practice, campaign brief, experiment isolation and surrender UI checks"%checks)
	quit(0 if failures==0 else 1)
