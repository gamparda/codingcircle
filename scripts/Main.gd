extends Control

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
var local_model: BattleModel
var local_ai: ServerAI
var current_ai_stage := 1
var bgm_player: AudioStreamPlayer
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

func _ready() -> void:
	network.connection_status.connect(_on_connection_status)
	network.match_found.connect(_on_match_found)
	network.snapshot_received.connect(_on_snapshot)
	network.combat_events_received.connect(_on_combat_events)
	network.opponent_disconnected.connect(_on_opponent_left)
	network.structure_placement_result.connect(_on_structure_placement_result)
	network.room_created.connect(_on_room_created)
	network.room_join_failed.connect(_on_room_join_failed)
	updater.update_started.connect(_on_update_started)
	updater.update_status.connect(_on_update_status)
	updater.update_failed.connect(_on_update_failed)
	var args := OS.get_cmdline_user_args()
	smoke_mode = args.has("--smoke-client")
	ai_smoke_mode = args.has("--ai-smoke")
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
	save_data = SaveData.load_data()
	_apply_settings()
	_setup_bgm()
	_build_connect_screen()
	if apk_update_required(OS.get_name(), String(ProjectSettings.get_setting("application/config/version", "0.0.0")), build_version()):
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
	var candidates: Array = []
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
	if running_as_server:
		_update_server_lifecycle(delta)
		updater.set_safe_to_update(_server_can_update())
	if local_ai_mode and battle_active and is_instance_valid(local_model):
		local_ai.update(local_model, delta)
		local_model.tick(delta)
		_on_combat_events(local_model.drain_combat_events())
		_on_snapshot(local_model.snapshot())
	if smoke_mode or ai_smoke_mode:
		smoke_elapsed += delta
		if smoke_elapsed > 45.0:
			printerr("SMOKE_CLIENT_TIMEOUT")
			get_tree().quit(2)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		battle_view.mouse_position = event.position - battle_view.get_global_rect().position
		battle_view.queue_redraw()
		return
	if event is InputEventScreenTouch and not event.pressed and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		var local_position: Vector2 = event.position - battle_view.get_global_rect().position
		if Rect2(Vector2.ZERO, battle_view.size).has_point(local_position):
			_on_battlefield_clicked(local_position.x / max(battle_view.size.x, 1.0) * 1280.0)
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		_set_fullscreen(not bool(save_data.settings.fullscreen))
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and battle_active and is_instance_valid(battle_view) and not battle_view.selected_structure.is_empty():
		battle_view.selected_structure = ""
		battle_view.queue_redraw()
		_show_placement_status("건설을 취소했습니다.")
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
	for child in get_children():
		if child != network and child != updater and child != bgm_player:
			child.queue_free()
	battle_view = null
	status_label = null
	result_overlay = null
	stats_overlay = null
	placement_status_label = null
	structure_count_label = null
	connect_button_ref = null
	join_button_ref = null
	room_code_input = null
	placement_pending = false
	placement_message_serial += 1

func _show_placement_status(message: String, duration: float = 2.5) -> void:
	if not is_instance_valid(placement_status_label):
		return
	placement_message_serial += 1
	var serial := placement_message_serial
	placement_status_label.text = message
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
		return "0.4.7"
	var data = JSON.parse_string(file.get_as_text())
	return String(data.get("version", "0.4.7")) if data is Dictionary else "0.4.7"

func _active_preset() -> Dictionary:
	return save_data.deck_presets[clampi(int(save_data.last_deck), 0, 2)]

func _apply_settings() -> void:
	var settings: Dictionary = save_data.settings
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
	bg.color = Color("#0e1421")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	return bg

