extends RefCounted
## BattleFlow: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
const GhostOpponent = preload("res://scripts/GhostOpponent.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const DraftMatch = preload("res://scripts/DraftMatch.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const CombatSounds = preload("res://scripts/CombatSounds.gd")

static func _start_local_ai_battle(main, stage: int = 1, reuse_deck: bool = false) -> void:
	main.ghost_context = {}
	main.daily_challenge = {}
	main.draft_context = {}
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	main.practice_used_tools = not main.campaign_mode and (main.practice.unlimited or not main.practice.enemy_units.is_empty() or main.practice.speed!=1.0)
	main.result_recorded = false
	main.current_ai_stage = clampi(stage, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
	main.own_side = 0
	main.local_model = BattleModel.new()
	main.local_model.configure_campaign_growth(main.own_side, SaveData.campaign_growth_level(main.save_data) if main.campaign_mode else main.current_ai_stage - 1)
	if not reuse_deck or main.battle_preset.is_empty():
		main.battle_preset = main._active_preset().duplicate(true)
	var preset = main.battle_preset
	main.local_model.configure_deck(0, preset.units, preset.structures)
	var ai_units: Array = ServerAI.stage_unit_deck(main.current_ai_stage)
	var ai_structures: Array = ServerAI.stage_structure_deck(main.current_ai_stage)
	if not main.campaign_mode and not main.practice.enemy_units.is_empty():
		ai_units = main.practice.enemy_units; ai_structures = main.practice.enemy_structures
	main.local_model.configure_deck(1, ai_units, ai_structures)
	main.local_model.resources[1] = min(BattleModel.MAX_RESOURCE, 35.0 + float(main.current_ai_stage) * 10.0)
	main.local_model.configure_base_health(1, 300.0 + float(main.current_ai_stage) * 20.0)
	main.local_ai = ServerAI.new(1, main.current_ai_stage)
	if not main.campaign_mode: main.practice.refill(main.local_model,main.own_side)
	main._build_battle_screen()
	if not main.ai_smoke_mode and not bool(main.save_data.get("tutorial_completed", false)):
		main._begin_tutorial()
	if main.ai_smoke_mode:
		main.local_model.spawn_unit(0, String(preset.units[0]))
	main.local_step_accumulator = 0.0
	main.local_recorder = null
	# Campaign and plain practice battles are recorded; practice tools (speed, free resources, custom enemy deck) are not.
	if (main.campaign_mode or not main.practice_used_tools) and not main.ai_smoke_mode:
		main.local_recorder = BattleReplay.Recorder.new(main.local_model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": main.current_ai_stage}, {"mode": "campaign" if main.campaign_mode else "practice", "stage": main.current_ai_stage})
	main._on_snapshot(main.local_model.snapshot())

## Shared start for scripted experiments (ghost battle, what-if branch): a local battle that is never
## recorded, never counted in the player's statistics and always runs at fixed 30 Hz.
static func _begin_scripted_battle(main, model: BattleModel, opponent, preset: Dictionary, context: Dictionary) -> void:
	main.ghost_context = context
	main.daily_challenge = {}
	main.draft_context = {}
	main.campaign_mode = false
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	main.practice_used_tools = true
	main.result_recorded = false
	main.current_ai_stage = 1
	main.own_side = 0
	main.local_model = model
	main.local_ai = opponent
	main.battle_preset = preset
	main._build_battle_screen()
	main.local_step_accumulator = 0.0
	main.local_recorder = null
	main._on_snapshot(model.snapshot())

## Play against the busiest player of a saved replay: their purchases and builds replay on schedule.
static func _start_ghost_battle(main, replay: Dictionary) -> void:
	var ghost_side := GhostOpponent.pick_side(replay)
	var mine := 1 - ghost_side
	var setup: Dictionary = replay.setup
	var model := BattleModel.new()
	model.configure_deck(0, setup.unit_decks[mine], setup.structure_decks[mine])
	model.configure_deck(1, setup.unit_decks[ghost_side], setup.structure_decks[ghost_side])
	for index in 2:
		var source := mine if index == 0 else ghost_side
		model.campaign_levels[index] = int(setup.campaign_levels[source])
		model.base_max_hp[index] = float(setup.base_max_hp[source])
		model.base_hp[index] = float(setup.base_hp[source])
		model.resources[index] = float(setup.resources[source])
	var preset := {"name": Localization.text("고스트 대전"), "units": setup.unit_decks[mine].duplicate(), "structures": setup.structure_decks[mine].duplicate()}
	_begin_scripted_battle(main, model, GhostOpponent.new(replay, ghost_side, ghost_side == 0), preset, {"mode": "ghost", "replay": replay, "tick": 0})

## "What if": continue a replay from `tick` with the human on blue; red keeps its recorded script (or its AI).
static func _start_branch_battle(main, replay: Dictionary, tick: int) -> void:
	var player := BattleReplay.Player.new(replay)
	while player.ticks < tick and player.step():
		pass
	if player.is_finished():
		return
	var opponent = player.ai if player.ai != null else GhostOpponent.new(replay, 1, false, player.ticks)
	var setup: Dictionary = replay.setup
	var preset := {"name": Localization.text("되감기 실험"), "units": setup.unit_decks[0].duplicate(), "structures": setup.structure_decks[0].duplicate()}
	player.model.drain_combat_events()
	_begin_scripted_battle(main, player.model, opponent, preset, {"mode": "branch", "replay": replay, "tick": player.ticks})

## Today's daily challenge: fixed decks and rule twist, recorded as a replay (mode "daily") and scored.
static func _start_daily_challenge(main, period: String = "daily") -> void:
	var challenge := DailyChallenge.current(period)
	var setup := DailyChallenge.build(challenge)
	main.ghost_context = {}
	main.draft_context = {}
	main.daily_challenge = challenge
	main.campaign_mode = false
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	main.practice_used_tools = false
	main.result_recorded = false
	main.current_ai_stage = int(setup.stage)
	main.own_side = 0
	main.local_model = setup.model
	main.local_ai = setup.ai
	main.battle_preset = {"name": Localization.text("주간 도전" if DailyChallenge.is_weekly(challenge) else "일일 도전"), "units": challenge.units.duplicate(), "structures": challenge.structures.duplicate()}
	main._build_battle_screen()
	main.local_step_accumulator = 0.0
	main.local_recorder = BattleReplay.Recorder.new(main.local_model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": int(setup.stage)}, {"mode": "daily", "stage": int(setup.stage), "date": String(challenge.key), "modifier": String(challenge.modifier), "period": String(challenge.get("period", "daily"))})
	main._on_snapshot(main.local_model.snapshot())

## A drafted battle: the player's drafted units and active structures against the AI's picks. Recorded as a
## replay (mode "draft"), never counted in the statistics.
static func _start_draft_battle(main, my_units: Array, enemy_units: Array, stage: int) -> void:
	var structures: Array = main._active_preset().structures.duplicate()
	var setup := DraftMatch.build(my_units, structures, enemy_units, ServerAI.stage_structure_deck(stage), stage)
	main.ghost_context = {}
	main.daily_challenge = {}
	main.draft_context = {"stage": int(setup.stage), "units": my_units.duplicate(), "enemy_units": enemy_units.duplicate()}
	main.campaign_mode = false
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	main.practice_used_tools = false
	main.result_recorded = false
	main.current_ai_stage = int(setup.stage)
	main.own_side = 0
	main.local_model = setup.model
	main.local_ai = setup.ai
	main.battle_preset = {"name": Localization.text("드래프트"), "units": my_units.duplicate(), "structures": structures}
	main._build_battle_screen()
	main.local_step_accumulator = 0.0
	main.local_recorder = BattleReplay.Recorder.new(main.local_model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": int(setup.stage)}, {"mode": "draft", "stage": int(setup.stage)})
	main._on_snapshot(main.local_model.snapshot())

static func _restart_context(main) -> void:
	var context: Dictionary = main.ghost_context
	if context.is_empty():
		return
	if String(context.mode) == "branch":
		_start_branch_battle(main, context.replay, int(context.tick))
	else:
		_start_ghost_battle(main, context.replay)

static func _on_match_found(main, side: int) -> void:
	if not main.resuming_battle_ui: main.result_recorded = false
	main.resuming_battle_ui = false
	main.multiplayer_screen = ""
	main.local_ai_mode = false
	main.battle_preset = main._active_preset().duplicate(true)
	main.own_side = side
	main._build_battle_screen()
	if main.smoke_mode:
		print("CLIENT_MATCH_FOUND side=%d" % side)
		main.network.send_spawn("swordsman")

static func _on_battlefield_clicked(main, world_x: float) -> void:
	if main.network.client_is_spectator or (not main.local_ai_mode and main.network_paused) or main.result_shown or (main.local_ai_mode and not main.campaign_mode and main.practice.paused): return
	if not is_instance_valid(main.battle_view) or main.battle_view.selected_structure.is_empty() or main.placement_pending:
		return
	var kind = main.battle_view.selected_structure
	var error = main.local_model.structure_placement_error(main.own_side, kind, world_x) if main.local_ai_mode else main.battle_view.placement_error(kind, world_x)
	if not error.is_empty():
		main._show_placement_status(error)
		return
	if main.local_ai_mode:
		if not main.campaign_mode: main.practice.refill(main.local_model,main.own_side)
		if main.local_model.place_structure(main.own_side, kind, world_x):
			if main.local_recorder != null: main.local_recorder.on_place(main.own_side, kind, world_x)
			main._show_placement_status(Localization.text("건설 완료"))
			main.battle_view.selected_structure = ""
			main._refresh_structure_selection()
			main._tutorial_advance(1)
	else:
		main.placement_pending = true
		main.network.send_structure(kind, world_x)
		main._show_placement_status(Localization.text("서버 확인 중..."), 0.0)

static func _on_structure_placement_result(main, success: bool, error: String) -> void:
	main.placement_pending = false
	if not main.battle_active or main.local_ai_mode or not is_instance_valid(main.battle_view):
		return
	if success:
		main.battle_view.selected_structure = ""
		main._refresh_structure_selection()
	main._show_placement_status(Localization.text("건설 완료") if success else (error if not error.is_empty() else Localization.text("구조물을 설치하지 못했습니다.")))

static func _on_snapshot(main, data: Dictionary) -> void:
	if not main.battle_active or not is_instance_valid(main.battle_view):
		return
	main.current_snapshot = data
	main.battle_view.set_snapshot(data)
	if float(data.get("elapsed", 0.0)) >= main.curve_next_elapsed and int(data.get("winner", -1)) == -1:
		main.curve_next_elapsed = float(data.get("elapsed", 0.0)) + 0.5
		main.battle_curve.append(ReplayAnalysis.momentum_from_snapshot(data))
	if main.ai_smoke_mode:
		var has_human: bool = data.get("units", []).any(func(unit): return int(unit.side) == 0)
		var has_ai: bool = data.get("units", []).any(func(unit): return int(unit.side) == 1)
		if has_human and has_ai:
			print("OFFLINE_AI_READY human_units=1 ai_units=1")
			main.get_tree().quit(0)
	if main.smoke_mode and data.get("units", []).size() > 0:
		print("CLIENT_SNAPSHOT units=%d" % data.get("units", []).size())
		main.get_tree().quit(0)
	var resources: Array = data.get("resources", [0.0, 0.0])
	var bases: Array = data.get("base_hp", [0.0, 0.0])
	var own_structures: int = data.get("structures", []).filter(func(structure): return int(structure.side) == main.own_side).size()
	if is_instance_valid(main.structure_count_label):
		main.structure_count_label.text = Localization.text("구조물 %d / 3") % own_structures
	var resource_cap = main.local_model.resource_capacity(main.own_side) if main.local_ai_mode and is_instance_valid(main.local_model) else BattleModel.MAX_RESOURCE
	main.resource_label.text = "%d / %d" % [int(resources[main.own_side]), int(resource_cap)]
	var resource_bar = main.resource_label.get_meta("bar", null)
	if is_instance_valid(resource_bar):
		resource_bar.max_value = resource_cap
		resource_bar.value = float(resources[main.own_side])
	main._refresh_purchase_buttons(float(resources[main.own_side]))
	if main.local_ai_mode and main.tutorial_step == 2 and float(resources[main.own_side]) > main.tutorial_low_resource + 0.5:
		main._tutorial_advance(2)
	var maxima: Array = data.get("base_max_hp", [BattleModel.BASE_MAX_HP, BattleModel.BASE_MAX_HP])
	main.blue_hp_bar.max_value = float(maxima[0])
	main.red_hp_bar.max_value = float(maxima[1])
	main.blue_hp_bar.value = float(bases[0])
	main.red_hp_bar.value = float(bases[1])
	main.blue_hp_label.text = "%d / %d" % [int(bases[0]), int(maxima[0])]
	main.red_hp_label.text = "%d / %d" % [int(bases[1]), int(maxima[1])]
	var elapsed_seconds := int(data.get("elapsed", 0.0))
	main.timer_label.text = "%02d:%02d" % [elapsed_seconds / 60, elapsed_seconds % 60]
	main._update_base_warning(data)
	var winner: int = int(data.get("winner", -1))
	if winner != -1 and not main.result_shown:
		if not _begin_finale(main, data, winner):
			main._show_result(winner)
	elif winner == -1 and main.result_shown:
		main._dismiss_result_overlay()
		main.result_recorded = false
		main.updater.set_safe_to_update(false)

const FINALE_TIME_SCALE := 0.35

## When a base has actually been destroyed, let it collapse in slow motion before the result appears.
## Returns true while the finale is still running (the caller must not show the result yet).
static func _begin_finale(main, data: Dictionary, winner: int) -> bool:
	if main.finale_active:
		return true
	if main.finale_seconds <= 0.0 or winner < 0 or winner > 1 or not is_instance_valid(main.battle_view):
		return false
	if float(data.get("base_hp", [1.0, 1.0])[1 - winner]) > 0.0:
		return false # surrender or disconnect: nothing was destroyed
	main.finale_active = true
	main.battle_view.start_finale(1 - winner)
	Engine.time_scale = FINALE_TIME_SCALE
	main.get_tree().create_timer(main.finale_seconds, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0
		main.finale_active = false
		if main.battle_active and not main.result_shown and is_instance_valid(main.battle_view):
			main._show_result(int(main.current_snapshot.get("winner", winner))))
	return true

static func _on_rage_started(main, _unit_id: int) -> void:
	if DisplayServer.get_name() == "headless" or bool(main.save_data.settings.muted): return
	var now := Time.get_ticks_msec()
	if now - main.last_rage_sfx_msec < 300: return
	main.last_rage_sfx_msec = now
	if not is_instance_valid(main.rage_sfx_player):
		main.rage_sfx_player = AudioStreamPlayer.new()
		main.rage_sfx_player.name = "RageSFX"
		main.rage_sfx_player.bus = &"SFX"
		main.rage_sfx_player.volume_db = -12.0
		main.rage_sfx_player.stream = preload("res://scripts/RageSound.gd").stream()
		main.add_child(main.rage_sfx_player)
	main.rage_sfx_player.play()

static func _on_combat_events(main, events: Array) -> void:
	if main.battle_active: main._play_combat_events(events)
	if is_instance_valid(main.battle_view) and not events.is_empty():
		main.battle_view.push_combat_events(events)
		if bool(main.save_data.settings.screen_shake) and events.any(func(event): return String(event.get("type", "")) == "BASE_HIT"):
			var strength := 3.0 * float(main.save_data.settings.effect_intensity)
			var tween = main.create_tween()
			tween.tween_property(main.battle_view, "position", Vector2(strength, 88.0), 0.04)
			tween.tween_property(main.battle_view, "position", Vector2.ZERO + Vector2(0.0, 88.0), 0.08)

static func _exit_battle_to_menu(main) -> void:
	if not main.network.client_session.is_empty():
		main.network.request_session_leave.rpc_id(1)
		return
	main.battle_active = false
	main._dismiss_result_overlay()
	main._dismiss_stats_panel()
	if not main.local_ai_mode:
		main.network.disconnect_from_server()
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	main.current_snapshot.clear()
	main._build_connect_screen()

static func _exit_ai_battle(main) -> void:
	if not main.local_ai_mode:
		return
	main.battle_active = false
	main.local_model = null
	main.local_ai = null
	main.current_snapshot.clear()
	main.updater.set_safe_to_update(true)
	main._build_ai_stage_screen(main.campaign_mode)

static func _handle_battle_hotkey(main, event: InputEventKey) -> bool:
	if not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or not main.battle_active or main.result_shown or (not main.local_ai_mode and main.network_paused) or main.network.client_is_spectator or main._battle_text_has_focus() or is_instance_valid(main.stats_overlay) or is_instance_valid(main.report_overlay) or is_instance_valid(main.action_overlay): return false
	var key := event.physical_keycode if event.physical_keycode!=0 else event.keycode
	var codes: Array = main.save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)
	var index := codes.find(key)
	if index<0 or index>=main.purchase_buttons.size(): return false
	var button: Button = main.purchase_buttons[index]
	if not is_instance_valid(button) or button.disabled: return true
	if button.toggle_mode: button.set_pressed_no_signal(not button.button_pressed)
	button.pressed.emit()
	return true

static func _purchase_unit(main, kind: String) -> void:
	if main.network.client_is_spectator or (not main.local_ai_mode and main.network_paused) or not main.battle_active or main.result_shown or (main.local_ai_mode and not main.campaign_mode and main.practice.paused) or float(main.client_purchase_gates.get(kind,0))>Time.get_ticks_msec(): return
	var accepted := false
	if main.local_ai_mode:
		if not main.campaign_mode: main.practice.refill(main.local_model,main.own_side)
		accepted = main.local_model.spawn_unit(main.own_side,kind)
		if accepted and main.local_recorder != null: main.local_recorder.on_spawn(main.own_side, kind)
		if accepted: main._tutorial_advance(0)
	else:
		main.network.send_spawn(kind); accepted = true
	if accepted:
		main.client_purchase_gates[kind] = Time.get_ticks_msec()+350
		main._refresh_purchase_buttons(main.latest_resources)

static func _play_combat_events(main, events: Array) -> void:
	if DisplayServer.get_name()=="headless" or bool(main.save_data.settings.muted): return
	var played := 0
	for event in events:
		var kind := CombatSounds.event_sound(event)
		if not kind.is_empty() and main._play_battle_sound(kind):
			played += 1
			if played>=3: break

static func _play_battle_sound(main, kind: String) -> bool:
	if DisplayServer.get_name()=="headless" or bool(main.save_data.settings.muted): return false
	var now := Time.get_ticks_msec()
	if now-int(main.sound_gate.get(kind,-1000))<90: return false
	var player: AudioStreamPlayer = null
	for candidate in main.combat_sfx_players:
		if is_instance_valid(candidate) and not candidate.playing: player = candidate; break
	if player==null:
		if main.combat_sfx_players.size()>=4: return false
		player = AudioStreamPlayer.new(); player.bus = &"SFX"; player.volume_db = -16.0; main.add_child(player); main.combat_sfx_players.append(player)
	player.stream = CombatSounds.stream(kind); player.play(); main.sound_gate[kind] = now
	return true

static func _update_base_warning(main, data: Dictionary) -> void:
	if not is_instance_valid(main.base_warning_label): return
	var maximum: float = data.get("base_max_hp",[500.0,500.0])[main.own_side]
	var hp: float = data.get("base_hp",[500.0,500.0])[main.own_side]
	var danger = not main.network.client_is_spectator and int(data.get("winner",-1))==-1 and hp>0.0 and hp<=maximum*0.25
	main.base_warning_label.visible = danger
	var bar = main.blue_hp_bar if main.own_side==0 else main.red_hp_bar
	if is_instance_valid(bar): bar.modulate = Color("#ff8a96") if danger else Color.WHITE
	if danger and not main.base_warning_fired:
		main.base_warning_fired = true; main._play_battle_sound("warning")

static func _toggle_practice_pause(main) -> void:
	if not main.local_ai_mode or main.campaign_mode or main.result_shown: return
	main.practice.paused = not main.practice.paused
	if is_instance_valid(main.practice_pause_button): main.practice_pause_button.text="계속" if main.practice.paused else "일시정지"
	main._refresh_purchase_buttons(main.latest_resources)

static func _restart_practice(main) -> void:
	if not main.local_ai_mode or main.campaign_mode: return
	main._start_local_ai_battle(main.current_ai_stage,true)
