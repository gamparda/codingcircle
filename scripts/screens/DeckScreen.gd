extends RefCounted
## DeckScreen: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")

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
			card_text = Localization.text("%s\n비용 %d · HP %d · 범위 %d\n공속 +%d%% 영구 · 상한 +%d%% · 쿨 %d초") % [unit_names[kind], int(stats.cost), int(stats.hp), int(stats.range), roundi(BattleModel.SUPPORT_INCREMENT * 100.0), roundi(BattleModel.SUPPORT_INCREMENT * BattleModel.SUPPORT_MAX_STACKS * 100.0), int(stats.interval)]
		var card = main._styled_button(card_text, Color("#5b8cff"), false)
		card.name = "DeckUnit_" + kind
		card.tooltip_text = BattleModel.unit_stat_summary(kind)
		card.add_theme_font_size_override("font_size", 13)
		main._configure_deck_card(card, card_text, Color("#5b8cff"), selected.units.has(kind))
		card.custom_minimum_size = Vector2(240, 108)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_dress_card(card, UIKit.UNIT_COLORS[kind], kind, true)
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
	var structure_stats: Dictionary = BattleModel.STRUCTURE_STATS
	var roles := {
		"wall": Localization.text("뒤 대상을 차폐 · 최대 %d") % int(structure_stats.wall.max_count),
		"swamp": Localization.text("반경 %d · %d%% 감속 · %d초") % [int(structure_stats.swamp.radius), roundi((1.0 - float(structure_stats.swamp.speed_scale)) * 100.0), int(structure_stats.swamp.lifetime)],
		"turret": Localization.text("사거리 %d · 최대 %d") % [int(structure_stats.turret.range), int(structure_stats.turret.max_count)],
		"generator": Localization.text("후방 전용 · 초당 +%d") % int(structure_stats.generator.income),
	}
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
		_dress_card(card, Color("#3ec6b0"), kind, false)
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
	card.set_pressed_no_signal(selected)
	main._refresh_deck_card(card)
	card.toggled.connect(func(_pressed): main._refresh_deck_card(card))

## Replaces the flat button look with a portrait card: art on the left, text on the right,
## gold frame and a check badge when selected.
static func _dress_card(card: Button, color: Color, kind: String, is_unit: bool) -> void:
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # wrapped text must not widen the grid beyond the panel
	card.add_theme_font_size_override("font_size", 12)
	card.add_theme_color_override("font_pressed_color", Color.WHITE)
	card.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	var normal := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.10), UIKit.SURFACE.darkened(0.14), Color(color.r, color.g, color.b, 0.45), 14, 1.0, 0.45, Color(0, 0, 0, 0), 0.08)
	var hover := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.22), UIKit.SURFACE.lerp(color, 0.08), color.lightened(0.3), 14, 1.5, 0.8, Color(color.r, color.g, color.b, 0.45), 0.16)
	var chosen := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.42), UIKit.SURFACE.lerp(color, 0.20), UIKit.GOLD, 14, 2.0, 0.9, Color(1.0, 0.84, 0.4, 0.45), 0.2)
	var chosen_hover := UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.52), UIKit.SURFACE.lerp(color, 0.28), UIKit.GOLD.lightened(0.2), 14, 2.0, 1.0, Color(1.0, 0.84, 0.4, 0.55), 0.24)
	var map := {"normal": normal, "hover": hover, "pressed": chosen, "hover_pressed": chosen_hover, "disabled": normal}
	for state in map:
		var style: StyleBox = map[state].duplicate()
		style.content_margin_left = 90
		style.content_margin_right = 8
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		card.add_theme_stylebox_override(state, style)
	UIKit.juice(card, 1.015)
	var art := Control.new()
	art.name = "CardArt"
	art.position = Vector2(8, 0)
	art.size = Vector2(80, 108)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(art)
	art.draw.connect(func():
		var center := Vector2(40, card.size.y * 0.5)
		for i in 5:
			var t := float(i) / 4.0
			art.draw_circle(center, 38.0 - t * 22.0, Color(color.r, color.g, color.b, 0.07 + t * 0.08)))
	card.resized.connect(art.queue_redraw)
	if is_unit:
		var sprite := Sprite2D.new()
		sprite.name = "DeckUnitPortrait"
		sprite.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.scale = Vector2(0.2, 0.2)
		art.add_child(sprite)
		var place := func(): sprite.position = Vector2(40, card.size.y * 0.5)
		card.resized.connect(place)
		place.call()
	else:
		var emblem := Label.new()
		emblem.text = {"wall": "▤", "swamp": "≈", "turret": "⌖", "generator": "⚡"}.get(kind, "◆")
		emblem.size = Vector2(80, 108)
		emblem.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		emblem.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		emblem.add_theme_font_size_override("font_size", 40)
		emblem.add_theme_color_override("font_color", color.lightened(0.25))
		emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(emblem)
	var badge := Label.new()
	badge.name = "SelectedBadge"
	badge.text = "✓"
	badge.size = Vector2(24, 24)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 14)
	badge.add_theme_color_override("font_color", Color("#2b1d02"))
	var pill := StyleBoxFlat.new()
	pill.bg_color = UIKit.GOLD
	pill.set_corner_radius_all(12)
	pill.anti_aliasing = true
	badge.add_theme_stylebox_override("normal", pill)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(badge)
	var place_badge := func(): badge.position = Vector2(card.size.x - 32, 8)
	card.resized.connect(place_badge)
	place_badge.call()
	badge.visible = card.button_pressed
	card.toggled.connect(func(pressed):
		badge.visible = pressed
		UIKit.UISounds.play("toggle"))

static func _refresh_deck_card(main, card: Button) -> void:
	var marker := Localization.text("✓ 선택됨") if card.button_pressed else Localization.text("○ 선택 가능")
	card.text = marker + "\n" + String(card.get_meta("deck_base_text", ""))