func _build_connect_screen(message: String = "") -> void:
	battle_active = false
	result_shown = false
	_clear_screen()
	root_background = _make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_background.add_child(backdrop)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 674)
	panel.position = Vector2(300, 23)
	root_background.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#0f1119")
	style.border_color = Color(1.0, 1.0, 1.0, 0.10)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 22
	style.corner_radius_top_right = 22
	style.corner_radius_bottom_left = 22
	style.corner_radius_bottom_right = 22
	style.content_margin_left = 48
	style.content_margin_right = 48
	style.content_margin_top = 20
	style.content_margin_bottom = 18
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	var badge := Label.new()
	badge.text = "  ✦  BATTLEFIELD PROTOCOL  ·  v%s  " % build_version()
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("#8f98ad"))
	column.add_child(badge)
	var title := Label.new()
	title.text = "CAT  WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "자동 전투  ×  전장 개조  ×  실시간 전략"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color("#858da0"))
	column.add_child(subtitle)
	var divider := HSeparator.new()
	divider.modulate = Color(1.0, 1.0, 1.0, 0.10)
	column.add_child(divider)
	var online_label := Label.new()
	online_label.text = "온라인 아레나 · ROOM CODE"
	online_label.add_theme_font_size_override("font_size", 12)
	online_label.add_theme_color_override("font_color", Color("#6f7890"))
	column.add_child(online_label)

	var endpoint_label := Label.new()
	endpoint_label.text = "공식 서버  ·  %s:%d" % [OFFICIAL_SERVER_ADDRESS, OFFICIAL_SERVER_PORT]
	endpoint_label.custom_minimum_size = Vector2(0, 48)
	endpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	endpoint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	endpoint_label.add_theme_font_size_override("font_size", 16)
	endpoint_label.add_theme_color_override("font_color", Color("#a7afc0"))
	column.add_child(endpoint_label)
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 8)
	column.add_child(room_row)
	var create_button := _styled_button("방 만들기", Color("#5e6ad2"), true)
	connect_button_ref = create_button
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_button.pressed.connect(func(): _connect_for_room("create"))
	room_row.add_child(create_button)
	room_code_input = LineEdit.new()
	room_code_input.name = "RoomCodeInput"
	room_code_input.placeholder_text = "방 코드 6자리"
	room_code_input.max_length = NetworkController.ROOM_CODE_LENGTH
	room_code_input.custom_minimum_size = Vector2(190, 50)
	room_code_input.text_changed.connect(func(value): room_code_input.text = value.to_upper())
	room_row.add_child(room_code_input)
	var join_button := _styled_button("코드로 참가", Color("#3d8f83"), false)
	join_button_ref = join_button
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.pressed.connect(func(): _connect_for_room("join", room_code_input.text))
	room_row.add_child(join_button)
	var or_label := Label.new()
	or_label.text = "──────────────   또는   ──────────────"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_color_override("font_color", Color("#454b5a"))
	or_label.add_theme_font_size_override("font_size", 12)
	column.add_child(or_label)
	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 8)
	column.add_child(ai_row)
	var campaign_button := _styled_button("AI 캠페인", Color("#8b5cf6"), false)
	campaign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_button.pressed.connect(_build_ai_stage_screen.bind(true))
	ai_row.add_child(campaign_button)
	var practice_button := _styled_button("AI 연습", Color("#6d5bd0"), false)
	practice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_button.pressed.connect(_build_ai_stage_screen.bind(false))
	ai_row.add_child(practice_button)
	var management_row := HBoxContainer.new()
	management_row.add_theme_constant_override("separation", 8)
	column.add_child(management_row)
	for entry in [["덱 편성", _build_deck_screen], ["전적", _build_records_screen], ["설정", _build_settings_screen], ["종료", _quit_game]]:
		var menu_button := _styled_button(entry[0], Color("#3d8f83"), false)
		menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_button.pressed.connect(entry[1])
		management_row.add_child(menu_button)
	status_label = Label.new()
	status_label.text = message if not message.is_empty() else "선택 덱: %s  ·  온라인은 전용 서버 권한형  ·  AI는 완전 오프라인" % _active_preset().name
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#747d91"))
	column.add_child(status_label)
	updater.set_safe_to_update(true)
	updater.check_for_update()

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
	var panel_style := _panel_style(Color("#0f1119"), Color(0.55, 0.36, 0.96, 0.55), 20)
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
	title.text = "AI 캠페인" if campaign_mode else "AI 연습"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	stage_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "승리하여 다음 단계를 해금하고 별과 기록을 남기세요." if campaign_mode else "진행도와 무관하게 원하는 AI 단계와 즉시 대전합니다."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	stage_column.add_child(subtitle)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	stage_column.add_child(grid)
	for stage in range(ServerAI.MIN_STAGE, ServerAI.MAX_STAGE + 1):
		var intensity := float(stage - 1) / 9.0
		var color := Color("#5b8cff").lerp(Color("#ff627d"), intensity)
		var record: Dictionary = save_data.campaign_records[stage - 1]
		var stars := "★".repeat(int(record.best_stars)) + "☆".repeat(3 - int(record.best_stars))
		var locked := campaign_mode and stage > int(save_data.campaign_unlocked)
		var stage_button := _styled_button(
			"%02d  %s  %s\n%s" % [stage, ServerAI.stage_name(stage), "🔒" if locked else stars, ServerAI.stage_summary(stage)],
			color,
			stage == current_ai_stage
		)
		stage_button.custom_minimum_size = Vector2(174, 148)
		stage_button.add_theme_font_size_override("font_size", 14)
		stage_button.disabled = locked
		stage_button.pressed.connect(_start_local_ai_battle.bind(stage))
		grid.add_child(stage_button)
	var back_button := _styled_button("메인 화면으로", Color("#596174"), false)
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
	var style := _panel_style(Color("#0f1119"), Color(0.36, 0.55, 0.70, 0.5), 18)
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
	title.text = title_text
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = subtitle_text
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	column.add_child(subtitle)
	return column

