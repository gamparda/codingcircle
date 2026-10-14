extends PanelContainer
## Live, read-only population comparison, sharing the battle reference modal lifecycle.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const LocalBattlePause = preload("res://scripts/screens/LocalBattlePause.gd")
const OverviewNavigation = preload("res://scripts/ui/BattleOverviewNavigation.gd")
const ArmyComposition = preload("res://scripts/ui/ArmyComposition.gd")

# Each living kind belongs to one primary role; summons are part of the front line.
# These are presentation groups, independent of combat rules and deck eligibility.
const ARMY_ROLES = ArmyComposition.ROLES

var main
var status: Label
var capacity: Label
var economy_summary: Label
var totals: Dictionary = {}
var amounts: Dictionary = {}
var kind_rows: Dictionary = {}
var role_amounts: Dictionary = {}
var role_rows: Dictionary = {}
var role_titles: Dictionary = {}
var role_buttons: Dictionary = {}
var all_kinds_button: Button
var role_hint: Label
var kinds_heading: Label
var active_role := ""
var scroll: ScrollContainer
var focus_controls: Array[Control] = []
var selected_side := 0
var navigation_pending := false

func setup(owner_main, side_selection: int, role_selection: String = "") -> void:
	main = owner_main
	selected_side = side_selection
	active_role = role_selection if ARMY_ROLES.has(role_selection) else ""
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
	var hint := _label("아군 열은 생존 수와 다음 생산 조건을 함께 보여 줍니다. 예상은 현재 회복·생산 대기 기준이며 추가 구매·발전기 파괴로 달라집니다.\n종류 이름·진영별 수를 누르면 스탯을 확인합니다. 이 화면에서는 생산하지 않습니다. 공유 한도는 양쪽 병력·소환수를 포함하며 사망 후 정리되면 빈자리가 생깁니다.", 14, UIKit.TEXT_MUTED)
	if main.network.client_is_spectator:
		hint.text = "관전 중에는 양쪽 생존 수·소환수·공유 한도를 확인합니다. 종류 이름·진영별 수를 누르면 스탯을 확인합니다.\n공유 한도는 양쪽 병력·소환수를 포함하며 사망 후 정리되면 빈자리가 생깁니다. 구조물은 별도 한도를 사용합니다."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	economy_summary = _label("최신 전투 상태를 받은 뒤 자원·생산 조건을 표시합니다.", 14, UIKit.TEXT_MUTED)
	economy_summary.name = "ArmyEconomy"
	economy_summary.custom_minimum_size.y = 42
	economy_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(economy_summary)
	var header := HBoxContainer.new()
	column.add_child(header)
	var kind_heading := _label("진영별 생존 병력", 16, UIKit.TEXT_MUTED)
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
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	column.add_child(filters)
	all_kinds_button = _button("모든 병력 보기", "ArmyRoleAll", _select_role.bind(""))
	all_kinds_button.add_theme_font_size_override("font_size", 14)
	filters.add_child(all_kinds_button)
	for role in ARMY_ROLES:
		var button := _button(String(ARMY_ROLES[role].title), "ArmyRole_%s" % role, _select_role.bind(role))
		button.add_theme_font_size_override("font_size", 14)
		button.tooltip_text = "%s의 병력 종류만 보기 · 다시 누르면 모든 병력 보기" % ARMY_ROLES[role].title
		filters.add_child(button)
		role_buttons[role] = button
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
	rows.add_child(_label("역할별 생존 구성 · 각 진영의 전체 생존 병력 중 비율", 16, UIKit.TEXT))
	for role in ARMY_ROLES:
		var role_row := HBoxContainer.new()
		rows.add_child(role_row)
		role_rows[role] = role_row
		var title := _label(String(ARMY_ROLES[role].title) + (" · 소환 포함" if role == "front" else ""), 14, UIKit.TEXT_MUTED)
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		role_row.add_child(title)
		role_titles[role] = title
		role_amounts[role] = {}
		for side in sides:
			var amount := _number_label()
			amount.name = "ArmyRoleAmount_%s_%d" % [role, int(side)]
			role_row.add_child(amount)
			role_amounts[role][side] = amount
	role_hint = _label("", 14, UIKit.TEXT_MUTED)
	role_hint.name = "ArmyRoleHint"
	role_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(role_hint)
	kinds_heading = _label("", 16, UIKit.TEXT)
	rows.add_child(kinds_heading)
	for kind in BattleModel.UNIT_NAMES:
		var row := HBoxContainer.new()
		var row_height := 58 if main.network.client_is_spectator else 80
		row.custom_minimum_size.y = row_height
		rows.add_child(row)
		kind_rows[kind] = row
		var title := _button(String(BattleModel.UNIT_NAMES[kind]) + (" · 소환" if BattleModel.SUMMON_STATS.has(kind) else "") + " ▸", "ArmyStats_%s" % kind, _open_kind.bind(kind, -1))
		title.alignment = HORIZONTAL_ALIGNMENT_LEFT
		title.add_theme_color_override("font_color", UIKit.UNIT_COLORS.get(kind, UIKit.TEXT))
		title.tooltip_text = "%s의 양쪽 진영 스탯 확인" % BattleModel.UNIT_NAMES[kind]
		row.add_child(title)
		amounts[kind] = {}
		for side in sides:
			var amount := _button("—", "ArmyKind_%s_%d" % [kind, int(side)], _open_kind.bind(kind, int(side)))
			amount.custom_minimum_size.x = 200
			amount.custom_minimum_size.y = row_height
			if int(side) == main.own_side and not main.network.client_is_spectator: amount.add_theme_font_size_override("font_size", 14)
			amount.size_flags_horizontal = Control.SIZE_SHRINK_END
			amount.tooltip_text = "%s · %s 진영 스탯 확인" % [BattleModel.UNIT_NAMES[kind], "블루" if int(side) == 0 else "레드"]
			row.add_child(amount)
			amounts[kind][side] = amount
	# Keep long instructions scrollable so role controls don't shrink the kind list.
	rows.add_child(hint)
	_apply_role_filter()
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var reference := _button("유닛 스탯", "ArmyOpenStats", main._show_stats_panel)
	actions.add_child(reference)
	actions.add_child(_button("구조물 현황", "ArmyOpenStructures", main._show_structure_panel))
	var close := _button("닫기 · Esc", "CloseArmyDetails", main._dismiss_stats_panel)
	actions.add_child(close)
	close.grab_focus()
	OverviewNavigation.configure(self)

