extends RefCounted
## BattleHud: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")

static func _build_battle_screen(main) -> void:
	main.replay_recording_error = ""
	main.base_warning_fired = false; main.client_purchase_gates.clear(); main.sound_gate.clear()
	main.battle_active = true
	main.result_shown = false
	main.updater.set_safe_to_update(false)
	main._clear_screen()
	# A new view must not inherit the previous battle's winner, resources or cooldowns.
	main.current_snapshot = {}
	main.latest_resources = 0.0
	main.awaiting_battle_snapshot = not main.local_ai_mode
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
	main.timer_label.position = Vector2(0, 3)
	main.timer_label.size = Vector2(220, 34)
	main.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.display(main.timer_label, 30, UIKit.TEXT)
	timer_inner.add_child(main.timer_label)
	var mode_label := Label.new()
	mode_label.text = Localization.text("드래프트 대전") if main.local_ai_mode and not main.draft_context.is_empty() else Localization.text("고스트 대전") if main.local_ai_mode and String(main.ghost_context.get("mode", "")) == "ghost" else (Localization.text("되감기 실험") if main.local_ai_mode and String(main.ghost_context.get("mode", "")) == "branch" else "AI 단계 %02d" % main.current_ai_stage) if main.local_ai_mode else ("관전 중" if main.network.client_is_spectator else "온라인 대전")
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
	main.battle_view.build_touch_cancelled.connect(func(): main._show_placement_status("설치 동작을 취소했습니다. 전장에서 다시 위치를 선택하세요."))
	main.root_background.add_child(main.battle_view)
	main.placement_status_label = ToastLabel.new()
	main.placement_status_label.tone = UIKit.DANGER
	main.root_background.add_child(main.placement_status_label)
	main.placement_status_label.place_center(640.0, 548.0)
	main.placement_hint_label = ToastLabel.new()
	main.placement_hint_label.name = "BuildPlacementHint"
	main.placement_hint_label.tone = UIKit.TEAL
	main.root_background.add_child(main.placement_hint_label)
	main.placement_hint_label.place_center(640.0, 440.0)
	main.unit_capacity_label = Label.new()
	main.unit_capacity_label.name = "UnitCapacity"
	main.unit_capacity_label.position = Vector2(20, 520)
	main.unit_capacity_label.size = Vector2(360, 28)
	main.unit_capacity_label.add_theme_font_size_override("font_size", 14)
	main.unit_capacity_label.mouse_filter = Control.MOUSE_FILTER_PASS
	main.root_background.add_child(main.unit_capacity_label)
	var structure_details := Button.new()
	structure_details.name = "StructureDetailsButton"
	structure_details.position = Vector2(1018, 520)
	structure_details.size = Vector2(240, 58)
	structure_details.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	structure_details.tooltip_text = "양쪽 구조물의 설치 수·종류별 한도·남은 체력·발전기 수입을 비교합니다."
	UIKit.style_button(structure_details, UIKit.TEAL)
	structure_details.pressed.connect(main._show_structure_panel)
	main.root_background.add_child(structure_details)
	main.structure_count_label = Label.new()
	main.structure_count_label.position = Vector2(10, 15)
	main.structure_count_label.size = Vector2(220, 28)
	main.structure_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main.structure_count_label.text = "구조물 0 / %d" % BattleModel.STRUCTURE_LIMIT
	main.structure_count_label.add_theme_color_override("font_color", Color("#a7afc0"))
	main.structure_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	structure_details.add_child(main.structure_count_label)
	main.structure_count_label.set_meta("details_button", structure_details)

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
	UIKit.display(main.resource_label, 28, UIKit.GOLD)
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
	side_label.name = "ResourceIncome"
	side_label.text = "회복 정보 대기"
	side_label.mouse_filter = Control.MOUSE_FILTER_PASS
	side_label.position = Vector2(14, 80)
	side_label.size = Vector2(145, 22)
	side_label.add_theme_font_size_override("font_size", 12)
	side_label.add_theme_color_override("font_color", own_color)
	resource_inner.add_child(side_label)
	main.resource_label.set_meta("income_label", side_label)

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
			card_text = "%s · %d" % [structure_names[kind], int(stats.cost)] + char(10) + BattleModel.swamp_summary()
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
		main.practice_pause_button = main._styled_button("일시정지", Color("#3d647d"))
		main.practice_pause_button.name = "CampaignPauseButton"
		main.practice_pause_button.position = Vector2(970, 98)
		main.practice_pause_button.size = Vector2(146, 58)
		main.practice_pause_button.z_index = 10
		main.practice_pause_button.pressed.connect(main._toggle_practice_pause)
		main.root_background.add_child(main.practice_pause_button)
	if main.local_ai_mode and is_instance_valid(main.practice_pause_button):
		main.practice_pause_button.tooltip_text = "전투 일시정지 · Space로도 조작할 수 있습니다."
		main.practice_pause_button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if not main.local_ai_mode:
		for side in 2:
			var name_label := ToastLabel.new(); name_label.name = "BattlePlayerName%d"%side; name_label.text = main._report_side_name(side)
			name_label.tone = UIKit.TEAM_BLUE if side == main.own_side else UIKit.TEAM_RED
			main.root_background.add_child(name_label)
			name_label.place_edge(164.0 if side == main.own_side else 1116.0, 154.0, side != main.own_side)
			name_label.add_theme_font_size_override("font_size", 14)
		main.latency_label = ToastLabel.new(); main.latency_label.name = "LatencyLabel"; main.latency_label.tone = UIKit.TEAL; main.root_background.add_child(main.latency_label)
		main.latency_label.place_edge(1116.0, 96.0, true)
		main.latency_label.add_theme_font_size_override("font_size", 13)
		var surrender = main._styled_button("항복",Color("#8f4652")); surrender.name = "SurrenderButton"; surrender.position = Vector2(14,98); surrender.size = Vector2(136,48); surrender.z_index = 10; surrender.visible = not main.network.client_is_spectator; surrender.pressed.connect(main._confirm_surrender); main.root_background.add_child(surrender)
		main.recovery_label = ToastLabel.new(); main.recovery_label.name = "NetworkRecoveryStatus"; main.recovery_label.tone = UIKit.GOLD; main.root_background.add_child(main.recovery_label)
		main.recovery_label.place_center(640.0, 156.0)
		main.recovery_label.text = "최신 전투 상태를 받는 중"
	if not main.network.client_session.is_empty(): main._add_battle_chat()
	if not main.local_ai_mode: main._on_latency_updated(main.network.latency_ms)

	main.base_warning_label = ToastLabel.new(); main.base_warning_label.name = "BaseDangerWarning"; main.base_warning_label.text = "기지 체력 위험"; main.base_warning_label.tone = UIKit.DANGER; main.base_warning_label.visible = false; main.root_background.add_child(main.base_warning_label)
	main.base_warning_label.place_center(640.0, 96.0)
	main.cancel_build_button = main._styled_button("설치 취소 · Esc",Color("#697386")); main.cancel_build_button.name = "CancelBuildButton"; main.cancel_build_button.position = Vector2(536,480); main.cancel_build_button.size = Vector2(208,58); main.cancel_build_button.visible = false; main.cancel_build_button.z_index = 10; main.cancel_build_button.pressed.connect(main._cancel_build_selection); main.root_background.add_child(main.cancel_build_button)
	main._refresh_purchase_buttons(main.latest_resources)
	_battle_intro(main)
	if main.local_ai_mode and main.local_battle_backgrounded and DisplayServer.get_name() != "headless":
		preload("res://scripts/screens/LocalBattlePause.gd").pause(main, true)

