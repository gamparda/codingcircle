extends Control

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MenuScreens = preload("res://scripts/screens/MenuScreens.gd")
const DeckScreen = preload("res://scripts/screens/DeckScreen.gd")
const SettingsScreen = preload("res://scripts/screens/SettingsScreen.gd")
const BattleHud = preload("res://scripts/screens/BattleHud.gd")
const ResultScreens = preload("res://scripts/screens/ResultScreens.gd")
const UpdateOverlay = preload("res://scripts/screens/UpdateOverlay.gd")
const Tutorial = preload("res://scripts/screens/Tutorial.gd")
const PracticeUI = preload("res://scripts/screens/PracticeUI.gd")
const PatchNotes = preload("res://scripts/PatchNotes.gd")

const OFFICIAL_SERVER_ADDRESS := "ruellyya.kr"
const OFFICIAL_SERVER_FALLBACK_ADDRESS := "211.176.222.145"
const OFFICIAL_SERVER_LAN_ADDRESS := "192.168.0.4"
const OFFICIAL_SERVER_PORT := 7777
const ANDROID_APK_URL := "https://gamparda.github.io/codingcircle/CatWar.apk"
const DEFAULT_SMOKE_ROOM_CODE := "CAT234"
const BATTLE_BGM := preload("res://assets/audio/battle_bgm.wav")

@onready var network: NetworkController = $NetworkController
@onready var updater: UpdateManager = $UpdateManager

var own_side := 0
var battle_view: BattleView
var resource_label: Label
var timer_label: Label
var base_label: Label
var blue_hp_bar: ProgressBar
var red_hp_bar: ProgressBar
var blue_hp_label: Label
var red_hp_label: Label
var status_label: Label
var current_snapshot: Dictionary = {}
var battle_active := false
var result_shown := false
var result_overlay: Control
var stats_overlay: Control
var root_background: ColorRect
var smoke_mode := false
var smoke_elapsed := 0.0
var connect_button_ref: Button
var quick_button_ref: Button
var join_button_ref: Button
var local_ai_mode := false
var ai_smoke_mode := false
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var practice = PracticeTools.new()
var practice_used_tools := false
var practice_pause_button: Button
var practice_speed_button: Button
var action_overlay: Control
var latency_label: Label
var recovery_label: Label
var network_paused := false
var resuming_battle_ui := false
const BattleBindings = preload("res://scripts/BattleBindings.gd")
var binding_draft: Array = []
var binding_buttons: Array = []
var binding_capture_index := -1
var binding_hint: Label
var binding_capture_overlay: Control
var local_model: BattleModel
var local_ai: ServerAI
var local_recorder = null # BattleReplay.Recorder for campaign battles
var local_step_accumulator := 0.0
var last_replay_path := ""
var current_ai_stage := 1
var bgm_player: AudioStreamPlayer
const CombatSounds = preload("res://scripts/CombatSounds.gd")
const Report = preload("res://scripts/BattleReport.gd")
var combat_sfx_players: Array = []
var sound_gate: Dictionary = {}
var base_warning_fired := false
var base_warning_label: Label
var cancel_build_button: Button
var report_overlay: Control
var client_purchase_gates: Dictionary = {}
var latest_resources := 0.0
var rage_sfx_player: AudioStreamPlayer
var last_rage_sfx_msec := -1000
var running_as_server := false
var update_overlay: Control
var update_message_label: Label
var update_progress_bar: ProgressBar
var update_note_label: Label
var server_state_dir := ""
var server_status_accumulator := 0.0
var server_draining := false
var save_data: Dictionary = {}
var campaign_mode := false
var result_recorded := false
var placement_status_label: Label
var structure_count_label: Label
var placement_pending := false
var placement_message_serial := 0
var room_code_input: LineEdit
var multiplayer_screen := ""
var lobby_rows: VBoxContainer
var lobby_page_label: Label
var lobby_page := 0
var lobby_total := 0
var lobby_data := {"rooms":[],"page":0,"total":0}
var lobby_previous_button: Button
var lobby_next_button: Button
var session_title: Label
var session_roster: VBoxContainer
var session_spectators: Label
var session_deck_selector: OptionButton
var session_deck_names: Label
var session_ready_button: Button
var session_start_button: Button
var session_chat_log: RichTextLabel
var session_chat_input: LineEdit
var battle_chat_panel: PanelContainer
var last_chat_sent_msec := -1000
var room_create_dialog: ConfirmationDialog
var battle_preset: Dictionary = {}
var tutorial_step := -1
var tutorial_low_resource := 0.0
var tutorial_banner: Control
var tutorial_hint: Label
var structure_buttons: Array[Button] = []
var purchase_buttons: Array[Button] = []
var settings_touch_scroll: ScrollContainer
var settings_touch_index := -1
var settings_touch_dragged := false
var settings_touch_start := Vector2.ZERO

