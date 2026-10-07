extends RefCounted
## BattleHud: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")

static func _build_battle_screen(main) -> void:
	main.base_warning_fired = false; main.client_purchase_gates.clear(); main.sound_gate.clear()
	main.battle_active = true
	main.result_shown = false
	main.updater.set_safe_to_update(false)
	main._clear_screen()
	main.root_background = main._make_background()

	var top := ColorRect.new()
	top.color = Color("#090d17")
	top.position = Vector2.ZERO
	top.size = Vector2(1280, 88)
	main.root_background.add_child(top)
	var top_line := TextureRect.new()
	top_line.texture = _team_gradient(main.own_side)
	top_line.stretch_mode = TextureRect.STRETCH_SCALE
	top_line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	top_line.position = Vector2(0, 85)
	top_line.size = Vector2(1280, 3)
	top_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_line)
	main._create_hp_card(top, Vector2(18, 12), main.own_side)
	main._create_hp_card(top, Vector2(842, 12), 1 - main.own_side)

	var timer_card := PanelContainer.new()
	timer_card.position = Vector2(530, 12)
	timer_card.size = Vector2(220, 64)
	timer_card.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE.darkened(0.2), Color(1, 1, 1, 0.16), 14, 1.0, 0.6, Color(0, 0, 0, 0), 0.10))
	top.add_child(timer_card)
	var timer_inner := Control.new()
	timer_inner.custom_minimum_size = Vector2(220, 64)
	timer_card.add_child(timer_inner)
	main.timer_label = Label.new()
	main.timer_label.position = Vector2(0, 7)
	main.timer_label.size = Vector2(220, 34)
	main.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.timer_label.add_theme_font_size_override("font_size", 28)
	main.timer_label.add_theme_color_override("font_color", UIKit.TEXT)
	timer_inner.add_child(main.timer_label)
	var mode_label := Label.new()
	mode_label.text = "AI 단계 %02d" % main.current_ai_stage if main.local_ai_mode else ("관전 중" if main.network.client_is_spectator else "온라인 대전")
	mode_label.position = Vector2(0, 39)
	mode_label.size = Vector2(220, 18)
	mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mode_label.add_theme_font_size_override("font_size", 10)
	mode_label.add_theme_color_override("font_color", Color("#747d91"))
	timer_inner.add_child(mode_label)

	main.battle_view = BattleView.new()
	main.battle_view.position = Vector2(0, 88)
	main.battle_view.size = Vector2(1280, 492)
	main.battle_view.own_side = main.own_side
	main.battle_view.interpolate_positions = not main.local_ai_mode
	main.battle_view.rage_started.connect(main._on_rage_started)
	main.battle_view.show_damage_numbers = bool(main.save_data.settings.damage_numbers)
	main.battle_view.show_battle_effects = bool(main.save_data.settings.battle_effects)
	main.battle_view.effect_intensity = float(main.save_data.settings.effect_intensity)
	main.battle_view.battlefield_clicked.connect(main._on_battlefield_clicked)
	main.root_background.add_child(main.battle_view)
	main.placement_status_label = Label.new()
	main.placement_status_label.position = Vector2(360, 548)
	main.placement_status_label.size = Vector2(560, 28)
	main.placement_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.placement_status_label.add_theme_color_override("font_color", Color("#ff8a96"))
	main.root_background.add_child(main.placement_status_label)
	main.structure_count_label = Label.new()
	main.structure_count_label.position = Vector2(1030, 548)
	main.structure_count_label.size = Vector2(220, 28)
	main.structure_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main.structure_count_label.text = Localization.text("구조물 0 / 3")
	main.structure_count_label.add_theme_color_override("font_color", Color("#a7afc0"))
	main.root_background.add_child(main.structure_count_label)

	var controls := ColorRect.new()
	controls.color = Color("#090d17")
	controls.position = Vector2(0, 580)
	controls.size = Vector2(1280, 140)
	main.root_background.add_child(controls)
	var controls_line := ColorRect.new()
	controls_line.color = Color(1.0, 1.0, 1.0, 0.09)
	controls_line.size = Vector2(1280, 1)
	controls.add_child(controls_line)

	var resource_card := PanelContainer.new()
	resource_card.position = Vector2(16, 16)
	resource_card.size = Vector2(174, 108)
	var own_color := UIKit.TEAM_BLUE
	resource_card.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI.lerp(own_color, 0.12), UIKit.SURFACE.darkened(0.2), Color(own_color.r, own_color.g, own_color.b, 0.6), 14, 1.0, 0.6, Color(own_color.r, own_color.g, own_color.b, 0.35), 0.08))
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
	main.resource_label = Label.new()
	main.resource_label.position = Vector2(14, 28)
	main.resource_label.size = Vector2(145, 42)
	main.resource_label.add_theme_font_size_override("font_size", 27)
	main.resource_label.add_theme_color_override("font_color", UIKit.GOLD)
	resource_inner.add_child(main.resource_label)
	var resource_bar := HpBar.new()
	resource_bar.name = "ResourceBar"
	resource_bar.color = UIKit.GOLD_DEEP
	resource_bar.pulse_below = 0.0
	resource_bar.show_ticks = false
	resource_bar.position = Vector2(14, 66)
	resource_bar.size = Vector2(146, 8)
	resource_bar.max_value = BattleModel.MAX_RESOURCE
	resource_bar.value = 0.0
	resource_inner.add_child(resource_bar)
	main.resource_label.set_meta("bar", resource_bar)
	var side_label := Label.new()
	side_label.text = "●  아군 진영"
	side_label.position = Vector2(14, 80)
	side_label.size = Vector2(145, 22)
	side_label.add_theme_font_size_override("font_size", 12)
	side_label.add_theme_color_override("font_color", own_color)
	resource_inner.add_child(side_label)

	var row := HBoxContainer.new()
	row.position = Vector2(205, 19)
	row.size = Vector2(1058, 102)
	row.add_theme_constant_override("separation", 8)
	controls.add_child(row)
	var preset = main.battle_preset if not main.battle_preset.is_empty() else main._active_preset()
	var unit_names := BattleModel.UNIT_NAMES
	var unit_colors := {"shield": Color("#5b8cff"), "healer": Color("#d8b85a"), "archer": Color("#8b72df"), "swordsman": Color("#d56b5f"), "berserker": Color("#db7254"), "warlock": Color("#a775e6"), "necromancer": Color("#906bd1")}
	for kind in preset.units:
		main._add_spawn_button(row, unit_names[kind], kind, unit_colors[kind])
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
		main._add_structure_button(row, card_text, kind, structure_colors[kind])
	# A raised z_index draws above the battlefield, but input follows sibling order.
	# Add these actions after BattleView so it cannot consume their pointer events.
	var stats_button = main._styled_button(Localization.text("유닛 스탯"), Color("#3d8f83"), false)
	stats_button.name = "UnitStatsButton"
	stats_button.position = Vector2(1130, 98)
	stats_button.size = Vector2(136, 48)
	stats_button.z_index = 10
	stats_button.add_theme_font_size_override("font_size", 12)
	stats_button.pressed.connect(main._toggle_stats_panel)
	main.root_background.add_child(stats_button)
	if main.local_ai_mode:
		var exit_button = main._styled_button(Localization.text("대전 나가기"), Color("#8f4652"), false)
		exit_button.name = "ExitAIBattleButton"
		exit_button.position = Vector2(14, 98)
		exit_button.size = Vector2(136, 48)
		exit_button.z_index = 10
		exit_button.add_theme_font_size_override("font_size", 12)
		exit_button.text = "항복"; exit_button.pressed.connect(main._confirm_surrender)
		main.root_background.add_child(exit_button)

	if main.local_ai_mode and not main.campaign_mode: main._add_practice_controls()
	if main.campaign_mode and main.local_ai_mode:
		var goal := Label.new(); goal.name = "CampaignBattleGoal"; goal.text = CampaignBrief.goal(main.current_ai_stage); goal.position = Vector2(160,98); goal.size = Vector2(340,48); goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; goal.add_theme_font_size_override("font_size",12); goal.mouse_filter = Control.MOUSE_FILTER_IGNORE; main.root_background.add_child(goal)
	if not main.local_ai_mode:
		for side in 2:
			var name_label := Label.new(); name_label.name = "BattlePlayerName%d"%side; name_label.text = main._report_side_name(side); name_label.position = Vector2(164 if side==main.own_side else 918,154); name_label.size = Vector2(270,28); name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side==main.own_side else HORIZONTAL_ALIGNMENT_RIGHT; name_label.add_theme_font_size_override("font_size",13); name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; main.root_background.add_child(name_label)
		main.latency_label = Label.new(); main.latency_label.name = "LatencyLabel"; main.latency_label.position = Vector2(760,96); main.latency_label.size = Vector2(150,20); main.latency_label.add_theme_font_size_override("font_size",12); main.latency_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; main.root_background.add_child(main.latency_label)
		var surrender = main._styled_button("항복",Color("#8f4652")); surrender.name = "SurrenderButton"; surrender.position = Vector2(14,98); surrender.size = Vector2(136,48); surrender.z_index = 10; surrender.visible = not main.network.client_is_spectator; surrender.pressed.connect(main._confirm_surrender); main.root_background.add_child(surrender)
		main.recovery_label = Label.new(); main.recovery_label.name = "NetworkRecoveryStatus"; main.recovery_label.position = Vector2(350,155); main.recovery_label.size = Vector2(580,38); main.recovery_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; main.recovery_label.add_theme_color_override("font_color",Color("#f0d592")); main.recovery_label.mouse_filter = Control.MOUSE_FILTER_IGNORE; main.root_background.add_child(main.recovery_label)
	if not main.network.client_session.is_empty(): main._add_battle_chat()
	if not main.local_ai_mode: main._on_latency_updated(main.network.latency_ms)

	main.base_warning_label = Label.new(); main.base_warning_label.name = "BaseDangerWarning"; main.base_warning_label.text = "기지 체력 위험"; main.base_warning_label.position = Vector2(530,96); main.base_warning_label.size = Vector2(220,28); main.base_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; main.base_warning_label.add_theme_color_override("font_color",Color("#ff8a96")); main.base_warning_label.visible = false; main.root_background.add_child(main.base_warning_label)
	main.cancel_build_button = main._styled_button("설치 취소 · Esc",Color("#697386")); main.cancel_build_button.name = "CancelBuildButton"; main.cancel_build_button.position = Vector2(536,500); main.cancel_build_button.size = Vector2(208,44); main.cancel_build_button.visible = false; main.cancel_build_button.z_index = 10; main.cancel_build_button.pressed.connect(main._cancel_build_selection); main.root_background.add_child(main.cancel_build_button)