## "STAGE 03 · 전진" style band that slides in, holds, and leaves. Purely decorative (ignores input).
static func _battle_intro(main) -> void:
	var title_text := ""
	var sub_text := ""
	if main.local_ai_mode and main.campaign_mode:
		title_text = "STAGE %02d" % main.current_ai_stage
		sub_text = ServerAI.stage_name(main.current_ai_stage)
	elif main.local_ai_mode:
		title_text = "PRACTICE"
		sub_text = Localization.text("AI 단계 %02d") % main.current_ai_stage
	elif main.network.client_is_spectator:
		title_text = "SPECTATE"
		sub_text = Localization.text("관전 중")
	else:
		title_text = "BATTLE START"
		sub_text = Localization.text("온라인 대전")
	var band := Control.new()
	band.name = "BattleIntroBanner"
	band.position = Vector2(0, 250)
	band.size = Vector2(1280, 120)
	band.z_index = 40
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = Color(0.02, 0.03, 0.08, 0.72)
	fill.size = band.size
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(fill)
	for edge_y in [0.0, 118.0]:
		var edge := TextureRect.new()
		edge.texture = _team_gradient(main.own_side)
		edge.stretch_mode = TextureRect.STRETCH_SCALE
		edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		edge.position = Vector2(0, edge_y)
		edge.size = Vector2(1280, 2)
		edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		band.add_child(edge)
	var title := Label.new()
	title.text = title_text
	title.size = Vector2(1280, 70)
	title.position = Vector2(0, 8)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.display(title, 58, UIKit.GOLD)
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.07, 0.02, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(title)
	var sub := Label.new()
	sub.text = sub_text
	sub.size = Vector2(1280, 30)
	sub.position = Vector2(0, 78)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(sub)
	main.root_background.add_child(band)
	UIKit.UISounds.play("start", -8.0)
	band.modulate.a = 0.0
	band.position.x = -160.0
	var tween := band.create_tween()
	tween.tween_property(band, "modulate:a", 1.0, 0.22)
	tween.parallel().tween_property(band, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.9)
	tween.tween_property(band, "modulate:a", 0.0, 0.3)
	tween.parallel().tween_property(band, "position:x", 160.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(band.queue_free)

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
	faction.size = Vector2(96, 22)
	faction.add_theme_font_size_override("font_size", 13)
	faction.add_theme_color_override("font_color", color.lightened(0.25))
	inner.add_child(faction)
	var army_count := Label.new()
	army_count.name = "ArmyCount%d" % side
	army_count.position = Vector2(114, 7)
	army_count.size = Vector2(178, 22)
	army_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	army_count.add_theme_font_size_override("font_size", 12)
	army_count.add_theme_color_override("font_color", color.lightened(0.25))
	army_count.mouse_filter = Control.MOUSE_FILTER_PASS
	inner.add_child(army_count)
	main.army_count_labels[side] = army_count
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
	# The entire base card is a touch target; keep its health display underneath.
	var details := Button.new()
	details.name = "ArmyDetails%d" % side
	details.position = Vector2.ZERO
	details.size = Vector2(420, 64)
	details.flat = true
	details.focus_mode = Control.FOCUS_ALL
	details.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	# Hover/press feedback must remain translucent over the health and count labels.
	for state in ["normal", "hover", "pressed", "hover_pressed"]:
		var feedback := StyleBoxFlat.new()
		feedback.bg_color = Color(1, 1, 1, 0.10 if state in ["pressed", "hover_pressed"] else 0.05 if state == "hover" else 0.0)
		feedback.set_corner_radius_all(12)
		details.add_theme_stylebox_override(state, feedback)
	details.add_theme_stylebox_override("focus", UIKit.button_styles(color, false)["focus"])
	details.pressed.connect(_show_army_panel.bind(main, side))
	inner.add_child(details)
	army_count.set_meta("details_button", details)
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
	var primary := Localization.text("공속 +%d%% 누적") % roundi(BattleModel.SUPPORT_INCREMENT * 100.0) if kind == "healer" else Localization.text("공격 %d") % int(stats.damage)
	var button = main._styled_button(Localization.text("%s  ·  %d\n체력 %d  ·  %s") % [title, int(stats.cost), int(stats.hp), primary], color)
	button.tooltip_text = BattleModel.unit_stat_summary(kind, growth_level)
	button.set_meta("base_tooltip", button.tooltip_text)
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
		if is_instance_valid(main.battle_view) and not main.placement_pending and main._battle_purchase_block_reason().is_empty() and not button.disabled:
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

static func _show_army_panel(main, side: int) -> void:
	if not main.battle_active or not is_instance_valid(main.battle_view) or main.result_shown or main.finale_active or is_instance_valid(main.local_pause_overlay) or is_instance_valid(main.action_overlay) or is_instance_valid(main.report_overlay): return
	main.battle_view.reset_build_touch()
	main._dismiss_stats_panel()
	main.stats_overlay = ColorRect.new()
	main.stats_overlay.name = "ArmyDetailsOverlay"
	main.stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	main.stats_overlay.size = Vector2(1280, 720)
	main.stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.stats_overlay.z_index = 120
	main.root_background.add_child(main.stats_overlay)
	var origin = main.army_count_labels.get(side)
	if is_instance_valid(origin): main.stats_overlay.set_meta("return_focus", origin.get_meta("details_button", null))
	var panel := preload("res://scripts/ui/BattleArmyPanel.gd").new()
	main.stats_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 36
	panel.offset_bottom = -36
	panel.setup(main, side)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
	main._refresh_purchase_buttons(main.latest_resources)
	UIKit.reveal(panel, 0.25, 0.0)

static func _show_structure_panel(main) -> void:
	if not main.battle_active or not is_instance_valid(main.battle_view) or main.result_shown or main.finale_active or is_instance_valid(main.local_pause_overlay) or is_instance_valid(main.action_overlay) or is_instance_valid(main.report_overlay): return
	main.battle_view.reset_build_touch()
	main._dismiss_stats_panel()
	main.stats_overlay = ColorRect.new()
	main.stats_overlay.name = "StructureDetailsOverlay"
	main.stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	main.stats_overlay.size = Vector2(1280, 720)
	main.stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.stats_overlay.z_index = 120
	main.root_background.add_child(main.stats_overlay)
	if is_instance_valid(main.structure_count_label): main.stats_overlay.set_meta("return_focus", main.structure_count_label.get_meta("details_button", null))
	var panel := preload("res://scripts/ui/BattleStructurePanel.gd").new()
	main.stats_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 36
	panel.offset_bottom = -36
	panel.setup(main)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
	main._refresh_purchase_buttons(main.latest_resources)
	UIKit.reveal(panel, 0.25, 0.0)

static func _show_stats_panel(main) -> void:
	if is_instance_valid(main.battle_view): main.battle_view.reset_build_touch()
	main._dismiss_stats_panel()
	main.stats_overlay = ColorRect.new()
	main.stats_overlay.name = "UnitStatsPanel"
	main.stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	main.stats_overlay.position = Vector2.ZERO
	main.stats_overlay.size = Vector2(1280, 720)
	main.stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.stats_overlay.z_index = 120
	main.root_background.add_child(main.stats_overlay)
	var panel := preload("res://scripts/ui/BattleStatsBrowser.gd").new()
	main.stats_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 36
	panel.offset_bottom = -36
	var growth_level := int(main.local_model.campaign_levels[main.own_side]) if main.local_ai_mode and is_instance_valid(main.local_model) else 0
	panel.setup(main, growth_level)
	UIKit.reveal(panel, 0.25, 0.0)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
		main._refresh_purchase_buttons(main.latest_resources)

static func _add_battle_chat(main) -> void:
	var toggle = main._styled_button("방 채팅",Color("#3d647d")); toggle.name = "BattleChatButton"; toggle.position = Vector2(970,190); toggle.size = Vector2(144,44); toggle.z_index = 10; main.root_background.add_child(toggle)
	main.battle_chat_panel = PanelContainer.new(); main.battle_chat_panel.name = "BattleChatPanel"; main.battle_chat_panel.position = Vector2(750,204); main.battle_chat_panel.size = Vector2(360,320); main.battle_chat_panel.z_index = 20
	var style = main._panel_style(Color("#101a29"),Color("#2b415c"),12); style.content_margin_left = 12; style.content_margin_right = 12; style.content_margin_top = 12; style.content_margin_bottom = 12; main.battle_chat_panel.add_theme_stylebox_override("panel",style); main.root_background.add_child(main.battle_chat_panel)
	var content := VBoxContainer.new(); content.add_theme_constant_override("separation",8); main.battle_chat_panel.add_child(content)
	main.session_chat_log = RichTextLabel.new(); main.session_chat_log.bbcode_enabled = false; main.session_chat_log.scroll_following = true; main.session_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(main.session_chat_log)
	main.session_chat_input = LineEdit.new(); main.session_chat_input.placeholder_text = "메시지 입력 · Enter 전송"; main.session_chat_input.max_length = 160; main.session_chat_input.custom_minimum_size.y = 40; main.session_chat_input.text_submitted.connect(func(_value): main._send_session_chat()); content.add_child(main.session_chat_input)
	main.battle_chat_panel.visible = false
	toggle.pressed.connect(func():
		if is_instance_valid(main.battle_view): main.battle_view.reset_build_touch()
		main.battle_chat_panel.visible = not main.battle_chat_panel.visible)
	MultiplayerUI.chat(main)

static func _refresh_structure_selection(main) -> void:
	var selected: bool = is_instance_valid(main.battle_view) and not main.battle_view.selected_structure.is_empty()
	if is_instance_valid(main.battle_view): main.battle_view.reset_build_touch()
	if is_instance_valid(main.cancel_build_button):
		main.cancel_build_button.visible = selected
		main.cancel_build_button.disabled = main.placement_pending
		main.cancel_build_button.text = "서버 확인 중..." if main.placement_pending else "설치 취소 · Esc"
	if is_instance_valid(main.placement_hint_label):
		main.placement_hint_label.text = ""
		if selected:
			var kind: String = main.battle_view.selected_structure
			var title: String = {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}.get(kind, kind)
			main.placement_hint_label.text = "%s · 서버의 설치 결과를 기다리는 중" % title if main.placement_pending else "%s · 전장을 클릭하거나, 누른 채 이동 후 놓아 설치 · 전장 밖에 놓으면 취소" % title
	for button in main.structure_buttons:
		if is_instance_valid(button):
			button.set_pressed_no_signal(is_instance_valid(main.battle_view) and main.battle_view.selected_structure == String(button.get_meta("structure_kind")))
	if is_instance_valid(main.battle_view):
		main.battle_view.queue_redraw()

## Share the same battle-wide lock across card feedback and every purchase input.
## A completed snapshot arrives before the finale/result UI, so check its winner too.
static func _purchase_block_reason(main) -> String:
	if not main.battle_active or main.result_shown or main.finale_active or int(main.current_snapshot.get("winner", -1)) != -1:
		return "전투 종료"
	if main.network.client_is_spectator:
		return "관전"
	if not main.local_ai_mode:
		if main.network.client_reconnecting: return "연결 복구 중"
		if main.awaiting_battle_snapshot: return "상태 수신 중"
		if main.network_paused: return "복구 대기"
	elif preload("res://scripts/screens/LocalBattlePause.gd").is_paused(main):
		return "일시정지"
	return ""

static func _purchase_block_hint(reason: String) -> String:
	return {
		"전투 종료": "전투가 종료되어 병력 생산과 구조물 설치를 할 수 없습니다.",
		"관전": "관전 중에는 병력 생산과 구조물 설치를 할 수 없습니다.",
		"연결 복구 중": "서버 연결을 복구하고 있습니다. 복구 후 전투 상태를 받으면 자원과 생산 대기에 맞춰 구매 카드가 갱신됩니다.",
		"상태 수신 중": "최신 전투 상태를 기다리고 있습니다. 자원·생산 대기·설치 개수를 받은 뒤 구매할 수 있습니다.",
		"복구 대기": "전투 상태를 복구하고 있습니다. 전투가 재개되면 자원과 생산 대기에 맞춰 구매 카드가 갱신됩니다.",
		"일시정지": "전투가 일시정지되어 있습니다. 계속하기 또는 Space로 재개하거나 열려 있는 안내 창을 닫으세요.",
	}.get(reason, "")

## The cap applies to both sides and summons together, using the raw array size.
## Living counts describe the army; dead entries still occupy a slot until cleanup.
static func _battle_units(main) -> Array:
	if main.local_ai_mode and is_instance_valid(main.local_model): return main.local_model.units
	return main.current_snapshot.get("units", [])

static func _unit_population(main) -> Dictionary:
	var values := _battle_units(main)
	var counts := {"occupied": values.size(), "living": [0, 0], "summons": [0, 0], "kinds": [{}, {}]}
	for unit in values:
		if float(unit.hp) <= 0.0: continue
		var side := int(unit.side)
		var kind := String(unit.kind)
		counts.living[side] += 1
		counts.kinds[side][kind] = int(counts.kinds[side].get(kind, 0)) + 1
		if BattleModel.SUMMON_STATS.has(kind): counts.summons[side] += 1
	return counts

static func _unit_limit_hint() -> String:
	return "양쪽 병력과 소환수를 합쳐 전장에 최대 %d명까지 유지할 수 있습니다. 병력이 사망하고 정리되어 빈자리가 생기면 다시 생산할 수 있습니다. 구조물은 별도 한도를 사용합니다." % BattleModel.MAX_ACTIVE_UNITS

static func _unit_production_limit_error(main) -> String:
	return "전장 병력 한도 %d명 · 병력이 줄어들면 다시 생산할 수 있습니다." % BattleModel.MAX_ACTIVE_UNITS if _battle_units(main).size() >= BattleModel.MAX_ACTIVE_UNITS else ""

static func _refresh_unit_population(main, counts: Dictionary) -> void:
	var awaiting: bool = main.current_snapshot.is_empty() or (not main.local_ai_mode and (main.awaiting_battle_snapshot or main.network.client_reconnecting or main.network_paused))
	for side in main.army_count_labels:
		var label = main.army_count_labels[side]
		if not is_instance_valid(label): continue
		var text := "병력 —" if awaiting else "병력 %d" % int(counts.living[side])
		var tooltip := "최신 전투 상태를 받은 뒤 병력 현황을 표시합니다."
		if not awaiting:
			var summons := int(counts.summons[side])
			if summons > 0: text += " · 소환 %d" % summons
			var side_name := "블루" if int(side) == 0 else "레드"
			if not main.network.client_is_spectator: side_name = "아군" if int(side) == main.own_side else "적군"
			tooltip = "%s · 살아 있는 병력 %d명 (소환 %d명 포함)" % [side_name, int(counts.living[side]), summons]
			for kind in BattleModel.UNIT_NAMES:
				var amount := int(counts.kinds[side].get(kind, 0))
				if amount > 0:
					tooltip += "\n%s %d명" % [String(BattleModel.UNIT_NAMES[kind]), amount]
					if BattleModel.SUMMON_STATS.has(kind): tooltip += " · 소환 병력"
		text += " ▸"
		var details = label.get_meta("details_button", null)
		if is_instance_valid(details):
			var details_hint := tooltip + "\n누르면 양쪽 병력의 종류별 생존 수와 생산 한도를 확인합니다."
			if details.tooltip_text != details_hint: details.tooltip_text = details_hint
		if label.text != text: label.text = text
		if label.tooltip_text != tooltip: label.tooltip_text = tooltip
	if is_instance_valid(main.stats_overlay):
		var panel = main.stats_overlay.get_node_or_null("BattleArmyPanel")
		if panel != null: panel.refresh(counts, awaiting)
	if not is_instance_valid(main.unit_capacity_label): return
	var capacity_text := "전장 병력 — / %d" % BattleModel.MAX_ACTIVE_UNITS if awaiting else "전장 병력 %d / %d" % [int(counts.occupied), BattleModel.MAX_ACTIVE_UNITS]
	var full: bool = not awaiting and int(counts.occupied) >= BattleModel.MAX_ACTIVE_UNITS
	if full: capacity_text += " · 생산 한도"
	var capacity_hint := "최신 전투 상태를 받은 뒤 전체 병력 수와 생산 한도를 표시합니다." if awaiting else _unit_limit_hint()
	var pending := int(counts.occupied) - int(counts.living[0]) - int(counts.living[1])
	if not awaiting and pending > 0: capacity_hint += "\n사망 후 정리 대기 %d명도 현재 전장 한도에 포함됩니다." % pending
	var tone := UIKit.GOLD if full else UIKit.TEXT_MUTED
	if main.unit_capacity_label.text != capacity_text: main.unit_capacity_label.text = capacity_text
	if main.unit_capacity_label.tooltip_text != capacity_hint: main.unit_capacity_label.tooltip_text = capacity_hint
	if main.unit_capacity_label.get_theme_color("font_color") != tone: main.unit_capacity_label.add_theme_color_override("font_color", tone)

## Read the same growth and living-generator inputs used by BattleModel.tick.
## Keep forecasts separate from authoritative resources and purchase eligibility.
static func _resource_economy(main, counts: Dictionary) -> Dictionary:
	var income := BattleModel.RESOURCE_RATE
	var capacity := BattleModel.MAX_RESOURCE
	var speed := 1.0
	var unlimited := false
	if main.local_ai_mode and is_instance_valid(main.local_model):
		income = main.local_model.resource_income(main.own_side)
		capacity = main.local_model.resource_capacity(main.own_side)
		# Campaigns and scripted/challenge battles advance at fixed 30 Hz even
		# when a previous practice session left tool settings enabled.
		if not main.campaign_mode and main.ghost_context.is_empty() and main.daily_challenge.is_empty():
			speed = maxf(0.001, float(main.practice.speed))
			unlimited = bool(main.practice.unlimited)
	var generators := int(counts.kinds.get("generator", 0))
	income += generators * float(BattleModel.STRUCTURE_STATS.generator.income)
	return {"income": income, "capacity": capacity, "speed": speed, "unlimited": unlimited, "generators": generators}

static func _refresh_resource_income(main, resources: float, economy: Dictionary, block_reason: String) -> void:
	if not is_instance_valid(main.resource_label): return
	var label = main.resource_label.get_meta("income_label", null)
	if not is_instance_valid(label): return
	var text := "회복 +%.1f/초" % (float(economy.income) * float(economy.speed))
	var tone := UIKit.TEAL
	var tooltip := "전투 시간 기준 자원 +%.1f/초 · 살아 있는 아군 발전기 %d개 · 보유 한도 %d" % [float(economy.income), int(economy.generators), int(economy.capacity)]
	# Spectator card locks take priority over recovery locks; income still needs
	# a fresh snapshot before it can describe the observed side's economy.
	var awaiting_income: bool = not main.local_ai_mode and (main.awaiting_battle_snapshot or main.network.client_reconnecting or main.network_paused)
	if awaiting_income or main.current_snapshot.is_empty():
		text = "회복 정보 대기"
		if awaiting_income:
			text = "연결 복구 중" if main.network.client_reconnecting else "복구 대기" if main.network_paused else "상태 수신 중"
		tooltip = "최신 전투 상태를 받은 뒤 자원 회복 속도를 표시합니다."
		tone = UIKit.TEXT_MUTED
	elif block_reason == "전투 종료":
		text = "회복 종료"
		tooltip = _purchase_block_hint(block_reason)
		tone = UIKit.TEXT_MUTED
	elif block_reason == "일시정지":
		text = "회복 일시정지"
		tooltip += "\n전투를 재개하면 자원 회복도 이어집니다."
		tone = UIKit.GOLD
	elif bool(economy.unlimited):
		text = "무한 자원 · 자동 보충"
		tooltip = "연습 도구가 자원을 보유 한도까지 자동으로 보충합니다."
	elif resources >= float(economy.capacity):
		text = "한도 도달 · 회복 멈춤"
		tooltip += "\n한도에 도달해 추가 자원을 쌓을 수 없습니다. 자원을 사용하면 회복이 이어집니다."
		tone = UIKit.GOLD
	elif not is_equal_approx(float(economy.speed), 1.0):
		tooltip += "\n현재 %.1f배속 · 실제 시간 기준 +%.1f/초" % [float(economy.speed), float(economy.income) * float(economy.speed)]
	if label.text != text: label.text = text
	if label.tooltip_text != tooltip: label.tooltip_text = tooltip
	if label.get_theme_color("font_color") != tone: label.add_theme_color_override("font_color", tone)

static func _refresh_purchase_buttons(main, resources: float) -> void:
	main.latest_resources = resources
	var awaiting_state: bool = not main.local_ai_mode and main.awaiting_battle_snapshot
	if awaiting_state and is_instance_valid(main.resource_label):
		main.resource_label.text = "동기화 중"
		var resource_bar = main.resource_label.get_meta("bar", null)
		if is_instance_valid(resource_bar): resource_bar.visible = false
	var block_reason := _purchase_block_reason(main)
	var block_hint := _purchase_block_hint(block_reason)
	var counts := BattleModel.structure_counts(main.current_snapshot.get("structures", []), main.own_side)
	var population := _unit_population(main)
	_refresh_unit_population(main, population)
	var own_name := "아군"
	if main.network.client_is_spectator: own_name = "블루" if main.own_side == 0 else "레드"
	var economy := _resource_economy(main, counts)
	_refresh_resource_income(main, resources, economy, block_reason)
	if is_instance_valid(main.structure_count_label):
		var awaiting_structures: bool = main.current_snapshot.is_empty() or (not main.local_ai_mode and (main.awaiting_battle_snapshot or main.network.client_reconnecting or main.network_paused))
		var structure_text := "구조물 — / %d ▸" % BattleModel.STRUCTURE_LIMIT if awaiting_structures else "구조물 %d / %d ▸" % [int(counts.total), BattleModel.STRUCTURE_LIMIT]
		if main.structure_count_label.text != structure_text: main.structure_count_label.text = structure_text
		var structure_tone := UIKit.GOLD if not awaiting_structures and int(counts.total) >= BattleModel.STRUCTURE_LIMIT else Color("#a7afc0")
		if main.structure_count_label.get_theme_color("font_color") != structure_tone: main.structure_count_label.add_theme_color_override("font_color", structure_tone)
		if is_instance_valid(main.stats_overlay):
			var panel = main.stats_overlay.get_node_or_null("BattleStructurePanel")
			if panel != null:
				var values: Array = main.current_snapshot.get("structures", [])
				var side_counts: Array = [counts if main.own_side == 0 else BattleModel.structure_counts(values, 0), counts if main.own_side == 1 else BattleModel.structure_counts(values, 1)]
				panel.refresh(values, side_counts, float(main.current_snapshot.get("elapsed", 0.0)), awaiting_structures)
	var clear_selection := false
	for button in main.purchase_buttons:
		if not is_instance_valid(button):
			continue
		var cooldown := 0.0
		var cooldown_wait := 0.0
		if button.has_meta("unit_kind") and not awaiting_state:
			var kind: String = button.get_meta("unit_kind")
			var advertised: Array = main.current_snapshot.get("spawn_cooldowns",[{},{}])
			var model_wait := float(advertised[main.own_side].get(kind, 0.0))
			var client_wait := maxf(0.0, float(main.client_purchase_gates.get(kind, 0)) - Time.get_ticks_msec()) / 1000.0
			cooldown = maxf(model_wait, client_wait)
			cooldown_wait = maxf(model_wait / float(economy.speed), client_wait)
		var cost := float(button.get_meta("purchase_cost"))
		var deficit := maxf(0.0, cost - resources)
		var missing := 0 if awaiting_state else ceili(deficit)
		var above_capacity := cost > float(economy.capacity)
		# Use the fractional deficit; ceil is only for the displayed missing amount.
		var resource_wait := deficit / maxf(0.001, float(economy.income) * float(economy.speed))
		var purchase_wait := maxf(resource_wait, cooldown_wait)
		var resource_hint := ""
		if missing > 0:
			resource_hint = "\n자원이 %d 더 필요합니다." % missing
			if block_reason.is_empty():
				if above_capacity:
					resource_hint += " 비용이 보유 한도 %d보다 높아 회복만으로 구매할 수 없습니다." % int(economy.capacity)
				elif bool(economy.unlimited):
					resource_hint += " 무한 자원 도구의 보충을 기다리고 있습니다."
				else:
					resource_hint += " 구매 대기 예상 약 %.1f초 (현재 회복 속도·생산 대기 기준). 추가 구매나 발전기 파괴로 달라질 수 있습니다." % (ceilf(purchase_wait * 10.0) / 10.0)
		var waiting: bool = main.placement_pending and button.has_meta("structure_kind")
		var limit_error := ""
		var limit_state := ""
		var tooltip := String(button.get_meta("base_tooltip", ""))
		if button.has_meta("unit_kind") and not awaiting_state:
			if int(population.occupied) >= BattleModel.MAX_ACTIVE_UNITS:
				limit_error = _unit_limit_hint()
				limit_state = "전장 한도 %d/%d" % [int(population.occupied), BattleModel.MAX_ACTIVE_UNITS]
		if button.has_meta("structure_kind"):
			var kind: String = button.get_meta("structure_kind")
			var count := int(counts.kinds.get(kind, 0))
			var maximum := int(BattleModel.STRUCTURE_STATS[kind].get("max_count", BattleModel.STRUCTURE_LIMIT))
			var lines := String(button.get_meta("base_text")).split("\n")
			lines[0] += " · —/%d" % maximum if awaiting_state else " · %d/%d" % [count, maximum]
			var card_text := "\n".join(lines)
			if button.text != card_text: button.text = card_text
			limit_error = "" if awaiting_state else BattleModel.structure_limit_error(kind, counts)
			if not limit_error.is_empty():
				limit_state = "전체 한도 %d/%d" % [int(counts.total), BattleModel.STRUCTURE_LIMIT] if int(counts.total) >= BattleModel.STRUCTURE_LIMIT else "종류 한도 %d/%d" % [count, maximum]
			tooltip = String(button.get_meta("base_text"))
			if not awaiting_state:
				tooltip += "\n설치 %d / %d · 전체 %d / %d" % [count, maximum, int(counts.total), BattleModel.STRUCTURE_LIMIT]
			if not block_hint.is_empty():
				tooltip += "\n" + block_hint
			if waiting:
				tooltip += "\n서버 확인 중입니다. 이미 요청한 설치는 취소할 수 없습니다."
			elif not limit_error.is_empty():
				tooltip += "\n" + limit_error
				tooltip += " 아군 구조물이 파괴되거나 만료되어 전체·종류별 한도에 빈자리가 생기면 다시 선택할 수 있습니다."
			elif missing > 0:
				tooltip += resource_hint
			elif block_reason.is_empty():
				tooltip += "\n카드를 선택한 뒤 전장에서 위치를 선택하세요."
			if kind == "generator": tooltip += "\n발전기는 자신의 후방에만 설치할 수 있습니다."
		else:
			if not block_hint.is_empty(): tooltip += "\n" + block_hint
			if not awaiting_state:
				var kind: String = button.get_meta("unit_kind")
				tooltip += "\n살아 있는 %s %d명 · 전장 전체 %d / %d (양쪽·소환 포함)" % [own_name, int(population.kinds[main.own_side].get(kind, 0)), int(population.occupied), BattleModel.MAX_ACTIVE_UNITS]
				if kind == "necromancer": tooltip += "\n살아 있는 %s 해골 %d명 · 전장 병력 한도에 포함" % [own_name, int(population.kinds[main.own_side].get("skeleton", 0))]
			if not limit_error.is_empty(): tooltip += "\n" + limit_error
			elif missing > 0: tooltip += resource_hint
			if cooldown > 0.001: tooltip += "\n생산 대기 %.1f초" % (ceilf(cooldown_wait * 10.0) / 10.0)
		if button.tooltip_text != tooltip: button.tooltip_text = tooltip
		var unavailable: bool = not block_reason.is_empty() or waiting or not limit_error.is_empty() or missing>0 or cooldown>0.001
		var state_label := button.get_node_or_null("PurchaseState") as Label
		if state_label:
			var state_text := ""
			if not block_reason.is_empty(): state_text = block_reason
			elif waiting: state_text = "서버 확인 중"
			elif not limit_state.is_empty(): state_text = limit_state
			elif missing > 0:
				if above_capacity: state_text = "자원 한도 초과"
				elif bool(economy.unlimited): state_text = "자원 보충 중"
				else: state_text = "자원 약 %.1f초" % (ceilf(purchase_wait * 10.0) / 10.0)
			elif cooldown > 0.001: state_text = "대기 %.1f초" % (ceilf(cooldown_wait * 10.0) / 10.0)
			if state_label.text!=state_text: state_label.text = state_text
			state_label.visible = not state_text.is_empty()
		if button.disabled != unavailable:
			button.disabled = unavailable
			button.modulate = Color(0.4, 0.4, 0.4, 1.0) if unavailable else Color.WHITE
		if state_label: state_label.modulate = Color(2.5,2.5,2.5,1.0) if unavailable else Color.WHITE
		if unavailable and block_reason != "일시정지" and not waiting and button.has_meta("structure_kind") and is_instance_valid(main.battle_view) and main.battle_view.selected_structure == String(button.get_meta("structure_kind")):
			if not block_reason.is_empty(): main._show_placement_status(block_hint)
			elif not limit_error.is_empty(): main._show_placement_status(limit_error)
			main.battle_view.selected_structure = ""
			clear_selection = true
	if clear_selection:
		main._refresh_structure_selection()
