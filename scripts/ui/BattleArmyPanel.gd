extends PanelContainer
## Live, read-only population comparison, sharing the battle reference modal lifecycle.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const LocalBattlePause = preload("res://scripts/screens/LocalBattlePause.gd")

var main
var status: Label
var capacity: Label
var totals: Dictionary = {}
var amounts: Dictionary = {}
var scroll: ScrollContainer
var focus_controls: Array[Control] = []

func setup(owner_main, selected_side: int) -> void:
	main = owner_main
	name = "BattleArmyPanel"
	add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(UIKit.TEAL, 16, 1.0), 22, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(_label("전장 병력 현황", 26, UIKit.TEXT))
	status = _label("", 14, UIKit.TEXT_MUTED)
	status.name = "ArmyState"
	column.add_child(status)
	capacity = _label("", 16, UIKit.TEXT)
	capacity.name = "ArmyCapacity"
	column.add_child(capacity)
	var hint := _label("양쪽 병력·소환수가 공유 한도를 채우면 생산·추가 소환이 멈춥니다. 사망한 병력이 정리되면 다시 생산합니다.\n소환수는 생존 병력에 포함되고, 구조물은 별도 한도입니다. 휠·터치·PageUp/PageDown으로 이동하세요.", 14, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var header := HBoxContainer.new()
	column.add_child(header)
	var kind_heading := _label("병력 종류", 16, UIKit.TEXT_MUTED)
	kind_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(kind_heading)
	# Keep the same row/column order when numbers change, including zero counts.
	var sides: Array = [main.own_side, 1 - main.own_side]
	for side in sides:
		var side_name := "블루" if int(side) == 0 else "레드"
		if not main.network.client_is_spectator: side_name = "아군" if int(side) == main.own_side else "적군"
		var title := _label(side_name + (" · 선택" if int(side) == selected_side else ""), 18, UIKit.TEAM_BLUE if int(side) == 0 else UIKit.TEAM_RED)
		title.custom_minimum_size.x = 200
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(title)
	var total_row := HBoxContainer.new()
	column.add_child(total_row)
	var total_heading := _label("살아 있는 병력", 16, UIKit.TEXT)
	total_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	total_row.add_child(total_heading)
	for side in sides:
		var total := _number_label()
		total.name = "ArmyTotal%d" % int(side)
		total_row.add_child(total)
		totals[side] = total
	scroll = ScrollContainer.new()
	scroll.name = "ArmyKindsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	column.add_child(scroll)
	focus_controls.append(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 6)
	scroll.add_child(rows)
	for kind in BattleModel.UNIT_NAMES:
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 44
		rows.add_child(row)
		var title := _label(String(BattleModel.UNIT_NAMES[kind]) + (" · 소환" if BattleModel.SUMMON_STATS.has(kind) else ""), 18, UIKit.UNIT_COLORS.get(kind, UIKit.TEXT))
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(title)
		amounts[kind] = {}
		for side in sides:
			var amount := _number_label()
			amount.name = "ArmyKind_%s_%d" % [kind, int(side)]
			row.add_child(amount)
			amounts[kind][side] = amount
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var reference := _button("유닛 스탯", "ArmyOpenStats", main._show_stats_panel)
	actions.add_child(reference)
	actions.add_child(_button("구조물 현황", "ArmyOpenStructures", main._show_structure_panel))
	var close := _button("닫기 · Esc", "CloseArmyDetails", main._dismiss_stats_panel)
	actions.add_child(close)
	close.grab_focus()

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _number_label() -> Label:
	var label := _label("—", 16, UIKit.TEXT)
	label.custom_minimum_size.x = 200
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label

func _button(text: String, node_name: String, callback: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 58
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	UIKit.style_button(button, UIKit.TEAL)
	button.pressed.connect(callback)
	focus_controls.append(button)
	return button

func refresh(counts: Dictionary, awaiting: bool) -> void:
	var state := "최신 전투 상태를 기다리고 있습니다." if awaiting else "전투 일시정지 중" if LocalBattlePause.is_paused(main) else "온라인 전투 진행 중 · 최신 수신 상태"
	if not awaiting and (main.result_shown or main.finale_active or int(main.current_snapshot.get("winner", -1)) != -1): state = "전투 종료 · 마지막 병력 현황"
	_set_text(status, state)
	var pending := int(counts.occupied) - int(counts.living[0]) - int(counts.living[1])
	var summary := "전장 병력 — / %d" % BattleModel.MAX_ACTIVE_UNITS if awaiting else "전장 병력 %d / %d · 생존 %d · 정리 대기 %d" % [int(counts.occupied), BattleModel.MAX_ACTIVE_UNITS, int(counts.living[0]) + int(counts.living[1]), pending]
	var full: bool = not awaiting and int(counts.occupied) >= BattleModel.MAX_ACTIVE_UNITS
	if full: summary += " · 생산 한도"
	_set_text(capacity, summary)
	var tone := UIKit.GOLD if full else UIKit.TEXT
	if capacity.get_theme_color("font_color") != tone: capacity.add_theme_color_override("font_color", tone)
	for side in totals:
		_set_text(totals[side], "—" if awaiting else "%d명 · 소환 %d명 포함" % [int(counts.living[side]), int(counts.summons[side])])
	for kind in amounts:
		for side in amounts[kind]:
			_set_text(amounts[kind][side], "—" if awaiting else "%d명" % int(counts.kinds[side].get(kind, 0)))

func _set_text(label: Label, text: String) -> void:
	if label.text != text: label.text = text

func handle_key(event: InputEventKey) -> bool:
	if not event.pressed: return false
	if event.keycode == KEY_F11:
		if not event.echo: main._set_fullscreen(not bool(main.save_data.settings.fullscreen))
		return true
	if event.keycode == KEY_ESCAPE:
		if not event.echo: main._dismiss_stats_panel()
		return true
	if event.keycode == KEY_TAB:
		var index := focus_controls.find(get_viewport().gui_get_focus_owner())
		focus_controls[posmod(index + (-1 if event.shift_pressed else 1), focus_controls.size())].grab_focus()
		return true
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	match event.keycode:
		KEY_PAGEUP: scroll.scroll_vertical -= maxi(1, int(scroll.size.y) - 32)
		KEY_PAGEDOWN: scroll.scroll_vertical += maxi(1, int(scroll.size.y) - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return false
	return true