static func _team_gradient(own_side: int) -> GradientTexture2D:
	var gradient := Gradient.new()
	var left := UIKit.TEAM_BLUE
	var right := UIKit.TEAM_RED
	gradient.colors = PackedColorArray([Color(left.r, left.g, left.b, 0.9), Color(1, 1, 1, 0.06), Color(right.r, right.g, right.b, 0.9)])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 4
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(1, 0)
	return texture

static func _create_hp_card(main, parent: Control, position_value: Vector2, side: int) -> void:
	var card := PanelContainer.new()
	card.position = position_value
	card.size = Vector2(420, 64)
	var color := UIKit.TEAM_BLUE if side == main.own_side else UIKit.TEAM_RED
	card.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.10), UIKit.SURFACE.darkened(0.2), Color(color.r, color.g, color.b, 0.55), 12, 1.0, 0.6, Color(color.r, color.g, color.b, 0.35), 0.08))
	parent.add_child(card)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(420, 64)
	card.add_child(inner)
	var accent := ColorRect.new()
	accent.color = color
	accent.position = Vector2(0, 14)
	accent.size = Vector2(4, 36)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(accent)
	var faction := Label.new()
	faction.text = "아군 기지" if side == main.own_side else "적군 기지"
	faction.position = Vector2(16, 7)
	faction.size = Vector2(240, 22)
	faction.add_theme_font_size_override("font_size", 13)
	faction.add_theme_color_override("font_color", color.lightened(0.25))
	inner.add_child(faction)
	var value_label := Label.new()
	value_label.position = Vector2(300, 5)
	value_label.size = Vector2(104, 24)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 16)
	value_label.add_theme_color_override("font_color", UIKit.TEXT)
	inner.add_child(value_label)
	var hp_bar := HpBar.new()
	hp_bar.color = color
	hp_bar.position = Vector2(16, 34)
	hp_bar.size = Vector2(388, 16)
	hp_bar.max_value = BattleModel.BASE_MAX_HP
	hp_bar.value = BattleModel.BASE_MAX_HP
	inner.add_child(hp_bar)
	if side == 0:
		main.blue_hp_bar = hp_bar
		main.blue_hp_label = value_label
	else:
		main.red_hp_bar = hp_bar
		main.red_hp_label = value_label