func _build_deck_screen(preset_index: int = -1) -> void:
	var index := int(save_data.last_deck) if preset_index < 0 else clampi(preset_index, 0, 2)
	var column := _submenu("덱 편성", "유닛 4종 중 3종, 구조물 4종 중 3종을 선택합니다. 온라인에서도 서버가 이 덱을 검증합니다.")
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab_index in 3:
		var tab := _styled_button(String(save_data.deck_presets[tab_index].name), Color("#5e6ad2"), tab_index == index)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(_build_deck_screen.bind(tab_index))
		tabs.add_child(tab)
	var name_edit := LineEdit.new()
	name_edit.text = String(save_data.deck_presets[index].name)
	name_edit.placeholder_text = "프리셋 이름"
	column.add_child(name_edit)
	var selected: Dictionary = save_data.deck_presets[index]
	var unit_buttons := {}
	var structure_buttons := {}
	var unit_row := HBoxContainer.new()
	unit_row.add_theme_constant_override("separation", 8)
	column.add_child(unit_row)
	var unit_names := {"shield": "탱커", "swordsman": "검사", "archer": "궁수", "healer": "마법사"}
	for kind in BattleModel.UNIT_STATS.keys():
		var stats: Dictionary = BattleModel.UNIT_STATS[kind]
		var role := "회복/지원" if kind == "healer" else "원거리" if kind == "archer" else "방어" if kind == "shield" else "근접 공격"
		var card_text := "%s\n비용 %d · HP %d · 공격 %d\nDPS %.1f · 사거리 %d · %s" % [unit_names[kind], int(stats.cost), int(stats.hp), int(stats.damage), float(stats.damage) / float(stats.interval), int(stats.range), role]
		var card := _styled_button(card_text, Color("#5b8cff"), false)
		_configure_deck_card(card, card_text, Color("#5b8cff"), selected.units.has(kind))
		card.custom_minimum_size = Vector2(240, 105)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unit_buttons[kind] = card
		unit_row.add_child(card)
	var structure_grid := GridContainer.new()
	structure_grid.columns = 5
	structure_grid.add_theme_constant_override("h_separation", 8)
	column.add_child(structure_grid)
	var structure_names := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
	var roles := {"wall": "뒤 대상을 차폐 · 최대 2", "swamp": "반경 95 · 이동 45%", "turret": "사거리 240 · 최대 1", "generator": "후방 전용 · 초당 +1"}
	for kind in BattleModel.STRUCTURE_STATS.keys():
		var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
		var card_text := "%s\n비용 %d · HP %d\n%s" % [structure_names[kind], int(stats.cost), int(stats.hp), roles[kind]]
		var card := _styled_button(card_text, Color("#3d8f83"), false)
		_configure_deck_card(card, card_text, Color("#3d8f83"), selected.structures.has(kind))
		card.custom_minimum_size = Vector2(190, 92)
		structure_buttons[kind] = card
		structure_grid.add_child(card)
	var status := Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_color_override("font_color", Color("#ff8a96"))
	column.add_child(status)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	var save_button := _styled_button("덱 저장 및 사용", Color("#5e6ad2"), true)
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(func():
		var selected_units: Array = []
		var selected_structures: Array = []
		for kind in unit_buttons:
			if unit_buttons[kind].button_pressed: selected_units.append(kind)
		for kind in structure_buttons:
			if structure_buttons[kind].button_pressed: selected_structures.append(kind)
		if not NetworkController.validate_deck_payload(selected_units, selected_structures):
			status.text = "유닛과 구조물을 각각 정확히 3종 선택해야 합니다."
			return
		save_data.deck_presets[index] = {"name": name_edit.text.strip_edges().left(20) if not name_edit.text.strip_edges().is_empty() else "덱 %d" % (index + 1), "units": selected_units, "structures": selected_structures}
		save_data.last_deck = index
		SaveData.save_data(save_data)
		_build_connect_screen("덱을 저장했습니다.")
	)
	actions.add_child(save_button)
	var back := _styled_button("취소", Color("#697386"), false)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_build_connect_screen)
	actions.add_child(back)

