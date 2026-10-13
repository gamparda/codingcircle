extends PanelContainer
## Read-only battle reference. Side data is captured on opening; filtering never changes the model.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const Localization = preload("res://scripts/Localization.gd")

var main
var category := 0
var cards: Array[Control] = []
var tabs: Array[Button] = []
var focus_controls: Array[Control] = []
var search: LineEdit
var deck_only: CheckBox
var scope: OptionButton
var deck_hint: Label
var side_decks: Array = [{}, {}]
var deck_known: Array = [false, false]
var growth_levels: Array = [0, 0]
var side_names: Array = ["내", "상대"]
var clear: Button
var count: Label
var scroll: ScrollContainer
var grid: GridContainer

func setup(owner_main, growth_level: int) -> void:
	main = owner_main
	_capture_sides(growth_level)
	name = "BattleStatsBrowser"
	add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(UIKit.TEAL, 16, 1.0), 22, 18))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_label(Localization.text("유닛 상세 스탯"), 26, UIKit.TEXT))
	var basis := "진영별 성장 반영 · 일시적인 지원·장판 효과 제외" if growth_levels[0] > 0 or growth_levels[1] > 0 else "기본 병력 수치 · 일시적인 지원·장판 효과 제외"
	var pause_hint := "전투 일시정지 중" if main.local_ai_mode else "온라인 전투는 계속 진행됩니다"
	column.add_child(_label("%s · DPS는 공격력 ÷ 공격 간격 · %s" % [basis, pause_hint], 14, UIKit.TEXT_MUTED))
	var tab_row := HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 8)
	column.add_child(tab_row)
	for index in 3:
		var button := Button.new()
		button.name = "StatsCategory%d" % index
		button.text = ["병력", "구조물", "전투 규칙"][index]
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 58
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		UIKit.style_button(button, UIKit.TEAL)
		button.pressed.connect(_select_category.bind(index))
		tab_row.add_child(button)
		tabs.append(button)
		focus_controls.append(button)
	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	column.add_child(search_row)
	search = LineEdit.new()
	search.name = "StatsSearch"
	search.placeholder_text = "이름·효과 검색 · Ctrl+F"
	search.tooltip_text = "현재 분류에서 이름과 설명을 검색합니다. 띄어쓴 단어를 모두 포함하는 항목을 표시합니다."
	search.max_length = 80
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(0, 58)
	search.text_changed.connect(func(_text: String): _refresh())
	search_row.add_child(search)
	focus_controls.append(search)
	clear = Button.new()
	clear.name = "ClearStatsSearch"
	clear.text = "지우기"
	clear.custom_minimum_size = Vector2(100, 58)
	clear.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	UIKit.style_button(clear, UIKit.ACCENT)
	clear.pressed.connect(func(): search.text = ""; _refresh(); search.grab_focus())
	search_row.add_child(clear)
	focus_controls.append(clear)
	var filter_row := HBoxContainer.new()
	filter_row.add_theme_constant_override("separation", 8)
	column.add_child(filter_row)
	scope = OptionButton.new()
	scope.name = "StatsSideScope"
	scope.custom_minimum_size = Vector2(210, 58)
	scope.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	for title in ["%s 진영" % side_names[0], "%s 진영" % side_names[1], "양쪽 비교", "공통 출전", "%s 전용 출전" % side_names[0], "%s 전용 출전" % side_names[1]]:
		scope.add_item(title)
	if not deck_known[0]: scope.set_item_text(0, "기본 수치")
	scope.tooltip_text = "진영별 수치를 보거나 양쪽의 공통·전용 출전 구성을 비교합니다. 미출전 병력의 수치는 참고용입니다."
	scope.get_popup().name = "StatsSideScopePopup"
	scope.get_popup().add_theme_constant_override("v_separation", 18)
	# A missing enemy deck is unknown, never an empty deck or a guessed AI deck.
	for index in range(1, scope.item_count):
		scope.set_item_disabled(index, not deck_known[0] or not deck_known[1])
	UIKit.style_button(scope, UIKit.TEAL)
	scope.item_selected.connect(func(_index: int): _refresh())
	filter_row.add_child(scope)
	focus_controls.append(scope)
	deck_only = CheckBox.new()
	deck_only.name = "StatsDeckOnly"
	deck_only.text = "%s 출전 덱만" % side_names[0]
	deck_only.tooltip_text = "이번 전투의 출전 구성만 표시합니다. 네크로맨서의 해골도 함께 표시합니다."
	deck_only.custom_minimum_size.y = 58
	deck_only.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	deck_only.focus_mode = Control.FOCUS_ALL
	deck_only.add_theme_stylebox_override("focus", UIKit.button_styles(UIKit.TEAL, false)["focus"])
	deck_only.toggled.connect(func(_pressed: bool): _refresh())
	filter_row.add_child(deck_only)
	focus_controls.append(deck_only)
	count = _label("", 14, UIKit.TEXT_MUTED)
	count.name = "StatsResultCount"
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filter_row.add_child(count)
	deck_hint = _label("", 14, UIKit.TEXT_MUTED)
	deck_hint.name = "StatsDeckBasis"
	column.add_child(deck_hint)
	scroll = ScrollContainer.new()
	scroll.name = "UnitStatsScroll"
	scroll.tooltip_text = "휠·터치로 스크롤 · PageUp/PageDown으로 이동 · Home/End로 처음/끝 이동"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE
	scroll.resized.connect(_resize_grid)
	column.add_child(scroll)
	focus_controls.append(scroll)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	for kind in BattleModel.UNIT_NAMES:
		var unit_name := String(BattleModel.UNIT_NAMES[kind])
		_add_card(unit_name, BattleModel.unit_stat_summary(kind, int(growth_levels[0])), 0, _in_deck(kind, 0, "units"), UIKit.UNIT_COLORS.get(kind, UIKit.ACCENT), kind)
		_configure_side_card(cards.back(), kind, "units", BattleModel.unit_stat_summary(kind, int(growth_levels[1])))
	var structure_names := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
	for kind in BattleModel.STRUCTURE_STATS:
		_add_card(structure_names.get(kind, kind), _structure_summary(kind), 1, _in_deck(kind, 0, "structures"), UIKit.TEAL)
		_configure_side_card(cards.back(), kind, "structures", _structure_summary(kind))
	# Keep the established descriptions generated from authoritative constants.
	var rules := BattleModel.battle_stat_summary().split("\n")
	for index in range(2, rules.size()):
		_add_card("지원 효과" if index == 2 else "기본 전투 규칙", rules[index], 2, false, UIKit.GOLD)
	if main.local_ai_mode and is_instance_valid(main.local_model):
		var model = main.local_model
		for index in 2:
			var side: int = main.own_side if index == 0 else 1 - main.own_side
			var bonuses: Dictionary = BattleModel.campaign_bonuses(int(growth_levels[index]))
			var summary := "기지 최대 체력 %d\n자원 +%.1f/초 · 최대 %d\n병력 체력·공격력 +%d%%" % [
				int(model.base_max_hp[side]), model.resource_income(side), int(model.resource_capacity(side)),
				roundi((float(bonuses.stat_scale) - 1.0) * 100.0)]
			summary += "\n발전기의 추가 수입과 전투 중 지원 효과는 별도로 적용됩니다."
			_add_card("%s 진영 전투 수치" % side_names[index], summary, 2, false, UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED)
	var close := Button.new()
	close.name = "CloseUnitStatsButton"
	close.text = "닫기 · Esc"
	close.custom_minimum_size = Vector2(0, 58)
	close.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	close.tooltip_text = "오프라인 전투는 다른 정지 창이 없으면 이어집니다." if main.local_ai_mode else "온라인 전투는 계속 진행됩니다."
	UIKit.style_button(close, UIKit.TEAL, true)
	close.pressed.connect(main._dismiss_stats_panel)
	column.add_child(close)
	focus_controls.append(close)
	_select_category(0)
	_resize_grid()
	close.grab_focus()