func _open_kind(kind: String, side: int) -> void:
	var navigation := OverviewNavigation.capture(self)
	navigation["selected_side"] = selected_side
	navigation["role"] = active_role
	navigation["focus"] = "ArmyStats_%s" % kind if side == -1 else "ArmyKind_%s_%d" % [kind, side]
	main._show_stats_reference(0, kind, side, navigation)

func _select_role(role: String) -> void:
	if role != "" and not ARMY_ROLES.has(role): return
	navigation_pending = false
	active_role = "" if role == active_role else role
	_apply_role_filter()
	# Start with the composition and explanation; leave focus on the role button.
	scroll.scroll_vertical = 0

func _apply_role_filter() -> void:
	all_kinds_button.text = ("✓ " if active_role.is_empty() else "") + "모든 병력 보기"
	for role in role_buttons:
		var selected: bool = role == active_role
		role_buttons[role].text = ("✓ " if selected else "") + String(ARMY_ROLES[role].title)
		role_rows[role].visible = active_role.is_empty() or selected
		for state_name in ["font_color", "font_hover_color", "font_pressed_color"]:
			role_buttons[role].add_theme_color_override(state_name, UIKit.GOLD if selected else UIKit.TEXT)
		var tone := UIKit.GOLD if selected else UIKit.TEXT_MUTED
		if role_titles[role].get_theme_color("font_color") != tone: role_titles[role].add_theme_color_override("font_color", tone)
	for kind in kind_rows:
		kind_rows[kind].visible = active_role.is_empty() or ARMY_ROLES[active_role].kinds.has(kind)
	if active_role.is_empty():
		role_hint.text = "위 역할 버튼으로 종류 목록을 좁힐 수 있습니다. 각 병력은 한 역할에만 집계하며, 해골은 근접 전열에 포함합니다. 비율은 생존 인원 기준입니다."
		kinds_heading.text = "모든 병력 종류 · 생존 수와 생산 조건"
	else:
		var role: Dictionary = ARMY_ROLES[active_role]
		var members := PackedStringArray()
		for kind in role.kinds: members.append(String(BattleModel.UNIT_NAMES.get(kind, kind)))
		role_hint.text = "%s: %s\n%s" % [role.title, " · ".join(members), role.description]
		kinds_heading.text = "%s의 병력 종류 · 생존 수와 생산 조건" % role.title
	if main.network.client_is_spectator: kinds_heading.text = kinds_heading.text.replace("생존 수와 생산 조건", "생존 수")

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