static func _add_spawn_button(main, row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var stats: Dictionary = BattleModel.UNIT_STATS[kind].duplicate()
	var growth_level := int(main.local_model.campaign_levels[main.own_side]) if main.local_ai_mode and is_instance_valid(main.local_model) else 0
	var stat_scale := float(BattleModel.campaign_bonuses(growth_level).stat_scale)
	for key in ["hp", "damage", "heal"]:
		if stats.has(key):
			stats[key] = float(stats[key]) * stat_scale
	var primary := Localization.text("공속 +3% 누적") if kind == "healer" else Localization.text("공격 %d") % int(stats.damage)
	var button = main._styled_button(Localization.text("%s  ·  %d\n체력 %d  ·  %s") % [title, int(stats.cost), int(stats.hp), primary], color)
	button.tooltip_text = BattleModel.unit_stat_summary(kind, growth_level)
	button.set_meta("purchase_cost", float(stats.cost))
	button.set_meta("unit_kind", kind)
	button.set_meta("base_text",button.text)
	main._add_purchase_labels(button,BattleBindings.key_name(int(main.save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[main.purchase_buttons.size()])))
	button.disabled = true
	button.modulate = Color(0.4, 0.4, 0.4, 1.0)
	main.purchase_buttons.append(button)
	button.custom_minimum_size = Vector2(136, 102)
	button.set_meta("card_color", color)
	main._decorate_battle_card(button)
	_card_badges(main, button, color)
	var portrait := Sprite2D.new()
	portrait.name = "BattleUnitPortrait"
	portrait.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	portrait.position = Vector2(68, 27)
	portrait.scale = Vector2(0.185, 0.185)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(portrait)
	button.pressed.connect(main._purchase_unit.bind(kind))
	row.add_child(button)

static func _decorate_battle_card(main, button: Button) -> void:
	var color: Color = button.get_meta("card_color", UIKit.ACCENT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", UIKit.TEXT)
	var normal := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.20), UIKit.SURFACE.darkened(0.16), Color(color.r, color.g, color.b, 0.75), 12, 1.0, 0.55, Color(0, 0, 0, 0), 0.10)
	var hover := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.34), UIKit.SURFACE.lerp(color, 0.10), color.lightened(0.35), 12, 1.5, 0.9, Color(color.r, color.g, color.b, 0.55), 0.18)
	var pressed := UIKit.box(UIKit.SURFACE.darkened(0.15), UIKit.BG_DEEP, color, 12, 1.0, 0.1, Color(0, 0, 0, 0), 0.0)
	var selected := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.46), UIKit.SURFACE.lerp(color, 0.22), UIKit.GOLD, 12, 2.0, 0.9, Color(1.0, 0.85, 0.4, 0.5), 0.2)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style: StyleBox = {"normal": normal, "hover": hover, "pressed": selected if button.toggle_mode else pressed, "hover_pressed": selected if button.toggle_mode else pressed, "disabled": normal}[state].duplicate()
		style.content_margin_top = 54
		style.content_margin_bottom = 5
		style.content_margin_left = 4
		style.content_margin_right = 4
		button.add_theme_stylebox_override(state, style)
	UIKit.juice(button, 1.04)

