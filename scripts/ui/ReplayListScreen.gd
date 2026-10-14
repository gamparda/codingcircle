extends "res://scripts/ui/SubMenuFrame.gd"
## Search the complete shelf snapshot; create cards only for the current page.

signal refresh_requested
signal deck_filters_changed(queries: PackedStringArray)
signal loading_completed(entries: Array, error: String)

const MODES := ["", "campaign", "practice", "daily", "weekly", "draft", "online", "unreadable"]
const PAGE_SIZE := 8
const LOAD_BATCH_FILES := 4
const SCAN_BATCH_NAMES := 64
const LOAD_BUDGET_USEC := 4000

var _loading := false
var _load_scanning := false
var _load_directory: DirAccess
var _load_directory_path := ""
var _load_paths: Array[String] = []
var _load_entries: Array = []
var _load_reader: Callable
var _load_factory: Callable
var _load_index := 0
var _load_panel: VBoxContainer
var _load_progress: Label
var _load_refresh: Button
var _load_error := ""
var _load_input_revision := 0

var _entries: Array = []
var _page_entries: Array = []
var _card_factory: Callable
var _page := 0
var _page_count := 1
var _first: Button
var _previous: Button
var _next: Button
var _last: Button
var _page_label: Label
var _pages: HFlowContainer
var _state: Dictionary = {}
var _search: LineEdit
var _deck_queries: Array[LineEdit] = []
var _deck_notice: Label
var _term_scroll: ScrollContainer
var _term_row: HBoxContainer
var _term_buttons: Array[Button] = []
var _mode: OptionButton
var _scope: OptionButton
var _outcome: OptionButton
var _retention: OptionButton
var _sort: OptionButton
var _applied_sort := -1
var _reset: Button
var _count: Label
var _empty: VBoxContainer
var _refresh_revision := 0
var _restoring := false
@onready var _scroll: ScrollContainer = $Column/ReplayScroll
@onready var _rows: VBoxContainer = $Column/ReplayScroll/ReplayRows

## The frame owns the scan so a queued ancestor cancels work before the next file.
## Keep the saved card/page bookmark untouched until the entire snapshot is ready.
func begin_loading(directory_path: String, entry_reader: Callable, card_factory: Callable, state: Dictionary) -> void:
	_state = state
	_load_directory_path = directory_path
	_load_reader = entry_reader
	_load_factory = card_factory
	_loading = true
	_load_scanning = true
	_load_panel = VBoxContainer.new()
	_load_panel.name = "ReplayShelfLoading"
	_load_panel.custom_minimum_size.y = 180
	_load_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	_load_panel.add_theme_constant_override("separation", 12)
	_rows.add_child(_load_panel)
	_load_progress = Label.new()
	_load_progress.name = "ReplayShelfLoadProgress"
	_load_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_load_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UIKit.display(_load_progress, 22, UIKit.TEXT)
	_load_progress.text = "보관함 파일을 찾고 있습니다"
	_load_panel.add_child(_load_progress)
	var hint := Label.new()
	hint.text = "읽기를 마치면 전체 검색·용량·페이지와 덱 분석을 사용할 수 있습니다. 지금 메인 화면·가져오기·코드·온라인 전투 메뉴로 이동할 수 있으며, 화면을 떠나면 남은 읽기를 중단합니다."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	_load_panel.add_child(hint)
	_load_refresh = UIKit.style_button(Button.new(), UIKit.TEAL)
	_load_refresh.name = "ReloadReplayShelf"
	_load_refresh.text = "읽기 다시 시작"
	_load_refresh.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	_load_refresh.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	_load_refresh.tooltip_text = "현재 읽기를 중단하고 파일을 다시 찾습니다. 기존 검색 조건·정렬·카드 위치는 유지합니다."
	_load_panel.add_child(_load_refresh)
	_load_refresh.pressed.connect(func():
		_load_refresh.grab_focus()
		refresh_requested.emit())
	get_viewport().gui_focus_changed.connect(_remember_focus)
	_load_directory = DirAccess.open(directory_path)
	if _load_directory == null:
		# A shelf that has never been created is empty; an inaccessible one is not.
		var error := "보관 폴더를 열지 못했습니다. 파일 권한과 저장 장치 연결을 확인한 뒤 새로고침하세요." if DirAccess.dir_exists_absolute(directory_path) or FileAccess.file_exists(directory_path) else ""
		_finish_loading(error)
		return
	if _load_directory.list_dir_begin() != OK:
		_finish_loading("보관 폴더의 파일 목록을 읽지 못했습니다. 파일 권한과 저장 장치 연결을 확인한 뒤 새로고침하세요.")
		return
	set_process(true)
	# Small shelves finish immediately, but even this first pass has the same budget.
	_load_batch()

