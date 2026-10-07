extends RefCounted
## DeckScreen: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")

static func _build_deck_screen(main, preset_index: int = -1) -> void:
	var index := int(main.save_data.last_deck) if preset_index < 0 else clampi(preset_index, 0, 2)
	var column = main._submenu(Localization.text("덱 편성"), "유닛 3종 · 구조물 3종 선택")
	var deck_panel := column.get_parent() as PanelContainer
	deck_panel.name = "DeckPanel"
	deck_panel.position = Vector2(110, 18)
	deck_panel.size = Vector2(1060, 684)
	column.add_theme_constant_override("separation", 8)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	for tab_index in 3:
		var tab = main._styled_button(String(main.save_data.deck_presets[tab_index].name), Color("#5e6ad2"), tab_index == index)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(main._build_deck_screen.bind(tab_index))
		tabs.add_child(tab)
	var name_edit := LineEdit.new()
	name_edit.text = String(main.save_data.deck_presets[index].name)
	name_edit.placeholder_text = Localization.text("프리셋 이름")
	column.add_child(name_edit)
	var selected: Dictionary = main.save_data.deck_presets[index]
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
		var card = main._styled_button(card_text, Color("#5b8cff"), false)
		card.name = "DeckUnit_" + kind
		card.tooltip_text = BattleModel.unit_stat_summary(kind)
		card.add_theme_font_size_override("font_size", 13)
		main._configure_deck_card(card, card_text, Color("#5b8cff"), selected.units.has(kind))
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
		var card = main._styled_button(card_text, Color("#3d8f83"), false)
		card.name = "DeckStructure_" + kind
		card.add_theme_font_size_override("font_size", 13)
		main._configure_deck_card(card, card_text, Color("#3d8f83"), selected.structures.has(kind))
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
	var save_button = main._styled_button(Localization.text("덱 저장 및 사용"), Color("#5e6ad2"), true)
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
		main.save_data.deck_presets[index] = {"name": name_edit.text.strip_edges().left(20) if not name_edit.text.strip_edges().is_empty() else Localization.text("덱 %d") % (index + 1), "units": selected_units, "structures": selected_structures}
		main.save_data.last_deck = index
		SaveData.save_data(main.save_data)
		main._build_connect_screen(Localization.text("덱을 저장했습니다."))
	)
	actions.add_child(save_button)
	var back = main._styled_button(Localization.text("취소"), Color("#697386"), false)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(main._build_connect_screen)
	actions.add_child(back)

static func _configure_deck_card(main, card: Button, base_text: String, color: Color, selected: bool) -> void:
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
	main._refresh_deck_card(card)
	card.toggled.connect(func(_pressed): main._refresh_deck_card(card))

static func _refresh_deck_card(main, card: Button) -> void:
	var marker := Localization.text("✓ 선택됨") if card.button_pressed else Localization.text("○ 선택 가능")
	card.text = marker + "\n" + String(card.get_meta("deck_base_text", ""))
