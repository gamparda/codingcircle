extends RefCounted
## MenuScreens: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const PatchNotes = preload("res://scripts/PatchNotes.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Achievements = preload("res://scripts/Achievements.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const HeroShowcase = preload("res://scripts/ui/HeroShowcase.gd")
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

	# Hero stage on the right: rotating roster showcase.
	var hero := HeroShowcase.new()
	hero.name = "HeroShowcase"
	hero.position = Vector2(660, 84)
	hero.size = Vector2(560, 560)
	main.root_background.add_child(hero)

	# Left column: brand + navigation.
	var column := VBoxContainer.new()
	column.name = "MenuColumn"
	column.position = Vector2(84, 74)
	column.size = Vector2(500, 580)
	column.add_theme_constant_override("separation", 10)
	main.root_background.add_child(column)

	var badge := PanelContainer.new()
	badge.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(Color(0.43, 0.49, 1.0, 0.22), Color(0.43, 0.49, 1.0, 0.10), Color(0.55, 0.6, 1.0, 0.7), 12, 1.0, 0.0, Color(0, 0, 0, 0), 0.0), 14, 4))
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	column.add_child(badge)
	var badge_label := Label.new()
	badge_label.text = "◆  전장 개조 전략   ·   v%s" % main.build_version()
	badge_label.add_theme_font_size_override("font_size", 13)
	badge_label.add_theme_color_override("font_color", Color("#b9c2ff"))
	badge.add_child(badge_label)

	var title := Label.new()
	title.name = "GameTitle"
	title.text = "CAT WAR"
	UIKit.display(title, 96, UIKit.GOLD)
	title.add_theme_color_override("font_outline_color", Color("#3a2a0c"))
	title.add_theme_constant_override("outline_size", 14)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.55))
	title.add_theme_constant_override("shadow_offset_y", 6)
	title.add_theme_constant_override("shadow_offset_x", 0)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = Localization.text("자동 전투  ×  전장 개조  ×  실시간 전략")
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	column.add_child(subtitle)
	var gap := Control.new()
	gap.custom_minimum_size.y = 14
	column.add_child(gap)

	var multiplayer_button = main._styled_button("멀티플레이", Color("#6d7cff"), true)
	multiplayer_button.name = "MultiplayerButton"
	multiplayer_button.custom_minimum_size.y = 68
	multiplayer_button.add_theme_font_size_override("font_size", 22)
	multiplayer_button.text = "▶   " + Localization.text("멀티플레이")
	multiplayer_button.pressed.connect(main._open_multiplayer)
	column.add_child(multiplayer_button)

	var ai_row := HBoxContainer.new()
	ai_row.add_theme_constant_override("separation", 10)
	column.add_child(ai_row)
	var campaign_button = main._styled_button(Localization.text("AI 캠페인"), Color("#8b6cf6"), false)
	campaign_button.name = "CampaignButton"
	campaign_button.custom_minimum_size.y = 56
	campaign_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	campaign_button.pressed.connect(main._build_ai_stage_screen.bind(true))
	ai_row.add_child(campaign_button)
	var practice_button = main._styled_button(Localization.text("AI 연습"), Color("#5fa8d3"), false)
	practice_button.name = "PracticeButton"
	practice_button.custom_minimum_size.y = 56
	practice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	practice_button.pressed.connect(main._build_ai_stage_screen.bind(false))
	ai_row.add_child(practice_button)

	var today := DailyChallenge.date_key()
	var done_today: bool = bool(main.save_data.get("daily", {}).get(today, {}).get("won", false))
	var daily_button = main._styled_button(Localization.text("일일 도전") + ("  ✓" if done_today else ""), UIKit.GOLD_DEEP, false)
	daily_button.name = "DailyButton"
	daily_button.custom_minimum_size.y = 56
	daily_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	daily_button.pressed.connect(main._show_daily_brief)
	ai_row.add_child(daily_button)
	var management_row := HBoxContainer.new()
	management_row.add_theme_constant_override("separation", 10)
	column.add_child(management_row)
	for entry in [[Localization.text("덱 편성"), main._build_deck_screen, "DeckButton"], [Localization.text("전적"), main._build_records_screen, "RecordsButton"], [Localization.text("리플레이"), main._build_replay_list, "ReplaysButton"], [Localization.text("설정"), main._build_settings_screen, "SettingsButton"], [Localization.text("종료"), main._quit_game, "QuitButton"]]:
		var menu_button = main._styled_button(entry[0], Color("#3ec6b0") if entry[2] != "QuitButton" else Color("#ff6b81"), false)
		menu_button.name = entry[2]
		menu_button.custom_minimum_size = Vector2(0, 46)
		menu_button.add_theme_font_size_override("font_size", 14)
		menu_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu_button.pressed.connect(entry[1])
		management_row.add_child(menu_button)

	var deck_chip := PanelContainer.new()
	deck_chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	deck_chip.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE, 12, 1.0, 0.0, Color(0, 0, 0, 0), 0.06), 14, 6))
	column.add_child(deck_chip)
	main.status_label = Label.new()
	main.status_label.text = Localization.text(message) if not message.is_empty() else "선택 덱: %s" % String(main._active_preset().name)
	main.status_label.add_theme_font_size_override("font_size", 14)
	main.status_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	deck_chip.add_child(main.status_label)

	var patch_notes = main._styled_button(Localization.text("패치노트"), Color("#3ec6b0"))
	patch_notes.name = "PatchNotesButton"
	patch_notes.position = Vector2(1086, 22)
	patch_notes.size = Vector2(170, 42)
	patch_notes.custom_minimum_size = Vector2(0, 0)
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
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(Color(0.55, 0.40, 0.98), 18, 1.0), 38, 28))
	UIKit.reveal(panel, 0.3, 12.0)
	main.root_background.add_child(panel)
	var stage_column := VBoxContainer.new()
	stage_column.add_theme_constant_override("separation", 14)
	panel.add_child(stage_column)
	var title := Label.new()
	title.text = Localization.text("AI 캠페인") if main.campaign_mode else Localization.text("AI 연습")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.display(title, 38, UIKit.TEXT)
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
		_dress_stage_card(stage_button, color, stage, locked, stage == main.current_ai_stage, record)
		stage_button.pressed.connect(main._show_stage_brief.bind(stage) if main.campaign_mode else main._start_local_ai_battle.bind(stage))
		grid.add_child(stage_button)
	var back_button = main._styled_button(Localization.text("메인 화면으로"), Color("#596174"), false)
	back_button.custom_minimum_size.y = 48
	back_button.pressed.connect(main._build_connect_screen)
	stage_column.add_child(back_button)