func _capture_sides(growth_level: int) -> void:
	growth_levels[0] = growth_level
	if main.local_ai_mode and is_instance_valid(main.local_model):
		for index in 2:
			var side: int = main.own_side if index == 0 else 1 - main.own_side
			side_decks[index] = {"units": main.local_model.unit_decks[side].duplicate(), "structures": main.local_model.structure_decks[side].duplicate()}
			growth_levels[index] = int(main.local_model.campaign_levels[side])
			deck_known[index] = true
		return
	var spectator: bool = main.network.client_is_spectator
	if spectator: side_names = ["블루", "레드"]
	var session: Dictionary = main.network.client_session
	var players: Array = session.get("members", []).filter(func(member): return member.get("role", "") == "player")
	# Server side assignment follows player insertion order, as does public_state.
	# Waiting-room decks can belong to a different battle; do not use them here.
	if session.get("phase", "") in ["playing", "finished"] and players.size() == 2:
		var own: int = 0 if spectator else main.own_side
		if spectator or int(players[own].id) == main.multiplayer.get_unique_id():
			for index in 2:
				var side: int = own if index == 0 else 1 - own
				side_decks[index] = players[side].deck.duplicate(true)
				deck_known[index] = true
	if not deck_known[0] and not spectator:
		# The submitted client deck remains the source for legacy room connections.
		# Editing a saved preset must not change the apparent in-battle deck.
		side_decks[0] = {"units": main.network.client_unit_deck.duplicate(), "structures": main.network.client_structure_deck.duplicate()}
		deck_known[0] = true