func _process(_delta: float) -> void:
	if _loading: _load_batch()

func _load_batch() -> void:
	if not _alive():
		_cancel_loading()
		return
	var deadline := Time.get_ticks_usec() + LOAD_BUDGET_USEC
	if _load_scanning:
		for _name_index in SCAN_BATCH_NAMES:
			var file := _load_directory.get_next()
			if file.is_empty():
				_load_directory.list_dir_end()
				_load_scanning = false
				break
			if not _load_directory.current_is_dir() and file.ends_with(".json"):
				_load_paths.append(_load_directory_path.path_join(file))
			if Time.get_ticks_usec() >= deadline: break
		if _load_scanning:
			_load_progress.text = "보관함 파일을 찾고 있습니다 · %d개 발견" % _load_paths.size()
			return
	for _file_index in LOAD_BATCH_FILES:
		if _load_index >= _load_paths.size(): break
		if Time.get_ticks_usec() >= deadline: break
		if not _alive():
			_cancel_loading()
			return
		_load_entries.append(_load_reader.call(_load_paths[_load_index], _load_directory))
		_load_index += 1
	if _load_index == _load_paths.size():
		_finish_loading("")
	else:
		_load_progress.text = "보관함 읽는 중 · %d / %d개\n검색·용량 집계를 준비하고 있습니다" % [_load_index, _load_paths.size()]

func _finish_loading(error: String) -> void:
	if not _alive():
		_cancel_loading()
		return
	var entries := _load_entries
	var factory := _load_factory
	_load_error = error
	_cancel_loading()
	_rows.remove_child(_load_panel)
	_load_panel.queue_free()
	_load_panel = null
	populate(entries, factory, _state)
	loading_completed.emit(entries, error)

## Existing post-action focus/reopen callbacks must wait for cards to exist.
## A new user action while waiting cancels automatic navigation.
func after_loading(action: Callable) -> void:
	var revision := _load_input_revision
	if _loading:
		loading_completed.connect(func(_loaded: Array, _error: String): _queue_loaded_action(action, revision), CONNECT_ONE_SHOT)
	else:
		_queue_loaded_action(action, revision)

func _queue_loaded_action(action: Callable, revision: int) -> void:
	if _alive():
		get_tree().process_frame.connect(_run_loaded_action.bind(action, revision), CONNECT_ONE_SHOT)

func _run_loaded_action(action: Callable, revision: int) -> void:
	if _alive() and revision == _load_input_revision: action.call()

func _cancel_loading() -> void:
	set_process(false)
	if _load_directory != null: _load_directory.list_dir_end()
	_load_directory = null
	_load_paths = []
	_load_entries = []
	_load_reader = Callable()
	_load_factory = Callable()
	_loading = false
	_load_scanning = false

func _exit_tree() -> void:
	_cancel_loading()

