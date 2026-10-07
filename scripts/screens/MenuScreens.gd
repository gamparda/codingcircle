extends RefCounted
## MenuScreens: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const PatchNotes = preload("res://scripts/PatchNotes.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
const SUBMENU_FRAME := preload("res://scenes/ui/SubMenuFrame.tscn")
const PATCH_NOTES_SCREEN := preload("res://scenes/ui/PatchNotesScreen.tscn")
const RECORDS_SCREEN := preload("res://scenes/ui/RecordsScreen.tscn")

static func _add_menu_portrait(main, parent: Control, texture_path: String, position_value: Vector2, accent: Color, label_text: String) -> void:
	var frame := PanelContainer.new()
	frame.position = position_value
	frame.size = Vector2(216, 256)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame_style = main._panel_style(Color("#121c27"), Color(accent.r, accent.g, accent.b, 0.56), 6)
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

static func _build_connect_screen(main, message: String = "") -> void:
	main.multiplayer_screen = ""
	main.battle_active = false
	main.result_shown = false
	main._clear_screen()
	main.root_background = main._make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.root_background.add_child(backdrop)
	main._add_menu_portrait(main.root_background, "res://assets/units/tanker.png", Vector2(42, 232), Color("#86abff"), "탱커")
	main._add_menu_portrait(main.root_background, "res://assets/units/archer.png", Vector2(1022, 232), Color("#e5c47d"), "궁수")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	panel.position = Vector2(300, 100)
	main.root_background.add_child(panel)
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
	badge.text = "◆  전장 개조 전략   /   v%s" % main.build_version()
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

	var multiplayer_button = main._styled_button("멀티플레이",Color("#5e6ad2"),true)
	multiplayer_button.name = "MultiplayerButton"
	multiplayer_button.pressed.connect(main._open_multiplayer)
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
	var campaign_button = main._styled_button(Localization.text("AI 캠페인"), Color("#8b5cf6"), false)
	campaign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_button.pressed.connect(main._build_ai_stage_screen.bind(true))
	ai_row.add_child(campaign_button)
	var practice_button = main._styled_button(Localization.text("AI 연습"), Color("#6d5bd0"), false)
	practice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_button.pressed.connect(main._build_ai_stage_screen.bind(false))
	ai_row.add_child(practice_button)
	var management_row := HBoxContainer.new()
	management_row.add_theme_constant_override("separation", 8)
	column.add_child(management_row)
	for entry in [[Localization.text("덱 편성"), main._build_deck_screen], [Localization.text("전적"), main._build_records_screen], [Localization.text("설정"), main._build_settings_screen], [Localization.text("종료"), main._quit_game]]:
		var menu_button = main._styled_button(entry[0], Color("#3d8f83"), false)
		menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_button.pressed.connect(entry[1])
		management_row.add_child(menu_button)
	main.status_label = Label.new()
	main.status_label.text = Localization.text(message) if not message.is_empty() else "선택 덱: %s" % String(main._active_preset().name)
	main.status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.status_label.add_theme_font_size_override("font_size", 13)
	main.status_label.add_theme_color_override("font_color", Color("#747d91"))
	column.add_child(main.status_label)
	var patch_notes = main._styled_button(Localization.text("패치노트"), Color("#3d8f83"))
	patch_notes.name = "PatchNotesButton"
	patch_notes.position = Vector2(1035, 20)
	patch_notes.size = Vector2(225, 50)
	patch_notes.add_theme_font_size_override("font_size", 14)
	patch_notes.pressed.connect(main._build_patch_notes_screen)
	main.root_background.add_child(patch_notes)
	main.updater.set_safe_to_update(true)
	main.updater.check_for_update()

