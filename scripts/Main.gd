extends Control

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const LobbyFlow = preload("res://scripts/screens/LobbyFlow.gd")
const BattleFlow = preload("res://scripts/screens/BattleFlow.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ReplayScreens = preload("res://scripts/screens/ReplayScreens.gd")
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
var replay_viewer = null
var quick_wait_started_msec := 0
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
	if UIKit.is_touch():
		get_tree().node_added.connect(_enlarge_for_touch)
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
		if campaign_mode or (local_recorder != null and practice.speed == 1.0 and not practice.unlimited):
			# Fixed 30 Hz steps keep recorded battles deterministic, so their replays reproduce exactly.
			if not campaign_mode and practice.paused: delta = 0.0
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
	replay_viewer = null
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

## On touch devices every button gets a finger-sized minimum height as it enters the tree.
func _enlarge_for_touch(node: Node) -> void:
	if node is BaseButton and is_ancestor_of(node):
		var button := node as BaseButton
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, UIKit.TOUCH_MIN_HEIGHT)
	elif node is Slider and is_ancestor_of(node):
		(node as Slider).custom_minimum_size.y = maxf((node as Slider).custom_minimum_size.y, 44.0)

func _build_replay_list() -> void:
	ReplayScreens._build_replay_list(self)

func _play_replay(path: String) -> void:
	ReplayScreens._play_replay(self, path)

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
	LobbyFlow._on_connection_status(self, text)

func _set_room_controls_disabled(disabled: bool) -> void:
	LobbyFlow._set_room_controls_disabled(self, disabled)

func _connect_for_room(mode: String, code: String = "") -> void:
	LobbyFlow._connect_for_room(self, mode, code)

func _on_room_created(code: String) -> void:
	LobbyFlow._on_room_created(self, code)

func _on_room_join_failed(error: String) -> void:
	LobbyFlow._on_room_join_failed(self, error)

func _on_match_found(side: int) -> void:
	BattleFlow._on_match_found(self, side)

func _start_local_ai_battle(stage: int = 1, reuse_deck: bool = false) -> void:
	BattleFlow._start_local_ai_battle(self, stage, reuse_deck)

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
	BattleFlow._on_battlefield_clicked(self, world_x)

func _on_structure_placement_result(success: bool, error: String) -> void:
	BattleFlow._on_structure_placement_result(self, success, error)

func _on_snapshot(data: Dictionary) -> void:
	BattleFlow._on_snapshot(self, data)

func _on_rage_started(_unit_id: int) -> void:
	BattleFlow._on_rage_started(self, _unit_id)

func _on_combat_events(events: Array) -> void:
	BattleFlow._on_combat_events(self, events)

func _show_result(winner: int) -> void:
	ResultScreens._show_result(self, winner)

func _dismiss_result_overlay() -> void:
	if is_instance_valid(result_overlay):
		result_overlay.queue_free()
	result_overlay = null
	result_shown = false

func _exit_battle_to_menu() -> void:
	BattleFlow._exit_battle_to_menu(self)

func _exit_ai_battle() -> void:
	BattleFlow._exit_ai_battle(self)

func _on_update_started(version: String) -> void:
	UpdateOverlay._on_update_started(self, version)

func _show_android_apk_notice() -> void:
	UpdateOverlay._show_android_apk_notice(self)

func _on_update_status(message: String, progress: float) -> void:
	UpdateOverlay._on_update_status(self, message, progress)

func _on_update_failed(message: String) -> void:
	UpdateOverlay._on_update_failed(self, message)

func _on_opponent_left() -> void:
	LobbyFlow._on_opponent_left(self)

func _open_multiplayer() -> void:
	LobbyFlow._open_multiplayer(self)

func _build_lobby_screen() -> void:
	MultiplayerUI.browser(self)


func _toggle_quick_match() -> void:
	LobbyFlow._toggle_quick_match(self)

func _on_quick_match_status(state: String) -> void:
	LobbyFlow._on_quick_match_status(self, state)

func _refresh_quick_button() -> void:
	LobbyFlow._refresh_quick_button(self)

