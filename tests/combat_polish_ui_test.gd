extends SceneTree

var checks := 0
var failures := 0
var capture_dir := ""

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	Engine.max_fps=20
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="): capture_dir=arg.trim_prefix("--capture-dir=")
	call_deferred("run")

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("Polish view watchdog expired"); quit(1))
	var view := BattleView.new()
	view.size=Vector2(1280,492)
	get_root().add_child(view)
	view.set_process(false)
	var model := BattleModel.new()
	model.configure_deck(0,["berserker","warlock","necromancer"],["wall","swamp","generator"])
	model.resources=[180.0,180.0]
	model.spawn_unit(0,"berserker")
	model.spawn_unit(0,"warlock")
	model.resources[0]=180.0
	model.spawn_unit(0,"necromancer")
	for index in model.units.size():
		model.units[index].x=400.0+index*140.0
		model.units[index].speed=0.0
	var rage_count := [0]
	view.rage_started.connect(func(_id): rage_count[0]+=1)
	view.set_snapshot(model.snapshot())
	model.units[0].hp=model.units[0].max_hp*0.5
	view.set_snapshot(model.snapshot())
	check(rage_count[0]==1 and view.rage_flashes.has(model.units[0].id),"threshold crossing flashes and emits one sound cue")
	view.set_snapshot(model.snapshot())
	check(rage_count[0]==1,"repeated snapshots do not repeat the rage cue")
	check(BattleView.action_opacity(0.0)==0.0 and BattleView.action_opacity(0.1)==1.0 and BattleView.action_opacity(0.7)==0.0,"walk/action crossfade has smooth entry and exit")
	var id: int=model.units[0].id
	view.moving_units[id]=true
	view._process(0.2)
	var phase: float=view.walk_times[id]
	view.moving_units[id]=false
	view._process(0.2)
	check(view.walk_times[id]==phase,"stopping does not reset the walk pose")
	view.interpolate_positions=true
	view.set_snapshot(model.snapshot())
	model.elapsed=0.1; model.units[0].x=410.0
	view.set_snapshot(model.snapshot())
	view._process(0.05)
	check(is_equal_approx(view.motion.position(id,410.0),405.0),"battle view actually uses the display-only network interpolation")
	check(view.snapshot.units[0].x==410.0,"rendered smoothing leaves snapshot coordinates untouched")
	view.selected_structure="turret"
	var preview=view.build_preview(500.0)
	check(preview.radius==240.0,"turret placement previews its true range")
	view.selected_structure="swamp"
	preview=view.build_preview(500.0)
	check(preview.radius==95.0,"swamp placement previews its true effect radius")
	view.selected_structure="generator"
	preview=view.build_preview(500.0)
	check(preview.upper==BattleModel.BLUE_REAR_MAX and not preview.error.is_empty(),"generator guide restricts the preview to the actual rear zone")
	view.own_side=1
	preview=view.build_preview(1100.0)
	check(preview.lower==BattleModel.RED_REAR_MIN and preview.upper==BattleModel.RED_BUILD_MAX,"red-side rear guide is authoritative and mirror-safe")
	view.selected_structure="swamp"
	var clicks: Array=[]
	view.battlefield_clicked.connect(func(x): clicks.append(x))
	var touch := InputEventScreenTouch.new()
	touch.position=Vector2(view.world_to_screen_x(1100.0),220.0); touch.pressed=true
	view._gui_input(touch)
	check(clicks.is_empty(),"touch press only positions the placement preview")
	var drag := InputEventScreenDrag.new(); drag.position=Vector2(view.world_to_screen_x(1150.0),220.0)
	view._gui_input(drag)
	view._process(0.01)
	check(view.mouse_position==drag.position,"touch drag preview is not overwritten by an unrelated desktop cursor")
	touch.position=drag.position; touch.pressed=false
	view._gui_input(touch)
	check(clicks.size()==1 and is_equal_approx(clicks[0],1150.0),"release emits exactly one correctly mirrored world coordinate")
	view.own_side=0
	model.elapsed=0.0
	model.resources[0]=180.0
	model.place_structure(0,"swamp",550.0)
	model._install_curse(model.units[1],800.0)
	model.units[2].summon_remaining=3.0
	model.units[1].support_stacks=3
	view.set_snapshot(model.snapshot())
	check(is_equal_approx(view.effect_remaining(model.curses[0]),5.0),"curse lifetime begins at the real expiry")
	view._process(0.2)
	check(is_equal_approx(view.effect_remaining(model.curses[0]),4.8),"remaining-time indicator counts down between packets")
	view.selected_structure="swamp"
	view.mouse_position=Vector2(view.world_to_screen_x(350.0),220.0)
	view.touch_preview_active=true
	view.queue_redraw()
	if not capture_dir.is_empty() and DisplayServer.get_name()!="headless":
		DirAccess.make_dir_recursive_absolute(capture_dir)
		await process_frame
		await RenderingServer.frame_post_draw
		get_root().get_texture().get_image().save_png(capture_dir.path_join("combat-feedback-preview.png"))
	view.queue_free()
	await process_frame
	if failures==0: print("PASS: %d combat feedback, transition and mirrored-touch checks" % checks)
	quit(0 if failures==0 else 1)