func refresh(counts: Dictionary, awaiting: bool, purchase: Dictionary = {}) -> void:
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
	_refresh_economy(purchase, awaiting)
	_refresh_roles(counts, awaiting)
	for side in totals:
		_set_text(totals[side], "—" if awaiting else "%d명 · 소환 %d명 포함" % [int(counts.living[side]), int(counts.summons[side])])
	for kind in amounts:
		for side in amounts[kind]:
			var amount: Button = amounts[kind][side]
			var text := "—" if awaiting else "%d명" % int(counts.kinds[side].get(kind, 0))
			var hint := "%s · %s 진영 스탯 확인" % [BattleModel.UNIT_NAMES[kind], "블루" if int(side) == 0 else "레드"]
			var amount_tone := UIKit.TEXT
			if int(side) == main.own_side and not main.network.client_is_spectator:
				var readiness := _production_readiness(kind, purchase, awaiting, full)
				text += String(readiness.text)
				hint += "\n" + String(readiness.hint)
				amount_tone = readiness.tone
			_set_text(amount, text)
			if amount.tooltip_text != hint: amount.tooltip_text = hint
			for state_name in ["font_color", "font_hover_color", "font_pressed_color"]:
				if amount.get_theme_color(state_name) != amount_tone: amount.add_theme_color_override(state_name, amount_tone)

func _refresh_roles(counts: Dictionary, awaiting: bool) -> void:
	for role in role_amounts:
		for side in role_amounts[role]:
			var text := "—"
			if not awaiting:
				var living := int(counts.living[side])
				var amount := 0
				for kind in ARMY_ROLES[role].kinds: amount += int(counts.kinds[side].get(kind, 0))
				text = "%d명 · %d%%" % [amount, roundi(float(amount) * 100.0 / float(living))] if living > 0 else "0명 · —"
			_set_text(role_amounts[role][side], text)

func _refresh_economy(purchase: Dictionary, awaiting: bool) -> void:
	var text := "최신 전투 상태를 받은 뒤 자원·생산 조건을 표시합니다.\n복구 중에는 이전 상태의 예상 대기를 표시하지 않습니다."
	if not awaiting and purchase.has("economy"):
		var economy: Dictionary = purchase.economy
		var resources := float(purchase.get("resources", 0.0))
		var own_name := "아군" if not main.network.client_is_spectator else "블루" if main.own_side == 0 else "레드"
		var rate := float(economy.income) * float(economy.speed)
		var recovery := ("재개 시 회복 +%.1f/초" if LocalBattlePause.is_paused(main) else "회복 +%.1f/초") % rate
		if bool(economy.unlimited): recovery = "무한 자원 · 자동 보충"
		elif resources >= float(economy.capacity): recovery = "한도 도달 · 추가 회복 멈춤"
		text = "%s 자원 %d / %d · %s · 발전기 %d개" % [own_name, int(resources), int(economy.capacity), recovery, int(economy.generators)]
		if String(purchase.get("block_reason", "")) == "전투 종료":
			text += "\n전투 종료 · 마지막 자원 상태 · 생산 불가"
		elif LocalBattlePause.is_paused(main):
			text += "\n읽는 동안 자원·생산 대기 정지 · 예상은 전투 재개 후 기준"
		elif main.network.client_is_spectator:
			text += "\n관전 진영의 최신 수신 상태 · 직접 생산 불가"
		else:
			text += "\n온라인 전투 진행 중 · 최신 수신 상태 · 예상은 실제 시간 기준"
		if not is_equal_approx(float(economy.speed), 1.0): text += " · 연습 %.1f배속" % float(economy.speed)
	_set_text(economy_summary, text)

