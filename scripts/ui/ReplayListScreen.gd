extends "res://scripts/ui/SubMenuFrame.gd"
## Filter a snapshot of the shelf without reloading files or rebuilding cards on each keystroke.

signal refresh_requested

const MODES := ["", "campaign", "practice", "daily", "weekly", "draft", "online", "unreadable"]

var _entries: Array = []
var _state: Dictionary = {}
var _search: LineEdit
var _mode: OptionButton
var _scope: OptionButton
var _outcome: OptionButton
var _retention: OptionButton
var _reset: Button
var _count: Label
var _empty: VBoxContainer
var _refresh_revision := 0
@onready var _scroll: ScrollContainer = $Column/ReplayScroll
@onready var _rows: VBoxContainer = $Column/ReplayScroll/ReplayRows

func populate(entries: Array, card_factory: Callable, state: Dictionary) -> void:
	_entries = entries
	_state = state
	var search_row := HBoxContainer.new()
	search_row.name = "ReplaySearchTools"
	search_row.add_theme_constant_override("separation", 8)
	column.add_child(search_row)
	column.move_child(search_row, _scroll.get_index())
	_search = LineEdit.new()
	_search.name = "ReplaySearch"
	_search.placeholder_text = "전투·날짜·병력·메모·클립 구간 검색"
	_search.tooltip_text = "공백으로 나눈 검색어가 모두 포함된 기록을 표시합니다. 예: 일일 20261013 / 방패병 / 00:10 / 구간 메모"
	_search.max_length = 160
	_search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text = String(state.get("query", ""))
	_search.clear_button_enabled = true
	search_row.add_child(_search)
	_reset = UIKit.style_button(Button.new(), UIKit.TEAL)
	_reset.name = "ResetReplayFilters"
	_reset.text = "초기화"
	search_row.add_child(_reset)
	var refresh := UIKit.style_button(Button.new(), UIKit.ACCENT)
	refresh.name = "RefreshReplayList"
	refresh.text = "새로고침"
	refresh.tooltip_text = "파일을 다시 읽습니다. 검색 조건과 스크롤 위치는 유지합니다."
	refresh.pressed.connect(func(): refresh_requested.emit())
	search_row.add_child(refresh)
	var filters := HFlowContainer.new()
	filters.name = "ReplayFilters"
	filters.add_theme_constant_override("h_separation", 8)
	filters.add_theme_constant_override("v_separation", 8)
	column.add_child(filters)
	column.move_child(filters, _scroll.get_index())
	_mode = _option(filters, "ReplayModeFilter", ["종류 전체", "캠페인", "연습", "일일 도전", "주간 도전", "드래프트", "온라인·기타", "읽기 실패"], int(state.get("mode", 0)))
	_scope = _option(filters, "ReplayScopeFilter", ["전투·클립 전체", "전체 전투만", "클립만"], int(state.get("scope", 0)))
	_outcome = _option(filters, "ReplayOutcomeFilter", ["결과 전체", "승리·블루 승", "패배·레드 승", "무승부"], int(state.get("outcome", 0)))
	_outcome.tooltip_text = "캠페인·연습·도전·드래프트는 플레이어 승패, 온라인·기타는 블루/레드 결과로 구분합니다. 클립의 결과는 전체 전투 기준입니다."
	_retention = _option(filters, "ReplayRetentionFilter", ["보존 전체", "정리 제외만", "일반만"], int(state.get("retention", 0)))
	_retention.tooltip_text = "정리 제외한 전투는 최근 50개와 별도로 남습니다. 이 필터는 목록 표시만 바꿉니다."
	_count = Label.new()
	_count.name = "ReplayMatchCount"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	filters.add_child(_count)
	for entry in _entries:
		var card: Control = card_factory.call(entry)
		_rows.add_child(card)
		entry["card"] = card
	_search.text_changed.connect(func(_text): _refresh(true))
	_mode.item_selected.connect(func(_index): _refresh(true))
	_scope.item_selected.connect(func(_index): _refresh(true))
	_outcome.item_selected.connect(func(_index): _refresh(true))
	_retention.item_selected.connect(func(_index): _refresh(true))
	_reset.pressed.connect(_reset_filters)
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.gui_input.connect(_on_scroll_input)
	# Capture the requested position before the initial layout updates its scrollbar.
	_refresh(false)
	_scroll.get_v_scroll_bar().value_changed.connect(func(value): _state["scroll"] = int(value))