## Stage tile: gradient frame tinted by difficulty, big faded numeral, difficulty pips, lock veil.
static func _dress_stage_card(card: Button, color: Color, stage: int, locked: bool, current: bool, record: Dictionary) -> void:
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var base := UIKit.SURFACE_HI.lerp(color, 0.10 if not locked else 0.0)
	var border := Color(color.r, color.g, color.b, 0.55 if not locked else 0.18)
	var normal := UIKit.box(base, UIKit.SURFACE.darkened(0.16), border, 14, 1.0, 0.45, Color(0, 0, 0, 0), 0.08)
	var hover := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.24), UIKit.SURFACE.lerp(color, 0.10), color.lightened(0.35), 14, 1.5, 0.85, Color(color.r, color.g, color.b, 0.5), 0.16)
	var chosen := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.40), UIKit.SURFACE.lerp(color, 0.18), UIKit.GOLD, 14, 2.0, 0.9, Color(1.0, 0.85, 0.4, 0.45), 0.2) if current else hover
	var map := {"normal": chosen if current else normal, "hover": hover, "pressed": chosen, "hover_pressed": chosen, "disabled": normal}
	for state in map:
		var style: StyleBox = map[state].duplicate()
		style.content_margin_left = 18
		style.content_margin_right = 16
		style.content_margin_top = 16
		style.content_margin_bottom = 30
		card.add_theme_stylebox_override(state, style)
	card.add_theme_color_override("font_disabled_color", UIKit.TEXT_DIM)
	UIKit.juice(card, 1.03)
	var numeral := Label.new()
	numeral.name = "StageNumeral"
	numeral.text = "%d" % stage
	numeral.size = Vector2(100, 90)
	numeral.position = Vector2(112, 22)
	numeral.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	UIKit.display(numeral, 84)
	numeral.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.16 if not locked else 0.06))
	numeral.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(numeral)
	var pips := HBoxContainer.new()
	pips.name = "DifficultyPips"
	pips.position = Vector2(18, 108)
	pips.add_theme_constant_override("separation", 3)
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(pips)
	for i in ServerAI.MAX_STAGE:
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(14, 4)
		pip.color = (color if not locked else UIKit.TEXT_DIM) if i < stage else Color(1, 1, 1, 0.10)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pips.add_child(pip)
	if current and not locked:
		var tag := Label.new()
		tag.text = "NEXT" if int(record.best_stars) == 0 else "●"
		tag.position = Vector2(170, 104)
		tag.add_theme_font_size_override("font_size", 11)
		tag.add_theme_color_override("font_color", UIKit.GOLD)
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(tag)

static func _show_scene(main, scene: PackedScene, title_text: String, subtitle_text: String) -> Node:
	main.battle_active = false
	main._clear_screen()
	main.root_background = main._make_background()
	var frame = scene.instantiate()
	main.root_background.add_child(frame)
	frame.setup(title_text, subtitle_text)
	UIKit.reveal(frame, 0.26, 10.0)
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
	var gallery = main._styled_button(Localization.text("업적 보기  (%d / %d)") % [Achievements.unlocked_count(main.save_data), Achievements.DEFS.size()], UIKit.GOLD_DEEP, false)
	gallery.name = "AchievementsButton"
	gallery.pressed.connect(main._build_achievements_screen)
	frame.column.add_child(gallery)
	var back = main._styled_button(Localization.text("메인 화면으로"), Color("#697386"), false)
	back.pressed.connect(main._build_connect_screen)
	frame.column.add_child(back)