func _ready() -> void:
	theme = UIKit.build_theme()
	network.connection_status.connect(_on_connection_status)
	network.match_found.connect(_on_match_found)
	network.snapshot_received.connect(_on_snapshot)
	network.combat_events_received.connect(_on_combat_events)
	network.opponent_disconnected.connect(_on_opponent_left)
	network.structure_placement_result.connect(_on_structure_placement_result)
	network.room_created.connect(_on_room_created)
	network.room_join_failed.connect(_on_room_join_failed)
	network.room_list_received.connect(_on_room_list)
	network.session_changed.connect(_on_session_changed)
	network.session_error.connect(_on_session_error)
	network.quick_match_status.connect(_on_quick_match_status)
	network.session_chat.connect(_on_session_chat)
	network.spectate_started.connect(_on_spectate_started)
	network.session_closed.connect(_on_session_closed)
	network.latency_updated.connect(_on_latency_updated)
	network.reconnect_status.connect(_on_reconnect_status)
	network.recovery_changed.connect(_on_recovery_changed)
	network.client_nickname = String(save_data.get("nickname","플레이어"))
	updater.update_started.connect(_on_update_started)
	updater.update_status.connect(_on_update_status)
	updater.update_failed.connect(_on_update_failed)
	var args := OS.get_cmdline_user_args()
	smoke_mode = args.has("--smoke-client")
	ai_smoke_mode = args.has("--ai-smoke")
	var has_saved_profile := FileAccess.file_exists(SaveData.SAVE_PATH)
	save_data = SaveData.default_data() if args.has("--server") else SaveData.load_data()
	if not args.has("--server") and not has_saved_profile:
		save_data.settings.language = Localization.normalize_locale(TranslationServer.get_locale())
	Localization.install("ko" if args.has("--server") else String(save_data.settings.language))
	if args.has("--server"):
		running_as_server = true
		# Headless mode has no display refresh rate to pace the main loop.
		# Cap it so an idle dedicated server does not spin a CPU core.
		Engine.max_fps = 60
		visible = false
		var port := _arg_int(args, "--port=", NetworkController.DEFAULT_PORT)
		if not network.start_dedicated_server(port):
			get_tree().quit(1)
		server_state_dir = OS.get_environment("CATWAR_STATE_DIR").strip_edges()
		if not server_state_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(server_state_dir)
		_update_server_lifecycle(1.0)
		updater.set_safe_to_update(true)
		updater.check_for_update()
		return
	_apply_settings()
	_setup_bgm()
	_build_connect_screen()
	if apk_update_required(OS.get_name(), String(ProjectSettings.get_setting("application/config/version", "0.0.0")), build_binary_version()):
		_show_android_apk_notice()
	if args.has("--offline-ai") or ai_smoke_mode:
		_start_local_ai_battle(_arg_int(args, "--ai-stage=", 1))
		return
	var auto_address := _arg_string(args, "--connect=", "")
	var auto_fallback := _arg_string(args, "--fallback=", "")
	if smoke_connect_allowed(smoke_mode, auto_address) and (auto_fallback.is_empty() or smoke_connect_allowed(smoke_mode, auto_fallback)):
		network.set_room_request("enter", _arg_string(args, "--room-code=", DEFAULT_SMOKE_ROOM_CODE))
		network.connect_to_server(auto_address, _arg_int(args, "--port=", NetworkController.DEFAULT_PORT), auto_fallback)

static func official_connection_candidates(local_addresses) -> Array:
	# ENet uses the game server address directly, not the web proxy endpoint.
	var candidates: Array = [OFFICIAL_SERVER_FALLBACK_ADDRESS]
	for local_address in local_addresses:
		if String(local_address).begins_with("192.168.0."):
			candidates.append(OFFICIAL_SERVER_LAN_ADDRESS)
			break
	for address in [OFFICIAL_SERVER_ADDRESS, OFFICIAL_SERVER_FALLBACK_ADDRESS]:
		if not candidates.has(address):
			candidates.append(address)
	return candidates

static func smoke_connect_allowed(is_smoke: bool, address: String) -> bool:
	return is_smoke and (address.begins_with("127.") or address == "localhost" or address == "::1" or address.ends_with(".invalid") or address == OFFICIAL_SERVER_LAN_ADDRESS)

static func apk_update_required(os_name: String, binary_version: String, content_version: String) -> bool:
	return os_name == "Android" and UpdateManager.is_newer_version(content_version, binary_version)

func _arg_int(args: PackedStringArray, prefix: String, fallback: int) -> int:
	for arg in args:
		if arg.begins_with(prefix):
			return int(arg.trim_prefix(prefix))
	return fallback

func _arg_string(args: PackedStringArray, prefix: String, fallback: String) -> String:
	for arg in args:
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback

func _process(delta: float) -> void:
	if not local_ai_mode and battle_active and not current_snapshot.is_empty():
		var active_gate := false
		for deadline in client_purchase_gates.values():
			if float(deadline)>Time.get_ticks_msec(): active_gate = true; break
		if active_gate: _refresh_purchase_buttons(latest_resources)
	if OS.has_feature("android"):
		var keyboard := DisplayServer.virtual_keyboard_get_height()
		var logical := float(keyboard)*720.0/maxf(1.0,float(DisplayServer.window_get_size().y))
		var focused := is_instance_valid(session_chat_input) and session_chat_input.has_focus()
		if is_instance_valid(battle_chat_panel): battle_chat_panel.position.y = clampf(720.0-logical-battle_chat_panel.size.y-12.0,88.0,204.0) if focused and keyboard>0 else 204.0
		elif multiplayer_screen=="session" and is_instance_valid(root_background):
			root_background.position.y = -minf(logical,300.0) if focused and keyboard>0 else 0.0
	if running_as_server:
		_update_server_lifecycle(delta)
		updater.set_safe_to_update(_server_can_update())
	if local_ai_mode and battle_active and is_instance_valid(local_model) and not is_instance_valid(action_overlay):
		if campaign_mode:
			# Fixed 30 Hz steps keep campaign battles deterministic, so their replays reproduce exactly.
			local_step_accumulator += minf(delta, 0.25)
			var step := 1.0 / float(BattleReplay.DEFAULT_HZ)
			while local_step_accumulator >= step and local_model.winner == -1:
				local_ai.update(local_model, step); local_model.tick(step)
				if local_recorder != null: local_recorder.on_tick()
				local_step_accumulator -= step
		else: practice.advance(local_model,local_ai,delta,own_side)
		_on_combat_events(local_model.drain_combat_events())
		_on_snapshot(local_model.snapshot())
	if smoke_mode or ai_smoke_mode:
		smoke_elapsed += delta
		if smoke_elapsed > 45.0:
			printerr("SMOKE_CLIENT_TIMEOUT")
			get_tree().quit(2)

func _input(event: InputEvent) -> void:
	if binding_capture_index>=0 and event is InputEventKey:
		if not event.pressed or event.echo: get_viewport().set_input_as_handled(); return
		get_viewport().set_input_as_handled()
		if event.keycode==KEY_ESCAPE: _cancel_binding_capture(); return
		if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
			binding_hint.text="조합 키 대신 단일 키를 눌러주세요."; return
		var code: int = event.physical_keycode if event.physical_keycode!=0 else event.keycode
		var error: String = BattleBindings.assign(binding_draft,binding_capture_index,code)
		if not error.is_empty(): binding_hint.text=error; return
		_cancel_binding_capture(); _refresh_binding_buttons(); return
	if is_instance_valid(settings_touch_scroll):
		if event is InputEventScreenTouch:
			if event.pressed and settings_touch_index < 0 and settings_touch_scroll.get_global_rect().has_point(event.position):
				settings_touch_index = event.index
				settings_touch_dragged = false
				settings_touch_start = event.position
			elif not event.pressed and event.index == settings_touch_index:
				settings_touch_index = -1
				if settings_touch_dragged:
					get_viewport().set_input_as_handled()
				settings_touch_dragged = false
		elif event is InputEventScreenDrag and event.index == settings_touch_index:
			if not settings_touch_dragged and absf(event.position.y - settings_touch_start.y) < 12.0:
				return
			settings_touch_dragged = true
			settings_touch_scroll.scroll_vertical = maxi(0, settings_touch_scroll.scroll_vertical - roundi(event.relative.y))
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenDrag and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		battle_view.mouse_position = event.position - battle_view.get_global_rect().position
		battle_view.queue_redraw()
		return
	if event is InputEventScreenTouch and not event.pressed and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		var local_position: Vector2 = battle_view.get_global_transform_with_canvas().affine_inverse() * event.position
		if Rect2(Vector2.ZERO, battle_view.size).has_point(local_position):
			_on_battlefield_clicked(battle_view.screen_to_world_x(local_position.x))
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and _battle_text_has_focus(): return
	if event is InputEventKey and _handle_battle_hotkey(event):
		get_viewport().set_input_as_handled(); return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_set_fullscreen(not bool(save_data.settings.fullscreen))
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		battle_view.selected_structure = ""
		_refresh_structure_selection()
		_show_placement_status(Localization.text("건설을 취소했습니다."))
		get_viewport().set_input_as_handled()