func populate(entries: Array, card_factory: Callable, state: Dictionary) -> void:
	_entries = entries
	_state = state
	_card_factory = card_factory
	_page = maxi(0, int(state.get("page", 0)))
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
	refresh.tooltip_text = "파일과 용량을 다시 읽습니다. 검색 조건·정렬·카드 위치·키보드 초점은 유지합니다."
	refresh.pressed.connect(func():
		refresh.grab_focus()
		refresh_requested.emit())
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
	_sort = _option(filters, "ReplaySort", ["최근 보관순", "오래된 보관순", "용량 큰 순"], int(state.get("sort", 0)))
	_sort.tooltip_text = "목록 순서만 바꿉니다. 자동 정리는 계속 최근 일반 기록 50개를 보존합니다. 용량 미상 파일은 용량 큰 순에서 마지막에 표시합니다."
	_count = Label.new()
	_count.name = "ReplayMatchCount"
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 14)
	_count.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	filters.add_child(_count)
	var deck_filters := HFlowContainer.new()
	deck_filters.name = "ReplayDeckFilters"
	deck_filters.add_theme_constant_override("h_separation", 12)
	deck_filters.add_theme_constant_override("v_separation", 4)
	column.add_child(deck_filters)
	column.move_child(deck_filters, _scroll.get_index())
	for side in 2:
		var field := VBoxContainer.new()
		field.name = "ReplayBlueDeckField" if side == 0 else "ReplayRedDeckField"
		field.custom_minimum_size.x = 280
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_constant_override("separation", 2)
		deck_filters.add_child(field)
		var heading := Label.new()
		heading.text = "내 덱 (블루) / 온라인: 블루 덱" if side == 0 else "상대 덱 (레드) / 온라인: 레드 덱"
		heading.add_theme_font_size_override("font_size", 14)
		heading.add_theme_color_override("font_color", UIKit.TEAM_BLUE.lightened(0.3) if side == 0 else UIKit.TEAM_RED.lightened(0.3))
		field.add_child(heading)
		var query := LineEdit.new()
		query.name = "ReplayBlueDeckSearch" if side == 0 else "ReplayRedDeckSearch"
		query.placeholder_text = "병력·구조물 검색 (예: 탱커 포탑)" if side == 0 else "병력·구조물 검색 (예: 궁수 방벽)"
		query.tooltip_text = "저장된 %s 진영의 병력·구조물 이름과 영문 ID만 검색합니다. 캠페인·연습·도전·드래프트는 내 덱이 블루입니다. 온라인·기타는 내 진영을 식별하지 않고 블루·레드 기준으로 찾습니다. 공백으로 나눈 검색어를 모두 포함해야 하며, 전체 검색·다른 덱·필터 조건과 함께 적용합니다. 클립도 전체 전투의 덱을 사용합니다." % ("블루" if side == 0 else "레드")
		query.max_length = 160
		query.clear_button_enabled = true
		query.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
		query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		query.text = String(state.get("blue_query" if side == 0 else "red_query", ""))
		field.add_child(query)
		_deck_queries.append(query)
	# Keep removal controls outside the result cards, including an empty result.
	# A single horizontal row bounds the height even for many manually typed terms.
	_term_scroll = ScrollContainer.new()
	_term_scroll.name = "ReplaySearchTerms"
	_term_scroll.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT + 18
	_term_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_term_scroll.follow_focus = true
	_term_scroll.get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
	_term_scroll.tooltip_text = "현재 검색어를 하나씩 해제합니다. 좌우로 스크롤하거나 Tab으로 이동할 수 있습니다. 블루·레드는 저장된 진영 기준입니다."
	column.add_child(_term_scroll)
	column.move_child(_term_scroll, _scroll.get_index())
	_term_row = HBoxContainer.new()
	_term_row.name = "Terms"
	_term_row.add_theme_constant_override("separation", 8)
	_term_scroll.add_child(_term_row)
	_deck_notice = Label.new()
	_deck_notice.name = "ReplayDeckSearchNotice"
	_deck_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_deck_notice.add_theme_font_size_override("font_size", 14)
	_deck_notice.add_theme_color_override("font_color", UIKit.TEAL)
	_deck_notice.visible = false
	column.add_child(_deck_notice)
	column.move_child(_deck_notice, _scroll.get_index())
	var storage := Label.new()
	storage.name = "ReplayStorageSummary"
	storage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	storage.add_theme_font_size_override("font_size", 14)
	storage.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	var totals := storage_totals(_entries)
	storage.text = "전체 보관 %d개 · %s\n일반 %s · 정리 제외 %s · 읽기 실패 %s" % [_entries.size(), storage_size_text(int(totals.bytes), int(totals.unknown)), _storage_group_text(totals.normal), _storage_group_text(totals.protected), _storage_group_text(totals.unreadable)]
	storage.tooltip_text = "검색 조건과 관계없는 이 기기의 전체 보관함입니다. 새로고침할 때 JSON 파일 크기를 다시 확인합니다. 용량은 파일 내용의 크기이며 디스크 사용량·남은 저장 공간과는 다릅니다. 클립도 전체 전투 기록을 포함합니다. 정리 제외·읽기 실패 파일은 자동 정리로 줄어들지 않습니다."
	if not _load_error.is_empty():
		storage.text = "전체 보관 개수·용량을 확인하지 못했습니다."
		storage.tooltip_text = _load_error
	column.add_child(storage)
	column.move_child(storage, _scroll.get_index())
	var pages := HFlowContainer.new()
	_pages = pages
	pages.name = "ReplayPages"
	pages.add_theme_constant_override("h_separation", 8)
	pages.add_theme_constant_override("v_separation", 4)
	column.add_child(pages)
	column.move_child(pages, _scroll.get_index() + 1)
	_first = _page_button(pages, "FirstReplayPage", "처음", 0)
	_previous = _page_button(pages, "PreviousReplayPage", "이전", -1)
	_page_label = Label.new()
	_page_label.name = "ReplayPageSummary"
	_page_label.custom_minimum_size = Vector2(210, UIKit.TOUCH_MIN_HEIGHT)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 14)
	_page_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	pages.add_child(_page_label)
	_next = _page_button(pages, "NextReplayPage", "다음", 1)
	_last = _page_button(pages, "LastReplayPage", "마지막", 2)
	_search.text_changed.connect(func(_text): _refresh(true))
	for query in _deck_queries:
		query.text_changed.connect(func(_text): _refresh(true))
	_mode.item_selected.connect(func(_index): _refresh(true))
	_scope.item_selected.connect(func(_index): _refresh(true))
	_outcome.item_selected.connect(func(_index): _refresh(true))
	_retention.item_selected.connect(func(_index): _refresh(true))
	_sort.item_selected.connect(func(_index): _refresh(true))
	_reset.pressed.connect(_reset_filters)
	_scroll.follow_focus = true
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.gui_input.connect(_on_scroll_input)
	# Capture the requested position before the initial layout updates its scrollbar.
	_refresh(false)
	_scroll.get_v_scroll_bar().value_changed.connect(_remember_scroll)
	if not get_viewport().gui_focus_changed.is_connected(_remember_focus):
		get_viewport().gui_focus_changed.connect(_remember_focus)