static func _build_ai_stage_screen(main, as_campaign: bool = false) -> void:
	main.campaign_mode = as_campaign
	main.battle_active = false
	main.result_shown = false
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	main.current_snapshot.clear()
	main.updater.set_safe_to_update(true)
	main._clear_screen()
	main.root_background = main._make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.root_background.add_child(backdrop)
	var panel := PanelContainer.new()
	panel.position = Vector2(140, 48)
	panel.size = Vector2(1000, 624)
	var panel_style = main._panel_style(Color("#121923"), Color(0.55, 0.36, 0.96, 0.55), 20)
	panel_style.content_margin_left = 38
	panel_style.content_margin_right = 38
	panel_style.content_margin_top = 30
	panel_style.content_margin_bottom = 30
	panel.add_theme_stylebox_override("panel", panel_style)
	main.root_background.add_child(panel)
	var stage_column := VBoxContainer.new()
	stage_column.add_theme_constant_override("separation", 14)
	panel.add_child(stage_column)
	var title := Label.new()
	title.text = Localization.text("AI 캠페인") if main.campaign_mode else Localization.text("AI 연습")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	stage_column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text("승리하여 다음 단계를 해금하고 별과 기록을 남기세요.") if main.campaign_mode else Localization.text("이전 단계를 모두 클리어한 성장 수치로 연습합니다. 실제 진행도는 바뀌지 않습니다.")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color("#8f98ad"))
	stage_column.add_child(subtitle)
	if main.campaign_mode:
		var growth := Label.new()
		growth.name = "CampaignGrowthSummary"
		growth.text = main._campaign_growth_summary()
		growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		growth.add_theme_font_size_override("font_size", 13)
		growth.add_theme_color_override("font_color", Color("#f0d592"))
		stage_column.add_child(growth)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	if not main.campaign_mode:
		var tools := HBoxContainer.new(); tools.add_theme_constant_override("separation",12); stage_column.add_child(tools)
		var edit = main._styled_button("상대 덱 설정",Color("#3d647d")); edit.custom_minimum_size = Vector2(260,40); edit.pressed.connect(main._show_practice_deck); tools.add_child(edit)
		var unlimited := CheckButton.new(); unlimited.name = "PracticeUnlimited"; unlimited.text = "자원 무제한"; unlimited.button_pressed = main.practice.unlimited; unlimited.toggled.connect(func(enabled): main.practice.unlimited=enabled); tools.add_child(unlimited)
		var normal = main._styled_button("기본 설정",Color("#596174")); normal.custom_minimum_size = Vector2(200,40); normal.pressed.connect(func(): main.practice = PracticeTools.new(); main._build_ai_stage_screen(false)); tools.add_child(normal)
	stage_column.add_child(grid)
	for stage in range(ServerAI.MIN_STAGE, ServerAI.MAX_STAGE + 1):
		var intensity := float(stage - 1) / float(ServerAI.MAX_STAGE - 1)
		var color := Color("#5b8cff").lerp(Color("#ff627d"), intensity)
		var record: Dictionary = main.save_data.campaign_records[stage - 1]
		var stars := "★".repeat(int(record.best_stars)) + "☆".repeat(3 - int(record.best_stars))
		var locked = main.campaign_mode and stage > int(main.save_data.campaign_unlocked)
		var stage_button = main._styled_button(
			"%02d  %s  %s\n%s" % [stage, ServerAI.stage_name(stage), "🔒" if locked else stars, ServerAI.stage_summary(stage)],
			color,
			stage == main.current_ai_stage
		)
		stage_button.custom_minimum_size = Vector2(220, 130)
		stage_button.add_theme_font_size_override("font_size", 14)
		stage_button.disabled = locked
		stage_button.pressed.connect(main._show_stage_brief.bind(stage) if main.campaign_mode else main._start_local_ai_battle.bind(stage))
		grid.add_child(stage_button)
	var back_button = main._styled_button(Localization.text("메인 화면으로"), Color("#596174"), false)
	back_button.custom_minimum_size.y = 48
	back_button.pressed.connect(main._build_connect_screen)
	stage_column.add_child(back_button)

static func _show_scene(main, scene: PackedScene, title_text: String, subtitle_text: String) -> Node:
	main.battle_active = false
	main._clear_screen()
	main.root_background = main._make_background()
	var frame = scene.instantiate()
	main.root_background.add_child(frame)
	frame.setup(title_text, subtitle_text)
	return frame

## Full-screen sub-menu frame (layout in scenes/ui/SubMenuFrame.tscn); returns its content column.
static func _submenu(main, title_text: String, subtitle_text: String) -> VBoxContainer:
	return _show_scene(main, SUBMENU_FRAME, title_text, subtitle_text).column

static func _build_patch_notes_screen(main) -> void:
	var frame = _show_scene(main, PATCH_NOTES_SCREEN, "패치노트", "최신 변경 사항과 이전 업데이트")
	frame.populate()
	var back = main._styled_button(Localization.text("메인 화면으로"), Color("#697386"))
	back.name = "PatchNotesBack"
	back.pressed.connect(main._build_connect_screen)
	frame.column.add_child(back)

static func _build_records_screen(main) -> void:
	var frame = _show_scene(main, RECORDS_SCREEN, Localization.text("개인 전적"), "이 기기에 저장된 전적")
	frame.populate(main.save_data)
	var back = main._styled_button(Localization.text("메인 화면으로"), Color("#697386"), false)
	back.pressed.connect(main._build_connect_screen)
	frame.column.add_child(back)