static func _card_badges(main, button: Button, color: Color) -> void:
	var cost := float(button.get_meta("purchase_cost", 0.0))
	var badge := Label.new()
	badge.name = "CostBadge"
	badge.text = "%d" % int(cost)
	badge.position = Vector2(92, 5)
	badge.size = Vector2(38, 20)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color", Color("#2b1d02"))
	var pill := StyleBoxFlat.new()
	pill.bg_color = UIKit.GOLD
	pill.border_color = UIKit.GOLD_DEEP
	pill.set_border_width_all(1)
	pill.set_corner_radius_all(10)
	pill.anti_aliasing = true
	badge.add_theme_stylebox_override("normal", pill)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(badge)
	var glow := Control.new()
	glow.name = "PortraitGlow"
	glow.position = Vector2.ZERO
	glow.size = Vector2(136, 52)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(func():
		for i in 5:
			var t := float(i) / 4.0
			glow.draw_circle(Vector2(68, 28), 30.0 - t * 18.0, Color(color.r, color.g, color.b, 0.06 + t * 0.07)))
	button.add_child(glow)
	button.move_child(glow, 0)

static func _add_structure_button(main, row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var button = main._styled_button(title, color)
	button.custom_minimum_size = Vector2(136, 102)
	button.toggle_mode = true
	button.set_meta("structure_kind", kind)
	button.set_meta("base_text",button.text)
	main._add_purchase_labels(button,BattleBindings.key_name(int(main.save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[3+main.structure_buttons.size()])))
	button.set_meta("purchase_cost", float(BattleModel.STRUCTURE_STATS[kind].cost))
	button.disabled = true
	button.modulate = Color(0.4, 0.4, 0.4, 1.0)
	main.purchase_buttons.append(button)
	button.set_meta("card_color", color)
	main._decorate_battle_card(button)
	_card_badges(main, button, color)
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
		if is_instance_valid(main.battle_view):
			main.battle_view.selected_structure = "" if main.battle_view.selected_structure == kind else kind
			main._refresh_structure_selection()
	)
	row.add_child(button)
	main.structure_buttons.append(button)