func _server_can_update() -> bool:
	return server_update_safe(network.models.values(), multiplayer.get_peers().size())

static func server_update_safe(models: Array, connected_peer_count: int) -> bool:
	if connected_peer_count > 0:
		return false
	for model in models:
		if model.winner == -1:
			return false
	return true

func _active_match_count() -> int:
	var count := 0
	for model in network.models.values():
		if model.winner == -1:
			count += 1
	return count

func _update_server_lifecycle(delta: float) -> void:
	if server_state_dir.is_empty():
		return
	var draining := FileAccess.file_exists(server_state_dir.path_join("update.pending"))
	if draining != server_draining:
		server_draining = draining
		network.set_accepting_players(not draining)
		print("SERVER_DRAINING enabled=%s" % draining)
	server_status_accumulator += delta
	if server_status_accumulator < 1.0:
		return
	server_status_accumulator = 0.0
	var status := {
		"active_matches": _active_match_count(),
		"accepting_players": not server_draining,
		"safe_to_update": _server_can_update(),
	}
	var status_path := server_state_dir.path_join("server-status.json")
	var temporary_path := status_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(status) + "\n")
	file.close()
	if FileAccess.file_exists(status_path):
		DirAccess.remove_absolute(status_path)
	DirAccess.rename_absolute(temporary_path, status_path)

func _clear_screen() -> void:
	_cancel_binding_capture()
	binding_buttons.clear(); binding_hint=null; binding_draft.clear()
	for player in combat_sfx_players:
		if is_instance_valid(player): player.stop()
	_dismiss_action_overlay()
	_dismiss_battle_report()
	practice_pause_button = null; practice_speed_button = null; latency_label = null; recovery_label = null
	base_warning_label = null; cancel_build_button = null
	session_chat_log = null; session_chat_input = null; session_roster = null; session_title = null
	if is_instance_valid(battle_chat_panel): battle_chat_panel.queue_free()
	battle_chat_panel = null
	for child in get_children():
		if child != network and child != updater and child != bgm_player:
			child.queue_free()
	battle_view = null
	status_label = null
	lobby_rows = null
	lobby_page_label = null
	room_create_dialog = null
	result_overlay = null
	stats_overlay = null
	placement_status_label = null
	structure_count_label = null
	connect_button_ref = null
	join_button_ref = null
	room_code_input = null
	settings_touch_scroll = null
	settings_touch_index = -1
	settings_touch_dragged = false
	settings_touch_start = Vector2.ZERO
	tutorial_banner = null
	tutorial_hint = null
	tutorial_step = -1
	placement_pending = false
	placement_message_serial += 1
	structure_buttons.clear()
	purchase_buttons.clear()

func _show_placement_status(message: String, duration: float = 2.5) -> void:
	if not is_instance_valid(placement_status_label):
		return
	placement_message_serial += 1
	var serial := placement_message_serial
	placement_status_label.text = Localization.text(message)
	if duration <= 0.0:
		return
	var timer := get_tree().create_timer(duration)
	timer.timeout.connect(func():
		if serial == placement_message_serial and is_instance_valid(placement_status_label):
			placement_status_label.text = ""
	)

static func build_version() -> String:
	var file := FileAccess.open("res://build_info.json", FileAccess.READ)
	if file == null:
		return "0.4.9"
	var data = JSON.parse_string(file.get_as_text())
	return String(data.get("version", "0.4.9")) if data is Dictionary else "0.4.9"

static func build_binary_version() -> String:
	var file := FileAccess.open("res://build_info.json", FileAccess.READ)
	if file == null:
		return "0.4.9"
	var data = JSON.parse_string(file.get_as_text())
	return String(data.get("binary_version", "0.4.9")) if data is Dictionary else "0.4.9"

func _active_preset() -> Dictionary:
	return save_data.deck_presets[clampi(int(save_data.last_deck), 0, 2)]

func _apply_settings() -> void:
	var settings: Dictionary = save_data.settings
	if String(settings.graphics_quality) == "auto":
		SaveData.apply_graphics_profile(settings, "auto", OS.has_feature("mobile"), DisplayServer.screen_get_size())
	for pair in [["Master", settings.master_volume], ["BGM", settings.bgm_volume], ["SFX", settings.sfx_volume]]:
		_preview_bus_volume(float(pair[1]), String(pair[0]))
	var master_bus := AudioServer.get_bus_index("Master")
	if master_bus >= 0:
		AudioServer.set_bus_mute(master_bus, bool(settings.muted))
	Engine.max_fps = clampi(int(settings.fps_limit), 30, 240)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	if bool(settings.fullscreen):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		var parts := String(settings.window_size).split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

func _preview_bus_volume(value: float, bus_name: String) -> void:
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_volume_db(bus_index, -80.0 if value <= 0.0 else linear_to_db(value))

func _set_fullscreen(enabled: bool) -> void:
	save_data.settings.fullscreen = enabled
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if enabled else DisplayServer.WINDOW_MODE_WINDOWED)
		if not enabled:
			var parts := String(save_data.settings.window_size).split("x")
			if parts.size() == 2:
				DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	var toggle := find_child("FullscreenToggle", true, false) as CheckButton
	if toggle != null:
		toggle.set_pressed_no_signal(enabled)
	SaveData.save_data(save_data)

