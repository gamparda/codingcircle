extends RefCounted
## MenuScreens: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const PatchNotes = preload("res://scripts/PatchNotes.gd")
const PracticeTools = preload("res://scripts/PracticeTools.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Achievements = preload("res://scripts/Achievements.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const NewFeatures = preload("res://scripts/NewFeatures.gd")
const Goals = preload("res://scripts/Goals.gd")
const LobbyScene = preload("res://scripts/ui/LobbyScene.gd")
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
	# The stage: the valley between two castles, the title plank and the dragon (LobbyScene); the menu sits on
	# its wooden board.
	var lobby := LobbyScene.new()
	lobby.animated = bool(main.save_data.settings.get("battle_effects", true))
	lobby.low_detail = float(main.save_data.settings.get("effect_intensity", 1.0)) < 0.5
	main.root_background.add_child(lobby)
	var column: VBoxContainer = lobby.menu_box

	var version := Label.new()
	version.name = "MenuVersion"
	version.text = "v%s" % main.build_version()
	version.add_theme_font_size_override("font_size", 13)
	version.add_theme_color_override("font_color", Color(0.75, 0.78, 0.9, 0.7))
	version.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	version.add_theme_constant_override("outline_size", 4)
	version.anchor_top = 1.0
	version.anchor_bottom = 1.0
	version.offset_left = 16.0
	version.offset_right = 300.0
	version.offset_top = -30.0
	version.offset_bottom = -8.0
	main.root_background.add_child(version)

	var battle_tile := UIKit.menu_tile("⚔", Localization.text("대전"), Localization.text("온라인 · 랭크 · 같은 와이파이"), UIKit.ACCENT, true, 86.0)
	battle_tile.name = "MultiplayerButton"
	battle_tile.pressed.connect(main._open_multiplayer)
	column.add_child(battle_tile)
	var solo_tile := UIKit.menu_tile("👑", Localization.text("혼자 하기"), _solo_caption(main), UIKit.GOLD_DEEP, false, 76.0)
	solo_tile.name = "SoloButton"
	solo_tile.pressed.connect(func(): _build_solo_screen(main))
	column.add_child(solo_tile)
	var preset: Dictionary = main._active_preset()
	var deck_names := PackedStringArray()
	for kind in preset.units:
		deck_names.append(String(BattleModel.UNIT_NAMES.get(kind, kind)))
	var deck_tile := UIKit.menu_tile("🃏", Localization.text("덱 편성"), "%s  ·  %s" % [String(preset.name), " · ".join(deck_names)], UIKit.TEAL, false, 70.0)
	deck_tile.name = "DeckButton"
	deck_tile.pressed.connect(main._build_deck_screen)
	column.add_child(deck_tile)
	var tools := HBoxContainer.new()
	tools.name = "MenuTools"
	tools.add_theme_constant_override("separation", 6)
	column.add_child(tools)
	var entries := [["📊 " + Localization.text("전적"), main._build_records_screen, "RecordsButton"], ["🎬 " + Localization.text("리플레이"), main._build_replay_list, "ReplaysButton"], ["⚙ " + Localization.text("설정"), main._build_settings_screen, "SettingsButton"]]
	if not UIKit.is_touch():
		entries.append(["⏻", main._quit_game, "QuitButton"])
	for entry in entries:
		var tool_button = main._styled_button(entry[0], UIKit.EDGE.lightened(0.25) if entry[2] != "QuitButton" else UIKit.DANGER, false)
		tool_button.name = entry[2]
		tool_button.custom_minimum_size = Vector2(52 if entry[2] == "QuitButton" else 0, 50)
		tool_button.add_theme_font_size_override("font_size", 13)
		if entry[2] == "QuitButton": tool_button.tooltip_text = Localization.text("종료")
		else: tool_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tool_button.pressed.connect(entry[1])
		tools.add_child(tool_button)
	main.status_label = Label.new()
	main.status_label.name = "MenuStatus"
	main.status_label.text = Localization.text(message)
	main.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.status_label.add_theme_font_size_override("font_size", 14)
	main.status_label.add_theme_color_override("font_color", UIKit.GOLD)
	column.add_child(main.status_label)

	var corner := HBoxContainer.new()
	corner.name = "MenuCorner"
	corner.add_theme_constant_override("separation", 10)
	corner.position = Vector2(20, 18)
	corner.size = Vector2(340, 44)
	main.root_background.add_child(corner)
	var patch_notes = main._styled_button("📰  " + Localization.text("패치노트"), UIKit.EDGE.lightened(0.25))
	patch_notes.name = "PatchNotesButton"
	patch_notes.custom_minimum_size = Vector2(0, 42)
	patch_notes.add_theme_font_size_override("font_size", 14)
	patch_notes.pressed.connect(main._build_patch_notes_screen)
	corner.add_child(patch_notes)
	Goals.add_chip(main, corner)
	corner.move_child(patch_notes, -1)
	# Every menu button wears the board's wood and iron.
	for tile in [battle_tile, solo_tile, deck_tile]:
		LobbyScene.dress_wood(tile, tile == battle_tile)
	for button in tools.get_children() + corner.get_children():
		if button is Button:
			LobbyScene.dress_wood(button)
	NewFeatures.decorate(main, column)
	main.updater.set_safe_to_update(main._client_can_update())
	main.updater.check_for_update()

static func _solo_caption(main) -> String:
	var parts := PackedStringArray()
	var expedition: Dictionary = preload("res://scripts/run/RunRecords.gd").expedition(main.save_data)
	if not expedition.saved.is_empty():
		parts.append(Localization.text("원정 진행 중"))
	if not bool(DailyChallenge.record_for(main.save_data, {"key": DailyChallenge.date_key()}).get("won", false)):
		parts.append(Localization.text("오늘의 도전 대기"))
	var unlocked := int(main.save_data.campaign_unlocked)
	if unlocked <= ServerAI.MAX_STAGE and not bool(main.save_data.campaign_records[unlocked - 1].cleared):
		parts.append(Localization.text("캠페인 %d단계") % unlocked)
	if parts.is_empty():
		return Localization.text("캠페인 · 도전 · 원정 · 무한 방어")
	return " · ".join(parts)

## "혼자 하기": every mode against the AI as a card with its own progress line.
static func _build_solo_screen(main) -> void:
	main.campaign_mode = false
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	var column = main._submenu(Localization.text("혼자 하기"), Localization.text("AI와 싸우는 모든 모드"))
	var records := preload("res://scripts/run/RunRecords.gd")
	var stars := 0
	for record in main.save_data.campaign_records:
		stars += int(record.best_stars)
	var unlocked := mini(int(main.save_data.campaign_unlocked), ServerAI.MAX_STAGE)
	var endless: Dictionary = records.endless(main.save_data)
	var expedition: Dictionary = records.expedition(main.save_data)
	var done_today: bool = bool(DailyChallenge.record_for(main.save_data, {"key": DailyChallenge.date_key()}).get("won", false))
	var done_week: bool = bool(DailyChallenge.record_for(main.save_data, {"key": DailyChallenge.week_key(), "period": "weekly"}).get("won", false))
	var featured := HBoxContainer.new()
	featured.name = "SoloFeatured"
	featured.add_theme_constant_override("separation", 14)
	column.add_child(featured)
	var cards := [
		[featured, "CampaignButton", "👑", "AI 캠페인", Localization.text("★ %d / %d · %d단계까지 열림") % [stars, ServerAI.MAX_STAGE * 3, unlocked], Color("#8b6cf6"), main._build_ai_stage_screen.bind(true)],
		[featured, "ExpeditionButton", "🧭", "원정", Localization.text("진행 중 · 이어하기") if not expedition.saved.is_empty() else (Localization.text("완주 %d회") % int(expedition.clears) if int(expedition.runs) > 0 else Localization.text("세 막의 로그라이크 원정")), Color("#4f8a3a"), func(): preload("res://scripts/screens/ExpeditionFlow.gd").show_brief(main)],
		[featured, "EndlessButton", "🌊", "무한 방어", Localization.text("최고 웨이브 %d") % int(endless.best_wave) if int(endless.runs) > 0 else Localization.text("끝없는 웨이브를 막아 내기"), Color("#c0563f"), func(): preload("res://scripts/screens/EndlessFlow.gd").show_brief(main)],
	]
	var minor := GridContainer.new()
	minor.name = "SoloMinor"
	minor.columns = 2
	minor.add_theme_constant_override("h_separation", 14)
	minor.add_theme_constant_override("v_separation", 12)
	column.add_child(minor)
	cards += [
		[minor, "DailyButton", "📅", "일일 도전", Localization.text("오늘 완료 ✓") if done_today else Localization.text("오늘의 고정 덱과 규칙"), UIKit.GOLD_DEEP, main._show_daily_brief],
		[minor, "WeeklyButton", "🏆", "주간 도전", Localization.text("이번 주 완료 ✓") if done_week else Localization.text("한 주 동안 이어지는 어려운 도전"), UIKit.GOLD_DEEP, func(): main._show_daily_brief("weekly")],
		[minor, "DraftButton", "🎲", "드래프트", Localization.text("AI와 번갈아 병력 뽑기"), Color("#8f7bd6"), func(): main._build_draft_screen()],
		[minor, "PracticeButton", "🎯", "AI 연습", Localization.text("기록 없이 단계를 골라 연습"), Color("#5fa8d3"), main._build_ai_stage_screen.bind(false)],
	]
	for card in cards:
		var big: bool = card[0] == featured
		var tile := UIKit.menu_tile(card[2], Localization.text(String(card[3])), String(card[4]), card[5], false, 168.0 if big else 96.0)
		tile.name = card[1]
		tile.pressed.connect(card[6])
		card[0].add_child(tile)
		if big:
			var title := tile.find_child("Title", true, false) as Label
			title.add_theme_font_size_override("font_size", 26)
	NewFeatures.decorate(main, column)

static func _build_ai_stage_screen(main, as_campaign: bool = false) -> void:
	main.campaign_mode = as_campaign
	main.battle_active = false
	main.result_shown = false
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	main.current_snapshot.clear()
	main.updater.set_safe_to_update(main._client_can_update())
	var stage_column: VBoxContainer = main._submenu(Localization.text("AI 캠페인") if as_campaign else Localization.text("AI 연습"),
		Localization.text("승리하여 다음 단계를 해금하고 별과 기록을 남기세요.") if as_campaign else Localization.text("이전 단계를 모두 클리어한 성장 수치로 연습합니다. 실제 진행도는 바뀌지 않습니다."),
		func(): _build_solo_screen(main), "StageBackButton")
	main.campaign_mode = as_campaign
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
		var tools: HBoxContainer = preload("res://scripts/ui/SubMenuFrame.gd").of(stage_column).actions
		var unlimited := CheckButton.new(); unlimited.name = "PracticeUnlimited"; unlimited.text = "자원 무제한"; unlimited.button_pressed = main.practice.unlimited; unlimited.toggled.connect(func(enabled): main.practice.unlimited=enabled); tools.add_child(unlimited)
		var edit = main._styled_button("상대 덱 설정",Color("#7a6248")); edit.custom_minimum_size = Vector2(150,44); edit.add_theme_font_size_override("font_size", 14); edit.pressed.connect(main._show_practice_deck); tools.add_child(edit)
		var normal = main._styled_button("초기화",Color("#596174")); normal.custom_minimum_size = Vector2(90,44); normal.add_theme_font_size_override("font_size", 14); normal.tooltip_text = "연습 설정을 기본값으로 되돌립니다."; normal.pressed.connect(func(): main.practice = PracticeTools.new(); main._build_ai_stage_screen(false)); tools.add_child(normal)
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
		stage_button.custom_minimum_size = Vector2(240, 150)
		stage_button.add_theme_font_size_override("font_size", 14)
		stage_button.disabled = locked
		_dress_stage_card(stage_button, color, stage, locked, stage == main.current_ai_stage, record)
		stage_button.pressed.connect(main._show_stage_brief.bind(stage) if main.campaign_mode else main._start_local_ai_battle.bind(stage))
		grid.add_child(stage_button)

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

static func _show_scene(main, scene: PackedScene, title_text: String, subtitle_text: String, back: Callable = Callable(), back_name: String = "SubMenuBack") -> Node:
	main.battle_active = false
	main._clear_screen()
	main.root_background = main._make_background()
	var backdrop := MenuBackdrop.new()
	backdrop.name = "SubMenuBackdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.root_background.add_child(backdrop)
	var frame = scene.instantiate()
	main.root_background.add_child(frame)
	frame.setup(title_text, subtitle_text)
	frame.set_back(back if back.is_valid() else main._build_connect_screen, back_name)
	UIKit.reveal(frame, 0.26, 10.0)
	return frame

## Full-screen sub-menu frame (layout in scenes/ui/SubMenuFrame.tscn); returns its content column. The header's
## back button goes to `back` (the main menu by default).
static func _submenu(main, title_text: String, subtitle_text: String, back: Callable = Callable(), back_name: String = "SubMenuBack") -> VBoxContainer:
	return _show_scene(main, SUBMENU_FRAME, title_text, subtitle_text, back, back_name).column

static func _build_patch_notes_screen(main) -> void:
	var frame = _show_scene(main, PATCH_NOTES_SCREEN, "패치노트", "최신 변경 사항과 이전 업데이트", Callable(), "PatchNotesBack")
	frame.populate()
	var features = main._styled_button("✨  " + Localization.text("새 기능 소개"), UIKit.GOLD_DEEP)
	features.name = "NewFeaturesButton"
	features.custom_minimum_size = Vector2(0, 44)
	features.add_theme_font_size_override("font_size", 14)
	features.pressed.connect(func(): NewFeatures.show_list(main))
	frame.actions.add_child(features)

static func _build_records_screen(main) -> void:
	var frame = _show_scene(main, RECORDS_SCREEN, Localization.text("개인 전적"), "이 기기에 저장된 전적")
	frame.populate(main.save_data, main.records_state)
	frame.challenge_replays_requested.connect(main._show_challenge_replays)
	frame.set_back(main._build_connect_screen, "RecordsBackButton")
	var gallery = main._styled_button("🏆  " + Localization.text("업적  %d / %d") % [Achievements.unlocked_count(main.save_data), Achievements.DEFS.size()], UIKit.GOLD_DEEP, false)
	gallery.name = "AchievementsButton"
	gallery.custom_minimum_size = Vector2(0, 44)
	gallery.add_theme_font_size_override("font_size", 14)
	gallery.pressed.connect(main._build_achievements_screen)
	frame.actions.add_child(gallery)

