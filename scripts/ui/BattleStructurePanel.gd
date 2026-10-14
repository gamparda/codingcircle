extends PanelContainer
## Read-only live structure comparison; updates reuse six slots and the battle modal lifecycle.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const LocalBattlePause = preload("res://scripts/screens/LocalBattlePause.gd")
const OverviewNavigation = preload("res://scripts/ui/BattleOverviewNavigation.gd")
const StructureLifetime = preload("res://scripts/ui/StructureLifetime.gd")
const NAMES := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}

var main
var status: Label
var totals: Dictionary = {}
var amounts: Dictionary = {}
var incomes: Dictionary = {}
var slots: Dictionary = {}
var scroll: ScrollContainer
var focus_controls: Array[Control] = []
var navigation_pending := false

func setup(owner_main) -> void:
	main = owner_main
	name = "BattleStructurePanel"
	add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(UIKit.TEAL, 16, 1.0), 22, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	column.add_child(_label("전장 구조물 현황", 26, UIKit.TEXT))
	status = _label("", 14, UIKit.TEXT_MUTED)
	column.add_child(status)
	var hint := _label("종류별 수를 누르면 해당 진영의 구조물 스탯·설치 조건을 바로 확인합니다.\n한도는 진영별로 적용되며 파괴·수명 종료 후 재설치할 수 있습니다. 위치는 후방 0% → 전방 100%, 수명·수입·만료 시각은 전투 시간 기준입니다. 남은 수명 2초 이하는 만료 임박으로 표시합니다.", 14, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	scroll = ScrollContainer.new()
	scroll.name = "StructureDetailsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	column.add_child(scroll)
	focus_controls.append(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	for side in [main.own_side, 1 - main.own_side]:
		var side_column := VBoxContainer.new()
		side_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		side_column.add_theme_constant_override("separation", 8)
		columns.add_child(side_column)
		var tone := UIKit.TEAM_BLUE if int(side) == 0 else UIKit.TEAM_RED
		var side_name := "블루" if int(side) == 0 else "레드"
		if not main.network.client_is_spectator: side_name = "아군" if int(side) == main.own_side else "적군"
		side_column.add_child(_label(side_name, 22, tone))
		totals[side] = _label("", 18, UIKit.TEXT)
		side_column.add_child(totals[side])
		amounts[side] = {}
		for kind in NAMES:
			var amount := _button("", "StructureStats_%s_%d" % [kind, int(side)], _open_kind.bind(kind, int(side)))
			amount.alignment = HORIZONTAL_ALIGNMENT_LEFT
			amount.add_theme_font_size_override("font_size", 16)
			amount.tooltip_text = "%s · %s 진영의 스탯·설치 조건 확인" % [NAMES[kind], side_name]
			side_column.add_child(amount)
			amounts[side][kind] = amount
		incomes[side] = _label("", 16, UIKit.TEAL)
		side_column.add_child(incomes[side])
		side_column.add_child(_label("설치 순서 · 남은 체력·수명", 16, UIKit.TEXT_MUTED))
		slots[side] = []
		for _index in BattleModel.STRUCTURE_LIMIT:
			var slot := VBoxContainer.new()
			slot.custom_minimum_size.y = 96
			slot.add_theme_constant_override("separation", 4)
			side_column.add_child(slot)
			var title := _label("", 17, UIKit.TEXT)
			slot.add_child(title)
			var health := ProgressBar.new()
			health.custom_minimum_size.y = 12
			health.show_percentage = false
			health.mouse_filter = Control.MOUSE_FILTER_IGNORE
			health.add_theme_stylebox_override("background", UIKit.box(UIKit.SURFACE, UIKit.SURFACE, Color.TRANSPARENT, 6))
			health.add_theme_stylebox_override("fill", UIKit.box(tone, tone, Color.TRANSPARENT, 6))
			slot.add_child(health)
			var detail := _label("", 14, UIKit.TEXT_MUTED)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slot.add_child(detail)
			var lifetime := _label("", 14, UIKit.TEXT_MUTED)
			lifetime.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			slot.add_child(lifetime)
			slots[side].append({"title": title, "health": health, "detail": detail, "lifetime": lifetime})
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	actions.add_child(_button("유닛 스탯", "StructureOpenStats", main._show_stats_panel))
	actions.add_child(_button("병력 현황", "StructureOpenArmy", main._show_army_panel.bind(main.own_side)))
	var close := _button("닫기 · Esc", "CloseStructureDetails", main._dismiss_stats_panel)
	actions.add_child(close)
	close.grab_focus()
	OverviewNavigation.configure(self)

func _open_kind(kind: String, side: int) -> void:
	var navigation := OverviewNavigation.capture(self)
	navigation["focus"] = "StructureStats_%s_%d" % [kind, side]
	main._show_stats_reference(1, kind, side, navigation)

func refresh(values: Array, counts: Array, elapsed: float, awaiting: bool) -> void:
	var state := "최신 전투 상태를 기다리고 있습니다." if awaiting else "전투 일시정지 중" if LocalBattlePause.is_paused(main) else "온라인 전투 진행 중 · 최신 수신 상태"
	if not awaiting and (main.result_shown or main.finale_active or int(main.current_snapshot.get("winner", -1)) != -1): state = "전투 종료 · 마지막 구조물 현황"
	_set_text(status, state)
	var living: Array = [[], []]
	if not awaiting:
		for structure in values:
			if float(structure.get("hp", 0.0)) > 0.0: living[int(structure.side)].append(structure)
		for side in 2:
			living[side].sort_custom(func(a: Dictionary, b: Dictionary): return int(a.id) < int(b.id))
	for side in totals:
		var total := int(counts[side].total)
		_set_text(totals[side], "설치 — / %d" % BattleModel.STRUCTURE_LIMIT if awaiting else "설치 %d / %d%s" % [total, BattleModel.STRUCTURE_LIMIT, " · 전체 한도" if total >= BattleModel.STRUCTURE_LIMIT else ""])
		_set_color(totals[side], UIKit.GOLD if not awaiting and total >= BattleModel.STRUCTURE_LIMIT else UIKit.TEXT)
		for kind in NAMES:
			var amount := int(counts[side].kinds.get(kind, 0))
			var limit := int(BattleModel.STRUCTURE_STATS[kind].get("max_count", BattleModel.STRUCTURE_LIMIT))
			_set_text(amounts[side][kind], "%s — / %d ▸" % [NAMES[kind], limit] if awaiting else "%s %d / %d%s ▸" % [NAMES[kind], amount, limit, " · 종류 한도" if amount >= limit else ""])
			_set_color(amounts[side][kind], UIKit.GOLD if not awaiting and amount >= limit else UIKit.TEXT)
		_set_text(incomes[side], "발전기 추가 수입 —" if awaiting else "발전기 추가 수입 +%.1f/전투 초" % (int(counts[side].kinds.get("generator", 0)) * float(BattleModel.STRUCTURE_STATS.generator.income)))
		for index in slots[side].size():
			var slot: Dictionary = slots[side][index]
			var present: bool = not awaiting and index < living[side].size()
			slot.health.visible = present
			if not present:
				_set_text(slot.title, "상태 수신 대기" if awaiting and index == 0 else "설치된 구조물이 없습니다." if index == 0 else "")
				_set_text(slot.detail, "")
				_set_text(slot.lifetime, "")
				slot.lifetime.hide()
				_set_color(slot.title, UIKit.TEXT_MUTED)
				continue
			var structure: Dictionary = living[side][index]
			var kind := String(structure.kind)
			var hp := float(structure.hp)
			var maximum := maxf(1.0, float(structure.get("max_hp", BattleModel.STRUCTURE_STATS[kind].hp)))
			var fraction := clampf(hp / maximum, 0.0, 1.0)
			var rear := BattleModel.BLUE_BUILD_MIN if int(side) == 0 else BattleModel.RED_BUILD_MAX
			var front := BattleModel.BLUE_BUILD_MAX if int(side) == 0 else BattleModel.RED_BUILD_MIN
			var position_percent := roundi(clampf((float(structure.x) - rear) / (front - rear), 0.0, 1.0) * 100.0)
			_set_text(slot.title, "%s · 건설 구역 %d%%" % [NAMES.get(kind, kind), position_percent])
			_set_color(slot.title, UIKit.DANGER if fraction <= 0.25 else UIKit.TEXT)
			var detail := "체력 %d / %d · %d%%%s" % [ceili(hp), ceili(maximum), roundi(fraction * 100.0), " · 파괴 주의" if fraction <= 0.25 else ""]
			_set_text(slot.detail, detail)
			slot.lifetime.show()
			var remaining := StructureLifetime.remaining(structure, elapsed)
			if remaining >= 0.0:
				var lifetime_text := "수명 %s · 만료 %s" % [StructureLifetime.countdown(remaining), StructureLifetime.expiry_clock(structure)]
				if remaining <= 0.0: lifetime_text = "만료 상태 확인 중 · 예정 %s" % StructureLifetime.expiry_clock(structure)
				elif remaining <= StructureLifetime.WARNING_SECONDS: lifetime_text += " · 만료 임박"
				_set_text(slot.lifetime, lifetime_text)
				_set_color(slot.lifetime, UIKit.GOLD if remaining <= StructureLifetime.WARNING_SECONDS else UIKit.TEXT_MUTED)
			else:
				_set_text(slot.lifetime, "수명 정보 없음" if BattleModel.STRUCTURE_STATS[kind].has("lifetime") else "수명 제한 없음 · 파괴될 때까지 유지")
				_set_color(slot.lifetime, UIKit.TEXT_MUTED)
			if not is_equal_approx(slot.health.max_value, maximum): slot.health.max_value = maximum
			if not is_equal_approx(slot.health.value, hp): slot.health.value = hp

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

func _set_text(label, text: String) -> void:
	if label.text != text: label.text = text

func _set_color(label: Control, color: Color) -> void:
	if label.get_theme_color("font_color") != color: label.add_theme_color_override("font_color", color)

func handle_key(event: InputEventKey) -> bool:
	if not event.pressed: return false
	navigation_pending = false
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