func _alive() -> bool:
	if not is_inside_tree(): return false
	var node: Node = self
	while is_instance_valid(node):
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true

func _usable(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled)

func _card_for(path: String) -> Control:
	for entry in _page_entries:
		if String(entry.path) == path and entry.card.visible: return entry.card
	return null

func _remember_focus(control: Control) -> void:
	if not _alive() or _restoring or not is_instance_valid(control): return
	# Dialogs are siblings of this frame. They must not replace the shelf bookmark.
	if not is_ancestor_of(control): return
	if _loading and control == _load_refresh:
		_state["focus_file"] = ""
		_state["focus_control"] = "Column/ReplaySearchTools/RefreshReplayList"
		return
	_store_focus(control)

func _store_focus(control: Control) -> void:
	_state["focus_file"] = ""
	_state["focus_control"] = String(get_path_to(control))
	for entry in _page_entries:
		if entry.card.is_ancestor_of(control):
			_state["focus_file"] = String(entry.path)
			_state["focus_control"] = String(control.name)
			break

func _remember_scroll(value: float) -> void:
	if not _alive() or _restoring: return
	_state["scroll"] = int(value)
	_state["anchor_file"] = ""
	# Keep the first visible card at the same viewport offset even if newer files
	# have been inserted above it. Never identify cards by their generated node names.
	for entry in _page_entries:
		var card: Control = entry.card
		if card.visible and card.position.y + card.size.y > value:
			_state["anchor_file"] = String(entry.path)
			_state["anchor_offset"] = int(card.position.y) - int(value)
			break

## Explicit post-action focus shares the same layout/scroll restoration as refresh.
func restore_focus(target: Control) -> void:
	if not _alive() or not _usable(target) or not is_ancestor_of(target): return
	_store_focus(target)
	_schedule_restore()

func deck_queries() -> PackedStringArray:
	return PackedStringArray([_deck_queries[0].text, _deck_queries[1].text])

## Deck analysis uses the entire loaded snapshot, independent of visible cards.
## Retain the newest deck's slot order even if the shelf is sorted oldest/largest.
func snapshot_replays() -> Array:
	var entries := _entries.duplicate()
	entries.sort_custom(func(a, b):
		return int(a.order) > int(b.order) or (int(a.order) == int(b.order) and String(a.path) > String(b.path)))
	return entries.map(func(entry): return entry.replay)

## Apply both fields together. Keep the source card reachable for repeated choices.
func apply_deck_queries(queries: PackedStringArray, source: Button, message: String) -> void:
	if not _alive() or not _usable(source) or not is_ancestor_of(source) or queries.size() != 2: return
	for side in 2:
		if queries[side].length() > _deck_queries[side].max_length:
			_deck_notice.text = "검색어가 길어 조건을 적용하지 못했습니다. 해당 덱 검색칸의 조건을 줄인 뒤 다시 누르세요. 기존 검색 조건은 유지했습니다."
			_deck_notice.add_theme_color_override("font_color", UIKit.DANGER)
			_deck_notice.show()
			# The pressed button toggled before validation; restore its actual state.
			deck_filters_changed.emit(deck_queries())
			_deck_queries[side].grab_focus()
			_store_focus(_deck_queries[side])
			return
	source.grab_focus()
	_store_focus(source)
	_remember_scroll(_scroll.scroll_vertical)
	# Assigning LineEdit.text does not emit text_changed. Refresh once after both.
	for side in 2: _deck_queries[side].text = queries[side]
	_deck_notice.text = message
	_deck_notice.add_theme_color_override("font_color", UIKit.TEAL)
	_deck_notice.show()
	_refresh(false)