func _make_background() -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color("#0b121c")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg

func _add_menu_portrait(parent: Control, texture_path: String, position_value: Vector2, accent: Color, label_text: String) -> void:
	MenuScreens._add_menu_portrait(self, parent, texture_path, position_value, accent, label_text)

func _build_connect_screen(message: String = "") -> void:
	MenuScreens._build_connect_screen(self, message)

func _normalize_room_code_input(value: String) -> void:
	if not is_instance_valid(room_code_input) or value == value.to_upper():
		return
	var caret := room_code_input.get_caret_column()
	room_code_input.text = value.to_upper()
	room_code_input.set_caret_column(caret)

func _campaign_growth_summary() -> String:
	var bonuses := BattleModel.campaign_bonuses(SaveData.campaign_growth_level(save_data))
	return Localization.text("원정 성장 %d · 병력 +%d%% · 자원 %.1f/초 · 최대 %d") % [int(bonuses.levels), roundi((float(bonuses.stat_scale) - 1.0) * 100.0), float(bonuses.income), int(bonuses.capacity)]

func _quit_game() -> void:
	get_tree().quit()

func _setup_bgm() -> void:
	if DisplayServer.get_name() == "headless" or is_instance_valid(bgm_player):
		return
	var stream := BATTLE_BGM.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * float(stream.mix_rate))
	bgm_player = AudioStreamPlayer.new()
	bgm_player.name = "BattleBGM"
	bgm_player.bus = &"BGM"
	bgm_player.stream = stream
	bgm_player.volume_db = 0.0
	add_child(bgm_player)
	bgm_player.play()

func _build_ai_stage_screen(as_campaign: bool = false) -> void:
	MenuScreens._build_ai_stage_screen(self, as_campaign)

func _submenu(title_text: String, subtitle_text: String) -> VBoxContainer:
	return MenuScreens._submenu(self, title_text, subtitle_text)

func _build_patch_notes_screen() -> void:
	MenuScreens._build_patch_notes_screen(self)

func _build_deck_screen(preset_index: int = -1) -> void:
	DeckScreen._build_deck_screen(self, preset_index)

func _build_records_screen() -> void:
	MenuScreens._build_records_screen(self)

func _build_settings_screen(mobile_layout_override: bool = false) -> void:
	SettingsScreen._build_settings_screen(self, mobile_layout_override)

func _add_settings_section(parent: VBoxContainer, title: String) -> void:
	SettingsScreen._add_settings_section(self, parent, title)

func _configure_deck_card(card: Button, base_text: String, color: Color, selected: bool) -> void:
	DeckScreen._configure_deck_card(self, card, base_text, color, selected)

func _refresh_deck_card(card: Button) -> void:
	DeckScreen._refresh_deck_card(self, card)

func _styled_button(text_value: String, color: Color, filled: bool = false) -> Button:
	var button := Button.new()
	button.text = Localization.text(text_value)
	button.custom_minimum_size = Vector2(120, 50)
	return UIKit.style_button(button, color, filled, 16)

func _on_connection_status(text: String) -> void:
	if not local_ai_mode and network.client_connection_state == "idle" and multiplayer_screen == "session":
		lobby_data = {"rooms":[],"page":0,"total":0}; _build_lobby_screen()
	if smoke_mode:
		print("SMOKE_STATUS %s" % text)
	if is_instance_valid(status_label):
		status_label.text = Localization.text(text)
	if network.client_connection_state == "idle":
		_set_room_controls_disabled(false)
		if multiplayer_screen == "lobby":
			_set_lobby_enabled(false)

func _set_room_controls_disabled(disabled: bool) -> void:
	if is_instance_valid(connect_button_ref):
		connect_button_ref.disabled = disabled
	if is_instance_valid(join_button_ref):
		join_button_ref.disabled = disabled
	if is_instance_valid(room_code_input):
		room_code_input.editable = not disabled

func _connect_for_room(mode: String, code: String = "") -> void:
	var normalized := code.strip_edges().to_upper()
	if not network.set_room_request(mode, normalized):
		_on_connection_status(Localization.text("올바른 방 코드 6자리를 입력하세요."))
		return
	_set_room_controls_disabled(true)
	var preset := _active_preset()
	network.set_client_deck(preset.units, preset.structures)
	network.connect_to_candidates(official_connection_candidates(IP.get_local_addresses()), OFFICIAL_SERVER_PORT)

func _on_room_created(code: String) -> void:
	if network.client_room_mode in ["lobby","session"]:
		_build_waiting_room(code)
		return
	if is_instance_valid(room_code_input):
		room_code_input.text = code
		room_code_input.editable = false
		room_code_input.add_theme_font_size_override("font_size", 22)
		room_code_input.add_theme_color_override("font_color", Color("#f0d592"))
	_on_connection_status(Localization.text("방 코드 %s · 상대가 참가하기를 기다리는 중...") % code)

func _on_room_join_failed(error: String) -> void:
	if network.client_room_mode in ["lobby","session"]:
		_on_connection_status(error)
		network.browse_rooms(lobby_page)
		_set_lobby_enabled(network.client_connection_state == "lobby")
		return
	network.disconnect_from_server()
	_on_connection_status(error)
	_set_room_controls_disabled(false)

func _on_match_found(side: int) -> void:
	if not resuming_battle_ui: result_recorded = false
	resuming_battle_ui = false
	multiplayer_screen = ""
	local_ai_mode = false
	battle_preset = _active_preset().duplicate(true)
	own_side = side
	_build_battle_screen()
	if smoke_mode:
		print("CLIENT_MATCH_FOUND side=%d" % side)
		network.send_spawn("swordsman")

