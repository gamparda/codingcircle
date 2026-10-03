extends Control

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
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
var join_button_ref: Button
var local_ai_mode := false
var ai_smoke_mode := false
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
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
			local_ai.update(local_model, delta); local_model.tick(delta)
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
	var frame := PanelContainer.new()
	frame.position = position_value
	frame.size = Vector2(216, 256)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style := _panel_style(Color("#121c27"), Color(accent.r, accent.g, accent.b, 0.56), 6)
	frame_style.content_margin_left = 12
	frame_style.content_margin_right = 12
	frame.add_theme_stylebox_override("panel", frame_style)
	parent.add_child(frame)
	var interior := Control.new()
	interior.custom_minimum_size = Vector2(192, 256)
	interior.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(interior)
	var portrait := Sprite2D.new()
	portrait.name = "MenuUnitPortrait"
	portrait.texture = load(texture_path)
	portrait.position = Vector2(96, 109)
	portrait.scale = Vector2(0.63, 0.63)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	interior.add_child(portrait)
	var caption := Label.new()
	caption.text = Localization.text(label_text)
	caption.position = Vector2(0, 212)
	caption.size = Vector2(192, 28)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 16)
	caption.add_theme_color_override("font_color", accent)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	interior.add_child(caption)

func _build_connect_screen(message: String = "") -> void:
	multiplayer_screen = ""
	battle_active = false
	result_shown = false
	_clear_screen()
	root_background = _make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_background.add_child(backdrop)
	_add_menu_portrait(root_background, "res://assets/units/tanker.png", Vector2(42, 232), Color("#86abff"), "탱커")
	_add_menu_portrait(root_background, "res://assets/units/archer.png", Vector2(1022, 232), Color("#e5c47d"), "궁수")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	panel.position = Vector2(300, 100)
	root_background.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#121923")
	style.border_color = Color("#667789")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 18
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var badge := Label.new()
	badge.text = "◆  전장 개조 전략   /   v%s" % build_version()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("#8f98ad"))
	column.add_child(badge)
	var title := Label.new()
	title.text = "CAT  WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#f0d592"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text("자동 전투  ×  전장 개조  ×  실시간 전략")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("#858da0"))
	column.add_child(subtitle)
	var divider := HSeparator.new()
	divider.modulate = Color(1.0, 1.0, 1.0, 0.10)
	column.add_child(divider)
	var online_label := Label.new()
	online_label.text = "온라인 대전"
	online_label.add_theme_font_size_override("font_size", 12)
	online_label.add_theme_color_override("font_color", Color("#6f7890"))
	column.add_child(online_label)

	var multiplayer_button := _styled_button("멀티플레이",Color("#5e6ad2"),true)
	multiplayer_button.name = "MultiplayerButton"
	multiplayer_button.pressed.connect(_open_multiplayer)
	column.add_child(multiplayer_button)
	var or_label := Label.new()
	or_label.text = Localization.text("──────────────   또는   ──────────────")
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_color_override("font_color", Color("#454b5a"))
	or_label.add_theme_font_size_override("font_size", 12)
	column.add_child(or_label)
	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 8)
	column.add_child(ai_row)
	var campaign_button := _styled_button(Localization.text("AI 캠페인"), Color("#8b5cf6"), false)
	campaign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_button.pressed.connect(_build_ai_stage_screen.bind(true))
	ai_row.add_child(campaign_button)
	var practice_button := _styled_button(Localization.text("AI 연습"), Color("#6d5bd0"), false)
	practice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_button.pressed.connect(_build_ai_stage_screen.bind(false))
	ai_row.add_child(practice_button)
	var management_row := HBoxContainer.new()
	management_row.add_theme_constant_override("separation", 8)
	column.add_child(management_row)
	for entry in [[Localization.text("덱 편성"), _build_deck_screen], [Localization.text("전적"), _build_records_screen], [Localization.text("설정"), _build_settings_screen], [Localization.text("종료"), _quit_game]]:
		var menu_button := _styled_button(entry[0], Color("#3d8f83"), false)
		menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_button.pressed.connect(entry[1])
		management_row.add_child(menu_button)
	status_label = Label.new()
	status_label.text = Localization.text(message) if not message.is_empty() else "선택 덱: %s" % String(_active_preset().name)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#747d91"))
	column.add_child(status_label)
	var patch_notes := _styled_button(Localization.text("패치노트"), Color("#3d8f83"))
	patch_notes.name = "PatchNotesButton"
	patch_notes.position = Vector2(1035, 20)
	patch_notes.size = Vector2(225, 50)
	patch_notes.add_theme_font_size_override("font_size", 14)
	patch_notes.pressed.connect(_build_patch_notes_screen)
	root_background.add_child(patch_notes)
	updater.set_safe_to_update(true)
	updater.check_for_update()

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
	campaign_mode = as_campaign
	battle_active = false
	result_shown = false
	local_ai_mode = false
	local_model = null
	local_ai = null
	current_snapshot.clear()
	updater.set_safe_to_update(true)
	_clear_screen()
	root_background = _make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_background.add_child(backdrop)
	var panel := PanelContainer.new()
	panel.position = Vector2(140, 48)
	panel.size = Vector2(1000, 624)
	var panel_style := _panel_style(Color("#121923"), Color(0.55, 0.36, 0.96, 0.55), 20)
	panel_style.content_margin_left = 38
	panel_style.content_margin_right = 38
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	root_background.add_child(panel)
	var stage_column := VBoxContainer.new()
	stage_column.add_theme_constant_override("separation", 14)
	panel.add_child(stage_column)
	var title := Label.new()
	title.text = Localization.text("AI 캠페인") if campaign_mode else Localization.text("AI 연습")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	stage_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text("승리하여 다음 단계를 해금하고 별과 기록을 남기세요.") if campaign_mode else Localization.text("이전 단계를 모두 클리어한 성장 수치로 연습합니다. 실제 진행도는 바뀌지 않습니다.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	stage_column.add_child(subtitle)
	if campaign_mode:
		var growth := Label.new()
		growth.name = "CampaignGrowthSummary"
		growth.text = _campaign_growth_summary()
		growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		growth.add_theme_font_size_override("font_size", 13)
		growth.add_theme_color_override("font_color", Color("#f0d592"))
		stage_column.add_child(growth)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	if not campaign_mode:
		var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation",12); stage_column.add_child(tools)
		var edit := _styled_button("상대 덱 설정",Color("#3d647d")); edit.custom_minimum_size = Vector2(260,40); edit.pressed.connect(_show_practice_deck); tools.add_child(edit)
		var unlimited := CheckButton.new(); unlimited.name = "PracticeUnlimited"; unlimited.text = "자원 무제한"; unlimited.button_pressed = practice.unlimited; unlimited.toggled.connect(func(enabled): practice.unlimited=enabled); tools.add_child(unlimited)
		var normal := _styled_button("기본 설정",Color("#596174")); normal.custom_minimum_size = Vector2(200,40); normal.pressed.connect(func(): practice = PracticeTools.new(); _build_ai_stage_screen(false)); tools.add_child(normal)
	stage_column.add_child(grid)
	for stage in range(ServerAI.MIN_STAGE, ServerAI.MAX_STAGE + 1):
		var intensity := float(stage - 1) / float(ServerAI.MAX_STAGE - 1)
		var color := Color("#5b8cff").lerp(Color("#ff627d"), intensity)
		var record: Dictionary = save_data.campaign_records[stage - 1]
		var stars := "★".repeat(int(record.best_stars)) + "☆".repeat(3 - int(record.best_stars))
		var locked := campaign_mode and stage > int(save_data.campaign_unlocked)
		var stage_button := _styled_button(
			"%02d  %s  %s\n%s" % [stage, ServerAI.stage_name(stage), "🔒" if locked else stars, ServerAI.stage_summary(stage)],
			color,
			stage == current_ai_stage
		)
		stage_button.custom_minimum_size = Vector2(220, 130)
		stage_button.add_theme_font_size_override("font_size", 14)
		stage_button.disabled = locked
		stage_button.pressed.connect(_show_stage_brief.bind(stage) if campaign_mode else _start_local_ai_battle.bind(stage))
		grid.add_child(stage_button)
	var back_button := _styled_button(Localization.text("메인 화면으로"), Color("#596174"), false)
	back_button.custom_minimum_size.y = 48
	back_button.pressed.connect(_build_connect_screen)
	stage_column.add_child(back_button)

func _submenu(title_text: String, subtitle_text: String) -> VBoxContainer:
	battle_active = false
	_clear_screen()
	root_background = _make_background()
	var panel := PanelContainer.new()
	panel.position = Vector2(110, 35)
	panel.size = Vector2(1060, 650)
	var style := _panel_style(Color("#121923"), Color(0.36, 0.55, 0.70, 0.5), 18)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", style)
	root_background.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = Localization.text(title_text)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text(subtitle_text)
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	column.add_child(subtitle)
	return column

func _build_patch_notes_screen() -> void:
	var column := _submenu("패치노트", "최신 변경 사항과 이전 업데이트")
	var scroll := ScrollContainer.new()
	scroll.name = "PatchNotesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var entries: Array = PatchNotes.entries()
	for entry in entries:
		var heading := Label.new()
		heading.text = String(entry.version)
		heading.add_theme_font_size_override("font_size", 24)
		heading.add_theme_color_override("font_color", Color("#86f7ad"))
		content.add_child(heading)
		for change in entry.changes:
			var label := Label.new()
			label.text = "• " + Localization.text(String(change))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_color", Color("#dce1ec"))
			content.add_child(label)
	var back := _styled_button(Localization.text("메인 화면으로"), Color("#697386"))
	back.name = "PatchNotesBack"
	back.pressed.connect(_build_connect_screen)
	column.add_child(back)

func _build_deck_screen(preset_index: int = -1) -> void:
	var index := int(save_data.last_deck) if preset_index < 0 else clampi(preset_index, 0, 2)
	var column := _submenu(Localization.text("덱 편성"), "유닛 3종 · 구조물 3종 선택")
	var deck_panel := column.get_parent() as PanelContainer
	deck_panel.name = "DeckPanel"
	deck_panel.position = Vector2(110, 18)
	deck_panel.size = Vector2(1060, 684)
	column.add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab_index in 3:
		var tab := _styled_button(String(save_data.deck_presets[tab_index].name), Color("#5e6ad2"), tab_index == index)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_build_deck_screen.bind(tab_index))
		tabs.add_child(tab)
	var name_edit := LineEdit.new()
	name_edit.text = String(save_data.deck_presets[index].name)
	name_edit.placeholder_text = Localization.text("프리셋 이름")
	column.add_child(name_edit)
	var selected: Dictionary = save_data.deck_presets[index]
	var unit_buttons := {}
	var structure_buttons := {}
	var choices := VBoxContainer.new()
	choices.name = "DeckChoices"
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 10)
	column.add_child(choices)
	var unit_row := GridContainer.new()
	unit_row.name = "DeckUnitGrid"
	unit_row.columns = 4
	unit_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	unit_row.size_flags_stretch_ratio = 2.0
	unit_row.add_theme_constant_override("h_separation", 8)
	unit_row.add_theme_constant_override("v_separation", 8)
	choices.add_child(unit_row)
	var unit_names := BattleModel.UNIT_NAMES
	for kind in BattleModel.UNIT_STATS.keys():
		var stats: Dictionary = BattleModel.UNIT_STATS[kind]
		var role: String = {"healer": "공격속도 지원", "archer": "원거리", "shield": "방어", "swordsman": "근접 공격", "berserker": "체력 50% 이하: 광폭화", "warlock": "공격력 -30% 장판", "necromancer": "5초마다 해골 소환"}[kind]
		var card_text := Localization.text("%s\n비용 %d · HP %d · 공격 %d\nDPS %.1f · 사거리 %d\n%s") % [unit_names[kind], int(stats.cost), int(stats.hp), int(stats.damage), float(stats.damage) / float(stats.interval), int(stats.range), role]
		if kind == "healer":
			card_text = Localization.text("%s\n비용 %d · HP %d · 범위 %d\n공속 +3%% 영구 · 상한 +30%% · 쿨 7초") % [unit_names[kind], int(stats.cost), int(stats.hp), int(stats.range)]
		var card := _styled_button(card_text, Color("#5b8cff"), false)
		card.name = "DeckUnit_" + kind
		card.tooltip_text = BattleModel.unit_stat_summary(kind)
		card.add_theme_font_size_override("font_size", 13)
		_configure_deck_card(card, card_text, Color("#5b8cff"), selected.units.has(kind))
		card.custom_minimum_size = Vector2(240, 108)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		unit_buttons[kind] = card
		unit_row.add_child(card)
	var structure_grid := GridContainer.new()
	structure_grid.name = "DeckStructureGrid"
	structure_grid.columns = 4
	structure_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	structure_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	structure_grid.add_theme_constant_override("h_separation", 8)
	choices.add_child(structure_grid)
	var structure_names := {"wall": Localization.text("방벽"), "swamp": Localization.text("늪"), "turret": Localization.text("포탑"), "generator": Localization.text("발전기")}
	var roles := {"wall": Localization.text("뒤 대상을 차폐 · 최대 2"), "swamp": Localization.text("반경 95 · 80% 감속 · 5초"), "turret": Localization.text("사거리 240 · 최대 1"), "generator": Localization.text("후방 전용 · 초당 +2")}
	for kind in BattleModel.STRUCTURE_STATS.keys():
		var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
		var card_text := Localization.text("%s\n비용 %d · HP %d\n%s") % [structure_names[kind], int(stats.cost), int(stats.hp), roles[kind]]
		var card := _styled_button(card_text, Color("#3d8f83"), false)
		card.name = "DeckStructure_" + kind
		card.add_theme_font_size_override("font_size", 13)
		_configure_deck_card(card, card_text, Color("#3d8f83"), selected.structures.has(kind))
		card.custom_minimum_size = Vector2(240, 108)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		structure_buttons[kind] = card
		structure_grid.add_child(card)
	choices.resized.connect(func():
		var row_gap := float(unit_row.get_theme_constant("v_separation"))
		var group_gap := float(choices.get_theme_constant("separation"))
		var row_height := maxf(108.0, (choices.size.y - row_gap - group_gap) / 3.0)
		unit_row.size_flags_stretch_ratio = 2.0 + row_gap / row_height
	)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color("#ff8a96"))
	column.add_child(status)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var save_button := _styled_button(Localization.text("덱 저장 및 사용"), Color("#5e6ad2"), true)
	save_button.name = "DeckSaveButton"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(func():
		var selected_units: Array = []
		var selected_structures: Array = []
		for kind in unit_buttons:
			if unit_buttons[kind].button_pressed: selected_units.append(kind)
		for kind in structure_buttons:
			if structure_buttons[kind].button_pressed: selected_structures.append(kind)
		if not NetworkController.validate_deck_payload(selected_units, selected_structures):
			status.text = Localization.text("유닛과 구조물을 각각 정확히 3종 선택해야 합니다.")
			return
		save_data.deck_presets[index] = {"name": name_edit.text.strip_edges().left(20) if not name_edit.text.strip_edges().is_empty() else Localization.text("덱 %d") % (index + 1), "units": selected_units, "structures": selected_structures}
		save_data.last_deck = index
		SaveData.save_data(save_data)
		_build_connect_screen(Localization.text("덱을 저장했습니다."))
	)
	actions.add_child(save_button)
	var back := _styled_button(Localization.text("취소"), Color("#697386"), false)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_build_connect_screen)
	actions.add_child(back)