func _option(parent: Control, node_name: String, labels: Array, selected: int) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
	for label in labels:
		option.add_item(String(label))
	option.select(clampi(selected, 0, labels.size() - 1))
	parent.add_child(option)
	return option

func _page_button(parent: Control, node_name: String, text: String, action: int) -> Button:
	var button := UIKit.style_button(Button.new(), UIKit.TEAL)
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(78, UIKit.TOUCH_MIN_HEIGHT)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.tooltip_text = "검색 결과를 %d개씩 탐색합니다. 검색·정렬·전체 용량 집계와 보관 파일은 유지합니다." % PAGE_SIZE
	parent.add_child(button)
	button.pressed.connect(func():
		var target := 0 if action == 0 else (_page_count - 1 if action == 2 else _page + action)
		_change_page(target, button))
	return button

func _change_page(page: int, button: Button) -> void:
	if not _alive() or button.disabled: return
	_page = clampi(page, 0, _page_count - 1)
	_state["page"] = _page
	_state["scroll"] = 0
	_state["anchor_file"] = ""
	button.grab_focus()
	_store_focus(button)
	_refresh(false)
	_scroll.scroll_vertical = 0
	# Boundary buttons become disabled on the destination page. Keep a usable
	# paging control focused so repeated keyboard navigation cannot lose its place.
	if button.disabled:
		var target := _previous if _page > 0 else _next
		restore_focus(target)

func _render_page(visible_entries: Array) -> void:
	var start := _page * PAGE_SIZE
	var current: Array = visible_entries.slice(start, mini(start + PAGE_SIZE, visible_entries.size()))
	var paths := {}
	for entry in current: paths[String(entry.path)] = true
	for entry in _page_entries:
		if paths.has(String(entry.path)): continue
		var card: Control = entry.card
		_rows.remove_child(card)
		card.queue_free()
		entry.erase("card")
	_page_entries = current
	for index in _page_entries.size():
		var entry: Dictionary = _page_entries[index]
		if not entry.has("card"):
			var card: Control = _card_factory.call(entry)
			card.set_meta("replay_path", String(entry.path))
			_rows.add_child(card)
			entry["card"] = card
		_rows.move_child(entry.card, index)
	_first.disabled = _page == 0
	_previous.disabled = _page == 0
	_next.disabled = _page + 1 >= _page_count
	_last.disabled = _page + 1 >= _page_count
	_pages.visible = _page_count > 1
	_page_label.text = "%d / %d쪽 · %d–%d / %d개" % [_page + 1, _page_count, start + 1 if not current.is_empty() else 0, start + current.size(), visible_entries.size()]
	_page_label.tooltip_text = "조건에 맞는 전체 결과 중 현재 페이지의 범위입니다. 새로고침·재생 복귀 시 보던 전투가 있는 페이지를 복원합니다."

static func matches(entry: Dictionary, query: String, mode: int, scope: int, outcome: int, retention: int = 0, blue_query: String = "", red_query: String = "") -> bool:
	if mode > 0 and String(entry.mode) != String(MODES[mode]): return false
	if scope > 0 and (entry.mode == "unreadable" or bool(entry.clip) != (scope == 2)): return false
	if outcome > 0 and int(entry.winner) != outcome - 1: return false
	if retention > 0 and (entry.mode == "unreadable" or bool(entry.get("protected", false)) != (retention == 1)): return false
	if not _query_matches(String(entry.search), query): return false
	var decks: PackedStringArray = entry.get("deck_search", PackedStringArray())
	return _query_matches(decks[0] if decks.size() == 2 else "", blue_query) and _query_matches(decks[1] if decks.size() == 2 else "", red_query)

static func _query_matches(text: String, query: String) -> bool:
	for term in _search_terms(query.to_lower()):
		if not text.contains(term): return false
	return true

static func _search_terms(query: String) -> PackedStringArray:
	return query.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)

