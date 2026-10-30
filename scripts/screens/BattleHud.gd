extends RefCounted
## BattleHud: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")
const StructureLifetime = preload("res://scripts/ui/StructureLifetime.gd")

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

	# The base health bars and the clock float over the battlefield sky (raised above it once the view exists).
	var top := ColorRect.new()
	top.name = "BattleTopBar"
	top.color = Color(0, 0, 0, 0)
	top.position = Vector2.ZERO
	top.size = Vector2(1280, 88)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.root_background.add_child(top)
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
	mode_label.name = "BattleModeLabel"
	mode_label.text = Localization.text("원정") if main.local_ai_mode and not main.expedition_run.is_empty() else Localization.text("무한 방어") if main.local_ai_mode and not main.endless_run.is_empty() else Localization.text("드래프트 대전") if main.local_ai_mode and not main.draft_context.is_empty() else Localization.text("고스트 대전") if main.local_ai_mode and String(main.ghost_context.get("mode", "")) == "ghost" else (Localization.text("되감기 실험") if main.local_ai_mode and String(main.ghost_context.get("mode", "")) == "branch" else "AI 단계 %02d" % main.current_ai_stage) if main.local_ai_mode else ("관전 중" if main.network.client_is_spectator else "온라인 대전")
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
	# The battlefield takes all the room between the top bar and the card tray on any screen shape.
	main.battle_view.set_anchor_and_offset(SIDE_RIGHT, 1.0, 0.0)
	main.battle_view.set_anchor_and_offset(SIDE_BOTTOM, 1.0, -140.0)
	main.root_background.move_child(top, main.battle_view.get_index())
	main.placement_status_label = ToastLabel.new()
	main.placement_status_label.tone = UIKit.DANGER
	main.root_background.add_child(main.placement_status_label)
	main.placement_status_label.place_center(640.0, 548.0)
	main.placement_hint_label = ToastLabel.new()
	main.placement_hint_label.name = "BuildPlacementHint"
	main.placement_hint_label.tone = UIKit.TEAL
	main.root_background.add_child(main.placement_hint_label)
	main.placement_hint_label.place_center(640.0, 300.0)
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
	structure_details.tooltip_text = "양쪽 구조물의 설치 수·종류별 한도·남은 체력·수명·만료 시각·발전기 수입을 비교합니다. 전장 구조물을 직접 클릭·터치하면 전투 중에도 개별 상태를 확인할 수 있습니다. 겹친 곳을 다시 누르면 병력 아래 구조물도 차례로 선택하며, Tab·Shift+Tab으로 앞뒤 대상을 확인합니다."
	UIKit.style_button(structure_details, UIKit.TEAL)
	structure_details.pressed.connect(main._show_structure_panel)
	main.root_background.add_child(structure_details)
	main.structure_count_label = Label.new()
	main.structure_count_label.position = Vector2(10, 5)
	main.structure_count_label.size = Vector2(220, 28)
	main.structure_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main.structure_count_label.text = "구조물 0 / %d" % BattleModel.STRUCTURE_LIMIT
	main.structure_count_label.add_theme_color_override("font_color", Color("#a7afc0"))
	main.structure_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	structure_details.add_child(main.structure_count_label)
	main.structure_count_label.set_meta("details_button", structure_details)
	var lifetime_hint := Label.new()
	lifetime_hint.name = "StructureLifetimeHint"
	lifetime_hint.position = Vector2(10, 34)
	lifetime_hint.size = Vector2(220, 18)
	lifetime_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lifetime_hint.add_theme_font_size_override("font_size", 12)
	lifetime_hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	lifetime_hint.text = "전장 구조물 터치 · 자세히 ▸"
	lifetime_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	structure_details.add_child(lifetime_hint)
	main.structure_count_label.set_meta("lifetime_hint", lifetime_hint)

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
	# Cards stay next to the resource card; a wider screen only adds room on the right.
	row.set_anchor_and_offset(SIDE_RIGHT, 1.0, -17.0)
	var preset = main.battle_preset if not main.battle_preset.is_empty() else main._active_preset()
	var unit_names := BattleModel.UNIT_NAMES
	var unit_colors := {"shield": Color("#5b8cff"), "healer": Color("#d8b85a"), "archer": Color("#8b72df"), "swordsman": Color("#d56b5f"), "berserker": Color("#db7254"), "warlock": Color("#a775e6"), "necromancer": Color("#906bd1"), "zombie": Color("#7fa36b"), "paladin": Color("#e8c45a"), "sniper": Color("#8f9a6a"), "demon_lord": Color("#d8443a")}
	for kind in preset.units:
		main._add_spawn_button(row, unit_names[kind], kind, unit_colors[kind])
	var separator := VSeparator.new()
	separator.modulate = Color(1.0, 1.0, 1.0, 0.10)
	separator.custom_minimum_size.x = 5
	row.add_child(separator)
	var structure_names := BattleModel.STRUCTURE_NAMES
	var structure_colors := {"wall": Color("#7c879d"), "swamp": Color("#906bd1"), "turret": Color("#d56b5f"), "generator": Color("#3d8f83"),
		"lightning": Color("#5f8fe0"), "fireball": Color("#e07a3c"), "frost": Color("#5cb8d6"), "blessing": Color("#d8b85a"), "seraph": Color("#c9b6e8")}
	for kind in preset.structures:
		var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
		var card_text := Localization.text("%s\n%d 자원") % [structure_names[kind], int(stats.cost)]
		if kind == "swamp":
			card_text = "%s · %d" % [structure_names[kind], int(stats.cost)] + char(10) + BattleModel.swamp_summary()
		elif BattleModel.is_spell(kind):
			card_text = "%s · %d" % [structure_names[kind], int(stats.cost)] + char(10) + BattleModel.spell_card_note(kind)
		main._add_structure_button(row, card_text, kind, structure_colors[kind])
	# A raised z_index draws above the battlefield, but input follows sibling order.
	# Add these actions after BattleView so it cannot consume their pointer events.
	# Two quiet corners instead of a row of buttons: ☰ (pause menu with every battle action) and the mode's
	# speed toggle on the left, ⓘ (unit and structure reference) on the right.
	var info := UIKit.icon_button("ⓘ", Localization.text("유닛·구조물 정보"), UIKit.TEAL, 52.0)
	info.name = "UnitStatsButton"
	info.position = Vector2(1214, 98)
	info.z_index = 10
	info.pressed.connect(main._toggle_stats_panel)
	main.root_background.add_child(info)
	var corner := HBoxContainer.new()
	corner.name = "BattleCorner"
	corner.position = Vector2(14, 98)
	corner.z_index = 10
	corner.add_theme_constant_override("separation", 8)
	main.root_background.add_child(corner)
	var menu := UIKit.icon_button("☰", Localization.text("메뉴 · 일시정지 (Space)") if main.local_ai_mode else Localization.text("메뉴"), UIKit.EDGE, 52.0)
	menu.name = "BattleMenuButton"
	menu.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	corner.add_child(menu)
	if main.local_ai_mode:
		main.practice_pause_button = menu
		menu.pressed.connect(main._toggle_practice_pause)
	else:
		menu.pressed.connect(func(): _online_menu(main))
	if main.local_ai_mode and not main.endless_run.is_empty(): preload("res://scripts/screens/EndlessFlow.gd").add_controls(main, corner)
	elif main.local_ai_mode and not main.expedition_run.is_empty(): preload("res://scripts/screens/ExpeditionFlow.gd").add_controls(main, corner)
	elif main.local_ai_mode and not main.campaign_mode: main._add_practice_controls(corner)
	if main.campaign_mode and main.local_ai_mode:
		var goal := UIKit.pill(CampaignBrief.goal(main.current_ai_stage), UIKit.GOLD, 12)
		goal.name = "CampaignBattleGoal"
		goal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		corner.add_child(goal)
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
		main.recovery_label = ToastLabel.new(); main.recovery_label.name = "NetworkRecoveryStatus"; main.recovery_label.tone = UIKit.GOLD; main.root_background.add_child(main.recovery_label)
		main.recovery_label.place_center(640.0, 156.0)
		main.recovery_label.text = "최신 전투 상태를 받는 중"
	if not main.local_ai_mode: main._on_latency_updated(main.network.latency_ms)

	main.base_warning_label = ToastLabel.new(); main.base_warning_label.name = "BaseDangerWarning"; main.base_warning_label.text = "기지 체력 위험"; main.base_warning_label.tone = UIKit.DANGER; main.base_warning_label.visible = false; main.root_background.add_child(main.base_warning_label)
	main.base_warning_label.place_center(640.0, 96.0)
	main.cancel_build_button = main._styled_button("설치 취소 · Esc",Color("#697386")); main.cancel_build_button.name = "CancelBuildButton"; main.cancel_build_button.position = Vector2(536,480); main.cancel_build_button.size = Vector2(208,58); main.cancel_build_button.visible = false; main.cancel_build_button.z_index = 10; main.cancel_build_button.pressed.connect(main._cancel_build_selection); main.root_background.add_child(main.cancel_build_button)
	main._refresh_purchase_buttons(main.latest_resources)
	_battle_intro(main)
	if main.local_ai_mode and main.local_battle_backgrounded and DisplayServer.get_name() != "headless":
		preload("res://scripts/screens/LocalBattlePause.gd").pause(main, true)