func _build_records_screen() -> void:
	var column := _submenu(Localization.text("개인 전적"), "이 기기에 저장된 전적")
	var stats: Dictionary = save_data.stats
	var online_rate := 0.0 if int(stats.online_completed) == 0 else float(stats.online_wins) / float(stats.online_completed) * 100.0
	var summary := Label.new()
	summary.text = Localization.text("AI  ·  경기 %d  /  승 %d  /  패 %d  /  최고 캠페인 %02d  /  별 %d\n\n온라인  ·  완료 %d  /  승 %d  /  패 %d  /  무 %d  /  중단 %d  /  승률 %.1f%%") % [stats.ai_matches, stats.ai_wins, stats.ai_losses, stats.highest_campaign, stats.total_stars, stats.online_completed, stats.online_wins, stats.online_losses, stats.online_draws, stats.online_interrupted, online_rate]
	summary.add_theme_font_size_override("font_size", 20)
	column.add_child(summary)
	var records := Label.new()
	var lines: Array = []
	for stage in ServerAI.MAX_STAGE:
		var record: Dictionary = save_data.campaign_records[stage]
		lines.append(Localization.text("%02d %-5s  %s  도전 %d / 승 %d  최단 %.1f초  최고 기지 HP %d") % [stage + 1, ServerAI.stage_name(stage + 1), "★".repeat(record.best_stars) + "☆".repeat(3 - record.best_stars), record.attempts, record.wins, record.fastest_win, int(record.best_base_hp)])
	records.text = "\n".join(lines)
	records.add_theme_font_size_override("font_size", 16)
	column.add_child(records)
	var back := _styled_button(Localization.text("메인 화면으로"), Color("#697386"), false)
	back.pressed.connect(_build_connect_screen)
	column.add_child(back)