func _sync_search_terms() -> void:
	var fields: Array[LineEdit] = [_search, _deck_queries[0], _deck_queries[1]]
	var focused := get_viewport().gui_get_focus_owner()
	var focus_index := _term_buttons.find(focused)
	var existing := {}
	for button in _term_buttons: existing[String(button.name)] = button
	var current: Array[Button] = []
	for field in fields.size():
		var seen := {}
		for term in _search_terms(fields[field].text):
			var key: String = term.to_lower()
			if seen.has(key): continue
			seen[key] = true
			var node_name := "RemoveSearchTerm%d_%s" % [field, key.sha256_text()]
			var button: Button = existing.get(node_name)
			if button == null:
				var tone: Color = [UIKit.TEAL, UIKit.TEAM_BLUE, UIKit.TEAM_RED][field]
				button = UIKit.style_button(Button.new(), tone, false, 14)
				button.name = node_name
				button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
				button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
				button.mouse_filter = Control.MOUSE_FILTER_PASS
				button.set_meta("search_field", field)
				button.set_meta("search_term", key)
				button.pressed.connect(_remove_search_term.bind(button))
				_term_row.add_child(button)
			existing.erase(node_name)
			var title: String = term
			if field > 0:
				title = String(BattleModel.UNIT_NAMES.get(key, {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}.get(key, term)))
			var field_name := String(["전체", "블루", "레드"][field])
			button.text = "%s: %s ×" % [field_name, title.left(22) + ("…" if title.length() > 22 else "")]
			button.tooltip_text = "%s 검색의 ‘%s’ 단어만 해제합니다. 같은 단어의 중복·대소문자 변형도 해제하며 부분 검색어·다른 검색칸·필터·정렬은 유지합니다." % [field_name, term]
			_term_row.move_child(button, current.size())
			current.append(button)
	for button in existing.values():
		_term_row.remove_child(button)
		button.queue_free()
	_term_buttons = current
	_term_scroll.visible = not current.is_empty()
	# Reuse surviving nodes and move a removed chip's focus to its nearest neighbor.
	# Never open a touch keyboard merely to remove a condition.
	if focus_index >= 0 and focused not in current:
		var target: Control = current[mini(focus_index, current.size() - 1)] if not current.is_empty() else _scroll
		target.grab_focus()
		_store_focus(target)

func _remove_search_term(button: Button) -> void:
	if not _alive() or not _usable(button): return
	button.grab_focus()
	_store_focus(button)
	_remember_scroll(_scroll.scroll_vertical)
	var field := int(button.get_meta("search_field"))
	var term := String(button.get_meta("search_term"))
	var query: LineEdit = _search if field == 0 else _deck_queries[field - 1]
	var remaining := PackedStringArray()
	for other in _search_terms(query.text):
		if other.to_lower() != term: remaining.append(other)
	# Assigning text does not emit text_changed; update cards and selections once.
	query.text = " ".join(remaining)
	_deck_notice.text = "%s 검색: ‘%s’ 해제 · 다른 검색·필터·정렬 조건은 유지합니다." % [["전체", "블루", "레드"][field], term]
	_deck_notice.add_theme_color_override("font_color", UIKit.TEAL)
	_deck_notice.show()
	_refresh(false)

## Only aggregate the loaded snapshot. Typing/filtering never opens files.
static func storage_totals(entries: Array) -> Dictionary:
	var totals := {"bytes": 0, "unknown": 0, "normal": {"count": 0, "bytes": 0, "unknown": 0}, "protected": {"count": 0, "bytes": 0, "unknown": 0}, "unreadable": {"count": 0, "bytes": 0, "unknown": 0}}
	for entry in entries:
		var group: Dictionary = totals.unreadable if String(entry.mode) == "unreadable" else (totals.protected if bool(entry.get("protected", false)) else totals.normal)
		group.count += 1
		var bytes := int(entry.get("file_bytes", -1))
		if bytes < 0:
			group.unknown += 1
			totals.unknown += 1
		else:
			group.bytes += bytes
			totals.bytes += bytes
	return totals

static func storage_size_text(bytes: int, unknown: int = 0) -> String:
	if bytes < 0 or (bytes == 0 and unknown > 0): return "용량 미상" + (" %d개" % unknown if unknown > 0 else "")
	var size := float(bytes)
	var units := ["B", "KiB", "MiB", "GiB", "TiB"]
	var unit := 0
	while size >= 1024.0 and unit < units.size() - 1:
		size /= 1024.0
		unit += 1
	var text := "%d B" % bytes if unit == 0 else "%.1f %s" % [size, units[unit]]
	return text if unknown == 0 else "최소 %s (+%d개 미상)" % [text, unknown]