func _in_deck(kind: String, index: int, group: String) -> bool:
	if not deck_known[index]: return false
	var deck: Array = side_decks[index].get(group, [])
	return deck.has(kind) or (group == "units" and kind == "skeleton" and deck.has("necromancer"))

func _configure_side_card(card: Control, kind: String, group: String, enemy_summary: String) -> void:
	card.set_meta("in_enemy_deck", _in_deck(kind, 1, group))
	card.set_meta("enemy_summary", enemy_summary)
	card.set_meta("summoned", kind == "skeleton")

func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _add_card(title: String, summary: String, section: int, in_deck: bool, color: Color, portrait_kind: String = "") -> void:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 126
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.set_meta("category", section)
	card.set_meta("in_deck", in_deck)
	card.set_meta("title", title)
	card.set_meta("own_summary", summary)
	card.set_meta("search_text", (title + " " + summary).to_lower())
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.08), UIKit.SURFACE.darkened(0.12), Color(color.r, color.g, color.b, 0.5), 12), 14, 12))
	grid.add_child(card)
	cards.append(card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	if not portrait_kind.is_empty():
		var portrait := TextureRect.new()
		portrait.texture = load("res://assets/units/%s.png" % ("tanker" if portrait_kind == "shield" else portrait_kind))
		portrait.custom_minimum_size = Vector2(64, 90)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(portrait)
	var text_column := VBoxContainer.new()
	text_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text_column)
	var heading := _label(title, 18, color.lightened(0.3))
	var body := _label(summary, 16, UIKit.TEXT)
	text_column.add_child(heading)
	text_column.add_child(body)
	card.set_meta("heading", heading)
	card.set_meta("body", body)

func _structure_summary(kind: String) -> String:
	var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
	var text := "비용 %d · 체력 %d\n종류 한도 %d개 · 진영 전체 한도 %d개" % [int(stats.cost), int(stats.hp), int(stats.get("max_count", BattleModel.STRUCTURE_LIMIT)), BattleModel.STRUCTURE_LIMIT]
	match kind:
		"wall": text += "\n적의 전진을 막는 방벽"
		"swamp": text += "\n%s · 반경 %d\n수명이 끝나면 사라집니다." % [BattleModel.swamp_summary(), int(stats.radius)]
		"turret": text += "\n공격력 %d · DPS %.1f\n공격 간격 %.2f초 · 사거리 %d" % [int(stats.damage), float(stats.damage) / float(stats.interval), float(stats.interval), int(stats.range)]
		"generator": text += "\n자원 +%d/초 · 후방에만 설치" % int(stats.income)
	return text

func _select_category(index: int) -> void:
	category = index
	for tab_index in tabs.size():
		tabs[tab_index].set_pressed_no_signal(tab_index == category)
	_refresh()

func _membership(card: Control) -> String:
	var first: bool = card.get_meta("in_deck")
	var second: bool = card.get_meta("in_enemy_deck")
	var action := "소환" if bool(card.get_meta("summoned")) else "출전"
	if first and second: return "양쪽 " + action
	if first: return "%s %s" % [side_names[0], action]
	if second: return "%s %s" % [side_names[1], action]
	if not deck_known[0]: return "출전 정보 미확인"
	return "출전 없음" if deck_known[1] else "%s 출전 없음" % side_names[0]

func _scope_matches(card: Control) -> bool:
	var first: bool = card.get_meta("in_deck")
	var second: bool = card.get_meta("in_enemy_deck")
	match scope.selected:
		0: return not deck_only.button_pressed or first
		1: return not deck_only.button_pressed or second
		2: return not deck_only.button_pressed or first or second
		3: return first and second
		4: return first and not second
		5: return second and not first
	return true

