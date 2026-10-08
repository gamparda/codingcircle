extends RefCounted
## Draft mode screen: a shared pool of units, alternate picks with the AI, then a normal battle.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const DraftMatch = preload("res://scripts/DraftMatch.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")

static func _build_draft_screen(main, stage: int = 3) -> void:
	var draft := DraftMatch.Draft.new(stage)
	var column = main._submenu("드래프트", "번갈아 병력을 고르세요. 한 번 뽑힌 병력은 상대가 쓸 수 없습니다.")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	column.add_child(top)
	var status := Label.new()
	status.name = "DraftStatus"
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", UIKit.GOLD)
	top.add_child(status)
	top.add_child(_label("상대 단계", 14, UIKit.TEXT_MUTED))
	var stage_picker := OptionButton.new()
	stage_picker.name = "DraftStagePicker"
	for number in range(ServerAI.MIN_STAGE, ServerAI.MAX_STAGE + 1):
		stage_picker.add_item("%02d단계 · %s" % [number, ServerAI.stage_name(number)], number)
	stage_picker.select(draft.stage - ServerAI.MIN_STAGE)
	top.add_child(stage_picker)
	var grid := GridContainer.new()
	grid.name = "DraftPool"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	var cards := {}
	for kind in DraftMatch.pool():
		var card := _card(String(kind))
		cards[kind] = card
		grid.add_child(card)
	var rows := HBoxContainer.new()
	rows.add_theme_constant_override("separation", 24)
	column.add_child(rows)
	var mine_row := _pick_row("내 덱", UIKit.TEAM_BLUE, "DraftMine")
	var theirs_row := _pick_row("상대 덱", UIKit.TEAM_RED, "DraftTheirs")
	rows.add_child(mine_row.root)
	rows.add_child(theirs_row.root)
	var start = main._styled_button(Localization.text("전투 시작"), UIKit.ACCENT, true)
	start.name = "DraftStart"
	start.custom_minimum_size.y = 52
	column.add_child(start)
	var again = main._styled_button(Localization.text("다시 뽑기"), UIKit.TEAL, false)
	again.name = "DraftReset"
	column.add_child(again)
	var back = main._styled_button(Localization.text("메인 화면으로"), Color("#697386"), false)
	back.name = "DraftBack"
	back.pressed.connect(main._build_connect_screen)
	column.add_child(back)

	var refresh := func():
		for kind in cards:
			cards[kind].disabled = not draft.available.has(kind) or draft.mine.size() >= DraftMatch.PICKS_PER_SIDE
			cards[kind].modulate = Color(1, 1, 1, 1.0 if draft.available.has(kind) else 0.35)
		_fill_row(mine_row.slots, draft.mine)
		_fill_row(theirs_row.slots, draft.theirs)
		start.disabled = not draft.done()
		status.text = Localization.text("전투 준비가 끝났습니다. 전투 시작을 누르세요.") if draft.done() else Localization.text("당신의 차례 · 병력을 고르세요 (%d / %d)") % [draft.mine.size() + 1, DraftMatch.PICKS_PER_SIDE]
	for kind in cards:
		cards[kind].pressed.connect(func():
			draft.human_pick(String(kind))
			refresh.call())
	stage_picker.item_selected.connect(func(index): _build_draft_screen(main, stage_picker.get_item_id(index)))
	again.pressed.connect(func(): _build_draft_screen(main, draft.stage))
	start.pressed.connect(func():
		if draft.done():
			main._start_draft_battle(draft.mine, draft.theirs, draft.stage))
	refresh.call()

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = Localization.text(text)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func _card(kind: String) -> Button:
	var stats: Dictionary = BattleModel.UNIT_STATS[kind]
	var community := MetaStats.kind_text("units", kind)
	var card := Button.new()
	card.name = "DraftCard_" + kind
	card.custom_minimum_size = Vector2(250, 92)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.text = "%s\n%s\n%s" % [BattleModel.UNIT_NAMES[kind], Localization.text("비용 %d · HP %d") % [int(stats.cost), int(stats.hp)], community if community != "" else BattleModel.unit_role(kind)]
	card.tooltip_text = BattleModel.unit_stat_summary(kind)
	UIKit.style_button(card, UIKit.UNIT_COLORS.get(kind, UIKit.ACCENT), false, 13)
	var icon := TextureRect.new()
	icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	icon.position = Vector2(8, 6)
	icon.size = Vector2(56, 80)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := card.get_theme_stylebox(state).duplicate()
		style.content_margin_left = 74
		card.add_theme_stylebox_override(state, style)
	return card

static func _pick_row(title: String, color: Color, node_name: String) -> Dictionary:
	var root := VBoxContainer.new()
	root.name = node_name
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(_label(title, 14, color.lightened(0.25)))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	root.add_child(line)
	var slots: Array = []
	for index in DraftMatch.PICKS_PER_SIDE:
		var slot := TextureRect.new()
		slot.custom_minimum_size = Vector2(54, 72)
		slot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		slot.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		slot.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		line.add_child(slot)
		slots.append(slot)
	return {"root": root, "slots": slots}

static func _fill_row(slots: Array, picks: Array) -> void:
	for index in slots.size():
		if index < picks.size():
			var kind := String(picks[index])
			slots[index].texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
			slots[index].tooltip_text = String(BattleModel.UNIT_NAMES[kind])
			slots[index].modulate = Color.WHITE
		else:
			slots[index].texture = null
			slots[index].tooltip_text = ""