func _start_local_ai_battle(stage: int = 1, reuse_deck: bool = false) -> void:
	local_ai_mode = true
	practice.reset_battle_state()
	practice_used_tools = not campaign_mode and (practice.unlimited or not practice.enemy_units.is_empty() or practice.speed!=1.0)
	result_recorded = false
	current_ai_stage = clampi(stage, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
	own_side = 0
	local_model = BattleModel.new()
	local_model.configure_campaign_growth(own_side, SaveData.campaign_growth_level(save_data) if campaign_mode else current_ai_stage - 1)
	if not reuse_deck or battle_preset.is_empty():
		battle_preset = _active_preset().duplicate(true)
	var preset := battle_preset
	local_model.configure_deck(0, preset.units, preset.structures)
	var ai_units: Array = ServerAI.stage_unit_deck(current_ai_stage)
	var ai_structures: Array = ServerAI.stage_structure_deck(current_ai_stage)
	if not campaign_mode and not practice.enemy_units.is_empty():
		ai_units = practice.enemy_units; ai_structures = practice.enemy_structures
	local_model.configure_deck(1, ai_units, ai_structures)
	local_model.resources[1] = min(BattleModel.MAX_RESOURCE, 35.0 + float(current_ai_stage) * 10.0)
	local_model.configure_base_health(1, 300.0 + float(current_ai_stage) * 20.0)
	local_ai = ServerAI.new(1, current_ai_stage)
	if not campaign_mode: practice.refill(local_model,own_side)
	_build_battle_screen()
	if not ai_smoke_mode and not bool(save_data.get("tutorial_completed", false)):
		_begin_tutorial()
	if ai_smoke_mode:
		local_model.spawn_unit(0, String(preset.units[0]))
	local_step_accumulator = 0.0
	local_recorder = null
	if campaign_mode and not ai_smoke_mode:
		local_recorder = BattleReplay.Recorder.new(local_model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": current_ai_stage}, {"mode": "campaign", "stage": current_ai_stage})
	_on_snapshot(local_model.snapshot())

func _build_battle_screen() -> void:
	BattleHud._build_battle_screen(self)

func _begin_tutorial() -> void:
	Tutorial._begin_tutorial(self)

func _update_tutorial_hint() -> void:
	Tutorial._update_tutorial_hint(self)

func _tutorial_advance(completed_step: int) -> void:
	Tutorial._tutorial_advance(self, completed_step)

func _finish_tutorial() -> void:
	Tutorial._finish_tutorial(self)

static func result_details(snapshot: Dictionary, side: int, deck_name: String) -> String:
	var bases: Array = snapshot.get("base_hp", [])
	var hp := maxi(0, int(bases[side])) if side >= 0 and side < bases.size() else 0
	var elapsed := maxi(0, int(snapshot.get("elapsed", 0.0)))
	return Localization.text("기지 체력 %d  ·  전투 시간 %02d:%02d\n사용 덱: %s") % [hp, elapsed / 60, elapsed % 60, deck_name]

func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(mini(radius, 8))
	if radius >= 8:
		style.shadow_color = Color(0.0, 0.0, 0.0, 0.24)
		style.shadow_size = 8
	return style

func _create_hp_card(parent: Control, position_value: Vector2, side: int) -> void:
	BattleHud._create_hp_card(self, parent, position_value, side)

func _add_spawn_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	BattleHud._add_spawn_button(self, row, title, kind, color)

func _decorate_battle_card(button: Button) -> void:
	BattleHud._decorate_battle_card(self, button)

func _toggle_stats_panel() -> void:
	if is_instance_valid(stats_overlay):
		_dismiss_stats_panel()
	else:
		_show_stats_panel()

func _dismiss_stats_panel() -> void:
	if is_instance_valid(stats_overlay):
		stats_overlay.queue_free()
	stats_overlay = null

func _show_stats_panel() -> void:
	BattleHud._show_stats_panel(self)

func _add_structure_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	BattleHud._add_structure_button(self, row, title, kind, color)

func _refresh_structure_selection() -> void:
	BattleHud._refresh_structure_selection(self)

func _refresh_purchase_buttons(resources: float) -> void:
	BattleHud._refresh_purchase_buttons(self, resources)

func _on_battlefield_clicked(world_x: float) -> void:
	if network.client_is_spectator or (not local_ai_mode and network_paused) or result_shown or (local_ai_mode and not campaign_mode and practice.paused): return
	if not is_instance_valid(battle_view) or battle_view.selected_structure.is_empty() or placement_pending:
		return
	var kind := battle_view.selected_structure
	var error := local_model.structure_placement_error(own_side, kind, world_x) if local_ai_mode else battle_view.placement_error(kind, world_x)
	if not error.is_empty():
		_show_placement_status(error)
		return
	if local_ai_mode:
		if not campaign_mode: practice.refill(local_model,own_side)
		if local_model.place_structure(own_side, kind, world_x):
			if local_recorder != null: local_recorder.on_place(own_side, kind, world_x)
			_show_placement_status(Localization.text("건설 완료"))
			battle_view.selected_structure = ""
			_refresh_structure_selection()
			_tutorial_advance(1)
	else:
		placement_pending = true
		network.send_structure(kind, world_x)
		_show_placement_status(Localization.text("서버 확인 중..."), 0.0)

func _on_structure_placement_result(success: bool, error: String) -> void:
	placement_pending = false
	if not battle_active or local_ai_mode or not is_instance_valid(battle_view):
		return
	if success:
		battle_view.selected_structure = ""
		_refresh_structure_selection()
	_show_placement_status(Localization.text("건설 완료") if success else (error if not error.is_empty() else Localization.text("구조물을 설치하지 못했습니다.")))

func _on_snapshot(data: Dictionary) -> void:
	if not battle_active or not is_instance_valid(battle_view):
		return
	current_snapshot = data
	battle_view.set_snapshot(data)
	if ai_smoke_mode:
		var has_human: bool = data.get("units", []).any(func(unit): return int(unit.side) == 0)
		var has_ai: bool = data.get("units", []).any(func(unit): return int(unit.side) == 1)
		if has_human and has_ai:
			print("OFFLINE_AI_READY human_units=1 ai_units=1")
			get_tree().quit(0)
	if smoke_mode and data.get("units", []).size() > 0:
		print("CLIENT_SNAPSHOT units=%d" % data.get("units", []).size())
		get_tree().quit(0)
	var resources: Array = data.get("resources", [0.0, 0.0])
	var bases: Array = data.get("base_hp", [0.0, 0.0])
	var own_structures: int = data.get("structures", []).filter(func(structure): return int(structure.side) == own_side).size()
	if is_instance_valid(structure_count_label):
		structure_count_label.text = Localization.text("구조물 %d / 3") % own_structures
	var resource_cap := local_model.resource_capacity(own_side) if local_ai_mode and is_instance_valid(local_model) else BattleModel.MAX_RESOURCE
	resource_label.text = "%d / %d" % [int(resources[own_side]), int(resource_cap)]
	var resource_bar = resource_label.get_meta("bar", null)
	if is_instance_valid(resource_bar):
		resource_bar.max_value = resource_cap
		resource_bar.value = float(resources[own_side])
	_refresh_purchase_buttons(float(resources[own_side]))
	if local_ai_mode and tutorial_step == 2 and float(resources[own_side]) > tutorial_low_resource + 0.5:
		_tutorial_advance(2)
	var maxima: Array = data.get("base_max_hp", [BattleModel.BASE_MAX_HP, BattleModel.BASE_MAX_HP])
	blue_hp_bar.max_value = float(maxima[0])
	red_hp_bar.max_value = float(maxima[1])
	blue_hp_bar.value = float(bases[0])
	red_hp_bar.value = float(bases[1])
	blue_hp_label.text = "%d / %d" % [int(bases[0]), int(maxima[0])]
	red_hp_label.text = "%d / %d" % [int(bases[1]), int(maxima[1])]
	var elapsed_seconds := int(data.get("elapsed", 0.0))
	timer_label.text = "%02d:%02d" % [elapsed_seconds / 60, elapsed_seconds % 60]
	_update_base_warning(data)
	var winner: int = int(data.get("winner", -1))
	if winner != -1 and not result_shown:
		_show_result(winner)
	elif winner == -1 and result_shown:
		_dismiss_result_overlay()
		result_recorded = false
		updater.set_safe_to_update(false)

func _on_rage_started(_unit_id: int) -> void:
	if DisplayServer.get_name() == "headless" or bool(save_data.settings.muted): return
	var now := Time.get_ticks_msec()
	if now - last_rage_sfx_msec < 300: return
	last_rage_sfx_msec = now
	if not is_instance_valid(rage_sfx_player):
		rage_sfx_player = AudioStreamPlayer.new()
		rage_sfx_player.name = "RageSFX"
		rage_sfx_player.bus = &"SFX"
		rage_sfx_player.volume_db = -12.0
		rage_sfx_player.stream = preload("res://scripts/RageSound.gd").stream()
		add_child(rage_sfx_player)
	rage_sfx_player.play()

func _on_combat_events(events: Array) -> void:
	if battle_active: _play_combat_events(events)
	if is_instance_valid(battle_view) and not events.is_empty():
		battle_view.push_combat_events(events)
		if bool(save_data.settings.screen_shake) and events.any(func(event): return String(event.get("type", "")) == "BASE_HIT"):
			var strength := 3.0 * float(save_data.settings.effect_intensity)
			var tween := create_tween()
			tween.tween_property(battle_view, "position", Vector2(strength, 88.0), 0.04)
			tween.tween_property(battle_view, "position", Vector2.ZERO + Vector2(0.0, 88.0), 0.08)

func _show_result(winner: int) -> void:
	ResultScreens._show_result(self, winner)

func _dismiss_result_overlay() -> void:
	if is_instance_valid(result_overlay):
		result_overlay.queue_free()
	result_overlay = null
	result_shown = false

func _exit_battle_to_menu() -> void:
	if not network.client_session.is_empty():
		network.request_session_leave.rpc_id(1)
		return
	battle_active = false
	_dismiss_result_overlay()
	_dismiss_stats_panel()
	if not local_ai_mode:
		network.disconnect_from_server()
	local_ai_mode = false
	local_model = null
	local_ai = null
	current_snapshot.clear()
	_build_connect_screen()

func _exit_ai_battle() -> void:
	if not local_ai_mode:
		return
	battle_active = false
	local_model = null
	local_ai = null
	current_snapshot.clear()
	updater.set_safe_to_update(true)
	_build_ai_stage_screen(campaign_mode)

func _on_update_started(version: String) -> void:
	UpdateOverlay._on_update_started(self, version)

func _show_android_apk_notice() -> void:
	UpdateOverlay._show_android_apk_notice(self)

func _on_update_status(message: String, progress: float) -> void:
	UpdateOverlay._on_update_status(self, message, progress)

func _on_update_failed(message: String) -> void:
	UpdateOverlay._on_update_failed(self, message)

func _on_opponent_left() -> void:
	if battle_active and not result_shown and not save_data.is_empty() and not network.client_is_spectator:
		save_data.stats.online_interrupted += 1; SaveData.save_data(save_data)
	local_ai_mode = false; battle_active = false
	network.disconnect_from_server()
	lobby_data = {"rooms":[],"page":0,"total":0}
	_build_lobby_screen()
	status_label.text = "서버 연결이 끊겼습니다. 새로고침으로 다시 연결하세요."

func _open_multiplayer() -> void:
	_build_lobby_screen()
	network.set_room_request("session")
	var preset := _active_preset()
	network.set_client_deck(preset.units,preset.structures)
	network.connect_to_candidates(official_connection_candidates(IP.get_local_addresses()),OFFICIAL_SERVER_PORT)

func _build_lobby_screen() -> void:
	MultiplayerUI.browser(self)


func _toggle_quick_match() -> void:
	if network.client_connection_state == "queued": network.cancel_quick_match()
	elif network.start_quick_match():
		_refresh_quick_button(); _set_lobby_enabled(false)
		if is_instance_valid(status_label): status_label.text = "상대를 찾는 중..."

func _on_quick_match_status(state: String) -> void:
	_refresh_quick_button()
	if multiplayer_screen != "lobby": return
	_set_lobby_enabled(state != "queued")
	if is_instance_valid(status_label):
		status_label.text = {"queued": "상대를 찾는 중... 다시 누르면 취소합니다.", "cancelled": "빠른 대전을 취소했습니다.", "timeout": "상대를 찾지 못했습니다. 다시 시도하거나 방을 만들어 보세요."}.get(state, "")

func _refresh_quick_button() -> void:
	if not is_instance_valid(quick_button_ref): return
	var queued: bool = network.client_connection_state == "queued"
	quick_button_ref.text = Localization.text("✕ 대기 취소") if queued else Localization.text("⚡ 빠른 대전")
	quick_button_ref.disabled = not queued and network.client_connection_state != "lobby"

func _set_lobby_enabled(enabled: bool) -> void:
	_refresh_quick_button()
	if is_instance_valid(connect_button_ref): connect_button_ref.disabled = not enabled
	if is_instance_valid(lobby_rows):
		for button in lobby_rows.find_children("JoinRoomButton","Button",true,false): button.disabled = not enabled or not bool(button.get_meta("available",true))
		for button in lobby_rows.find_children("WatchRoomButton","Button",true,false): button.disabled = not enabled or not bool(button.get_meta("available",false))

func _render_room_listing(data: Dictionary) -> void:
	MultiplayerUI.listing(self,data)


func _on_room_list(data: Dictionary) -> void:
	lobby_data = data.duplicate(true)
	if multiplayer_screen == "waiting" and network.client_connection_state == "lobby": _build_lobby_screen()
	if multiplayer_screen != "lobby": return
	_render_room_listing(data)
	_set_lobby_enabled(network.client_connection_state == "lobby")
	if network.client_connection_state == "lobby": status_label.text = "참가할 방을 선택하세요."

func _show_create_room_dialog() -> void:
	MultiplayerUI.create_dialog(self)

func _build_waiting_room(code: String) -> void:
	_clear_screen()
	multiplayer_screen = "waiting"
	root_background = _make_background()
	var panel := PanelContainer.new()
	panel.name = "WaitingRoomPanel"
	panel.position = Vector2(330,180)
	panel.size = Vector2(620,360)
	panel.add_theme_stylebox_override("panel",_panel_style(Color("#131c29"),Color("#52658a"),24))
	root_background.add_child(panel)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation",18); panel.add_child(column)
	var title := Label.new(); title.text = network.client_room_name; title.add_theme_font_size_override("font_size",28); column.add_child(title)
	var detail := Label.new(); detail.name = "WaitingRoomCode"; detail.text = "1 / 2  ·  방 코드 %s" % code; column.add_child(detail)
	status_label = Label.new(); status_label.text = "상대가 참가하기를 기다리는 중..."; column.add_child(status_label)
	var leave := _styled_button("방 나가기",Color("#3d8f83"))
	leave.name = "LeaveRoomButton"
	leave.pressed.connect(func(): leave.disabled = true; network.leave_lobby_room())
	column.add_child(leave)

func _save_nickname(value: String) -> void:
	value = value.strip_edges()
	if not preload("res://scripts/RoomSessions.gd").safe_text(value,16): return
	network.client_nickname = value
	if save_data.get("nickname","") != value:
		save_data.nickname = value; SaveData.save_data(save_data)

func _active_deck_names() -> String:
	var preset := _active_preset()
	var names := PackedStringArray()
	for kind in preset.units: names.append(String(BattleModel.UNIT_NAMES[kind]))
	return " · ".join(names)

func _choose_session_deck(index: int, in_room: bool) -> void:
	if index<0 or index>=save_data.deck_presets.size(): return
	save_data.last_deck = index; battle_preset = _active_preset().duplicate(true); SaveData.save_data(save_data)
	if in_room:
		network.request_session_deck.rpc_id(1,battle_preset.units,battle_preset.structures)
		if is_instance_valid(session_deck_names): session_deck_names.text = _active_deck_names()
	else:
		if network.client_connection_state == "lobby": network.request_lobby_deck.rpc_id(1,battle_preset.units,battle_preset.structures)
		var node := root_background.find_child("LobbyDeckNames",true,false)
		if node: node.text = _active_deck_names()

func _prompt_room_entry(room: Dictionary, spectator: bool) -> void:
	if network.client_connection_state != "lobby": return
	MultiplayerUI.entry_dialog(self,room,spectator)

func _join_session_entry(room: Dictionary, password: String, spectator: bool) -> void:
	var accepted := false
	if room.has("state"): accepted = network.join_session_room(room.code,password,spectator)
	elif not spectator: accepted = network.join_lobby_room(room.code)
	if accepted:
		_set_lobby_enabled(false); status_label.text = "방에 입장 중..."

func _self_session_member() -> Dictionary:
	for member in network.client_session.get("members",[]):
		if int(member.id)==network.multiplayer.get_unique_id(): return member
	return {}

func _on_session_changed(data: Dictionary) -> void:
	if data.is_empty(): return
	var member := _self_session_member()
	if data.phase == "waiting" or (data.phase == "finished" and member.get("returned",false)):
		resuming_battle_ui = false; network_paused = false
		if multiplayer_screen != "session": MultiplayerUI.room(self)
		else: MultiplayerUI.update_room(self,data)
	elif multiplayer_screen == "session": MultiplayerUI.update_room(self,data)

func _on_session_error(text: String) -> void:
	_refresh_quick_button()
	if is_instance_valid(status_label): status_label.text = text
	if multiplayer_screen == "lobby": _set_lobby_enabled(network.client_connection_state == "lobby")

func _on_session_closed(text: String) -> void:
	network_paused = false; resuming_battle_ui = false
	local_ai_mode = false; battle_active = false; battle_preset.clear()
	lobby_data = {"rooms":[],"page":0,"total":0}
	_build_lobby_screen()
	if not text.is_empty(): status_label.text = text

func _on_session_chat(_message: Dictionary) -> void:
	MultiplayerUI.chat(self)

func _send_session_chat() -> void:
	if not is_instance_valid(session_chat_input) or network.client_session.is_empty(): return
	var text := session_chat_input.text.strip_edges()
	if not preload("res://scripts/RoomSessions.gd").safe_text(text,160): return
	var now := Time.get_ticks_msec()
	if now-last_chat_sent_msec<750: return
	last_chat_sent_msec = now
	network.request_session_chat.rpc_id(1,text); session_chat_input.text = ""

func _on_spectate_started() -> void:
	local_ai_mode = false; campaign_mode = false; own_side = 0; multiplayer_screen = ""
	var players: Array = network.client_session.get("members",[]).filter(func(member): return member.role=="player")
	if not players.is_empty(): battle_preset = players[0].deck.duplicate(true)
	_build_battle_screen()

func _add_battle_chat() -> void:
	BattleHud._add_battle_chat(self)

func _battle_text_has_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _handle_battle_hotkey(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or not battle_active or result_shown or (not local_ai_mode and network_paused) or network.client_is_spectator or _battle_text_has_focus() or is_instance_valid(stats_overlay) or is_instance_valid(report_overlay) or is_instance_valid(action_overlay): return false
	var key := event.physical_keycode if event.physical_keycode!=0 else event.keycode
	var codes: Array = save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)
	var index := codes.find(key)
	if index<0 or index>=purchase_buttons.size(): return false
	var button: Button = purchase_buttons[index]
	if not is_instance_valid(button) or button.disabled: return true
	if button.toggle_mode: button.set_pressed_no_signal(not button.button_pressed)
	button.pressed.emit()
	return true

func _add_purchase_labels(button: Button, key_text: String) -> void:
	BattleHud._add_purchase_labels(self, button, key_text)

func _purchase_unit(kind: String) -> void:
	if network.client_is_spectator or (not local_ai_mode and network_paused) or not battle_active or result_shown or (local_ai_mode and not campaign_mode and practice.paused) or float(client_purchase_gates.get(kind,0))>Time.get_ticks_msec(): return
	var accepted := false
	if local_ai_mode:
		if not campaign_mode: practice.refill(local_model,own_side)
		accepted = local_model.spawn_unit(own_side,kind)
		if accepted and local_recorder != null: local_recorder.on_spawn(own_side, kind)
		if accepted: _tutorial_advance(0)
	else:
		network.send_spawn(kind); accepted = true
	if accepted:
		client_purchase_gates[kind] = Time.get_ticks_msec()+350
		_refresh_purchase_buttons(latest_resources)

func _cancel_build_selection() -> void:
	if is_instance_valid(battle_view): battle_view.selected_structure = ""
	_refresh_structure_selection(); _show_placement_status("건설을 취소했습니다.")

func _play_combat_events(events: Array) -> void:
	if DisplayServer.get_name()=="headless" or bool(save_data.settings.muted): return
	var played := 0
	for event in events:
		var kind := CombatSounds.event_sound(event)
		if not kind.is_empty() and _play_battle_sound(kind):
			played += 1
			if played>=3: break

func _play_battle_sound(kind: String) -> bool:
	if DisplayServer.get_name()=="headless" or bool(save_data.settings.muted): return false
	var now := Time.get_ticks_msec()
	if now-int(sound_gate.get(kind,-1000))<90: return false
	var player: AudioStreamPlayer = null
	for candidate in combat_sfx_players:
		if is_instance_valid(candidate) and not candidate.playing: player = candidate; break
	if player==null:
		if combat_sfx_players.size()>=4: return false
		player = AudioStreamPlayer.new(); player.bus = &"SFX"; player.volume_db = -16.0; add_child(player); combat_sfx_players.append(player)
	player.stream = CombatSounds.stream(kind); player.play(); sound_gate[kind] = now
	return true

func _update_base_warning(data: Dictionary) -> void:
	if not is_instance_valid(base_warning_label): return
	var maximum: float = data.get("base_max_hp",[500.0,500.0])[own_side]
	var hp: float = data.get("base_hp",[500.0,500.0])[own_side]
	var danger := not network.client_is_spectator and int(data.get("winner",-1))==-1 and hp>0.0 and hp<=maximum*0.25
	base_warning_label.visible = danger
	var bar := blue_hp_bar if own_side==0 else red_hp_bar
	if is_instance_valid(bar): bar.modulate = Color("#ff8a96") if danger else Color.WHITE
	if danger and not base_warning_fired:
		base_warning_fired = true; _play_battle_sound("warning")

func _dismiss_battle_report() -> void:
	if is_instance_valid(report_overlay): report_overlay.queue_free()
	report_overlay = null

func _report_side_name(side: int) -> String:
	return ResultScreens._report_side_name(self, side)

func _show_battle_report() -> void:
	ResultScreens._show_battle_report(self)

func _dismiss_action_overlay() -> void:
	if is_instance_valid(action_overlay): action_overlay.queue_free()
	action_overlay = null

func _action_panel(title: String, rect: Rect2) -> VBoxContainer:
	_dismiss_action_overlay()
	action_overlay = ColorRect.new(); action_overlay.name = "BattleActionOverlay"; action_overlay.color = Color(0.02,0.03,0.05,0.95); action_overlay.size = Vector2(1280,720); action_overlay.z_index = 160; root_background.add_child(action_overlay)
	var column := MultiplayerUI.panel(self,action_overlay,"BattleActionPanel",rect)
	column.add_child(MultiplayerUI.label(title,26,MultiplayerUI.GOLD))
	return column

func _show_stage_brief(stage: int) -> void:
	PracticeUI._show_stage_brief(self, stage)

func _show_practice_deck() -> void:
	PracticeUI._show_practice_deck(self)

func _add_practice_controls() -> void:
	PracticeUI._add_practice_controls(self)

func _toggle_practice_pause() -> void:
	if not local_ai_mode or campaign_mode or result_shown: return
	practice.paused = not practice.paused
	if is_instance_valid(practice_pause_button): practice_pause_button.text="계속" if practice.paused else "일시정지"
	_refresh_purchase_buttons(latest_resources)

func _restart_practice() -> void:
	if not local_ai_mode or campaign_mode: return
	_start_local_ai_battle(current_ai_stage,true)

func _confirm_surrender() -> void:
	PracticeUI._confirm_surrender(self)

func _on_latency_updated(milliseconds: int) -> void:
	if not is_instance_valid(latency_label): return
	latency_label.text="지연 %dms"%milliseconds if milliseconds>=0 else "지연 측정 중"
	latency_label.tone = UIKit.DANGER if milliseconds>200 else (UIKit.GOLD if milliseconds>120 else UIKit.TEAL); latency_label.add_theme_color_override("font_color",latency_label.tone.lightened(0.5)); latency_label.refresh_style()

func _on_reconnect_status(active: bool, remaining: float) -> void:
	if active:
		resuming_battle_ui = true
		if not network_paused:
			network_paused = true; _refresh_purchase_buttons(latest_resources)
		var text := "연결 복구 중 · %d초"%ceili(remaining)
		if is_instance_valid(recovery_label) and recovery_label.text!=text: recovery_label.text=text
		elif is_instance_valid(status_label): status_label.text=text
	elif is_instance_valid(recovery_label): recovery_label.text=""

func _on_recovery_changed(data: Dictionary) -> void:
	if local_ai_mode: return
	var paused: bool = data.get("paused",false) or network.client_reconnecting
	if network_paused!=paused:
		network_paused=paused; _refresh_purchase_buttons(latest_resources)
	if is_instance_valid(recovery_label) and not network.client_reconnecting:
		recovery_label.text="상대 연결 복구 대기 · %d초"%ceili(float(data.get("reconnect_remaining",0))) if paused else ""

func _add_binding_settings(column: VBoxContainer) -> void:
	SettingsScreen._add_binding_settings(self, column)

func _refresh_binding_buttons() -> void:
	SettingsScreen._refresh_binding_buttons(self)

func _begin_binding_capture(index: int) -> void:
	SettingsScreen._begin_binding_capture(self, index)

func _cancel_binding_capture() -> void:
	SettingsScreen._cancel_binding_capture(self)