func _build_settings_screen(mobile_layout_override: bool = false) -> void:
	var outer := _submenu(Localization.text("설정"), "변경 시 자동 저장")
	var mobile_layout := OS.has_feature("mobile") or mobile_layout_override
	var settings: Dictionary = save_data.settings
	binding_draft = BattleBindings.sanitize(settings.get("battle_keys"))
	var quality_row := HBoxContainer.new()
	var quality_label := Label.new()
	quality_label.text = Localization.text("화질")
	quality_label.custom_minimum_size.x = 180
	quality_row.add_child(quality_label)
	var quality := OptionButton.new()
	quality.name = "GraphicsQualitySelector"
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var quality_options: Array = SaveData.GRAPHICS_QUALITIES.duplicate()
	if String(settings.graphics_quality) == "custom":
		quality_options.append("custom")
	for key in quality_options:
		quality.add_item(Localization.text({"auto": "자동", "high": "높음", "medium": "중간", "low": "낮음", "custom": "사용자 지정"}[key]))
	quality.select(max(0, quality_options.find(String(settings.graphics_quality))))
	quality_row.add_child(quality)
	outer.add_child(quality_row)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 16
	outer.add_child(scroll)
	if mobile_layout:
		settings_touch_scroll = scroll
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	_add_settings_section(column, "오디오")
	var controls := GridContainer.new()
	controls.columns = 2
	column.add_child(controls)
	var master := HSlider.new(); master.name = "MasterVolumeSlider"; master.min_value = 0.0; master.max_value = 1.0; master.step = 0.05; master.value = settings.master_volume
	var bgm := HSlider.new(); bgm.name = "BGMVolumeSlider"; bgm.min_value = 0.0; bgm.max_value = 1.0; bgm.step = 0.05; bgm.value = settings.bgm_volume
	var sfx := HSlider.new(); sfx.name = "SFXVolumeSlider"; sfx.min_value = 0.0; sfx.max_value = 1.0; sfx.step = 0.05; sfx.value = settings.sfx_volume
	master.value_changed.connect(_preview_bus_volume.bind("Master"))
	bgm.value_changed.connect(_preview_bus_volume.bind("BGM"))
	sfx.value_changed.connect(_preview_bus_volume.bind("SFX"))
	for pair in [[Localization.text("전체 음량"), master], [Localization.text("BGM 음량"), bgm], [Localization.text("효과음 음량"), sfx]]:
		var label := Label.new(); label.text = pair[0]; controls.add_child(label); pair[1].custom_minimum_size.x = 600; controls.add_child(pair[1])
	var muted := CheckButton.new(); muted.text = Localization.text("음소거"); muted.button_pressed = settings.muted; muted.toggled.connect(func(enabled): AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), enabled)); column.add_child(muted)
	_add_settings_section(column, "화면")
	var fullscreen := CheckButton.new(); fullscreen.name = "FullscreenToggle"; fullscreen.text = Localization.text("전체화면 (F11)").replace(" (F11)", "") if mobile_layout else Localization.text("전체화면 (F11)"); fullscreen.button_pressed = settings.fullscreen; column.add_child(fullscreen)
	var vsync := CheckButton.new(); vsync.text = "VSync"; vsync.button_pressed = settings.vsync; column.add_child(vsync)
	if mobile_layout:
		var section_spacer := Control.new()
		section_spacer.custom_minimum_size.y = 28
		column.add_child(section_spacer)
	var hidden_display: Control
	if mobile_layout:
		hidden_display = Control.new()
		hidden_display.visible = false
		outer.add_child(hidden_display)
	var window_size := OptionButton.new()
	for option in ["1280x720", "1600x900", "1920x1080"]: window_size.add_item(option)
	window_size.select(max(0, ["1280x720", "1600x900", "1920x1080"].find(String(settings.window_size))))
	if mobile_layout:
		hidden_display.add_child(window_size)
	else:
		window_size.name = "ResolutionSelector"
		column.add_child(window_size)
	var fps_limit := OptionButton.new()
	for option in [30, 60, 120, 144, 240]: fps_limit.add_item(Localization.text("FPS 제한 %d") % option, option)
	var fps_options := [30, 60, 120, 144, 240]
	fps_limit.select(max(0, fps_options.find(int(settings.fps_limit))))
	if mobile_layout:
		hidden_display.add_child(fps_limit)
	else:
		fps_limit.name = "FPSSelector"
		column.add_child(fps_limit)
	_add_binding_settings(column)
	_add_settings_section(column, "전투 연출")
	var damage_numbers := CheckButton.new(); damage_numbers.text = Localization.text("피해 숫자"); damage_numbers.button_pressed = settings.damage_numbers; column.add_child(damage_numbers)
	var shake := CheckButton.new(); shake.text = Localization.text("화면 흔들림"); shake.button_pressed = settings.screen_shake; column.add_child(shake)
	var effects := CheckButton.new(); effects.text = Localization.text("전투 효과"); effects.button_pressed = settings.battle_effects; column.add_child(effects)
	var intensity_row := HBoxContainer.new()
	var intensity_label := Label.new(); intensity_label.text = Localization.text("효과 강도"); intensity_label.custom_minimum_size.x = 132; intensity_row.add_child(intensity_label)
	var intensity := HSlider.new(); intensity.name = "EffectIntensitySlider"; intensity.min_value = 0.2; intensity.max_value = 1.0; intensity.step = 0.1; intensity.value = settings.effect_intensity; intensity.tooltip_text = Localization.text("효과 강도"); intensity.custom_minimum_size.x = 560; intensity_row.add_child(intensity); column.add_child(intensity_row)
	quality.item_selected.connect(func(index: int):
		var key := String(quality_options[index])
		if key == "custom":
			return
		var profile := SaveData.graphics_profile(key, mobile_layout, DisplayServer.screen_get_size())
		window_size.select(SaveData.WINDOW_SIZES.find(String(profile.window_size)))
		fps_limit.select(SaveData.FPS_LIMITS.find(int(profile.fps_limit)))
		damage_numbers.button_pressed = bool(profile.damage_numbers)
		shake.button_pressed = bool(profile.screen_shake)
		effects.button_pressed = bool(profile.battle_effects)
		intensity.value = float(profile.effect_intensity)
	)
	var save_button := _styled_button(Localization.text("설정 저장"), Color("#5e6ad2"), true)
	save_button.name = "SettingsSaveButton"
	save_button.pressed.connect(func():
		settings.master_volume = master.value; settings.bgm_volume = bgm.value; settings.sfx_volume = sfx.value
		settings.muted = muted.button_pressed; settings.fullscreen = fullscreen.button_pressed; settings.vsync = vsync.button_pressed
		settings.window_size = window_size.get_item_text(window_size.selected); settings.fps_limit = fps_limit.get_item_id(fps_limit.selected)
		settings.damage_numbers = damage_numbers.button_pressed; settings.screen_shake = shake.button_pressed; settings.battle_effects = effects.button_pressed; settings.effect_intensity = intensity.value
		settings.graphics_quality = String(quality_options[quality.selected])
		if String(settings.graphics_quality) != "custom":
			var profile := SaveData.graphics_profile(String(settings.graphics_quality), mobile_layout, DisplayServer.screen_get_size())
			for key in profile:
				if settings[key] != profile[key]:
					settings.graphics_quality = "custom"
					break
		settings.language = "ko"
		settings.battle_keys = binding_draft.duplicate()
		SaveData.save_data(save_data); Localization.install(String(settings.language)); _apply_settings()
		_build_connect_screen(Localization.text("설정을 저장했습니다."))
	)
	outer.add_child(save_button)
	var back := _styled_button(Localization.text("취소"), Color("#697386"), false); back.pressed.connect(func(): _apply_settings(); _build_connect_screen()); outer.add_child(back)

func _add_settings_section(parent: VBoxContainer, title: String) -> void:
	var heading := Label.new()
	heading.text = Localization.text(title)
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("#ebcd8c"))
	parent.add_child(heading)
	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 3)
	parent.add_child(divider)

func _configure_deck_card(card: Button, base_text: String, color: Color, selected: bool) -> void:
	card.toggle_mode = true
	card.set_meta("deck_base_text", base_text)
	card.set_meta("deck_color", color)
	var selected_style := StyleBoxFlat.new()
	selected_style.bg_color = color.darkened(0.48)
	selected_style.border_color = color.lightened(0.28)
	selected_style.set_border_width_all(3)
	selected_style.set_corner_radius_all(8)
	selected_style.content_margin_left = 10
	selected_style.content_margin_right = 10
	var selected_hover := selected_style.duplicate()
	selected_hover.bg_color = color.darkened(0.36)
	card.add_theme_stylebox_override("pressed", selected_style)
	card.add_theme_stylebox_override("hover_pressed", selected_hover)
	card.add_theme_color_override("font_pressed_color", Color.WHITE)
	card.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	card.set_pressed_no_signal(selected)
	_refresh_deck_card(card)
	card.toggled.connect(func(_pressed): _refresh_deck_card(card))

func _refresh_deck_card(card: Button) -> void:
	var marker := Localization.text("✓ 선택됨") if card.button_pressed else Localization.text("○ 선택 가능")
	card.text = marker + "\n" + String(card.get_meta("deck_base_text", ""))