static func _add_purchase_labels(main, button: Button, key_text: String) -> void:
	var hotkey := Label.new()
	hotkey.name = "PurchaseHotkey"
	hotkey.text = key_text
	hotkey.position = Vector2(7, 6)
	hotkey.custom_minimum_size = Vector2(22, 20)
	hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotkey.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hotkey.add_theme_font_size_override("font_size", 12)
	hotkey.add_theme_color_override("font_color", UIKit.TEXT)
	var keycap := StyleBoxFlat.new()
	keycap.bg_color = Color(0.03, 0.05, 0.09, 0.85)
	keycap.border_color = Color(1, 1, 1, 0.22)
	keycap.set_border_width_all(1)
	keycap.border_width_bottom = 2
	keycap.set_corner_radius_all(5)
	keycap.content_margin_left = 5
	keycap.content_margin_right = 5
	keycap.anti_aliasing = true
	hotkey.add_theme_stylebox_override("normal", keycap)
	hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(hotkey)
	var state := Label.new()
	state.name = "PurchaseState"
	state.position = Vector2(8, 32)
	state.size = Vector2(120, 18)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 11)
	state.add_theme_color_override("font_color", UIKit.GOLD)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.02, 0.03, 0.06, 0.82)
	pill.set_corner_radius_all(9)
	pill.anti_aliasing = true
	state.add_theme_stylebox_override("normal", pill)
	state.visible = false
	button.add_child(state)

static func _show_stats_panel(main) -> void:
	main._dismiss_stats_panel()
	main.stats_overlay = ColorRect.new()
	main.stats_overlay.name = "UnitStatsPanel"
	main.stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	main.stats_overlay.position = Vector2.ZERO
	main.stats_overlay.size = Vector2(1280, 720)
	main.stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.stats_overlay.z_index = 120
	main.root_background.add_child(main.stats_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(145, 72)
	panel.size = Vector2(990, 576)
	panel.add_theme_stylebox_override("panel", UIKit.panel_box(UIKit.TEAL, 16, 1.0))
	main.stats_overlay.add_child(panel)
	UIKit.reveal(panel, 0.25, 12.0)
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
		var unit_color: Color = UIKit.UNIT_COLORS.get(kind, UIKit.ACCENT)
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(455, 126)
		card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI.lerp(unit_color, 0.08), UIKit.SURFACE.darkened(0.12), Color(unit_color.r, unit_color.g, unit_color.b, 0.5), 12, 1.0, 0.0, Color(0, 0, 0, 0), 0.08), 14, 10))
		grid.add_child(card)
		var card_row := HBoxContainer.new()
		card_row.add_theme_constant_override("separation", 14)
		card.add_child(card_row)
		var portrait := TextureRect.new()
		portrait.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
		portrait.custom_minimum_size = Vector2(78, 100)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		card_row.add_child(portrait)
		var label := Label.new()
		label.text = "%s\n%s" % [names[kind], BattleModel.unit_stat_summary(kind, int(main.local_model.campaign_levels[main.own_side]) if main.local_ai_mode and is_instance_valid(main.local_model) else 0)]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", UIKit.TEXT)
		card_row.add_child(label)
	var world_stats := Label.new()
	world_stats.text = BattleModel.battle_stat_summary()
	world_stats.add_theme_font_size_override("font_size", 13)
	world_stats.add_theme_color_override("font_color", Color("#9ba5b8"))
	content.add_child(world_stats)
	var close = main._styled_button(Localization.text("닫기"), Color("#3d8f83"), true)
	close.custom_minimum_size = Vector2(160, 44)
	close.pressed.connect(main._dismiss_stats_panel)
	content.add_child(close)