## Online battles cannot pause: the menu offers surrender (players) or leaving (spectators).
static func _online_menu(main) -> void:
	if not main.battle_active or main.result_shown:
		return
	var column = main._action_panel(Localization.text("메뉴"), Rect2(440, 220, 400, 260))
	if not main.network.client_is_spectator:
		var surrender := MultiplayerUI.button(main, column, Localization.text("항복"), "SurrenderButton", func():
			main._dismiss_action_overlay()
			main._confirm_surrender())
		UIKit.style_button(surrender, UIKit.DANGER, false, 16)
	else:
		MultiplayerUI.button(main, column, Localization.text("관전 나가기"), "LeaveSpectateButton", func():
			main._dismiss_action_overlay()
			main._exit_battle_to_menu())
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseBattleMenu", main._dismiss_action_overlay, true)

## "STAGE 03 · 전진" style band that slides in, holds, and leaves. Purely decorative (ignores input).
static func _battle_intro(main) -> void:
	var title_text := ""
	var sub_text := ""
	if main.local_ai_mode and main.campaign_mode:
		title_text = "STAGE %02d" % main.current_ai_stage
		sub_text = ServerAI.stage_name(main.current_ai_stage)
	elif main.local_ai_mode and not main.expedition_run.is_empty():
		title_text = "ACT %d" % int(main.expedition_run.act)
		sub_text = Localization.text(String(main.expedition_run.node.enemy.name))
	elif main.local_ai_mode and not main.endless_run.is_empty():
		title_text = "ENDLESS"
		sub_text = Localization.text("무한 방어")
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
	faction.text = "아군 기지" if side == main.own_side else ("몰려오는 적" if main.local_ai_mode and not main.endless_run.is_empty() else "적군 기지")
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
	var local: bool = main.local_ai_mode and is_instance_valid(main.local_model)
	for key in ["hp", "damage", "heal"]:
		if stats.has(key):
			var run_scale: float = main.local_model.unit_modifier(main.own_side, kind, "damage" if key == "heal" else key) if local else 1.0
			stats[key] = float(stats[key]) * stat_scale * run_scale
	if local:
		stats.cost = main.local_model.unit_cost(main.own_side, kind)
	var primary := Localization.text("공속 +%d%% 누적") % roundi(BattleModel.SUPPORT_INCREMENT * 100.0) if kind == "healer" else Localization.text("공격 %d") % int(stats.damage)
	var button = main._styled_button(Localization.text("%s  ·  %d\n체력 %d  ·  %s") % [title, int(stats.cost), int(stats.hp), primary], color)
	button.tooltip_text = BattleModel.unit_stat_summary(kind, growth_level)
	button.tooltip_text += "\n짧게 누르면 한 번 생산합니다. 카드·구매 단축키를 누르고 유지하면 자원·생산 대기·전장 한도에 맞춰 반복 생산합니다. 손을 떼거나 카드 밖으로 이동하면 취소합니다."
	button.set_meta("base_tooltip", button.tooltip_text)
	button.set_meta("purchase_cost", float(stats.cost))
	button.set_meta("unit_kind", kind)
	button.set_meta("base_text",button.text)
	main._add_purchase_labels(button,BattleBindings.key_name(int(main.save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[main.purchase_buttons.size()])))
	button.disabled = true
	button.modulate = Color(0.4, 0.4, 0.4, 1.0)
	main.purchase_buttons.append(button)
	button.custom_minimum_size = Vector2(118, 102)
	button.set_meta("card_color", color)
	main._decorate_battle_card(button)
	_card_badges(main, button, color)
	var portrait := Sprite2D.new()
	portrait.name = "BattleUnitPortrait"
	portrait.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	portrait.position = Vector2(59, 27)
	portrait.scale = Vector2(0.185, 0.185)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(portrait)
	button.pressed.connect(main._purchase_unit.bind(kind))
	var repeat_hint := Label.new()
	repeat_hint.name = "RepeatPurchaseHint"
	repeat_hint.position = Vector2(20, 31)
	repeat_hint.size = Vector2(96, 20)
	repeat_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	repeat_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	repeat_hint.add_theme_font_size_override("font_size", 11)
	repeat_hint.add_theme_color_override("font_color", UIKit.GOLD)
	var repeat_style := StyleBoxFlat.new()
	repeat_style.bg_color = Color("#101522")
	repeat_style.border_color = UIKit.GOLD_DEEP
	repeat_style.set_border_width_all(1)
	repeat_style.set_corner_radius_all(5)
	repeat_hint.add_theme_stylebox_override("normal", repeat_style)
	repeat_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	repeat_hint.hide()
	button.add_child(repeat_hint)
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
	badge.position = Vector2(74, 5)
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
	glow.size = Vector2(118, 52)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(func():
		for i in 5:
			var t := float(i) / 4.0
			glow.draw_circle(Vector2(59, 28), 30.0 - t * 18.0, Color(color.r, color.g, color.b, 0.06 + t * 0.07)))
	button.add_child(glow)
	button.move_child(glow, 0)