func _styled_button(text_value: String, color: Color, filled: bool = false) -> Button:
	var button := Button.new()
	button.text = Localization.text(text_value)
	button.custom_minimum_size = Vector2(120, 50)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#f3f4f0"))
	button.add_theme_color_override("font_disabled_color", Color("#778294"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color.darkened(0.22) if filled else Color("#19232f")
	normal.border_color = color.lightened(0.12) if filled else Color(color.r, color.g, color.b, 0.70)
	normal.set_border_width_all(2 if filled else 1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate()
	hover.bg_color = color if filled else Color("#273444")
	hover.border_color = color.lightened(0.28)
	var pressed := hover.duplicate()
	pressed.bg_color = color.darkened(0.38) if filled else Color("#101a26")
	pressed.set_border_width_all(2)
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#121923")
	disabled.border_color = Color("#343c47")
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = Color("#f0d592")
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", focus)
	return button

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
	_on_snapshot(local_model.snapshot())

func _build_battle_screen() -> void:
	base_warning_fired = false; client_purchase_gates.clear(); sound_gate.clear()
	battle_active = true
	result_shown = false
	updater.set_safe_to_update(false)
	_clear_screen()
	root_background = _make_background()

	var top := ColorRect.new()
	top.color = Color("#0b0d13")
	top.position = Vector2.ZERO
	top.size = Vector2(1280, 88)
	root_background.add_child(top)
	var top_line := ColorRect.new()
	top_line.color = Color(1.0, 1.0, 1.0, 0.08)
	top_line.position = Vector2(0, 87)
	top_line.size = Vector2(1280, 1)
	top.add_child(top_line)
	_create_hp_card(top, Vector2(18, 12), own_side)
	_create_hp_card(top, Vector2(842, 12), 1 - own_side)

	var timer_card := PanelContainer.new()
	timer_card.position = Vector2(530, 12)
	timer_card.size = Vector2(220, 64)
	timer_card.add_theme_stylebox_override("panel", _panel_style(Color("#141720"), Color(1.0, 1.0, 1.0, 0.08), 10))
	top.add_child(timer_card)
	var timer_inner := Control.new()
	timer_inner.custom_minimum_size = Vector2(220, 64)
	timer_card.add_child(timer_inner)
	timer_label = Label.new()
	timer_label.position = Vector2(0, 7)
	timer_label.size = Vector2(220, 34)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 25)
	timer_label.add_theme_color_override("font_color", Color("#f5f7fb"))
	timer_inner.add_child(timer_label)
	var mode_label := Label.new()
	mode_label.text = "AI 단계 %02d" % current_ai_stage if local_ai_mode else ("관전 중" if network.client_is_spectator else "온라인 대전")
	mode_label.position = Vector2(0, 39)
	mode_label.size = Vector2(220, 18)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.add_theme_color_override("font_color", Color("#747d91"))
	timer_inner.add_child(mode_label)

	battle_view = BattleView.new()
	battle_view.position = Vector2(0, 88)
	battle_view.size = Vector2(1280, 492)
	battle_view.own_side = own_side
	battle_view.interpolate_positions = not local_ai_mode
	battle_view.rage_started.connect(_on_rage_started)
	battle_view.show_damage_numbers = bool(save_data.settings.damage_numbers)
	battle_view.show_battle_effects = bool(save_data.settings.battle_effects)
	battle_view.effect_intensity = float(save_data.settings.effect_intensity)
	battle_view.battlefield_clicked.connect(_on_battlefield_clicked)
	root_background.add_child(battle_view)
	placement_status_label = Label.new()
	placement_status_label.position = Vector2(360, 548)
	placement_status_label.size = Vector2(560, 28)
	placement_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placement_status_label.add_theme_color_override("font_color", Color("#ff8a96"))
	root_background.add_child(placement_status_label)
	structure_count_label = Label.new()
	structure_count_label.position = Vector2(1030, 548)
	structure_count_label.size = Vector2(220, 28)
	structure_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	structure_count_label.text = Localization.text("구조물 0 / 3")
	structure_count_label.add_theme_color_override("font_color", Color("#a7afc0"))
	root_background.add_child(structure_count_label)

	var controls := ColorRect.new()
	controls.color = Color("#0b0d13")
	controls.position = Vector2(0, 580)
	controls.size = Vector2(1280, 140)
	root_background.add_child(controls)
	var controls_line := ColorRect.new()
	controls_line.color = Color(1.0, 1.0, 1.0, 0.09)
	controls_line.size = Vector2(1280, 1)
	controls.add_child(controls_line)

	var resource_card := PanelContainer.new()
	resource_card.position = Vector2(16, 16)
	resource_card.size = Vector2(174, 108)
	var own_color := Color("#5b8cff")
	resource_card.add_theme_stylebox_override("panel", _panel_style(Color("#141720"), Color(own_color.r, own_color.g, own_color.b, 0.48), 10))
	controls.add_child(resource_card)
	var resource_inner := Control.new()
	resource_inner.custom_minimum_size = Vector2(174, 108)
	resource_card.add_child(resource_inner)
	var resource_caption := Label.new()
	resource_caption.text = "자원"
	resource_caption.position = Vector2(14, 12)
	resource_caption.size = Vector2(145, 18)
	resource_caption.add_theme_font_size_override("font_size", 10)
	resource_caption.add_theme_color_override("font_color", Color("#6f7890"))
	resource_inner.add_child(resource_caption)
	resource_label = Label.new()
	resource_label.position = Vector2(14, 28)
	resource_label.size = Vector2(145, 42)
	resource_label.add_theme_font_size_override("font_size", 25)
	resource_label.add_theme_color_override("font_color", Color("#f6c85f"))
	resource_inner.add_child(resource_label)
	var side_label := Label.new()
	side_label.text = "●  아군 진영"
	side_label.position = Vector2(14, 76)
	side_label.size = Vector2(145, 22)
	side_label.add_theme_font_size_override("font_size", 12)
	side_label.add_theme_color_override("font_color", own_color)
	resource_inner.add_child(side_label)

	var row := HBoxContainer.new()
	row.position = Vector2(205, 19)
	row.size = Vector2(1058, 102)
	row.add_theme_constant_override("separation", 8)
	controls.add_child(row)
	var preset := battle_preset if not battle_preset.is_empty() else _active_preset()
	var unit_names := BattleModel.UNIT_NAMES
	var unit_colors := {"shield": Color("#5b8cff"), "healer": Color("#d8b85a"), "archer": Color("#8b72df"), "swordsman": Color("#d56b5f"), "berserker": Color("#db7254"), "warlock": Color("#a775e6"), "necromancer": Color("#906bd1")}
	for kind in preset.units:
		_add_spawn_button(row, unit_names[kind], kind, unit_colors[kind])
	var separator := VSeparator.new()
	separator.modulate = Color(1.0, 1.0, 1.0, 0.10)
	separator.custom_minimum_size.x = 5
	row.add_child(separator)
	var structure_names := {"wall": Localization.text("방벽"), "swamp": Localization.text("늪"), "turret": Localization.text("포탑"), "generator": Localization.text("발전기")}
	var structure_colors := {"wall": Color("#7c879d"), "swamp": Color("#906bd1"), "turret": Color("#d56b5f"), "generator": Color("#3d8f83")}
	for kind in preset.structures:
		var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
		var card_text := Localization.text("%s\n%d 자원") % [structure_names[kind], int(stats.cost)]
		if kind == "swamp":
			card_text = Localization.text("%s · %d\n80%% 감속 · 5초") % [structure_names[kind], int(stats.cost)]
		_add_structure_button(row, card_text, kind, structure_colors[kind])
	# A raised z_index draws above the battlefield, but input follows sibling order.
	# Add these actions after BattleView so it cannot consume their pointer events.
	var stats_button := _styled_button(Localization.text("유닛 스탯"), Color("#3d8f83"), false)
	stats_button.name = "UnitStatsButton"
	stats_button.position = Vector2(1130, 98)
	stats_button.size = Vector2(136, 48)
	stats_button.z_index = 10
	stats_button.add_theme_font_size_override("font_size", 12)
	stats_button.pressed.connect(_toggle_stats_panel)
	root_background.add_child(stats_button)
	if local_ai_mode:
		var exit_button := _styled_button(Localization.text("대전 나가기"), Color("#8f4652"), false)
		exit_button.name = "ExitAIBattleButton"
		exit_button.position = Vector2(14, 98)
		exit_button.size = Vector2(136, 48)
		exit_button.z_index = 10
		exit_button.add_theme_font_size_override("font_size", 12)
		exit_button.text = "항복"; exit_button.pressed.connect(_confirm_surrender)
		root_background.add_child(exit_button)

	if local_ai_mode and not campaign_mode: _add_practice_controls()
	if campaign_mode and local_ai_mode:
		var goal := Label.new(); goal.name = "CampaignBattleGoal"; goal.text = CampaignBrief.goal(current_ai_stage); goal.position = Vector2(160,98); goal.size = Vector2(340,48); goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; goal.add_theme_font_size_override("font_size",12); goal.mouse_filter = Control.MOUSE_FILTER_IGNORE; root_background.add_child(goal)
	if not local_ai_mode:
		for side in 2:
			var name_label := Label.new(); name_label.name = "BattlePlayerName%d"%side; name_label.text = _report_side_name(side); name_label.position = Vector2(164 if side==own_side else 918,154); name_label.size = Vector2(270,28); name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side==own_side else HORIZONTAL_ALIGNMENT_RIGHT; name_label.add_theme_font_size_override("font_size",13); name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; root_background.add_child(name_label)
		latency_label = Label.new(); latency_label.name = "LatencyLabel"; latency_label.position = Vector2(760,96); latency_label.size = Vector2(150,20); latency_label.add_theme_font_size_override("font_size",12); latency_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; root_background.add_child(latency_label)
		var surrender := _styled_button("항복",Color("#8f4652")); surrender.name = "SurrenderButton"; surrender.position = Vector2(14,98); surrender.size = Vector2(136,48); surrender.z_index = 10; surrender.visible = not network.client_is_spectator; surrender.pressed.connect(_confirm_surrender); root_background.add_child(surrender)
		recovery_label = Label.new(); recovery_label.name = "NetworkRecoveryStatus"; recovery_label.position = Vector2(350,155); recovery_label.size = Vector2(580,38); recovery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; recovery_label.add_theme_color_override("font_color",Color("#f0d592")); recovery_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; root_background.add_child(recovery_label)
	if not network.client_session.is_empty(): _add_battle_chat()
	if not local_ai_mode: _on_latency_updated(network.latency_ms)

	base_warning_label = Label.new(); base_warning_label.name = "BaseDangerWarning"; base_warning_label.text = "기지 체력 위험"; base_warning_label.position = Vector2(530,96); base_warning_label.size = Vector2(220,28); base_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; base_warning_label.add_theme_color_override("font_color",Color("#ff8a96")); base_warning_label.visible = false; root_background.add_child(base_warning_label)
	cancel_build_button = _styled_button("설치 취소 · Esc",Color("#697386")); cancel_build_button.name = "CancelBuildButton"; cancel_build_button.position = Vector2(536,500); cancel_build_button.size = Vector2(208,44); cancel_build_button.visible = false; cancel_build_button.z_index = 10; cancel_build_button.pressed.connect(_cancel_build_selection); root_background.add_child(cancel_build_button)

func _begin_tutorial() -> void:
	tutorial_step = 0
	var banner := PanelContainer.new()
	banner.name = "FirstBattleGuide"
	banner.position = Vector2(320, 94)
	banner.size = Vector2(640, 68)
	banner.z_index = 20
	banner.add_theme_stylebox_override("panel", _panel_style(Color("#151c2c"), Color("#f6c85f"), 12))
	root_background.add_child(banner)
	tutorial_banner = banner
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(640, 68)
	banner.add_child(inner)
	tutorial_hint = Label.new()
	tutorial_hint.name = "FirstBattleHint"
	tutorial_hint.position = Vector2(14, 7)
	tutorial_hint.size = Vector2(506, 54)
	tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_hint.add_theme_font_size_override("font_size", 16)
	tutorial_hint.add_theme_color_override("font_color", Color("#f5f7fb"))
	inner.add_child(tutorial_hint)
	var skip := _styled_button(Localization.text("건너뛰기"), Color("#697386"), false)
	skip.name = "SkipFirstBattleGuide"
	skip.position = Vector2(524, 12)
	skip.size = Vector2(104, 44)
	skip.pressed.connect(_finish_tutorial)
	inner.add_child(skip)
	_update_tutorial_hint()

func _update_tutorial_hint() -> void:
	if not is_instance_valid(tutorial_hint):
		return
	match tutorial_step:
		0: tutorial_hint.text = Localization.text("첫 전투: 아래 유닛을 눌러 소환하세요.")
		1: tutorial_hint.text = Localization.text("구조물을 고른 뒤 전장에 설치하세요.")
		2: tutorial_hint.text = Localization.text("자원은 시간이 지나면 회복됩니다. 잠시 기다려 보세요.")

func _tutorial_advance(completed_step: int) -> void:
	if not local_ai_mode or tutorial_step != completed_step:
		return
	if tutorial_step == 2:
		_finish_tutorial()
		return
	tutorial_step += 1
	if tutorial_step == 2:
		tutorial_low_resource = float(local_model.resources[own_side])
	_update_tutorial_hint()

func _finish_tutorial() -> void:
	if tutorial_step < 0:
		return
	save_data.tutorial_completed = true
	SaveData.save_data(save_data)
	tutorial_step = -1
	if is_instance_valid(tutorial_banner):
		tutorial_banner.queue_free()
	tutorial_banner = null
	tutorial_hint = null

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
	var card := PanelContainer.new()
	card.position = position_value
	card.size = Vector2(420, 64)
	var color := Color("#5b8cff") if side == own_side else Color("#ff627d")
	card.add_theme_stylebox_override("panel", _panel_style(Color("#141720"), Color(color.r, color.g, color.b, 0.34), 10))
	parent.add_child(card)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(420, 64)
	card.add_child(inner)
	var faction := Label.new()
	faction.text = "아군 기지" if side == own_side else "적군 기지"
	faction.position = Vector2(14, 7)
	faction.size = Vector2(240, 22)
	faction.add_theme_font_size_override("font_size", 12)
	faction.add_theme_color_override("font_color", color)
	inner.add_child(faction)
	var value_label := Label.new()
	value_label.position = Vector2(300, 6)
	value_label.size = Vector2(104, 23)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 14)
	value_label.add_theme_color_override("font_color", Color("#dce1ec"))
	inner.add_child(value_label)
	var hp_bar := ProgressBar.new()
	hp_bar.position = Vector2(14, 35)
	hp_bar.size = Vector2(390, 12)
	hp_bar.max_value = BattleModel.BASE_MAX_HP
	hp_bar.value = BattleModel.BASE_MAX_HP
	hp_bar.show_percentage = false
	hp_bar.add_theme_stylebox_override("background", _panel_style(Color("#080a0f"), Color(1.0, 1.0, 1.0, 0.05), 6))
	hp_bar.add_theme_stylebox_override("fill", _panel_style(color, color, 6))
	inner.add_child(hp_bar)
	if side == 0:
		blue_hp_bar = hp_bar
		blue_hp_label = value_label
	else:
		red_hp_bar = hp_bar
		red_hp_label = value_label

func _add_spawn_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var stats: Dictionary = BattleModel.UNIT_STATS[kind].duplicate()
	var growth_level := int(local_model.campaign_levels[own_side]) if local_ai_mode and is_instance_valid(local_model) else 0
	var stat_scale := float(BattleModel.campaign_bonuses(growth_level).stat_scale)
	for key in ["hp", "damage", "heal"]:
		if stats.has(key):
			stats[key] = float(stats[key]) * stat_scale
	var primary := Localization.text("공속 +3% 누적") if kind == "healer" else Localization.text("공격 %d") % int(stats.damage)
	var button := _styled_button(Localization.text("%s  ·  %d\n체력 %d  ·  %s") % [title, int(stats.cost), int(stats.hp), primary], color)
	button.tooltip_text = BattleModel.unit_stat_summary(kind, growth_level)
	button.set_meta("purchase_cost", float(stats.cost))
	button.set_meta("unit_kind", kind)
	button.set_meta("base_text",button.text)
	_add_purchase_labels(button,BattleBindings.key_name(int(save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[purchase_buttons.size()])))
	button.disabled = true
	button.modulate = Color(0.4, 0.4, 0.4, 1.0)
	purchase_buttons.append(button)
	button.custom_minimum_size = Vector2(136, 102)
	_decorate_battle_card(button)
	var portrait := Sprite2D.new()
	portrait.name = "BattleUnitPortrait"
	portrait.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	portrait.position = Vector2(68, 25)
	portrait.scale = Vector2(0.17, 0.17)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(portrait)
	button.pressed.connect(_purchase_unit.bind(kind))
	row.add_child(button)

func _decorate_battle_card(button: Button) -> void:
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_top = 52
		style.content_margin_bottom = 5
		style.content_margin_left = 4
		style.content_margin_right = 4
		button.add_theme_stylebox_override(state, style)

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
	_dismiss_stats_panel()
	stats_overlay = ColorRect.new()
	stats_overlay.name = "UnitStatsPanel"
	stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	stats_overlay.position = Vector2.ZERO
	stats_overlay.size = Vector2(1280, 720)
	stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_overlay.z_index = 120
	root_background.add_child(stats_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(145, 72)
	panel.size = Vector2(990, 576)
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#10141e"), Color("#3d8f83"), 16))
	stats_overlay.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var title := Label.new()
	title.text = Localization.text("유닛 상세 스탯")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text("현재 전투 수치 · DPS는 공격력 ÷ 공격 간격")
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	content.add_child(subtitle)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	var scroll := ScrollContainer.new()
	scroll.name = "UnitStatsScroll"
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(scroll)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var names := BattleModel.UNIT_NAMES
	for kind in names.keys():
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(455, 126)
		card.add_theme_stylebox_override("panel", _panel_style(Color("#171c28"), Color(1.0, 1.0, 1.0, 0.09), 10))
		grid.add_child(card)
		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 16)
		card_margin.add_theme_constant_override("margin_right", 16)
		card_margin.add_theme_constant_override("margin_top", 12)
		card_margin.add_theme_constant_override("margin_bottom", 12)
		card.add_child(card_margin)
		var label := Label.new()
		label.text = "%s\n%s" % [names[kind], BattleModel.unit_stat_summary(kind, int(local_model.campaign_levels[own_side]) if local_ai_mode and is_instance_valid(local_model) else 0)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("#dce1ec"))
		card_margin.add_child(label)
	var world_stats := Label.new()
	world_stats.text = BattleModel.battle_stat_summary()
	world_stats.add_theme_font_size_override("font_size", 13)
	world_stats.add_theme_color_override("font_color", Color("#9ba5b8"))
	content.add_child(world_stats)
	var close := _styled_button(Localization.text("닫기"), Color("#3d8f83"), true)
	close.custom_minimum_size = Vector2(160, 44)
	close.pressed.connect(_dismiss_stats_panel)
	content.add_child(close)

func _add_structure_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var button := _styled_button(title, color)
	button.custom_minimum_size = Vector2(136, 102)
	button.toggle_mode = true
	button.set_meta("structure_kind", kind)
	button.set_meta("base_text",button.text)
	_add_purchase_labels(button,BattleBindings.key_name(int(save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[3+structure_buttons.size()])))
	button.set_meta("purchase_cost", float(BattleModel.STRUCTURE_STATS[kind].cost))
	button.disabled = true
	button.modulate = Color(0.4, 0.4, 0.4, 1.0)
	purchase_buttons.append(button)
	_decorate_battle_card(button)
	var emblem := Label.new()
	emblem.name = "StructureEmblem"
	emblem.text = {"wall": "▤", "swamp": "≈", "turret": "⌖", "generator": "⚡"}.get(kind, "◆")
	emblem.position = Vector2(0, 5)
	emblem.size = Vector2(136, 42)
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.add_theme_font_size_override("font_size", 30)
	emblem.add_theme_color_override("font_color", color.lightened(0.2))
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(emblem)
	button.pressed.connect(func():
		if is_instance_valid(battle_view):
			battle_view.selected_structure = "" if battle_view.selected_structure == kind else kind
			_refresh_structure_selection()
	)
	row.add_child(button)
	structure_buttons.append(button)

func _refresh_structure_selection() -> void:
	if is_instance_valid(cancel_build_button): cancel_build_button.visible = is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty()
	for button in structure_buttons:
		if is_instance_valid(button):
			button.set_pressed_no_signal(is_instance_valid(battle_view) and battle_view.selected_structure == String(button.get_meta("structure_kind")))
	if is_instance_valid(battle_view):
		battle_view.queue_redraw()

func _refresh_purchase_buttons(resources: float) -> void:
	latest_resources = resources
	var clear_selection := false
	for button in purchase_buttons:
		if not is_instance_valid(button):
			continue
		var cooldown := 0.0
		if button.has_meta("unit_kind"):
			var kind: String = button.get_meta("unit_kind")
			var advertised: Array = current_snapshot.get("spawn_cooldowns",[{},{}])
			cooldown = maxf(float(advertised[own_side].get(kind,0.0)),maxf(0.0,float(client_purchase_gates.get(kind,0))-Time.get_ticks_msec())/1000.0)
		var missing := maxi(0,ceili(float(button.get_meta("purchase_cost"))-resources))
		var unavailable: bool = network.client_is_spectator or (not local_ai_mode and network_paused) or result_shown or (local_ai_mode and not campaign_mode and practice.paused) or missing>0 or cooldown>0.001
		var state_label := button.get_node_or_null("PurchaseState") as Label
		if state_label:
			var state_text := "관전" if network.client_is_spectator else ("자원 -%d" % missing if missing>0 else ("대기 %.1f초" % cooldown if cooldown>0.001 else ""))
			if state_label.text!=state_text: state_label.text = state_text
		if button.disabled != unavailable:
			button.disabled = unavailable
			button.modulate = Color(0.4, 0.4, 0.4, 1.0) if unavailable else Color.WHITE
		if state_label: state_label.modulate = Color(2.5,2.5,2.5,1.0) if unavailable else Color.WHITE
		if unavailable and button.has_meta("structure_kind") and is_instance_valid(battle_view) and battle_view.selected_structure == String(button.get_meta("structure_kind")):
			battle_view.selected_structure = ""
			clear_selection = true
	if clear_selection:
		_refresh_structure_selection()

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
	_dismiss_result_overlay()
	_dismiss_stats_panel()
	if is_instance_valid(tutorial_banner):
		tutorial_banner.queue_free()
	tutorial_banner = null
	tutorial_hint = null
	tutorial_step = -1
	result_shown = true
	updater.set_safe_to_update(true)
	updater.check_for_update()
	var awarded_stars := 0
	var growth_before := SaveData.campaign_growth_level(save_data)
	if not result_recorded and not network.client_is_spectator:
		result_recorded = true
		if local_ai_mode:
			if campaign_mode:
				awarded_stars = SaveData.record_campaign(save_data, current_ai_stage, winner == own_side, float(current_snapshot.elapsed), float(current_snapshot.base_hp[own_side]), winner == 2)
			elif not practice_used_tools:
				save_data.stats.ai_matches += 1
				save_data.stats.ai_wins += 1 if winner == own_side else 0
				save_data.stats.ai_losses += 1 if winner != own_side and winner != 2 else 0
		else:
			save_data.stats.online_completed += 1
			save_data.stats.online_wins += 1 if winner == own_side else 0
			save_data.stats.online_losses += 1 if winner != own_side and winner != 2 else 0
			save_data.stats.online_draws += 1 if winner == 2 else 0
		SaveData.save_data(save_data)
	var overlay := PanelContainer.new()
	overlay.name = "ResultOverlay"
	result_overlay = overlay
	overlay.position = Vector2(350, 155)
	overlay.size = Vector2(580, 410)
	var result_color := Color("#f6c85f") if winner == own_side else Color("#8f98ad")
	var overlay_style := _panel_style(Color("#121923"), Color(result_color.r, result_color.g, result_color.b, 0.55), 18)
	overlay_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	overlay_style.shadow_size = 28
	overlay.add_theme_stylebox_override("panel", overlay_style)
	root_background.add_child(overlay)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(580, 410)
	overlay.add_child(inner)
	var overline := Label.new()
	overline.text = "MATCH COMPLETE"
	overline.position = Vector2(0, 36)
	overline.size = Vector2(580, 24)
	overline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overline.add_theme_font_size_override("font_size", 11)
	overline.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(overline)
	var result := Label.new()
	result.text = "전투 종료" if network.client_is_spectator else (Localization.text("무승부") if winner == 2 else (Localization.text("승리") if winner == own_side else Localization.text("패배")))
	result.position = Vector2(0, 64)
	result.size = Vector2(580, 82)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 52)
	result.add_theme_color_override("font_color", result_color)
	inner.add_child(result)
	var advances := local_ai_mode and campaign_mode and winner == own_side and current_ai_stage < ServerAI.MAX_STAGE
	var note := Label.new()
	if local_ai_mode:
		note.text = Localization.text("%02d단계 승리 · 최고 ★ %d · 다음 단계 해금") % [current_ai_stage, awarded_stars] if campaign_mode and winner == own_side else Localization.text("%02d단계 결과가 개인 전적에 저장되었습니다.") % current_ai_stage
		if not campaign_mode and practice_used_tools: note.text = "실험 설정 결과는 전적에 기록하지 않습니다."
	else:
		note.text = "같은 방에서 덱을 바꾸고 다시 대전할 수 있습니다." if not network.client_session.is_empty() else Localization.text("두 플레이어가 모두 준비하면 다시 시작합니다.")
	note.position = Vector2(0, 157)
	note.size = Vector2(580, 34)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(note)
	var details := Label.new()
	details.name = "ResultDetails"
	details.text = result_details(current_snapshot, own_side, String(battle_preset.get("name", "")))
	details.position = Vector2(32, 193)
	details.size = Vector2(516, 54)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 15)
	details.add_theme_color_override("font_color", Color("#dce1ec"))
	inner.add_child(details)
	if current_snapshot.has("battle_report"):
		var report_button := _styled_button("전투 요약",Color("#3d647d"))
		report_button.name = "BattleReportButton"; report_button.position = Vector2(395,25); report_button.size = Vector2(155,44)
		report_button.pressed.connect(_show_battle_report); inner.add_child(report_button)
	if local_ai_mode and campaign_mode:
		var growth := Label.new()
		growth.name = "CampaignGrowthReward"
		growth.text = CampaignBrief.result_conditions(current_ai_stage,winner==own_side,float(current_snapshot.elapsed),float(current_snapshot.base_hp[own_side])) + "\n" + ("첫 클리어 보상 · 병력 +3% · 자원 +0.5/초 · 보유 +10 · 시작 +5" if SaveData.campaign_growth_level(save_data)>growth_before else _campaign_growth_summary())
		growth.position = Vector2(25, 250)
		growth.size = Vector2(530, 44)
		growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		growth.add_theme_font_size_override("font_size", 12)
		growth.add_theme_color_override("font_color", Color("#f0d592"))
		inner.add_child(growth)
	var rematch_text := Localization.text("다시 도전") if local_ai_mode else ("대기실로" if not network.client_session.is_empty() else Localization.text("재경기 준비"))
	var rematch := _styled_button(rematch_text, Color("#5e6ad2"), true)
	rematch.position = Vector2(25 if advances else 65, 306)
	rematch.size = Vector2(165 if advances else 215, 58)
	rematch.pressed.connect(func():
		rematch.disabled = true
		if local_ai_mode:
			_start_local_ai_battle(current_ai_stage, true)
		elif not network.client_session.is_empty():
			network.request_session_return.rpc_id(1)
		else:
			rematch.text = Localization.text("상대 준비 대기 중")
			network.send_rematch()
	)
	inner.add_child(rematch)
	if advances:
		var next_stage := _styled_button(Localization.text("다음 단계"), Color("#3d8f83"), true)
		next_stage.position = Vector2(207, 306)
		next_stage.size = Vector2(165, 58)
		next_stage.pressed.connect(func():
			next_stage.disabled = true
			_start_local_ai_battle(current_ai_stage + 1, true)
		)
		inner.add_child(next_stage)
	var back := _styled_button(Localization.text("단계 선택") if local_ai_mode else Localization.text("이전 화면으로"), Color("#697386"), false)
	back.name = "BackToMenuButton"
	back.position = Vector2(389 if advances else 300, 306)
	back.size = Vector2(165 if advances else 215, 58)
	if local_ai_mode:
		back.pressed.connect(_build_ai_stage_screen.bind(campaign_mode))
	else:
		back.pressed.connect(_exit_battle_to_menu)
	inner.add_child(back)

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
	if running_as_server:
		print("MANDATORY_UPDATE_FOUND version=%s" % version)
		return
	if is_instance_valid(update_overlay) or not is_instance_valid(root_background):
		return
	update_overlay = ColorRect.new()
	update_overlay.color = Color(0.025, 0.03, 0.055, 0.96)
	update_overlay.position = Vector2.ZERO
	update_overlay.size = Vector2(1280, 720)
	update_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	update_overlay.z_index = 200
	root_background.add_child(update_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(340, 205)
	panel.size = Vector2(600, 310)
	var style := _panel_style(Color("#11141e"), Color("#7170ff"), 18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 30
	panel.add_theme_stylebox_override("panel", style)
	update_overlay.add_child(panel)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(600, 310)
	panel.add_child(inner)
	var overline := Label.new()
	overline.text = "MANDATORY UPDATE"
	overline.position = Vector2(0, 38)
	overline.size = Vector2(600, 22)
	overline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overline.add_theme_font_size_override("font_size", 11)
	overline.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(overline)
	var title := Label.new()
	title.text = Localization.text("새 버전 %s") % version
	title.position = Vector2(0, 66)
	title.size = Vector2(600, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	inner.add_child(title)
	update_message_label = Label.new()
	update_message_label.text = Localization.text("업데이트를 준비하고 있습니다...")
	update_message_label.position = Vector2(45, 135)
	update_message_label.size = Vector2(510, 34)
	update_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_message_label.add_theme_color_override("font_color", Color("#a7afc0"))
	inner.add_child(update_message_label)
	update_progress_bar = ProgressBar.new()
	update_progress_bar.position = Vector2(65, 190)
	update_progress_bar.size = Vector2(470, 14)
	update_progress_bar.max_value = 100.0
	update_progress_bar.show_percentage = false
	update_progress_bar.add_theme_stylebox_override("background", _panel_style(Color("#080a0f"), Color(1.0, 1.0, 1.0, 0.06), 7))
	update_progress_bar.add_theme_stylebox_override("fill", _panel_style(Color("#7170ff"), Color("#828fff"), 7))
	inner.add_child(update_progress_bar)
	update_note_label = Label.new()
	update_note_label.text = Localization.text("경기 중에는 설치하지 않으며, 완료 후 게임이 자동으로 재시작됩니다.")
	update_note_label.position = Vector2(25, 232)
	update_note_label.size = Vector2(550, 36)
	update_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_note_label.add_theme_font_size_override("font_size", 12)
	update_note_label.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(update_note_label)

func _show_android_apk_notice() -> void:
	_on_update_started(build_binary_version())
	if not is_instance_valid(update_overlay):
		return
	update_message_label.text = Localization.text("APK 업데이트가 필요합니다.")
	update_progress_bar.visible = false
	update_note_label.text = Localization.text("새 APK를 설치한 뒤 게임을 다시 실행해 주세요.")
	var download_button := _styled_button(Localization.text("APK 다운로드"), Color("#7170ff"), true)
	download_button.position = Vector2(580, 420)
	download_button.size = Vector2(120, 50)
	download_button.pressed.connect(func(): OS.shell_open(ANDROID_APK_URL))
	update_overlay.add_child(download_button)

func _on_update_status(message: String, progress: float) -> void:
	if running_as_server:
		print("UPDATE_STATUS %s" % message)
		return
	if is_instance_valid(update_message_label):
		update_message_label.text = message
	if is_instance_valid(update_progress_bar) and progress >= 0.0:
		update_progress_bar.value = progress * 100.0

func _on_update_failed(message: String) -> void:
	if running_as_server:
		printerr("UPDATE_FAILED %s; retrying in 10 seconds" % message)
		return
	if is_instance_valid(update_message_label):
		update_message_label.text = message + Localization.text("\n10초 후 자동으로 다시 시도합니다.")
	if is_instance_valid(update_progress_bar):
		update_progress_bar.value = 0.0

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


func _set_lobby_enabled(enabled: bool) -> void:
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
	var toggle := _styled_button("방 채팅",Color("#3d647d")); toggle.name = "BattleChatButton"; toggle.position = Vector2(970,190); toggle.size = Vector2(144,44); toggle.z_index = 10; root_background.add_child(toggle)
	battle_chat_panel = PanelContainer.new(); battle_chat_panel.name = "BattleChatPanel"; battle_chat_panel.position = Vector2(750,204); battle_chat_panel.size = Vector2(360,320); battle_chat_panel.z_index = 20
	var style := _panel_style(Color("#101a29"),Color("#2b415c"),12); style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 12; style.content_margin_bottom = 12; battle_chat_panel.add_theme_stylebox_override("panel",style); root_background.add_child(battle_chat_panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",8); battle_chat_panel.add_child(content)
	session_chat_log = RichTextLabel.new(); session_chat_log.bbcode_enabled = false; session_chat_log.scroll_following = true; session_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(session_chat_log)
	session_chat_input = LineEdit.new(); session_chat_input.placeholder_text = "메시지 입력 · Enter 전송"; session_chat_input.max_length = 160; session_chat_input.custom_minimum_size.y = 40; session_chat_input.text_submitted.connect(func(_value): _send_session_chat()); content.add_child(session_chat_input)
	battle_chat_panel.visible = false
	toggle.pressed.connect(func(): battle_chat_panel.visible = not battle_chat_panel.visible)
	MultiplayerUI.chat(self)

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
	var hotkey := Label.new(); hotkey.name = "PurchaseHotkey"; hotkey.text = key_text; hotkey.position = Vector2(6,4); hotkey.add_theme_font_size_override("font_size",11); hotkey.add_theme_color_override("font_color",Color("#d2d8e8")); hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(hotkey)
	var state := Label.new(); state.name = "PurchaseState"; state.position = Vector2(28,2); state.size = Vector2(106,18); state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; state.add_theme_font_size_override("font_size",10); state.add_theme_color_override("font_color",Color("#f0d592")); state.mouse_filter = Control.MOUSE_FILTER_IGNORE; state.add_theme_stylebox_override("normal",_panel_style(Color(0.03,0.04,0.06,0.9),Color.TRANSPARENT,3)); button.add_child(state)

func _purchase_unit(kind: String) -> void:
	if network.client_is_spectator or (not local_ai_mode and network_paused) or not battle_active or result_shown or (local_ai_mode and not campaign_mode and practice.paused) or float(client_purchase_gates.get(kind,0))>Time.get_ticks_msec(): return
	var accepted := false
	if local_ai_mode:
		if not campaign_mode: practice.refill(local_model,own_side)
		accepted = local_model.spawn_unit(own_side,kind)
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
	if local_ai_mode: return "내 전투" if side==own_side else "상대 AI"
	var players: Array = network.client_session.get("members",[]).filter(func(member): return member.role=="player")
	return String(players[side].nickname) if players.size()==2 else ("내 전투" if side==own_side else "상대 전투")

func _show_battle_report() -> void:
	if not Report.valid(current_snapshot.get("battle_report",[])): return
	_dismiss_battle_report()
	report_overlay = ColorRect.new(); report_overlay.name = "BattleReportOverlay"; report_overlay.color = Color(0.02,0.03,0.05,0.97); report_overlay.size = Vector2(1280,720); report_overlay.z_index = 150; root_background.add_child(report_overlay)
	var content := MultiplayerUI.panel(self,report_overlay,"BattleReportPanel",Rect2(80,40,1120,640))
	content.add_child(MultiplayerUI.label("전투 요약",28,MultiplayerUI.GOLD))
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation",28); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",14); columns.add_child(column)
		var data: Dictionary = current_snapshot.battle_report[side]
		column.add_child(MultiplayerUI.label(_report_side_name(side),22))
		column.add_child(MultiplayerUI.label("사용 자원 %d · 건설 %d
처치 %d · 실제 피해 %d" % [roundi(float(data.resources_spent)),int(data.structures_built),int(data.kills),roundi(float(data.damage))],16,MultiplayerUI.GOLD))
		for text in Report.lines(data): column.add_child(MultiplayerUI.label(text,14,MultiplayerUI.MUTED))
	content.add_child(MultiplayerUI.label("피해는 실제로 감소시킨 체력입니다. 해골의 처치·피해는 네크로맨서에 합산합니다.",12,MultiplayerUI.MUTED))
	MultiplayerUI.button(self,content,"닫기","CloseBattleReportButton",_dismiss_battle_report)

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
	if not campaign_mode or stage>int(save_data.campaign_unlocked): return
	var column := _action_panel("%02d · %s" % [stage,ServerAI.stage_name(stage)],Rect2(200,130,880,460))
	column.add_child(MultiplayerUI.label(CampaignBrief.goal(stage),19))
	column.add_child(MultiplayerUI.label("상대 덱",14,MultiplayerUI.GOLD))
	var deck := MultiplayerUI.label(CampaignBrief.enemy_deck(stage),16); deck.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(deck)
	column.add_child(MultiplayerUI.label(CampaignBrief.conditions(stage),15,MultiplayerUI.GOLD))
	var record: Dictionary = save_data.campaign_records[stage-1]
	column.add_child(MultiplayerUI.label("최고 %s · 최단 %s" % ["★".repeat(int(record.best_stars)),"%.0f초"%float(record.fastest_win) if float(record.fastest_win)>0 else "기록 없음"],14,MultiplayerUI.MUTED))
	MultiplayerUI.button(self,column,"전투 시작","StartCampaignStage",func(): _dismiss_action_overlay(); _start_local_ai_battle(stage))
	MultiplayerUI.button(self,column,"돌아가기","CloseCampaignBrief",_dismiss_action_overlay)

func _show_practice_deck() -> void:
	if campaign_mode: return
	var column := _action_panel("연습 상대 덱",Rect2(220,70,840,580))
	column.add_child(MultiplayerUI.label("병력 3종 · 구조물 3종",15,MultiplayerUI.MUTED))
	var units: Array = practice.enemy_units.duplicate() if not practice.enemy_units.is_empty() else ServerAI.stage_unit_deck(current_ai_stage)
	var structures: Array = practice.enemy_structures.duplicate() if not practice.enemy_structures.is_empty() else ServerAI.stage_structure_deck(current_ai_stage)
	var unit_grid := GridContainer.new(); unit_grid.columns=4; unit_grid.add_theme_constant_override("h_separation",12); column.add_child(unit_grid)
	for kind in BattleModel.UNIT_NAMES:
		if kind=="skeleton": continue
		var button := CheckButton.new(); button.text = BattleModel.UNIT_NAMES[kind]; button.button_pressed = units.has(kind); button.toggled.connect(func(on):
			if on: units.append(kind)
			else: units.erase(kind)); unit_grid.add_child(button)
	var structure_grid := GridContainer.new(); structure_grid.columns=4; column.add_child(structure_grid)
	for kind in BattleModel.STRUCTURE_STATS:
		var button := CheckButton.new(); button.text = {"wall":"방벽","swamp":"늪","turret":"포탑","generator":"발전기"}[kind]; button.button_pressed = structures.has(kind); button.toggled.connect(func(on):
			if on: structures.append(kind)
			else: structures.erase(kind)); structure_grid.add_child(button)
	var error := MultiplayerUI.label("",15,Color("#ff8a96")); column.add_child(error)
	MultiplayerUI.button(self,column,"적용","ApplyPracticeDeck",func():
		if not practice.set_enemy_deck(units,structures): error.text="서로 다른 병력 3종과 구조물 3종을 선택하세요."; return
		_dismiss_action_overlay()
		if battle_active and local_ai_mode: _restart_practice()
	)
	MultiplayerUI.button(self,column,"단계 기본 덱","DefaultPracticeDeck",func(): practice.enemy_units.clear(); practice.enemy_structures.clear(); _dismiss_action_overlay(); _restart_practice() if battle_active and local_ai_mode else _build_ai_stage_screen(false))
	MultiplayerUI.button(self,column,"닫기","ClosePracticeDeck",_dismiss_action_overlay)

func _add_practice_controls() -> void:
	var row := HBoxContainer.new(); row.name = "PracticeControls"; row.position = Vector2(164,98); row.size = Vector2(342,44); row.z_index=10; row.add_theme_constant_override("separation",6); root_background.add_child(row)
	practice_pause_button = _styled_button("일시정지",Color("#3d647d")); practice_pause_button.name="PracticePauseButton"; practice_pause_button.custom_minimum_size = Vector2(90,44); practice_pause_button.add_theme_font_size_override("font_size",12); practice_pause_button.pressed.connect(_toggle_practice_pause); row.add_child(practice_pause_button)
	practice_speed_button = _styled_button("%.1f배" % practice.speed,Color("#3d647d")); practice_speed_button.name="PracticeSpeedButton"; practice_speed_button.custom_minimum_size = Vector2(66,44); practice_speed_button.add_theme_font_size_override("font_size",12); practice_speed_button.pressed.connect(func(): practice.cycle_speed(); practice_used_tools=true; practice_speed_button.text="%.1f배"%practice.speed); row.add_child(practice_speed_button)
	var reset := _styled_button("초기화",Color("#596174")); reset.name="PracticeResetButton"; reset.custom_minimum_size=Vector2(74,44); reset.add_theme_font_size_override("font_size",12); reset.pressed.connect(_restart_practice); row.add_child(reset)
	var settings := _styled_button("상대 덱",Color("#596174")); settings.custom_minimum_size=Vector2(84,44); settings.add_theme_font_size_override("font_size",12); settings.pressed.connect(_show_practice_deck); row.add_child(settings)

func _toggle_practice_pause() -> void:
	if not local_ai_mode or campaign_mode or result_shown: return
	practice.paused = not practice.paused
	if is_instance_valid(practice_pause_button): practice_pause_button.text="계속" if practice.paused else "일시정지"
	_refresh_purchase_buttons(latest_resources)

func _restart_practice() -> void:
	if not local_ai_mode or campaign_mode: return
	_start_local_ai_battle(current_ai_stage,true)

func _confirm_surrender() -> void:
	if not battle_active or result_shown or network.client_is_spectator: return
	var column := _action_panel("항복할까요?",Rect2(400,230,480,260))
	column.add_child(MultiplayerUI.label("이 경기는 패배로 종료됩니다.",16,MultiplayerUI.MUTED))
	MultiplayerUI.button(self,column,"항복","ConfirmSurrender",func():
		_dismiss_action_overlay()
		if local_ai_mode:
			local_model.winner=1-own_side; _on_snapshot(local_model.snapshot())
		else: network.send_surrender()
	)
	MultiplayerUI.button(self,column,"계속하기","CancelSurrender",_dismiss_action_overlay)

func _on_latency_updated(milliseconds: int) -> void:
	if not is_instance_valid(latency_label): return
	latency_label.text="지연 %dms"%milliseconds if milliseconds>=0 else "지연 측정 중"
	latency_label.modulate=Color("#ff8a96") if milliseconds>200 else Color("#a7afc0")

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
	_add_settings_section(column,"전투 단축키")
	var grid := GridContainer.new(); grid.name="BattleKeyBindings"; grid.columns=3; grid.add_theme_constant_override("h_separation",12); grid.add_theme_constant_override("v_separation",8); column.add_child(grid)
	for index in 6:
		var button := _styled_button("",Color("#3d647d")); button.name="BindingSlot%d"%index; button.custom_minimum_size=Vector2(250,44); button.add_theme_font_size_override("font_size",14); button.pressed.connect(_begin_binding_capture.bind(index)); grid.add_child(button); binding_buttons.append(button)
	binding_hint = Label.new(); binding_hint.name="BindingHint"; binding_hint.text="변경할 항목을 누르고 새 키를 입력하세요."; binding_hint.add_theme_font_size_override("font_size",13); binding_hint.add_theme_color_override("font_color",Color("#f0d592")); column.add_child(binding_hint)
	var reset := _styled_button("단축키 기본값 복원",Color("#596174")); reset.name="ResetBattleBindings"; reset.pressed.connect(func(): _cancel_binding_capture(); binding_draft=BattleBindings.DEFAULTS.duplicate(); _refresh_binding_buttons()); column.add_child(reset)
	_refresh_binding_buttons()

func _refresh_binding_buttons() -> void:
	for index in binding_buttons.size():
		if is_instance_valid(binding_buttons[index]): binding_buttons[index].text="%s · %s"%[BattleBindings.LABELS[index],BattleBindings.key_name(int(binding_draft[index]))]

func _begin_binding_capture(index: int) -> void:
	_cancel_binding_capture()
	binding_capture_index=index
	binding_capture_overlay=ColorRect.new(); binding_capture_overlay.name="BindingCaptureOverlay"; binding_capture_overlay.color=Color(0.02,0.03,0.05,0.96); binding_capture_overlay.size=Vector2(1280,720); binding_capture_overlay.z_index=170; root_background.add_child(binding_capture_overlay)
	var column := MultiplayerUI.panel(self,binding_capture_overlay,"BindingCapturePanel",Rect2(300,220,680,280))
	column.add_child(MultiplayerUI.label("%s · 새 키 입력"%BattleBindings.LABELS[index],24,MultiplayerUI.GOLD))
	binding_hint=MultiplayerUI.label("새 키를 누르세요. Esc는 변경 취소입니다.",14,MultiplayerUI.MUTED); binding_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(binding_hint)
	MultiplayerUI.button(self,column,"취소","CancelBindingCapture",_cancel_binding_capture)

func _cancel_binding_capture() -> void:
	binding_capture_index=-1
	if is_instance_valid(binding_capture_overlay): binding_capture_overlay.queue_free()
	binding_capture_overlay=null
	if is_instance_valid(root_background): binding_hint=root_background.find_child("BindingHint",true,false) as Label