func _update_side_card(card: Control) -> void:
	var first := String(card.get_meta("own_summary"))
	var second := String(card.get_meta("enemy_summary"))
	var summary := first
	if scope.selected == 1:
		summary = second
	elif scope.selected >= 2:
		# Keep identical values compact; growth differences are shown together.
		if first == second:
			summary = "양쪽 동일 수치\n" + first
		else:
			var first_basis := "%s 진영%s" % [side_names[0], " · 미출전 참고" if not bool(card.get_meta("in_deck")) else ""]
			var second_basis := "%s 진영%s" % [side_names[1], " · 미출전 참고" if not bool(card.get_meta("in_enemy_deck")) else ""]
			summary = "%s\n%s\n\n%s\n%s" % [first_basis, first, second_basis, second]
	var title := String(card.get_meta("title")) + " · " + _membership(card)
	var heading: Label = card.get_meta("heading")
	var body: Label = card.get_meta("body")
	heading.text = title
	body.text = summary
	card.set_meta("search_text", (title + " " + summary).to_lower())

func _refresh() -> void:
	var terms := search.text.strip_edges().to_lower().split(" ", false)
	var matches := 0
	var shared := 0
	var first_only := 0
	var second_only := 0
	scope.visible = category != 2
	deck_only.visible = category != 2 and scope.selected < 3
	deck_only.disabled = not deck_known[0]
	deck_only.text = "%s 출전 덱만" % side_names[scope.selected] if scope.selected < 2 else "양쪽 출전 덱만"
	for card in cards:
		var show_card: bool = int(card.get_meta("category")) == category
		if int(card.get_meta("category")) != 2:
			_update_side_card(card)
			if show_card:
				var first: bool = card.get_meta("in_deck")
				var second: bool = card.get_meta("in_enemy_deck")
				if first and second: shared += 1
				elif first: first_only += 1
				elif second: second_only += 1
				show_card = _scope_matches(card)
		for term in terms:
			if not String(card.get_meta("search_text")).contains(term): show_card = false
		card.visible = show_card
		if show_card: matches += 1
	count.text = "%d개 표시" % matches if matches > 0 else "일치하는 항목이 없습니다. 검색어·분류·진영 조건을 바꿔 보세요."
	deck_hint.visible = category != 2
	if not deck_known[0] or not deck_known[1]:
		deck_hint.text = "%s 출전 정보가 확인되지 않아 양쪽 비교를 사용할 수 없습니다. 이 연결 방식에서는 상대 덱이 제공되지 않을 수 있습니다." % (side_names[1] if deck_known[0] else "양쪽")
	else:
		deck_hint.text = "공통 %d · %s 전용 %d · %s 전용 %d%s" % [shared, side_names[0], first_only, side_names[1], second_only, " · 소환 병력 포함" if category == 0 else ""]
		if category == 0:
			var first_bonus: Dictionary = BattleModel.campaign_bonuses(int(growth_levels[0]))
			var second_bonus: Dictionary = BattleModel.campaign_bonuses(int(growth_levels[1]))
			deck_hint.text += " · 병력 성장 %s +%d%% / %s +%d%%" % [side_names[0], roundi((float(first_bonus.stat_scale) - 1.0) * 100.0), side_names[1], roundi((float(second_bonus.stat_scale) - 1.0) * 100.0)]
	clear.disabled = search.text.is_empty()
	scroll.scroll_vertical = 0

func _resize_grid() -> void:
	if is_instance_valid(grid):
		grid.columns = 2 if scroll.size.x >= 840.0 else 1

func handle_key(event: InputEventKey) -> bool:
	if not event.pressed: return false
	if event.keycode == KEY_F11:
		if not event.echo: main._set_fullscreen(not bool(main.save_data.settings.fullscreen))
		return true
	# PopupMenu owns its navigation, including Esc to close only the dropdown.
	if scope.get_popup().visible: return false
	if event.keycode == KEY_ESCAPE:
		if not event.echo: main._dismiss_stats_panel()
		return true
	if event.ctrl_pressed and event.keycode == KEY_F:
		search.grab_focus()
		search.select_all()
		return true
	if event.keycode == KEY_TAB:
		var available: Array[Control] = []
		for control in focus_controls:
			if control.is_visible_in_tree() and not (control is BaseButton and control.disabled): available.append(control)
		var index := available.find(get_viewport().gui_get_focus_owner())
		var next := posmod(index + (-1 if event.shift_pressed else 1), available.size())
		available[next].grab_focus()
		return true
	if get_viewport().gui_get_focus_owner() is LineEdit: return false
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	match event.keycode:
		KEY_PAGEUP: scroll.scroll_vertical -= maxi(1, int(scroll.size.y) - 32)
		KEY_PAGEDOWN: scroll.scroll_vertical += maxi(1, int(scroll.size.y) - 32)
		KEY_HOME: scroll.scroll_vertical = 0
		KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		_: return false
	return true
