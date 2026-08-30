extends Control

const OFFICIAL_SERVER_ADDRESS := "ruellyya.kr"
const OFFICIAL_SERVER_PORT := 7777

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
var root_background: ColorRect
var smoke_mode := false
var smoke_elapsed := 0.0
var connect_button_ref: Button
var local_ai_mode := false
var ai_smoke_mode := false
var local_model: BattleModel
var local_ai: ServerAI
var running_as_server := false
var update_overlay: Control
var update_message_label: Label
var update_progress_bar: ProgressBar
var server_state_dir := ""
var server_status_accumulator := 0.0
var server_draining := false

func _ready() -> void:
	network.connection_status.connect(_on_connection_status)
	network.match_found.connect(_on_match_found)
	network.snapshot_received.connect(_on_snapshot)
	network.opponent_disconnected.connect(_on_opponent_left)
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
	_build_connect_screen()
	if args.has("--offline-ai") or ai_smoke_mode:
		_start_local_ai_battle()
		return
	var auto_address := _arg_string(args, "--connect=", "")
	if smoke_connect_allowed(smoke_mode, auto_address):
		network.connect_to_server(auto_address, _arg_int(args, "--port=", NetworkController.DEFAULT_PORT))

static func smoke_connect_allowed(is_smoke: bool, address: String) -> bool:
	return is_smoke and (address == "127.0.0.1" or address == "localhost" or address == "::1")

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
		_on_snapshot(local_model.snapshot())
	if smoke_mode or ai_smoke_mode:
		smoke_elapsed += delta
		if smoke_elapsed > 15.0:
			printerr("SMOKE_CLIENT_TIMEOUT")
			get_tree().quit(2)

func _server_can_update() -> bool:
	for model in network.models.values():
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
		if child != network and child != updater:
			child.queue_free()
	battle_view = null
	status_label = null

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
	panel.custom_minimum_size = Vector2(600, 570)
	panel.position = Vector2(340, 70)
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
	style.content_margin_top = 32
	style.content_margin_bottom = 30
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	style.shadow_size = 24
	panel.add_theme_stylebox_override("panel", style)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var badge := Label.new()
	badge.text = "  ✦  BATTLEFIELD PROTOCOL  ·  v0.2  "
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("#8f98ad"))
	column.add_child(badge)
	var title := Label.new()
	title.text = "CAT  WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 50)
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
	online_label.text = "ONLINE ARENA"
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
	var connect_button := _styled_button("온라인 아레나 입장", Color("#5e6ad2"), true)
	connect_button_ref = connect_button
	connect_button.pressed.connect(func():
		connect_button.disabled = true
		network.connect_to_server(OFFICIAL_SERVER_ADDRESS, OFFICIAL_SERVER_PORT)
	)
	column.add_child(connect_button)
	var or_label := Label.new()
	or_label.text = "──────────────   또는   ──────────────"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_color_override("font_color", Color("#454b5a"))
	or_label.add_theme_font_size_override("font_size", 12)
	column.add_child(or_label)
	var ai_button := _styled_button("AI 훈련장  ·  오프라인 즉시 시작", Color("#8b5cf6"), false)
	ai_button.pressed.connect(_start_local_ai_battle)
	column.add_child(ai_button)
	status_label = Label.new()
	status_label.text = message if not message.is_empty() else "온라인은 전용 서버 매칭  ·  AI 훈련장은 인터넷 없이 작동합니다"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", Color("#747d91"))
	column.add_child(status_label)
	updater.set_safe_to_update(true)
	updater.check_for_update()

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
	if is_instance_valid(status_label):
		status_label.text = text
	if (text.contains("실패") or text.contains("끊어졌")) and is_instance_valid(connect_button_ref):
		connect_button_ref.disabled = false

func _on_match_found(side: int) -> void:
	local_ai_mode = false
	own_side = side
	_build_battle_screen()
	if smoke_mode:
		print("CLIENT_MATCH_FOUND side=%d" % side)
		network.send_spawn("swordsman")