static func _storage_group_text(group: Dictionary) -> String:
	return "%d개 / %s" % [int(group.count), storage_size_text(int(group.bytes), int(group.unknown))]

func _apply_sort() -> void:
	if _applied_sort == _sort.selected: return
	_applied_sort = _sort.selected
	_entries.sort_custom(func(a, b):
		if _applied_sort == 2:
			var a_bytes := int(a.get("file_bytes", -1))
			var b_bytes := int(b.get("file_bytes", -1))
			if a_bytes != b_bytes: return a_bytes > b_bytes
		var a_order := int(a.get("order", 0))
		var b_order := int(b.get("order", 0))
		if a_order != b_order:
			return a_order < b_order if _applied_sort == 1 else a_order > b_order
		return String(a.path) < String(b.path) if _applied_sort == 1 else String(a.path) > String(b.path))

func _refresh(reset_scroll: bool) -> void:
	_refresh_revision += 1
	if reset_scroll: _deck_notice.hide()
	_sync_search_terms()
	_state["query"] = _search.text
	_state["blue_query"] = _deck_queries[0].text
	_state["red_query"] = _deck_queries[1].text
	_state["mode"] = _mode.selected
	_state["scope"] = _scope.selected
	_state["outcome"] = _outcome.selected
	_state["retention"] = _retention.selected
	_state["sort"] = _sort.selected
	_apply_sort()
	var visible_entries: Array = []
	for entry in _entries:
		if matches(entry, _search.text, _mode.selected, _scope.selected, _outcome.selected, _retention.selected, _deck_queries[0].text, _deck_queries[1].text):
			visible_entries.append(entry)
	var shown := visible_entries.size()
	_count.text = "%d / %d개 검색 결과" % [shown, _entries.size()]
	var visible_storage := storage_totals(visible_entries)
	_count.text += " · " + storage_size_text(int(visible_storage.bytes), int(visible_storage.unknown))
	_count.tooltip_text = "현재 페이지뿐 아니라 검색 조건에 맞는 전체 파일의 개수와 용량입니다. 읽기 실패 파일도 포함합니다. 검색·필터·정렬·페이지는 자동 정리와 덱 분석의 대상에 영향을 주지 않습니다."
	if not _load_error.is_empty():
		_count.text = "목록 읽기 실패"
		_count.tooltip_text = _load_error
	_reset.disabled = _search.text.is_empty() and _deck_queries[0].text.is_empty() and _deck_queries[1].text.is_empty() and _mode.selected == 0 and _scope.selected == 0 and _outcome.selected == 0 and _retention.selected == 0 and _sort.selected == 0
	if is_instance_valid(_empty):
		_rows.remove_child(_empty)
		_empty.queue_free()
		_empty = null
	_page_count = maxi(1, int(ceil(float(shown) / float(PAGE_SIZE))))
	if reset_scroll:
		_page = 0
	else:
		# Newer files or changed sizes can move the bookmarked card across a page
		# boundary. Resolve by file identity rather than retaining an obsolete index.
		var file := String(_state.get("focus_file", ""))
		if file.is_empty(): file = String(_state.get("anchor_file", ""))
		for index in visible_entries.size():
			if String(visible_entries[index].path) == file:
				_page = int(index / PAGE_SIZE)
				break
	_page = clampi(_page, 0, _page_count - 1)
	_state["page"] = _page
	# Snapshot focus before freeing cards that leave the page. The snapshot below
	# must not dereference a detached card or accidentally bookmark another file.
	var focused := get_viewport().gui_get_focus_owner()
	if reset_scroll:
		_state["scroll"] = 0
		_state["anchor_file"] = ""
		if _usable(focused) and is_ancestor_of(focused) and not _rows.is_ancestor_of(focused):
			_store_focus(focused)
		else:
			_store_focus(_search)
	_restoring = true
	_render_page(visible_entries)
	if shown == 0:
		_empty = VBoxContainer.new()
		_empty.name = "NoReplays" if _entries.is_empty() else "NoReplayMatches"
		_empty.custom_minimum_size.y = 180
		_empty.alignment = BoxContainer.ALIGNMENT_CENTER
		_empty.add_theme_constant_override("separation", 10)
		_rows.add_child(_empty)
		var message := Label.new()
		message.text = "아직 저장된 리플레이가 없습니다" if _entries.is_empty() else "검색 조건에 맞는 리플레이가 없습니다"
		if not _load_error.is_empty(): message.text = "보관함을 읽지 못했습니다"
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UIKit.display(message, 22, UIKit.TEXT)
		_empty.add_child(message)
		var hint := Label.new()
		hint.text = "전투를 끝까지 치르면 자동 저장됩니다. 공유받은 텍스트는 클립보드에서 가져올 수 있습니다." if _entries.is_empty() else "상단의 ‘검색어 ×’로 조건을 하나씩 해제하거나 전체 검색·양쪽 덱 검색·종류·결과·보존 조건을 바꿔 보세요. 초기화는 모든 조건을 해제합니다. 읽기 실패 파일은 덱 조건을 해제해야 볼 수 있습니다."
		if not _load_error.is_empty(): hint.text = _load_error
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		_empty.add_child(hint)
	deck_filters_changed.emit(deck_queries())
	_schedule_restore()