static func _add_battle_chat(main) -> void:
	var toggle = main._styled_button("방 채팅",Color("#3d647d")); toggle.name = "BattleChatButton"; toggle.position = Vector2(970,190); toggle.size = Vector2(144,44); toggle.z_index = 10; main.root_background.add_child(toggle)
	main.battle_chat_panel = PanelContainer.new(); main.battle_chat_panel.name = "BattleChatPanel"; main.battle_chat_panel.position = Vector2(750,204); main.battle_chat_panel.size = Vector2(360,320); main.battle_chat_panel.z_index = 20
	var style = main._panel_style(Color("#101a29"),Color("#2b415c"),12); style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 12; style.content_margin_bottom = 12; main.battle_chat_panel.add_theme_stylebox_override("panel",style); main.root_background.add_child(main.battle_chat_panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",8); main.battle_chat_panel.add_child(content)
	main.session_chat_log = RichTextLabel.new(); main.session_chat_log.bbcode_enabled = false; main.session_chat_log.scroll_following = true; main.session_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(main.session_chat_log)
	main.session_chat_input = LineEdit.new(); main.session_chat_input.placeholder_text = "메시지 입력 · Enter 전송"; main.session_chat_input.max_length = 160; main.session_chat_input.custom_minimum_size.y = 40; main.session_chat_input.text_submitted.connect(func(_value): main._send_session_chat()); content.add_child(main.session_chat_input)
	main.battle_chat_panel.visible = false
	toggle.pressed.connect(func(): main.battle_chat_panel.visible = not main.battle_chat_panel.visible)
	MultiplayerUI.chat(main)

static func _refresh_structure_selection(main) -> void:
	if is_instance_valid(main.cancel_build_button): main.cancel_build_button.visible = is_instance_valid(main.battle_view) and not main.battle_view.selected_structure.is_empty()
	for button in main.structure_buttons:
		if is_instance_valid(button):
			button.set_pressed_no_signal(is_instance_valid(main.battle_view) and main.battle_view.selected_structure == String(button.get_meta("structure_kind")))
	if is_instance_valid(main.battle_view):
		main.battle_view.queue_redraw()

static func _refresh_purchase_buttons(main, resources: float) -> void:
	main.latest_resources = resources
	var clear_selection := false
	for button in main.purchase_buttons:
		if not is_instance_valid(button):
			continue
		var cooldown := 0.0
		if button.has_meta("unit_kind"):
			var kind: String = button.get_meta("unit_kind")
			var advertised: Array = main.current_snapshot.get("spawn_cooldowns",[{},{}])
			cooldown = maxf(float(advertised[main.own_side].get(kind,0.0)),maxf(0.0,float(main.client_purchase_gates.get(kind,0))-Time.get_ticks_msec())/1000.0)
		var missing := maxi(0,ceili(float(button.get_meta("purchase_cost"))-resources))
		var unavailable: bool = main.network.client_is_spectator or (not main.local_ai_mode and main.network_paused) or main.result_shown or (main.local_ai_mode and not main.campaign_mode and main.practice.paused) or missing>0 or cooldown>0.001
		var state_label := button.get_node_or_null("PurchaseState") as Label
		if state_label:
			var state_text := "관전" if main.network.client_is_spectator else ("자원 -%d" % missing if missing>0 else ("대기 %.1f초" % cooldown if cooldown>0.001 else ""))
			if state_label.text!=state_text: state_label.text = state_text
			state_label.visible = not state_text.is_empty()
		if button.disabled != unavailable:
			button.disabled = unavailable
			button.modulate = Color(0.4, 0.4, 0.4, 1.0) if unavailable else Color.WHITE
		if state_label: state_label.modulate = Color(2.5,2.5,2.5,1.0) if unavailable else Color.WHITE
		if unavailable and button.has_meta("structure_kind") and is_instance_valid(main.battle_view) and main.battle_view.selected_structure == String(button.get_meta("structure_kind")):
			main.battle_view.selected_structure = ""
			clear_selection = true
	if clear_selection:
		main._refresh_structure_selection()