func _option(parent: Control, node_name: String, labels: Array, selected: int) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
	for label in labels:
		option.add_item(String(label))
	option.select(clampi(selected, 0, labels.size() - 1))
	parent.add_child(option)
	return option

static func matches(entry: Dictionary, query: String, mode: int, scope: int, outcome: int, retention: int = 0) -> bool:
	if mode > 0 and String(entry.mode) != String(MODES[mode]): return false
	if scope > 0 and (entry.mode == "unreadable" or bool(entry.clip) != (scope == 2)): return false
	if outcome > 0 and int(entry.winner) != outcome - 1: return false
	if retention > 0 and (entry.mode == "unreadable" or bool(entry.get("protected", false)) != (retention == 1)): return false
	var text := String(entry.search)
	for term in query.to_lower().replace("\t", " ").replace("\n", " ").split(" ", false):
		if not text.contains(term): return false
	return true

func _refresh(reset_scroll: bool) -> void:
	_refresh_revision += 1
	_state["query"] = _search.text
	_state["mode"] = _mode.selected
	_state["scope"] = _scope.selected
	_state["outcome"] = _outcome.selected
	_state["retention"] = _retention.selected
	var shown := 0
	for entry in _entries:
		entry.card.visible = matches(entry, _search.text, _mode.selected, _scope.selected, _outcome.selected, _retention.selected)
		if entry.card.visible: shown += 1
	_count.text = "%d / %d개 표시" % [shown, _entries.size()]
	_count.tooltip_text = "읽기 실패 파일도 전체 개수에 포함합니다. 최신 보관순이며 검색·필터는 자동 정리와 덱 분석의 대상에 영향을 주지 않습니다."
	_reset.disabled = _search.text.is_empty() and _mode.selected == 0 and _scope.selected == 0 and _outcome.selected == 0 and _retention.selected == 0
	if is_instance_valid(_empty):
		_rows.remove_child(_empty)
		_empty.queue_free()
		_empty = null
	if shown == 0:
		_empty = VBoxContainer.new()
		_empty.name = "NoReplays" if _entries.is_empty() else "NoReplayMatches"
		_empty.custom_minimum_size.y = 180
		_empty.alignment = BoxContainer.ALIGNMENT_CENTER
		_empty.add_theme_constant_override("separation", 10)
		_rows.add_child(_empty)
		var message := Label.new()
		message.text = "아직 저장된 리플레이가 없습니다" if _entries.is_empty() else "검색 조건에 맞는 리플레이가 없습니다"
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIKit.display(message, 22, UIKit.TEXT)
		_empty.add_child(message)
		var hint := Label.new()
		hint.text = "전투를 끝까지 치르면 자동 저장됩니다. 공유받은 텍스트는 클립보드에서 가져올 수 있습니다." if _entries.is_empty() else "검색어·종류·결과·보존 조건을 바꾸거나 초기화를 눌러 전체 목록을 확인하세요."
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		_empty.add_child(hint)
	if reset_scroll: _state["scroll"] = 0
	# Restore after containers have laid out the visible cards. Ignore an older
	# pending restore if another keystroke changed the result set in the meantime.
	get_tree().process_frame.connect(_restore_scroll.bind(int(_state.get("scroll", 0)), _refresh_revision), CONNECT_ONE_SHOT)

func _restore_scroll(position: int, revision: int) -> void:
	if is_inside_tree() and revision == _refresh_revision:
		_scroll.scroll_vertical = position

func _reset_filters() -> void:
	_search.text = ""
	_mode.select(0)
	_scope.select(0)
	_outcome.select(0)
	_retention.select(0)
	_refresh(true)
	_search.grab_focus()

func _on_scroll_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var bar := _scroll.get_v_scroll_bar()
	var target := _scroll.scroll_vertical
	match event.keycode:
		KEY_UP: target -= 48
		KEY_DOWN: target += 48
		KEY_PAGEUP: target -= maxi(48, int(bar.page))
		KEY_PAGEDOWN: target += maxi(48, int(bar.page))
		KEY_HOME: target = 0
		KEY_END: target = int(bar.max_value - bar.page)
		_: return
	_scroll.scroll_vertical = clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
	_scroll.accept_event()