func _production_readiness(kind: String, purchase: Dictionary, awaiting: bool, full: bool) -> Dictionary:
	if awaiting: return {"text": "\n상태 수신 대기", "hint": "최신 전투 상태를 받은 뒤 생산 조건을 표시합니다.", "tone": UIKit.TEXT_MUTED}
	if BattleModel.SUMMON_STATS.has(kind):
		return {"text": "\n소환 병력", "hint": "해골은 네크로맨서가 소환합니다. 직접 생산할 수 없으며 공유 병력 한도를 사용합니다.", "tone": UIKit.TEXT_MUTED}
	if not purchase.has("production") or not purchase.has("economy"):
		return {"text": "", "hint": "생산 조건을 기다리고 있습니다.", "tone": UIKit.TEXT}
	var production: Dictionary = purchase.get("production", {})
	if not production.has(kind):
		return {"text": "\n미출전", "hint": "이번 전투의 아군 출전 덱에 없어 직접 생산할 수 없습니다.", "tone": UIKit.TEXT_MUTED}
	var forecast: Dictionary = production[kind]
	var missing := int(forecast.missing)
	var resource_text := "자원 충족" if missing == 0 else "자원 %d 부족" % missing
	var text := " · 비용 %d\n%s" % [int(forecast.cost), resource_text]
	var hint := "생산 비용 %d · %s" % [int(forecast.cost), resource_text]
	var economy: Dictionary = purchase.economy
	var paused := LocalBattlePause.is_paused(main)
	var condition := "재개 시 생산 가능" if paused else "생산 가능"
	var tone := UIKit.TEAL
	if String(purchase.get("block_reason", "")) == "전투 종료":
		condition = "전투 종료 · 생산 불가"
		tone = UIKit.TEXT_MUTED
	elif full:
		condition = "전장 한도 · 생산 불가"
		hint += "\n양쪽 병력·소환수가 공유 한도를 채웠습니다. 사망 후 정리되어 빈자리가 생겨야 생산할 수 있어 대기 시간을 예상할 수 없습니다."
		tone = UIKit.GOLD
	elif missing > 0 and bool(forecast.above_capacity):
		condition = "자원 한도 초과"
		hint += "\n비용이 보유 한도보다 높아 회복만으로 생산할 수 없습니다."
		tone = UIKit.GOLD
	elif missing > 0 and bool(economy.unlimited):
		condition = "재개 후 자원 보충" if paused else "자원 보충 중"
		hint += "\n무한 자원 도구가 전투 진행 중 자원을 자동 보충합니다."
		tone = UIKit.GOLD
	elif missing > 0 or float(forecast.cooldown) > 0.001:
		condition = ("재개 후 약 %.1f초" if paused else "예상 약 %.1f초") % (ceilf(float(forecast.purchase_wait) * 10.0) / 10.0)
		if missing == 0: condition = ("재개 후 대기 %.1f초" if paused else "생산 대기 %.1f초") % (ceilf(float(forecast.cooldown_wait) * 10.0) / 10.0)
		hint += "\n현재 회복 속도·생산 대기 기준의 예상입니다. 추가 구매·발전기 파괴·병력 한도 도달로 달라질 수 있습니다."
		tone = UIKit.GOLD
	if float(forecast.cooldown) > 0.001:
		hint += "\n생산 대기 %.1f초 (실제 시간 기준%s)" % [ceilf(float(forecast.cooldown_wait) * 10.0) / 10.0, " · 재개 후" if paused else ""]
	text += "\n" + condition
	if paused: hint += "\n읽는 동안에는 생산·자원 회복이 멈춥니다. 전장으로 돌아가 전투를 재개한 뒤 생산하세요."
	hint += "\n누르면 해당 진영의 스탯을 확인합니다. 이 버튼은 생산하지 않습니다."
	return {"text": text, "hint": hint, "tone": tone}

func _set_text(label, text: String) -> void:
	if label.text != text: label.text = text

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
		var visible_controls: Array[Control] = []
		for control in focus_controls:
			if control.is_visible_in_tree(): visible_controls.append(control)
		var index := visible_controls.find(get_viewport().gui_get_focus_owner())
		if not visible_controls.is_empty(): visible_controls[posmod(index + (-1 if event.shift_pressed else 1), visible_controls.size())].grab_focus()
		return true
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	match event.keycode:
		KEY_PAGEUP: scroll.scroll_vertical -= maxi(1, int(scroll.size.y) - 32)
		KEY_PAGEDOWN: scroll.scroll_vertical += maxi(1, int(scroll.size.y) - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return false
	return true