static func _add_structure_button(main, row: HBoxContainer, title: String, kind: String, color: Color) -> void:
	var button = main._styled_button(title, color)
	button.custom_minimum_size = Vector2(118, 102)
	button.toggle_mode = true
	button.set_meta("structure_kind", kind)
	button.set_meta("base_text",button.text)
	main._add_purchase_labels(button,BattleBindings.key_name(int(main.save_data.settings.get("battle_keys",BattleBindings.DEFAULTS)[BattleModel.DECK_SIZE+main.structure_buttons.size()])))
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
	emblem.size = Vector2(118, 42)
	emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem.add_theme_font_size_override("font_size", 30)
	emblem.add_theme_color_override("font_color", color.lightened(0.2))
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(emblem)
	var icon: Texture2D = preload("res://scripts/ui/SpellArt.gd").icon(kind)
	if icon != null:
		emblem.text = ""
		var art := TextureRect.new()
		art.name = "TacticIcon"
		art.texture = icon
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.position = Vector2(39, 6)
		art.size = Vector2(40, 40)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(art)
	button.pressed.connect(func():
		main.unit_purchase_hold.cancel()
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
	# A strip between the art and the card text, so the portrait or icon stays visible.
	state.position = Vector2(6, 49)
	state.size = Vector2(106, 16)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state.add_theme_font_size_override("font_size", 10)
	state.add_theme_color_override("font_color", UIKit.GOLD)
	state.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color(0.02, 0.03, 0.06, 0.82)
	pill.set_corner_radius_all(9)
	pill.anti_aliasing = true
	state.add_theme_stylebox_override("normal", pill)
	state.visible = false
	button.add_child(state)

static func _show_army_panel(main, side: int, navigation: Dictionary = {}) -> void:
	main.unit_purchase_hold.cancel()
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
	panel.setup(main, side, String(navigation.get("role", "")))
	panel.navigation_pending = not navigation.is_empty()
	preload("res://scripts/ui/BattleOverviewNavigation.gd").restore.call_deferred(panel, navigation)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
	main._refresh_purchase_buttons(main.latest_resources)
	UIKit.reveal(panel, 0.25, 0.0)

static func _show_structure_panel(main, navigation: Dictionary = {}) -> void:
	main.unit_purchase_hold.cancel()
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
	panel.navigation_pending = not navigation.is_empty()
	preload("res://scripts/ui/BattleOverviewNavigation.gd").restore.call_deferred(panel, navigation)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
	main._refresh_purchase_buttons(main.latest_resources)
	UIKit.reveal(panel, 0.25, 0.0)

static func _show_stats_panel(main, reference: Dictionary = {}) -> void:
	main.unit_purchase_hold.cancel()
	if is_instance_valid(main.battle_view): main.battle_view.reset_build_touch()
	var return_focus: Control = main.stats_overlay.get_meta("return_focus", null) if is_instance_valid(main.stats_overlay) else null
	main._dismiss_stats_panel()
	main.stats_overlay = ColorRect.new()
	main.stats_overlay.name = "UnitStatsPanel"
	main.stats_overlay.color = Color(0.02, 0.025, 0.045, 0.94)
	main.stats_overlay.position = Vector2.ZERO
	main.stats_overlay.size = Vector2(1280, 720)
	main.stats_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.stats_overlay.z_index = 120
	main.root_background.add_child(main.stats_overlay)
	if not reference.is_empty(): main.stats_overlay.set_meta("return_focus", return_focus)
	var panel := preload("res://scripts/ui/BattleStatsBrowser.gd").new()
	main.stats_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 90
	panel.offset_right = -90
	panel.offset_top = 36
	panel.offset_bottom = -36
	var growth_level := int(main.local_model.campaign_levels[main.own_side]) if main.local_ai_mode and is_instance_valid(main.local_model) else 0
	panel.setup(main, growth_level, reference)
	UIKit.reveal(panel, 0.25, 0.0)
	if main.local_ai_mode:
		main.local_battle_skip_delta = true
		main.battle_view.set_process(false)
		main._refresh_purchase_buttons(main.latest_resources)

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
			var title: String = BattleModel.STRUCTURE_NAMES.get(kind, kind)
			main.placement_hint_label.text = "%s · 클릭 / 터치 후 놓아 설치 · 붉은 띠는 간격 부족\n←/→ 이동 · Shift 정밀/구매 키 겹침 · Home/End 양끝 · Enter 설치 · Esc 취소" % title
			if BattleModel.is_spell(kind):
				main.placement_hint_label.text = "%s · 쓸 곳을 클릭 / 터치 · %s\n←/→ 이동 · Home/End 양끝 · Enter 사용 · Esc 취소" % [title, BattleModel.tactic_role(kind)]
			if main.placement_pending: main.placement_hint_label.text = "%s · 서버의 설치 결과를 기다리는 중" % title
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
	var counts := {"occupied": values.size(), "sides": [BattleModel.side_count(values, 0), BattleModel.side_count(values, 1)], "living": [0, 0], "summons": [0, 0], "kinds": [{}, {}]}
	for unit in values:
		if float(unit.hp) <= 0.0: continue
		var side := int(unit.side)
		var kind := String(unit.kind)
		counts.living[side] += 1
		counts.kinds[side][kind] = int(counts.kinds[side].get(kind, 0)) + 1
		if BattleModel.SUMMON_STATS.has(kind): counts.summons[side] += 1
	return counts

static func _unit_limit_hint() -> String:
	return "진영마다 병력과 소환수를 합쳐 전장에 최대 %d명까지 유지할 수 있습니다. 병력이 사망하고 정리되어 빈자리가 생기면 다시 생산할 수 있습니다. 구조물은 별도 한도를 사용합니다." % BattleModel.SIDE_UNIT_LIMIT

static func _unit_production_limit_error(main) -> String:
	return "전장 병력 한도 %d명 · 병력이 줄어들면 다시 생산할 수 있습니다." % BattleModel.SIDE_UNIT_LIMIT if BattleModel.side_count(_battle_units(main), main.own_side) >= BattleModel.SIDE_UNIT_LIMIT else ""

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
			var details_hint := tooltip + "\n누르면 양쪽 병력의 종류별 생존 수와 생산 한도를 확인합니다. 전장 병력을 직접 클릭·터치하면 현재 체력·분노·저주·공속 지원을 확인할 수 있습니다. 겹친 곳을 다시 누르면 차례로 선택하며, Tab·Shift+Tab으로 앞뒤 대상을 확인합니다."
			if details.tooltip_text != details_hint: details.tooltip_text = details_hint
		if label.text != text: label.text = text
		if label.tooltip_text != tooltip: label.tooltip_text = tooltip
	if not is_instance_valid(main.unit_capacity_label): return
	var capacity_text := "전장 병력 — / %d" % BattleModel.SIDE_UNIT_LIMIT if awaiting else "전장 병력 %d / %d" % [int(counts.sides[main.own_side]), BattleModel.SIDE_UNIT_LIMIT]
	var full: bool = not awaiting and int(counts.sides[main.own_side]) >= BattleModel.SIDE_UNIT_LIMIT
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
	if not block_reason.is_empty(): main.unit_purchase_hold.cancel()
	var block_hint := _purchase_block_hint(block_reason)
	var counts := BattleModel.structure_counts(main.current_snapshot.get("structures", []), main.own_side)
	var elapsed := float(main.current_snapshot.get("elapsed", 0.0))
	var timed := StructureLifetime.timed_structures(main.current_snapshot.get("structures", []), main.own_side)
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
		var lifetime_hint = main.structure_count_label.get_meta("lifetime_hint", null)
		if is_instance_valid(lifetime_hint):
			var lifetime_text := "수명 정보 수신 대기" if awaiting_structures else "전장 구조물 터치 · 자세히 ▸"
			var lifetime_tone := UIKit.TEXT_MUTED
			if not awaiting_structures and not timed.is_empty():
				var remaining := StructureLifetime.remaining(timed[0], elapsed)
				var imminent_count := 0
				for structure in timed:
					if StructureLifetime.remaining(structure, elapsed) <= StructureLifetime.WARNING_SECONDS: imminent_count += 1
				lifetime_text = "늪 만료 " + StructureLifetime.countdown(remaining) if remaining > 0.0 else "늪 만료 상태 확인 중"
				if imminent_count > 0:
					if remaining > 0.0: lifetime_text += " · %d개 임박" % imminent_count
					lifetime_tone = UIKit.GOLD
			if lifetime_hint.text != lifetime_text: lifetime_hint.text = lifetime_text
			if lifetime_hint.get_theme_color("font_color") != lifetime_tone: lifetime_hint.add_theme_color_override("font_color", lifetime_tone)
		if is_instance_valid(main.stats_overlay):
			var panel = main.stats_overlay.get_node_or_null("BattleStructurePanel")
			if panel != null:
				var values: Array = main.current_snapshot.get("structures", [])
				var side_counts: Array = [counts if main.own_side == 0 else BattleModel.structure_counts(values, 0), counts if main.own_side == 1 else BattleModel.structure_counts(values, 1)]
				panel.refresh(values, side_counts, float(main.current_snapshot.get("elapsed", 0.0)), awaiting_structures)
	var army_panel = main.stats_overlay.get_node_or_null("BattleArmyPanel") if is_instance_valid(main.stats_overlay) else null
	var production: Dictionary = {}
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
		# The overview describes the same purchase conditions as the cards. It
		# never queues a spawn or estimates an opponent's undisclosed deck.
		if army_panel != null and button.has_meta("unit_kind") and not main.network.client_is_spectator:
			production[String(button.get_meta("unit_kind"))] = {"cost": cost, "missing": missing, "cooldown": cooldown, "cooldown_wait": cooldown_wait, "purchase_wait": purchase_wait, "above_capacity": above_capacity}
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
		var expiration_wait := -1.0
		var tooltip := String(button.get_meta("base_tooltip", ""))
		if button.has_meta("unit_kind") and not awaiting_state:
			if int(population.sides[main.own_side]) >= BattleModel.SIDE_UNIT_LIMIT:
				limit_error = _unit_limit_hint()
				limit_state = "전장 한도 %d/%d" % [int(population.sides[main.own_side]), BattleModel.SIDE_UNIT_LIMIT]
			else:
				var unit_kind := String(button.get_meta("unit_kind"))
				limit_error = BattleModel.field_limit_error(_battle_units(main), main.own_side, unit_kind)
				if not limit_error.is_empty():
					limit_state = "출전 중 %d/%d" % [BattleModel.field_limit(unit_kind), BattleModel.field_limit(unit_kind)]
		if button.has_meta("structure_kind") and BattleModel.is_spell(String(button.get_meta("structure_kind"))):
			var kind: String = button.get_meta("structure_kind")
			var spell_sides: Array = main.current_snapshot.get("spell_cooldowns", [{}, {}])
			var use_sides: Array = main.current_snapshot.get("spell_uses", [{}, {}])
			limit_error = "" if awaiting_state else BattleModel.spell_error(kind, spell_sides[main.own_side], use_sides[main.own_side])
			if not limit_error.is_empty():
				var remaining := float(spell_sides[main.own_side].get(kind, 0.0))
				limit_state = "재사용 %d초" % ceili(remaining) if remaining > 0.0 else "사용 횟수 소진"
			tooltip = String(button.get_meta("base_text")) + "\n" + BattleModel.tactic_role(kind)
			if not block_hint.is_empty():
				tooltip += "\n" + block_hint
			if waiting:
				tooltip += "\n서버 확인 중입니다."
			elif not limit_error.is_empty():
				tooltip += "\n" + limit_error
			elif missing > 0:
				tooltip += resource_hint
			elif block_reason.is_empty():
				tooltip += "\n카드를 선택한 뒤 전장을 클릭·터치하거나 ←/→로 위치를 정하고 Enter로 사용하세요."
		elif button.has_meta("structure_kind"):
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
				if block_reason.is_empty():
					expiration_wait = StructureLifetime.limit_wait(timed, kind, counts, elapsed)
					if expiration_wait >= 0.0:
						limit_state = "한도 · 만료 " + StructureLifetime.countdown(expiration_wait) if expiration_wait > 0.0 else "한도 · 상태 확인 중"
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
				if expiration_wait >= 0.0:
					tooltip += "\n만료로 설치 공간이 생기기까지 %s (전투 시간 기준). 자원·설치 위치는 별도 조건이며 추가 설치·파괴로 달라질 수 있습니다." % StructureLifetime.countdown(expiration_wait)
					if not is_equal_approx(float(economy.speed), 1.0): tooltip += " 현재 배속의 실제 시간으로 약 %s." % StructureLifetime.countdown(expiration_wait / float(economy.speed))
			elif missing > 0:
				tooltip += resource_hint
			elif block_reason.is_empty():
				tooltip += "\n카드를 선택한 뒤 클릭·터치로 설치하거나 ←/→·Home/End로 위치를 정하고 Enter로 설치하세요. Shift+방향키는 정밀 이동입니다. 구매 단축키로 지정한 방향키·Home/End는 Shift와 함께 눌러 위치를 조정하세요."
			if kind == "generator": tooltip += "\n발전기는 자신의 후방에만 설치할 수 있습니다."
		else:
			if not block_hint.is_empty(): tooltip += "\n" + block_hint
			if not awaiting_state:
				var kind: String = button.get_meta("unit_kind")
				tooltip += "\n살아 있는 %s %d명 · 우리 진영 %d / %d (소환 포함)" % [own_name, int(population.kinds[main.own_side].get(kind, 0)), int(population.sides[main.own_side]), BattleModel.SIDE_UNIT_LIMIT]
				if kind == "necromancer": tooltip += "\n살아 있는 %s 해골 %d명 · 전장 병력 한도에 포함" % [own_name, int(population.kinds[main.own_side].get("skeleton", 0))]
			if not limit_error.is_empty(): tooltip += "\n" + limit_error
			elif missing > 0: tooltip += resource_hint
			if cooldown > 0.001: tooltip += "\n생산 대기 %.1f초" % (ceilf(cooldown_wait * 10.0) / 10.0)
		if button.tooltip_text != tooltip: button.tooltip_text = tooltip
		# A ranked ban: the opponent removed this card for the battle.
		var card_kind := String(button.get_meta("unit_kind", button.get_meta("structure_kind", "")))
		var bans: Array = main.current_snapshot.get("banned", [[], []])
		if not awaiting_state and bans.size() == 2 and main.own_side >= 0 and main.own_side < 2 and Array(bans[main.own_side]).has(card_kind):
			limit_error = "상대가 이번 경기에서 금지한 카드입니다."
			limit_state = "금지됨"
			if button.tooltip_text.find(limit_error) < 0: button.tooltip_text += "\n" + limit_error
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
	if is_instance_valid(army_panel) and not army_panel.is_queued_for_deletion():
		var awaiting_army: bool = main.current_snapshot.is_empty() or (not main.local_ai_mode and (main.awaiting_battle_snapshot or main.network.client_reconnecting or main.network_paused))
		army_panel.refresh(population, awaiting_army, {"resources": resources, "economy": economy, "production": production, "block_reason": block_reason})
