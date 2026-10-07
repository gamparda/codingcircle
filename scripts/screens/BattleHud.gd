extends RefCounted
## BattleHud: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")

static func _build_battle_screen(main) -> void:
	main.base_warning_fired = false; main.client_purchase_gates.clear(); main.sound_gate.clear()
	main.battle_active = true
	main.result_shown = false
	main.updater.set_safe_to_update(false)
	main._clear_screen()
	main.root_background = main._make_background()

	var top := ColorRect.new()
	top.color = Color("#0b0d13")
	top.position = Vector2.ZERO
	top.size = Vector2(1280, 88)
	main.root_background.add_child(top)
	var top_line := ColorRect.new()
	top_line.color = Color(1.0, 1.0, 1.0, 0.08)
	top_line.position = Vector2(0, 87)
	top_line.size = Vector2(1280, 1)
	top.add_child(top_line)
	main._create_hp_card(top, Vector2(18, 12), main.own_side)
	main._create_hp_card(top, Vector2(842, 12), 1 - main.own_side)

	var timer_card := PanelContainer.new()
	timer_card.position = Vector2(530, 12)
	timer_card.size = Vector2(220, 64)
	timer_card.add_theme_stylebox_override("panel", main._panel_style(Color("#141720"), Color(1.0, 1.0, 1.0, 0.08), 10))
	top.add_child(timer_card)
	var timer_inner := Control.new()
	timer_inner.custom_minimum_size = Vector2(220, 64)
	timer_card.add_child(timer_inner)
	main.timer_label = Label.new()
	main.timer_label.position = Vector2(0, 7)
	main.timer_label.size = Vector2(220, 34)
	main.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.timer_label.add_theme_font_size_override("font_size", 25)
	main.timer_label.add_theme_color_override("font_color", Color("#f5f7fb"))
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
	controls.color = Color("#0b0d13")
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
	var own_color := Color("#5b8cff")
	resource_card.add_theme_stylebox_override("panel", main._panel_style(Color("#141720"), Color(own_color.r, own_color.g, own_color.b, 0.48), 10))
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
	main.resource_label.add_theme_font_size_override("font_size", 25)
	main.resource_label.add_theme_color_override("font_color", Color("#f6c85f"))
	resource_inner.add_child(main.resource_label)
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

static func _create_hp_card(main, parent: Control, position_value: Vector2, side: int) -> void:
	var card := PanelContainer.new()
	card.position = position_value
	card.size = Vector2(420, 64)
	var color := Color("#5b8cff") if side == main.own_side else Color("#ff627d")
	card.add_theme_stylebox_override("panel", main._panel_style(Color("#141720"), Color(color.r, color.g, color.b, 0.34), 10))
	parent.add_child(card)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(420, 64)
	card.add_child(inner)
	var faction := Label.new()
	faction.text = "아군 기지" if side == main.own_side else "적군 기지"
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
	hp_bar.add_theme_stylebox_override("background", main._panel_style(Color("#080a0f"), Color(1.0, 1.0, 1.0, 0.05), 6))
	hp_bar.add_theme_stylebox_override("fill", main._panel_style(color, color, 6))
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
	main._decorate_battle_card(button)
	var portrait := Sprite2D.new()
	portrait.name = "BattleUnitPortrait"
	portrait.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	portrait.position = Vector2(68, 25)
	portrait.scale = Vector2(0.17, 0.17)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	button.add_child(portrait)
	button.pressed.connect(main._purchase_unit.bind(kind))
	row.add_child(button)

static func _decorate_battle_card(main, button: Button) -> void:
	button.add_theme_font_size_override("font_size", 12)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var style := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		style.content_margin_top = 52
		style.content_margin_bottom = 5
		style.content_margin_left = 4
		style.content_margin_right = 4
		button.add_theme_stylebox_override(state, style)

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
	main._decorate_battle_card(button)
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
	var hotkey := Label.new(); hotkey.name = "PurchaseHotkey"; hotkey.text = key_text; hotkey.position = Vector2(6,4); hotkey.add_theme_font_size_override("font_size",11); hotkey.add_theme_color_override("font_color",Color("#d2d8e8")); hotkey.mouse_filter = Control.MOUSE_FILTER_IGNORE; button.add_child(hotkey)
	var state := Label.new(); state.name = "PurchaseState"; state.position = Vector2(28,2); state.size = Vector2(106,18); state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT; state.add_theme_font_size_override("font_size",10); state.add_theme_color_override("font_color",Color("#f0d592")); state.mouse_filter = Control.MOUSE_FILTER_IGNORE; state.add_theme_stylebox_override("normal",main._panel_style(Color(0.03,0.04,0.06,0.9),Color.TRANSPARENT,3)); button.add_child(state)

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
	panel.add_theme_stylebox_override("panel", main._panel_style(Color("#10141e"), Color("#3d8f83"), 16))
	main.stats_overlay.add_child(panel)
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
		card.add_theme_stylebox_override("panel", main._panel_style(Color("#171c28"), Color(1.0, 1.0, 1.0, 0.09), 10))
		grid.add_child(card)
		var card_margin := MarginContainer.new()
		card_margin.add_theme_constant_override("margin_left", 16)
		card_margin.add_theme_constant_override("margin_right", 16)
		card_margin.add_theme_constant_override("margin_top", 12)
		card_margin.add_theme_constant_override("margin_bottom", 12)
		card.add_child(card_margin)
		var label := Label.new()
		label.text = "%s\n%s" % [names[kind], BattleModel.unit_stat_summary(kind, int(main.local_model.campaign_levels[main.own_side]) if main.local_ai_mode and is_instance_valid(main.local_model) else 0)]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color("#dce1ec"))
		card_margin.add_child(label)
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
		if button.disabled != unavailable:
			button.disabled = unavailable
			button.modulate = Color(0.4, 0.4, 0.4, 1.0) if unavailable else Color.WHITE
		if state_label: state_label.modulate = Color(2.5,2.5,2.5,1.0) if unavailable else Color.WHITE
		if unavailable and button.has_meta("structure_kind") and is_instance_valid(main.battle_view) and main.battle_view.selected_structure == String(button.get_meta("structure_kind")):
			main.battle_view.selected_structure = ""
			clear_selection = true
	if clear_selection:
		main._refresh_structure_selection()