func _build_records_screen() -> void:
	var column := _submenu("개인 전적", "user:// 로컬 기록이며 공식 랭킹이나 경쟁 기록으로 사용하지 않습니다.")
	var stats: Dictionary = save_data.stats
	var online_rate := 0.0 if int(stats.online_completed) == 0 else float(stats.online_wins) / float(stats.online_completed) * 100.0
	var summary := Label.new()
	summary.text = "AI  ·  경기 %d  /  승 %d  /  패 %d  /  최고 캠페인 %02d  /  별 %d\n\n온라인  ·  완료 %d  /  승 %d  /  패 %d  /  무 %d  /  중단 %d  /  승률 %.1f%%" % [stats.ai_matches, stats.ai_wins, stats.ai_losses, stats.highest_campaign, stats.total_stars, stats.online_completed, stats.online_wins, stats.online_losses, stats.online_draws, stats.online_interrupted, online_rate]
	summary.add_theme_font_size_override("font_size", 20)
	column.add_child(summary)
	var records := Label.new()
	var lines: Array = []
	for stage in 10:
		var record: Dictionary = save_data.campaign_records[stage]
		lines.append("%02d %-5s  %s  도전 %d / 승 %d  최단 %.1f초  최고 기지 HP %d" % [stage + 1, ServerAI.stage_name(stage + 1), "★".repeat(record.best_stars) + "☆".repeat(3 - record.best_stars), record.attempts, record.wins, record.fastest_win, int(record.best_base_hp)])
	records.text = "\n".join(lines)
	records.add_theme_font_size_override("font_size", 16)
	column.add_child(records)
	var back := _styled_button("메인 화면으로", Color("#697386"), false)
	back.pressed.connect(_build_connect_screen)
	column.add_child(back)