func _schedule_restore() -> void:
	_refresh_revision += 1
	_restoring = true
	var bookmark := _state.duplicate()
	get_tree().process_frame.connect(_restore_navigation.bind(bookmark, _refresh_revision), CONNECT_ONE_SHOT)

func _restore_navigation(bookmark: Dictionary, revision: int) -> void:
	if not _alive() or revision != _refresh_revision: return
	var owner := get_viewport().gui_get_focus_owner()
	var keep_modal_focus := false
	# A newly opened modal keeps its focus. Ignore an owner in the old queued screen.
	if _usable(owner) and not is_ancestor_of(owner):
		var node: Node = owner
		var queued := false
		while is_instance_valid(node):
			if node.is_queued_for_deletion(): queued = true
			node = node.get_parent()
		if not queued:
			keep_modal_focus = true
	var target: Control
	var file := String(bookmark.get("focus_file", ""))
	var path := String(bookmark.get("focus_control", ""))
	if not file.is_empty():
		var card := _card_for(file)
		if card != null and not path.is_empty(): target = card.find_child(path, true, false) as Control
	elif not path.is_empty():
		target = get_node_or_null(NodePath(path)) as Control
	var fallback := not path.is_empty() and not _usable(target)
	if fallback: target = _search
	if path.is_empty(): target = _scroll
	if keep_modal_focus: target = null
	if _usable(target): target.grab_focus()
	# ScrollContainer follows focus on a deferred call; apply the bookmark after it.
	get_tree().process_frame.connect(_finish_restore.bind(bookmark, target, revision), CONNECT_ONE_SHOT)

func _finish_restore(bookmark: Dictionary, target: Control, revision: int) -> void:
	if not _alive() or revision != _refresh_revision: return
	var owner := get_viewport().gui_get_focus_owner()
	if _usable(owner) and owner != target:
		# Programmatic modal opening between phases also takes precedence. The
		# shelf can still restore its position behind the modal without taking focus.
		target = null
	var position := int(bookmark.get("scroll", 0))
	var anchor := _card_for(String(bookmark.get("anchor_file", "")))
	if anchor != null: position = int(anchor.position.y) - int(bookmark.get("anchor_offset", 0))
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = clampi(position, 0, maxi(0, int(bar.max_value - bar.page)))
	if _usable(target) and _scroll.is_ancestor_of(target):
		# Restored focus must remain visible after a saved memo changes the filters or
		# card height. Other cards are never activated as part of this fallback.
		_scroll.ensure_control_visible(target)
	if target == _search and not String(bookmark.get("focus_file", "")).is_empty():
		var status: Label = column.get_node("ReplayStatus")
		var notice := "선택했던 전투가 없어졌거나 검색 조건에서 제외되어 검색칸으로 초점을 옮겼습니다."
		status.text = notice + ("\n" + status.text if not status.text.is_empty() else "")
	_restoring = false
	_remember_scroll(_scroll.scroll_vertical)
	_remember_focus(owner if target == null else target)

func _input(event: InputEvent) -> void:
	if not _alive(): return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or event is InputEventScreenDrag:
		_load_input_revision += 1
		if not _restoring: return
		_refresh_revision += 1
		_restoring = false
		_remember_scroll(_scroll.scroll_vertical)
		_remember_focus(get_viewport().gui_get_focus_owner())

func _reset_filters() -> void:
	_search.text = ""
	for query in _deck_queries: query.text = ""
	_mode.select(0)
	_scope.select(0)
	_outcome.select(0)
	_retention.select(0)
	_sort.select(0)
	_refresh(true)
	_search.grab_focus()
	_store_focus(_search)

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