func _start_local_ai_battle() -> void:
	local_ai_mode = true
	own_side = 0
	local_model = BattleModel.new()
	local_ai = ServerAI.new(1)
	_build_battle_screen()
	if ai_smoke_mode:
		local_model.spawn_unit(0, "swordsman")
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
	mode_label.text = "AI TRAINING" if local_ai_mode else "ONLINE MATCH"
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
	battle_view.battlefield_clicked.connect(_on_battlefield_clicked)
	root_background.add_child(battle_view)

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
	_add_spawn_button(row, "탱커\n40 자원", "shield", Color("#5b8cff"))
	_add_spawn_button(row, "힐러\n45 자원", "healer", Color("#d8b85a"))
	_add_spawn_button(row, "궁수\n45 자원", "archer", Color("#8b72df"))
	_add_spawn_button(row, "검사\n25 자원", "swordsman", Color("#d56b5f"))
	var separator := VSeparator.new()
	separator.modulate = Color(1.0, 1.0, 1.0, 0.10)
	separator.custom_minimum_size.x = 5
	row.add_child(separator)
	_add_structure_button(row, "방벽\n35 자원", "wall", Color("#7c879d"))
	_add_structure_button(row, "점프대\n30 자원", "jump_pad", Color("#e0a63d"))
	_add_structure_button(row, "늪지대\n30 자원", "swamp", Color("#906bd1"))

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
	var button := _styled_button(title, color)
	button.custom_minimum_size = Vector2(136, 102)
	button.pressed.connect(func():
		if local_ai_mode:
			local_model.spawn_unit(own_side, kind)
		else:
			network.send_spawn(kind)
	)
	row.add_child(button)

func _add_structure_button(row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var button := _styled_button(title, color)
	button.custom_minimum_size = Vector2(136, 102)
	button.pressed.connect(func():
		if is_instance_valid(battle_view):
			battle_view.selected_structure = kind
	)
	row.add_child(button)

func _on_battlefield_clicked(world_x: float) -> void:
	if not is_instance_valid(battle_view) or battle_view.selected_structure.is_empty():
		return
	if local_ai_mode:
		local_model.place_structure(own_side, battle_view.selected_structure, world_x)
	else:
		network.send_structure(battle_view.selected_structure, world_x)
	battle_view.selected_structure = ""

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
	resource_label.text = "%d / 150" % int(resources[own_side])
	blue_hp_bar.value = float(bases[0])
	red_hp_bar.value = float(bases[1])
	blue_hp_label.text = "%d / 500" % int(bases[0])
	red_hp_label.text = "%d / 500" % int(bases[1])
	var remaining: int = max(0, int(BattleModel.MATCH_LIMIT - float(data.get("elapsed", 0.0))))
	timer_label.text = "%02d:%02d" % [remaining / 60, remaining % 60]
	var winner: int = int(data.get("winner", -1))
	if winner != -1 and not result_shown:
		_show_result(winner)
	elif winner == -1 and result_shown:
		result_shown = false
		updater.set_safe_to_update(false)

func _show_result(winner: int) -> void:
	result_shown = true
	updater.set_safe_to_update(true)
	updater.check_for_update()
	var overlay := PanelContainer.new()
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
	var note := Label.new()
	note.text = "누르면 즉시 새로운 전투를 시작합니다." if local_ai_mode else "두 플레이어가 모두 준비하면 다시 시작합니다."
	note.position = Vector2(0, 157)
	note.size = Vector2(580, 34)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(note)
	var rematch := _styled_button("재경기 준비", Color("#5e6ad2"), true)
	rematch.position = Vector2(170, 218)
	rematch.size = Vector2(240, 58)
	rematch.pressed.connect(func():
		rematch.disabled = true
		if local_ai_mode:
			updater.set_safe_to_update(false)
			local_model.reset()
			local_ai = ServerAI.new(1)
			overlay.queue_free()
			result_shown = false
		else:
			rematch.text = "상대 준비 대기 중"
			network.send_rematch()
	)
	inner.add_child(rematch)

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
	var note := Label.new()
	note.text = "경기 중에는 설치하지 않으며, 완료 후 게임이 자동으로 재시작됩니다."
	note.position = Vector2(25, 232)
	note.size = Vector2(550, 36)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(note)

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
	if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_build_connect_screen("상대가 연결을 종료했습니다. 다시 접속해 주세요.")