func _build_settings_screen() -> void:
	var column := _submenu("설정", "오디오 · 화면 · 전투 연출 설정은 즉시 저장됩니다.")
	var settings: Dictionary = save_data.settings
	var controls := GridContainer.new()
	controls.columns = 2
	column.add_child(controls)
	var master := HSlider.new(); master.name = "MasterVolumeSlider"; master.min_value = 0.0; master.max_value = 1.0; master.step = 0.05; master.value = settings.master_volume
	var bgm := HSlider.new(); bgm.name = "BGMVolumeSlider"; bgm.min_value = 0.0; bgm.max_value = 1.0; bgm.step = 0.05; bgm.value = settings.bgm_volume
	var sfx := HSlider.new(); sfx.name = "SFXVolumeSlider"; sfx.min_value = 0.0; sfx.max_value = 1.0; sfx.step = 0.05; sfx.value = settings.sfx_volume
	master.value_changed.connect(_preview_bus_volume.bind("Master"))
	bgm.value_changed.connect(_preview_bus_volume.bind("BGM"))
	sfx.value_changed.connect(_preview_bus_volume.bind("SFX"))
	for pair in [["전체 음량", master], ["BGM 음량", bgm], ["효과음 음량", sfx]]:
		var label := Label.new(); label.text = pair[0]; controls.add_child(label); pair[1].custom_minimum_size.x = 600; controls.add_child(pair[1])
	var muted := CheckButton.new(); muted.text = "음소거"; muted.button_pressed = settings.muted; muted.toggled.connect(func(enabled): AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), enabled)); column.add_child(muted)
	var fullscreen := CheckButton.new(); fullscreen.name = "FullscreenToggle"; fullscreen.text = "전체화면 (F11)"; fullscreen.button_pressed = settings.fullscreen; column.add_child(fullscreen)
	var vsync := CheckButton.new(); vsync.text = "VSync"; vsync.button_pressed = settings.vsync; column.add_child(vsync)
	var window_size := OptionButton.new()
	for option in ["1280x720", "1600x900", "1920x1080"]: window_size.add_item(option)
	window_size.select(max(0, ["1280x720", "1600x900", "1920x1080"].find(String(settings.window_size))))
	column.add_child(window_size)
	var fps_limit := OptionButton.new()
	for option in [30, 60, 120, 144, 240]: fps_limit.add_item("FPS 제한 %d" % option, option)
	var fps_options := [30, 60, 120, 144, 240]
	fps_limit.select(max(0, fps_options.find(int(settings.fps_limit))))
	column.add_child(fps_limit)
	var damage_numbers := CheckButton.new(); damage_numbers.text = "피해/회복 숫자"; damage_numbers.button_pressed = settings.damage_numbers; column.add_child(damage_numbers)
	var shake := CheckButton.new(); shake.text = "화면 흔들림"; shake.button_pressed = settings.screen_shake; column.add_child(shake)
	var effects := CheckButton.new(); effects.text = "전투 효과"; effects.button_pressed = settings.battle_effects; column.add_child(effects)
	var intensity := HSlider.new(); intensity.min_value = 0.2; intensity.max_value = 1.0; intensity.step = 0.1; intensity.value = settings.effect_intensity; intensity.tooltip_text = "효과 강도"; column.add_child(intensity)
	var save_button := _styled_button("설정 저장", Color("#5e6ad2"), true)
	save_button.pressed.connect(func():
		settings.master_volume = master.value; settings.bgm_volume = bgm.value; settings.sfx_volume = sfx.value
		settings.muted = muted.button_pressed; settings.fullscreen = fullscreen.button_pressed; settings.vsync = vsync.button_pressed
		settings.window_size = window_size.get_item_text(window_size.selected); settings.fps_limit = fps_limit.get_item_id(fps_limit.selected)
		settings.damage_numbers = damage_numbers.button_pressed; settings.screen_shake = shake.button_pressed; settings.battle_effects = effects.button_pressed; settings.effect_intensity = intensity.value
		SaveData.save_data(save_data); _apply_settings()
		_build_connect_screen("설정을 저장했습니다.")
	)
	column.add_child(save_button)
	var back := _styled_button("취소", Color("#697386"), false); back.pressed.connect(func(): _apply_settings(); _build_connect_screen()); column.add_child(back)

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
	var marker := "✓ 선택됨" if card.button_pressed else "○ 선택 가능"
	card.text = marker + "\n" + String(card.get_meta("deck_base_text", ""))