func _set_lobby_enabled(enabled: bool) -> void:
	LobbyFlow._set_lobby_enabled(self, enabled)

func _render_room_listing(data: Dictionary) -> void:
	MultiplayerUI.listing(self,data)


func _on_room_list(data: Dictionary) -> void:
	LobbyFlow._on_room_list(self, data)

func _show_create_room_dialog() -> void:
	MultiplayerUI.create_dialog(self)

func _build_waiting_room(code: String) -> void:
	LobbyFlow._build_waiting_room(self, code)

func _save_nickname(value: String) -> void:
	LobbyFlow._save_nickname(self, value)

func _active_deck_names() -> String:
	var preset := _active_preset()
	var names := PackedStringArray()
	for kind in preset.units: names.append(String(BattleModel.UNIT_NAMES[kind]))
	return " · ".join(names)

func _choose_session_deck(index: int, in_room: bool) -> void:
	LobbyFlow._choose_session_deck(self, index, in_room)

func _prompt_room_entry(room: Dictionary, spectator: bool) -> void:
	if network.client_connection_state != "lobby": return
	MultiplayerUI.entry_dialog(self,room,spectator)

func _join_session_entry(room: Dictionary, password: String, spectator: bool) -> void:
	LobbyFlow._join_session_entry(self, room, password, spectator)

func _self_session_member() -> Dictionary:
	for member in network.client_session.get("members",[]):
		if int(member.id)==network.multiplayer.get_unique_id(): return member
	return {}

func _on_session_changed(data: Dictionary) -> void:
	LobbyFlow._on_session_changed(self, data)

func _on_session_error(text: String) -> void:
	LobbyFlow._on_session_error(self, text)

func _on_session_closed(text: String) -> void:
	LobbyFlow._on_session_closed(self, text)

func _on_session_chat(_message: Dictionary) -> void:
	MultiplayerUI.chat(self)

func _send_session_chat() -> void:
	LobbyFlow._send_session_chat(self)

func _on_spectate_started() -> void:
	LobbyFlow._on_spectate_started(self)

func _add_battle_chat() -> void:
	BattleHud._add_battle_chat(self)

func _battle_text_has_focus() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _handle_battle_hotkey(event: InputEventKey) -> bool:
	return BattleFlow._handle_battle_hotkey(self, event)

func _add_purchase_labels(button: Button, key_text: String) -> void:
	BattleHud._add_purchase_labels(self, button, key_text)

func _purchase_unit(kind: String) -> void:
	BattleFlow._purchase_unit(self, kind)

func _cancel_build_selection() -> void:
	if is_instance_valid(battle_view): battle_view.selected_structure = ""
	_refresh_structure_selection(); _show_placement_status("건설을 취소했습니다.")

func _play_combat_events(events: Array) -> void:
	BattleFlow._play_combat_events(self, events)

func _play_battle_sound(kind: String) -> bool:
	return BattleFlow._play_battle_sound(self, kind)

func _update_base_warning(data: Dictionary) -> void:
	BattleFlow._update_base_warning(self, data)

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
	BattleFlow._toggle_practice_pause(self)

func _restart_practice() -> void:
	BattleFlow._restart_practice(self)

func _confirm_surrender() -> void:
	PracticeUI._confirm_surrender(self)

func _on_latency_updated(milliseconds: int) -> void:
	LobbyFlow._on_latency_updated(self, milliseconds)

func _on_reconnect_status(active: bool, remaining: float) -> void:
	LobbyFlow._on_reconnect_status(self, active, remaining)

func _on_recovery_changed(data: Dictionary) -> void:
	LobbyFlow._on_recovery_changed(self, data)

func _add_binding_settings(column: VBoxContainer) -> void:
	SettingsScreen._add_binding_settings(self, column)

func _refresh_binding_buttons() -> void:
	SettingsScreen._refresh_binding_buttons(self)

func _begin_binding_capture(index: int) -> void:
	SettingsScreen._begin_binding_capture(self, index)

func _cancel_binding_capture() -> void:
	SettingsScreen._cancel_binding_capture(self)