func _styled_button(text_value: String, color: Color, filled: bool = false) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(120, 50)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("#f5f7fb"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = color if filled else Color("#171a24")
	normal.border_color = color.lightened(0.08) if filled else Color(color.r, color.g, color.b, 0.62)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(8)
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate()
	hover.bg_color = color.lightened(0.10) if filled else Color("#202536")
	hover.border_color = color.lightened(0.18)
	var pressed := hover.duplicate()
	pressed.bg_color = color.darkened(0.12) if filled else Color("#131620")
	var disabled := normal.duplicate()
	disabled.bg_color = Color("#11131a")
	disabled.border_color = Color(1.0, 1.0, 1.0, 0.05)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	return button

func _on_connection_status(text: String) -> void:
	if smoke_mode:
		print("SMOKE_STATUS %s" % text)
	if is_instance_valid(status_label):
		status_label.text = text
	if text.contains("실패") or text.contains("끊어졌"):
		_set_room_controls_disabled(false)

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
		_on_connection_status("올바른 방 코드 6자리를 입력하세요.")
		return
	_set_room_controls_disabled(true)
	var preset := _active_preset()
	network.set_client_deck(preset.units, preset.structures)
	network.connect_to_candidates(official_connection_candidates(IP.get_local_addresses()), OFFICIAL_SERVER_PORT)

func _on_room_created(code: String) -> void:
	_on_connection_status("방 코드 %s · 상대가 참가하기를 기다리는 중..." % code)

func _on_room_join_failed(error: String) -> void:
	network.disconnect_from_server()
	_on_connection_status(error)
	_set_room_controls_disabled(false)

func _on_match_found(side: int) -> void:
	local_ai_mode = false
	own_side = side
	_build_battle_screen()
	if smoke_mode:
		print("CLIENT_MATCH_FOUND side=%d" % side)
		network.send_spawn("swordsman")

func _start_local_ai_battle(stage: int = 1) -> void:
	local_ai_mode = true
	result_recorded = false
	current_ai_stage = clampi(stage, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
	own_side = 0
	local_model = BattleModel.new()
	var preset := _active_preset()
	local_model.configure_deck(0, preset.units, preset.structures)
	var ai_units := ["shield", "archer", "healer"] if current_ai_stage >= 5 else ["swordsman", "shield", "archer"]
	var ai_structures := ["wall", "swamp", "turret"] if current_ai_stage >= 6 else ["wall", "swamp", "generator"]
	local_model.configure_deck(1, ai_units, ai_structures)
	local_model.resources[1] = min(BattleModel.MAX_RESOURCE, 35.0 + float(current_ai_stage) * 10.0)
	local_model.base_hp[1] = 300.0 + float(current_ai_stage) * 20.0
	local_ai = ServerAI.new(1, current_ai_stage)
	_build_battle_screen()
	if ai_smoke_mode:
		local_model.spawn_unit(0, String(preset.units[0]))
	_on_snapshot(local_model.snapshot())

func _build_battle_screen() -> void:
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
	_create_hp_card(top, Vector2(18, 12), 0)
	_create_hp_card(top, Vector2(842, 12), 1)

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
	mode_label.text = "AI STAGE %02d" % current_ai_stage if local_ai_mode else "ONLINE MATCH"
	mode_label.position = Vector2(0, 39)
	mode_label.size = Vector2(220, 18)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.add_theme_color_override("font_color", Color("#747d91"))
	timer_inner.add_child(mode_label)
	var stats_button := _styled_button("유닛 스탯", Color("#3d8f83"), false)
	stats_button.name = "UnitStatsButton"
	stats_button.position = Vector2(758, 18)
	stats_button.size = Vector2(80, 52)
	stats_button.add_theme_font_size_override("font_size", 12)
	stats_button.pressed.connect(_toggle_stats_panel)
	top.add_child(stats_button)
	if local_ai_mode:
		var exit_button := _styled_button("대전 나가기", Color("#8f4652"), false)
		exit_button.name = "ExitAIBattleButton"
		exit_button.position = Vector2(430, 18)
		exit_button.size = Vector2(92, 52)
		exit_button.add_theme_font_size_override("font_size", 12)
		exit_button.pressed.connect(_exit_ai_battle)
		top.add_child(exit_button)

	battle_view = BattleView.new()
	battle_view.position = Vector2(0, 88)
	battle_view.size = Vector2(1280, 492)
	battle_view.own_side = own_side
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
	structure_count_label.text = "구조물 0 / 3"
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
	var own_color := Color("#5b8cff") if own_side == 0 else Color("#ff627d")
	resource_card.add_theme_stylebox_override("panel", _panel_style(Color("#141720"), Color(own_color.r, own_color.g, own_color.b, 0.48), 10))
	controls.add_child(resource_card)
	var resource_inner := Control.new()
	resource_inner.custom_minimum_size = Vector2(174, 108)
	resource_card.add_child(resource_inner)
	var resource_caption := Label.new()
	resource_caption.text = "ENERGY"
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
	side_label.text = "●  %s 진영" % ("BLUE" if own_side == 0 else "RED")
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
	var preset := _active_preset()
	var unit_names := {"shield": "탱커", "healer": "마법사", "archer": "궁수", "swordsman": "검사"}
	var unit_colors := {"shield": Color("#5b8cff"), "healer": Color("#d8b85a"), "archer": Color("#8b72df"), "swordsman": Color("#d56b5f")}
	for kind in preset.units:
		_add_spawn_button(row, unit_names[kind], kind, unit_colors[kind])
	var separator := VSeparator.new()
	separator.modulate = Color(1.0, 1.0, 1.0, 0.10)
	separator.custom_minimum_size.x = 5
	row.add_child(separator)
	var structure_names := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
	var structure_colors := {"wall": Color("#7c879d"), "swamp": Color("#906bd1"), "turret": Color("#d56b5f"), "generator": Color("#3d8f83")}
	for kind in preset.structures:
		var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
		_add_structure_button(row, "%s\n%d 자원" % [structure_names[kind], int(stats.cost)], kind, structure_colors[kind])

func _panel_style(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	return style

func _create_hp_card(parent: Control, position_value: Vector2, side: int) -> void:
	var card := PanelContainer.new()
	card.position = position_value
	card.size = Vector2(420, 64)
	var color := Color("#5b8cff") if side == 0 else Color("#ff627d")
	card.add_theme_stylebox_override("panel", _panel_style(Color("#141720"), Color(color.r, color.g, color.b, 0.34), 10))
	parent.add_child(card)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(420, 64)
	card.add_child(inner)
	var faction := Label.new()
	faction.text = "BLUE FORTRESS" if side == 0 else "RED FORTRESS"
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
	var stats: Dictionary = BattleModel.UNIT_STATS[kind]
	var primary := "회복 %d" % int(stats.heal) if float(stats.get("heal", 0.0)) > 0.0 else "공격 %d" % int(stats.damage)
	var button := _styled_button("%s  ·  %d\n체력 %d  ·  %s" % [title, int(stats.cost), int(stats.hp), primary], color)
	button.tooltip_text = BattleModel.unit_stat_summary(kind)
	button.custom_minimum_size = Vector2(136, 102)
	button.pressed.connect(func():
		if local_ai_mode:
			local_model.spawn_unit(own_side, kind)
		else:
			network.send_spawn(kind)
	)
	row.add_child(button)

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
	title.text = "유닛 상세 스탯"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	content.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "현재 서버 전투 수치 · DPS/HPS는 1회 수치 ÷ 공격 간격"
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	content.add_child(subtitle)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	var names := {"shield": "탱커", "healer": "마법사", "archer": "궁수", "swordsman": "검사"}
	for kind in ["shield", "healer", "archer", "swordsman"]:
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
		label.text = "%s\n%s" % [names[kind], BattleModel.unit_stat_summary(kind)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("#dce1ec"))
		card_margin.add_child(label)
	var world_stats := Label.new()
	world_stats.text = BattleModel.battle_stat_summary()
	world_stats.add_theme_font_size_override("font_size", 13)
	world_stats.add_theme_color_override("font_color", Color("#9ba5b8"))
	content.add_child(world_stats)
	var close := _styled_button("닫기", Color("#3d8f83"), true)
	close.custom_minimum_size = Vector2(160, 44)
	close.pressed.connect(_dismiss_stats_panel)
	content.add_child(close)

func _add_structure_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var button := _styled_button(title, color)
	button.custom_minimum_size = Vector2(136, 102)
	button.pressed.connect(func():
		if is_instance_valid(battle_view):
			battle_view.selected_structure = kind
	)
	row.add_child(button)

func _on_battlefield_clicked(world_x: float) -> void:
	if not is_instance_valid(battle_view) or battle_view.selected_structure.is_empty() or placement_pending:
		return
	var kind := battle_view.selected_structure
	var error := local_model.structure_placement_error(own_side, kind, world_x) if local_ai_mode else battle_view.placement_error(kind, world_x)
	if not error.is_empty():
		_show_placement_status(error)
		return
	if local_ai_mode:
		if local_model.place_structure(own_side, kind, world_x):
			_show_placement_status("건설 완료")
			battle_view.selected_structure = ""
	else:
		placement_pending = true
		network.send_structure(kind, world_x)
		_show_placement_status("서버 확인 중...", 0.0)

func _on_structure_placement_result(success: bool, error: String) -> void:
	placement_pending = false
	if not battle_active or local_ai_mode or not is_instance_valid(battle_view):
		return
	if success:
		battle_view.selected_structure = ""
		battle_view.queue_redraw()
	_show_placement_status("건설 완료" if success else (error if not error.is_empty() else "구조물을 설치하지 못했습니다."))

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
		structure_count_label.text = "구조물 %d / 3" % own_structures
	resource_label.text = "%d / 150" % int(resources[own_side])
	blue_hp_bar.value = float(bases[0])
	red_hp_bar.value = float(bases[1])
	blue_hp_label.text = "%d / 500" % int(bases[0])
	red_hp_label.text = "%d / 500" % int(bases[1])
	var elapsed_seconds := int(data.get("elapsed", 0.0))
	timer_label.text = "%02d:%02d" % [elapsed_seconds / 60, elapsed_seconds % 60]
	var winner: int = int(data.get("winner", -1))
	if winner != -1 and not result_shown:
		_show_result(winner)
	elif winner == -1 and result_shown:
		_dismiss_result_overlay()
		result_recorded = false
		updater.set_safe_to_update(false)

func _on_combat_events(events: Array) -> void:
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
	result_shown = true
	updater.set_safe_to_update(true)
	updater.check_for_update()
	var awarded_stars := 0
	if not result_recorded:
		result_recorded = true
		if local_ai_mode:
			if campaign_mode:
				awarded_stars = SaveData.record_campaign(save_data, current_ai_stage, winner == own_side, float(current_snapshot.elapsed), float(current_snapshot.base_hp[own_side]))
			else:
				save_data.stats.ai_matches += 1
				save_data.stats.ai_wins += 1 if winner == own_side else 0
				save_data.stats.ai_losses += 0 if winner == own_side else 1
		else:
			save_data.stats.online_completed += 1
			save_data.stats.online_wins += 1 if winner == own_side else 0
			save_data.stats.online_losses += 1 if winner != own_side and winner != 2 else 0
			save_data.stats.online_draws += 1 if winner == 2 else 0
		SaveData.save_data(save_data)
	var overlay := PanelContainer.new()
	overlay.name = "ResultOverlay"
	result_overlay = overlay
	overlay.position = Vector2(350, 190)
	overlay.size = Vector2(580, 330)
	var result_color := Color("#f6c85f") if winner == own_side else Color("#8f98ad")
	var overlay_style := _panel_style(Color("#0f1119"), Color(result_color.r, result_color.g, result_color.b, 0.55), 18)
	overlay_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	overlay_style.shadow_size = 28
	overlay.add_theme_stylebox_override("panel", overlay_style)
	root_background.add_child(overlay)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(580, 330)
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
	result.text = "무승부" if winner == 2 else ("승리" if winner == own_side else "패배")
	result.position = Vector2(0, 64)
	result.size = Vector2(580, 82)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 52)
	result.add_theme_color_override("font_color", result_color)
	inner.add_child(result)
	var advances := local_ai_mode and campaign_mode and winner == own_side and current_ai_stage < ServerAI.MAX_STAGE
	var note := Label.new()
	if local_ai_mode:
		note.text = "%02d단계 승리 · 최고 ★ %d · 다음 단계 해금" % [current_ai_stage, awarded_stars] if campaign_mode and winner == own_side else "%02d단계 결과가 개인 전적에 저장되었습니다." % current_ai_stage
	else:
		note.text = "두 플레이어가 모두 준비하면 다시 시작합니다."
	note.position = Vector2(0, 157)
	note.size = Vector2(580, 34)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(note)
	var rematch_text := "다음 단계" if advances else ("다시 도전" if local_ai_mode else "재경기 준비")
	var rematch := _styled_button(rematch_text, Color("#5e6ad2"), true)
	rematch.position = Vector2(65, 218)
	rematch.size = Vector2(215, 58)
	rematch.pressed.connect(func():
		rematch.disabled = true
		if local_ai_mode:
			_start_local_ai_battle(current_ai_stage + 1 if advances else current_ai_stage)
		else:
			rematch.text = "상대 준비 대기 중"
			network.send_rematch()
	)
	inner.add_child(rematch)
	var back := _styled_button("단계 선택" if local_ai_mode else "이전 화면으로", Color("#697386"), false)
	back.name = "BackToMenuButton"
	back.position = Vector2(300, 218)
	back.size = Vector2(215, 58)
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
	title.text = "새 버전 %s" % version
	title.position = Vector2(0, 66)
	title.size = Vector2(600, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	inner.add_child(title)
	update_message_label = Label.new()
	update_message_label.text = "업데이트를 준비하고 있습니다..."
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
	update_note_label.text = "경기 중에는 설치하지 않으며, 완료 후 게임이 자동으로 재시작됩니다."
	update_note_label.position = Vector2(25, 232)
	update_note_label.size = Vector2(550, 36)
	update_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	update_note_label.add_theme_font_size_override("font_size", 12)
	update_note_label.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(update_note_label)

func _show_android_apk_notice() -> void:
	_on_update_started(build_version())
	if not is_instance_valid(update_overlay):
		return
	update_message_label.text = "APK 업데이트가 필요합니다."
	update_progress_bar.visible = false
	update_note_label.text = "새 APK를 설치한 뒤 게임을 다시 실행해 주세요."
	var download_button := _styled_button("APK 다운로드", Color("#7170ff"), true)
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
		update_message_label.text = message + "\n10초 후 자동으로 다시 시도합니다."
	if is_instance_valid(update_progress_bar):
		update_progress_bar.value = 0.0

func _on_opponent_left() -> void:
	if battle_active and not result_shown and not save_data.is_empty():
		save_data.stats.online_interrupted += 1
		SaveData.save_data(save_data)
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_build_connect_screen("상대가 연결을 종료했습니다. 다시 접속해 주세요.")
