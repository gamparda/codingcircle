extends "res://scripts/ui/SubMenuFrame.gd"
## Personal records with campaign and versioned challenge history. Footer actions stay outside the scroll area.

signal challenge_replays_requested(period: String, date: String, ruleset: String, record: Dictionary)

const TABLE_HEADERS := ["단계", "이름", "별", "도전", "승", "최단", "최고 기지 HP"]
const TABLE_WIDTHS := [56, 150, 96, 70, 70, 100, 140]
const ServerStats = preload("res://scripts/ServerStats.gd")
const ChallengeReplays = preload("res://scripts/ChallengeReplays.gd")
const ChallengeReplayScan = preload("res://scripts/ui/ChallengeReplayScan.gd")
const HISTORY_HEADERS := ["날짜 (UTC)", "콘텐츠 버전", "결과", "최고 점수", "완료 시간", "보관 전투"]
const HISTORY_WIDTHS := [170, 0, 70, 115, 115]
const HISTORY_PAGE_DATES := 10

var _history: Dictionary = {}
var _history_panels: Dictionary = {}
var _history_state := {
	"daily": {"filter": 0, "outcome": 0, "query": "", "page": 0, "scroll": 0},
	"weekly": {"filter": 0, "outcome": 0, "query": "", "page": 0, "scroll": 0}}
var _active_period := "campaign"
var _records_summary: HBoxContainer
var _history_tools: HBoxContainer
var _history_filter: OptionButton
var _history_outcome: OptionButton
var _history_search: LineEdit
var _history_reset: Button
var _history_navigation: HBoxContainer
var _history_page_label: Label
var _history_page_buttons: Array[Button] = []
var _records_scroll: ScrollContainer
var _history_page_count := 1
var _campaign_scroll := 0
var _session_state: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _saved_replays: Array = []
var _replays_loaded := false
var _replay_scan: ChallengeReplayScan
var _replay_status: Label
var _scroll_revision := 0
var _return_focus := ""

func populate(save_data: Dictionary, session_state: Dictionary = {}) -> void:
	_session_state = session_state
	if session_state.has("history"):
		_history_state = session_state.history
	else:
		session_state["history"] = _history_state
	_campaign_scroll = int(session_state.get("campaign_scroll", 0))
	var restored_period := String(session_state.get("active", "campaign"))
	_return_focus = String(session_state.get("focus", ""))
	session_state.erase("focus")
	var stats: Dictionary = save_data.stats
	var online_rate := 0.0 if int(stats.online_completed) == 0 else float(stats.online_wins) / float(stats.online_completed) * 100.0
	var summary := HBoxContainer.new()
	summary.name = "RecordsSummary"
	summary.add_theme_constant_override("separation", 14)
	summary.add_child(_card("AI", [
		[str(stats.ai_matches), "경기", UIKit.TEXT], [str(stats.ai_wins), "승", UIKit.SUCCESS], [str(stats.ai_losses), "패", UIKit.DANGER],
		["%02d" % int(stats.highest_campaign), "최고 캠페인", UIKit.TEXT], [str(stats.total_stars), "별", UIKit.GOLD]]))
	summary.add_child(_card("온라인", [
		[str(stats.online_completed), "완료", UIKit.TEXT], [str(stats.online_wins), "승", UIKit.SUCCESS], [str(stats.online_losses), "패", UIKit.DANGER],
		[str(stats.online_draws), "무", UIKit.TEXT_MUTED], [str(stats.online_interrupted), "중단", UIKit.TEXT_MUTED], ["%.1f%%" % online_rate, "승률", UIKit.GOLD]]))
	column.add_child(summary)
	_records_summary = summary

	var tabs := HBoxContainer.new()
	tabs.name = "RecordsTabs"
	column.add_child(tabs)
	var tools := HBoxContainer.new()
	tools.name = "ChallengeHistoryTools"
	tools.visible = false
	tools.add_theme_constant_override("separation", 10)
	column.add_child(tools)
	_history_tools = tools
	var filter := OptionButton.new()
	filter.name = "ChallengeHistoryFilter"
	filter.add_item("전체 버전", 0)
	filter.add_item("현재 버전", 1)
	filter.add_item("이전·미상 버전", 2)
	filter.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
	tools.add_child(filter)
	_history_filter = filter
	var outcome := OptionButton.new()
	outcome.name = "ChallengeHistoryOutcome"
	outcome.add_item("결과 전체", 0)
	outcome.add_item("성공만", 1)
	outcome.add_item("실패만", 2)
	outcome.tooltip_text = "날짜·버전별 보관된 최고 기록을 성공/실패로 필터링합니다. 성공 기록이 있는 날짜·버전의 실패 시도는 별도로 표시하지 않습니다."
	outcome.custom_minimum_size.y = filter.custom_minimum_size.y
	tools.add_child(outcome)
	_history_outcome = outcome
	var search := LineEdit.new()
	search.name = "ChallengeHistorySearch"
	search.placeholder_text = "날짜 검색 · 2026-10 / 20261011"
	search.tooltip_text = "UTC 날짜의 앞부분으로 검색합니다. 연도·월·일을 숫자로 입력하세요. 주간 기록은 월요일 날짜입니다."
	search.max_length = 10
	search.custom_minimum_size.y = filter.custom_minimum_size.y
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(search)
	_history_search = search
	_history_reset = UIKit.style_button(Button.new(), UIKit.TEAL)
	_history_reset.name = "ChallengeHistoryReset"
	_history_reset.text = "초기화"
	tools.add_child(_history_reset)
	var replay_refresh := UIKit.style_button(Button.new(), UIKit.TEAL, false, 14)
	replay_refresh.name = "RefreshChallengeReplayCounts"
	replay_refresh.text = "보관 새로고침"
	replay_refresh.tooltip_text = "보관 전투 파일을 다시 읽습니다. 날짜·버전·결과 조건과 페이지·스크롤은 유지합니다."
	replay_refresh.pressed.connect(func():
		if _active_period == "campaign" or not _screen_alive(): return
		_remember_scroll(_records_scroll.scroll_vertical)
		_begin_replay_scan())
	tools.add_child(replay_refresh)
	_replay_status = Label.new()
	_replay_status.name = "ChallengeReplayCountProgress"
	_replay_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_replay_status.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	_replay_status.visible = false
	column.add_child(_replay_status)
	_build_history_navigation()
	var scroll := ScrollContainer.new()
	scroll.name = "RecordsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.gui_input.connect(_on_records_scroll_input)
	column.add_child(scroll)
	_records_scroll = scroll
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	var buttons := {}
	var group := ButtonGroup.new()
	for entry in [["campaign", "캠페인"], ["daily", "일일 도전"], ["weekly", "주간 도전"]]:
		var page := VBoxContainer.new()
		page.name = "RecordsPage_" + entry[0]
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = entry[0] == "campaign"
		pages.add_child(page)
		_history_panels[entry[0]] = page
		var button := UIKit.style_button(Button.new(), UIKit.ACCENT)
		button.name = "RecordsTab_" + entry[0]
		button.text = entry[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = entry[0] == "campaign"
		tabs.add_child(button)
		buttons[entry[0]] = button
	for id in buttons:
		buttons[id].pressed.connect(_select_records_tab.bind(id))
	_tab_buttons = buttons
	# Keep a read-only snapshot so filtering does not modify best scores or pending submissions.
	_history = {"daily": save_data.daily.duplicate(true), "weekly": save_data.weekly.duplicate(true)}
	filter.item_selected.connect(_on_history_filter_changed)
	outcome.item_selected.connect(_on_history_outcome_changed)
	search.text_changed.connect(_on_history_search_changed)
	_history_reset.pressed.connect(_reset_history_search)
	_populate_campaign(_history_panels.campaign, save_data)
	_records_scroll.get_v_scroll_bar().value_changed.connect(_remember_scroll)
	if restored_period in ["daily", "weekly"]:
		_select_records_tab(restored_period, false)
	else:
		_restore_scroll_after_layout(_campaign_scroll)

func _remember_scroll(value: float) -> void:
	if not _screen_alive(): return
	if _active_period == "campaign":
		_campaign_scroll = int(value)
		_session_state["campaign_scroll"] = int(value)
	else:
		_history_state[_active_period].scroll = int(value)

func _restore_scroll_after_layout(position: int) -> void:
	_scroll_revision += 1
	get_tree().process_frame.connect(_restore_scroll.bind(position, _active_period, _scroll_revision), CONNECT_ONE_SHOT)

func _restore_scroll(position: int, period: String, revision: int) -> void:
	if _screen_alive() and period == _active_period and revision == _scroll_revision:
		if not _return_focus.is_empty():
			var target := find_child(_return_focus, true, false) as Control
			if target != null and target.is_visible_in_tree() and not (target is Button and target.disabled):
				target.grab_focus()
			else:
				_records_scroll.grab_focus()
			_return_focus = ""
		_records_scroll.scroll_vertical = position

func _screen_alive() -> bool:
	if not is_inside_tree(): return false
	var node: Node = self
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true

func _begin_replay_scan() -> void:
	if _replay_scan != null: _replay_scan.cancel()
	_replay_scan = ChallengeReplayScan.new()
	_replay_scan.begin()
	_update_replay_progress()
	_update_replay_buttons()
	set_process(true)

func _process(_delta: float) -> void:
	if _replay_scan == null: return
	if not _screen_alive():
		_replay_scan.cancel()
		_replay_scan = null
		set_process(false)
		return
	_replay_scan.step()
	_update_replay_progress()
	if not _replay_scan.done: return
	var error := _replay_scan.error
	if error.is_empty():
		_saved_replays = _replay_scan.entries
		_replays_loaded = true
	_replay_scan = null
	set_process(false)
	_replay_status.text = error + ("\n이전 조회 개수는 유지합니다." if _replays_loaded and not error.is_empty() else "")
	_replay_status.visible = _active_period != "campaign" and not error.is_empty()
	# Update counts in place; preserve date filters, page, scroll and keyboard focus.
	_update_replay_buttons()

func _update_replay_progress() -> void:
	_replay_status.text = _replay_scan.progress + (" · 이전 조회 개수 표시 중" if _replays_loaded else "")
	_replay_status.visible = _active_period != "campaign"

func _update_replay_buttons() -> void:
	for page in _history_panels.values():
		for button in page.find_children("ChallengeReplays_*", "Button", true, false):
			_update_replays_button(button)
			if button.disabled and get_viewport().gui_get_focus_owner() == button:
				_records_scroll.grab_focus()

func _exit_tree() -> void:
	if _replay_scan != null: _replay_scan.cancel()
	_replay_scan = null

func _build_history_navigation() -> void:
	_history_navigation = HBoxContainer.new()
	_history_navigation.name = "ChallengeHistoryNavigation"
	_history_navigation.visible = false
	_history_navigation.add_theme_constant_override("separation", 8)
	column.add_child(_history_navigation)
	for entry in [["First", "최신", 0], ["Previous", "더 최근", -1], ["Next", "더 이전", 1], ["Last", "마지막", 0]]:
		var button := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 14)
		button.name = "ChallengeHistory" + entry[0]
		button.text = entry[1]
		button.custom_minimum_size.x = 90
		_history_navigation.add_child(button)
		_history_page_buttons.append(button)
		button.pressed.connect(_move_history_page.bind(String(entry[0]), int(entry[2])))
	_history_page_label = Label.new()
	_history_page_label.name = "ChallengeHistoryPage"
	_history_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_history_page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_history_page_label.add_theme_font_size_override("font_size", 14)
	_history_page_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	_history_navigation.add_child(_history_page_label)
	_history_navigation.move_child(_history_page_label, 2)

func _move_history_page(action: String, direction: int) -> void:
	if _active_period == "campaign": return
	var state: Dictionary = _history_state[_active_period]
	var target := 0 if action == "First" else (_history_page_count - 1 if action == "Last" else int(state.page) + direction)
	state.page = clampi(target, 0, _history_page_count - 1)
	state.scroll = 0
	_refresh_history()

func _select_records_tab(period: String, remember_current: bool = true) -> void:
	if period == _active_period:
		return
	if remember_current:
		_remember_scroll(_records_scroll.scroll_vertical)
	var target_scroll := _campaign_scroll if period == "campaign" else int(_history_state[period].scroll)
	_active_period = period
	_session_state["active"] = period
	_tab_buttons[period].button_pressed = true
	for key in _history_panels:
		_history_panels[key].visible = key == period
	_history_tools.visible = period != "campaign"
	_replay_status.visible = period != "campaign" and (_replay_scan != null or not _replay_status.text.is_empty())
	_history_navigation.visible = period != "campaign"
	# Summary cards remain on the campaign tab, leaving room for challenge navigation.
	_records_summary.visible = period == "campaign"
	if period == "campaign":
		_restore_scroll_after_layout(target_scroll)
	else:
		if not _replays_loaded:
			if _replay_scan == null: _begin_replay_scan()
		var state: Dictionary = _history_state[period]
		_history_filter.select(int(state.filter))
		_history_outcome.select(int(state.outcome))
		_history_search.set_block_signals(true)
		_history_search.text = String(state.query)
		_history_search.set_block_signals(false)
		state.scroll = target_scroll
		_refresh_history()

func _on_history_filter_changed(index: int) -> void:
	if _active_period == "campaign": return
	_history_state[_active_period].filter = index
	_restart_history_page()

func _on_history_outcome_changed(index: int) -> void:
	if _active_period == "campaign": return
	_history_state[_active_period].outcome = index
	_restart_history_page()

func _on_history_search_changed(query: String) -> void:
	if _active_period == "campaign": return
	_history_state[_active_period].query = query
	_restart_history_page()

func _reset_history_search() -> void:
	if _active_period == "campaign": return
	_history_state[_active_period].filter = 0
	_history_state[_active_period].outcome = 0
	_history_state[_active_period].query = ""
	_history_filter.select(0)
	_history_outcome.select(0)
	_history_search.text = ""
	_restart_history_page()

func _restart_history_page() -> void:
	_history_state[_active_period].page = 0
	_history_state[_active_period].scroll = 0
	_refresh_history()

func _refresh_history() -> void:
	var state: Dictionary = _history_state[_active_period]
	var position := int(state.scroll)
	var result := _populate_history(_history_panels[_active_period], _history[_active_period], _active_period, int(state.filter), String(state.query), int(state.page), int(state.outcome))
	state.page = result.page
	_history_page_count = result.pages
	var first := int(result.page) * HISTORY_PAGE_DATES + 1 if int(result.dates) > 0 else 0
	var last := mini((int(result.page) + 1) * HISTORY_PAGE_DATES, int(result.dates))
	_history_page_label.text = "%d–%d / %d%s · %d개 기록" % [first, last, int(result.dates), "주" if _active_period == "weekly" else "일", int(result.records)]
	_history_page_label.tooltip_text = "날짜·버전·결과 조건에 맞는 날짜 수와 전체 기록 수입니다. 같은 날짜에서 조건에 맞는 버전별 기록은 한 페이지에 표시합니다."
	for index in _history_page_buttons.size():
		_history_page_buttons[index].disabled = int(state.page) == (0 if index < 2 else _history_page_count - 1)
	_history_reset.disabled = int(state.filter) == 0 and int(state.outcome) == 0 and String(state.query).is_empty() and int(state.page) == 0
	_restore_scroll_after_layout(position)

func _on_records_scroll_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var bar := _records_scroll.get_v_scroll_bar()
	var target := _records_scroll.scroll_vertical
	match event.keycode:
		KEY_UP: target -= 48
		KEY_DOWN: target += 48
		KEY_PAGEUP: target -= maxi(48, int(bar.page))
		KEY_PAGEDOWN: target += maxi(48, int(bar.page))
		KEY_HOME: target = 0
		KEY_END: target = int(bar.max_value - bar.page)
		_: return
	_records_scroll.scroll_vertical = clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
	_records_scroll.accept_event()

func _populate_campaign(page: VBoxContainer, save_data: Dictionary) -> void:

	var heading := Label.new()
	heading.text = Localization.text("캠페인 기록")
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", UIKit.GOLD)
	page.add_child(heading)
	var table := GridContainer.new()
	table.name = "CampaignTable"
	table.columns = TABLE_HEADERS.size()
	table.add_theme_constant_override("h_separation", 10)
	table.add_theme_constant_override("v_separation", 3)
	page.add_child(table)
	for index in TABLE_HEADERS.size():
		table.add_child(_cell(Localization.text(TABLE_HEADERS[index]), index, UIKit.TEXT_DIM, 13))
	for stage in ServerAI.MAX_STAGE:
		var record: Dictionary = save_data.campaign_records[stage]
		var stars := int(record.best_stars)
		var played := int(record.attempts) > 0
		var cells := [
			"%02d" % (stage + 1), ServerAI.stage_name(stage + 1), "★".repeat(stars) + "☆".repeat(3 - stars),
			str(record.attempts), str(record.wins),
			("%.1f초" % float(record.fastest_win)) if float(record.fastest_win) > 0.0 else "—",
			str(int(record.best_base_hp)) if played else "—"]
		for index in cells.size():
			var color := UIKit.TEXT if played else UIKit.TEXT_MUTED
			if index == 2:
				color = UIKit.GOLD if stars > 0 else UIKit.TEXT_DIM
			table.add_child(_cell(String(cells[index]), index, color, 16))

func _populate_history(page: VBoxContainer, history: Dictionary, period: String, filter: int, query: String = "", page_index: int = 0, outcome: int = 0) -> Dictionary:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	var prefix := query.strip_edges().replace("-", "").replace("/", "")
	var valid_query := prefix.length() <= 8
	for character in prefix:
		if not "0123456789".contains(character): valid_query = false
	# Count the date/version selection before applying outcome, then paginate the
	# matching dates. Versions with different outcomes must be filtered separately.
	var matching_rows := _history_rows(history, filter, prefix) if valid_query else []
	var successes := 0
	var failures := 0
	var rows: Array = []
	for row in matching_rows:
		var won := bool(row.record.get("won", false))
		if won:
			successes += 1
		else:
			failures += 1
		if (outcome == 1 and not won) or (outcome == 2 and won): continue
		rows.append(row)
	var dates: Array = []
	for row in rows:
		if dates.is_empty() or dates.back() != row.date:
			dates.append(row.date)
	var pages := maxi(1, ceili(float(dates.size()) / HISTORY_PAGE_DATES))
	page_index = clampi(page_index, 0, pages - 1)
	var page_dates := dates.slice(page_index * HISTORY_PAGE_DATES, (page_index + 1) * HISTORY_PAGE_DATES)
	var hint := Label.new()
	hint.text = "기기에 보관된 최고 기록 · %s · 버전이 다른 점수는 따로 표시합니다." % ("최근 %d주, 주 시작일 기준" % SaveData.WEEKLY_HISTORY if period == "weekly" else "최근 %d일" % SaveData.DAILY_HISTORY)
	hint.text += "\n완료 시간은 해당 최고 점수를 낸 전투의 시간입니다. 같은 점수라면 더 빠른 성공 기록을 보관합니다."
	hint.text += "\n성공이 보관된 날짜·버전의 실패 시도는 별도로 표시하지 않습니다."
	hint.text += "\n보관 전투는 같은 날짜·버전의 도전과 버전 미상 전투입니다. 최고 점수의 전투인지는 별도로 확인하세요."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	page.add_child(hint)
	if valid_query and not history.is_empty():
		var summary := Label.new()
		summary.name = "ChallengeHistorySummary_" + period
		summary.text = "날짜·버전 조건: 성공 %d개 · 실패 %d개  |  %s %d개" % [successes, failures, "전체 표시" if outcome == 0 else ("성공만 표시" if outcome == 1 else "실패만 표시"), rows.size()]
		summary.tooltip_text = "모든 페이지에 걸친 날짜·버전별 보관 기록 수입니다. 전체 도전 횟수나 승률이 아닙니다. 결과 필터를 바꿔도 왼쪽의 성공·실패 수는 유지됩니다."
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 14)
		summary.add_theme_color_override("font_color", UIKit.TEXT)
		page.add_child(summary)
	var table := GridContainer.new()
	table.name = "ChallengeHistoryTable_" + period
	table.columns = HISTORY_HEADERS.size()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 8)
	page.add_child(table)
	for index in HISTORY_HEADERS.size():
		if index < HISTORY_WIDTHS.size():
			table.add_child(_history_cell(HISTORY_HEADERS[index], index, UIKit.TEXT_DIM))
		else:
			var heading := Label.new()
			heading.text = HISTORY_HEADERS[index]
			heading.add_theme_color_override("font_color", UIKit.TEXT_DIM)
			table.add_child(heading)
	var current := ServerStats.ruleset_id()
	for row in rows:
		if not page_dates.has(row.date): continue
		var item: Dictionary = row.record
		var rule := String(row.ruleset)
		var won := bool(item.get("won", false))
		var status := "버전 미상" if rule == "0" else ("현재" if rule == current else "이전")
		var key := String(row.date)
		var cells := ["%s-%s-%s" % [key.substr(0, 4), key.substr(4, 2), key.substr(6, 2)],
			"%s · %s" % [status, rule], "성공" if won else "실패", "%d점" % int(item.get("score", 0)), "%.1f초" % float(item.get("seconds", 0.0))]
		for index in cells.size():
			var color := UIKit.GOLD if rule == current else UIKit.TEXT_MUTED
			if index == 2: color = UIKit.SUCCESS if won else UIKit.DANGER
			var cell := _history_cell(cells[index], index, color)
			if index == 4:
				cell.tooltip_text = "최고 점수를 낸 전투의 완료 시간" if won else "기록된 실패 도전의 전투 시간"
			table.add_child(cell)
		table.add_child(_replays_button(period, key, rule, item))
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "ChallengeHistoryEmpty_" + period
		if not valid_query:
			empty.text = "날짜를 2026-10 또는 20261011처럼 입력하세요."
		elif history.is_empty():
			empty.text = "저장된 %s 도전 기록이 없습니다." % ("주간" if period == "weekly" else "일일")
		elif not matching_rows.is_empty():
			empty.text = "날짜·버전 조건에 맞는 %s 기록이 없습니다. '결과 전체'를 선택하면 %s 기록 %d개를 볼 수 있습니다." % ["성공" if outcome == 1 else "실패", "실패" if outcome == 1 else "성공", matching_rows.size()]
		elif not prefix.is_empty():
			empty.text = "날짜와 버전 조건에 맞는 기록이 없습니다. 주간 기록은 월요일 날짜로 검색하세요." if period == "weekly" else "날짜와 버전 조건에 맞는 기록이 없습니다. 검색 날짜나 버전을 바꿔 보세요."
		else:
			empty.text = "선택한 버전의 기록이 없습니다. 다른 버전을 선택해 보세요."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		page.add_child(empty)
	return {"page": page_index, "pages": pages, "dates": dates.size(), "records": rows.size()}

func _replays_button(period: String, date: String, ruleset: String, record: Dictionary) -> Button:
	var button := UIKit.style_button(Button.new(), UIKit.TEAL, false, 14)
	button.name = "ChallengeReplays_" + period + "_" + date + "_" + ruleset.replace(".", "_")
	button.set_meta("challenge_lookup", [period, date, ruleset])
	button.custom_minimum_size = Vector2(114, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40)
	_update_replays_button(button)
	button.pressed.connect(func():
		if not _screen_alive(): return
		_remember_scroll(_records_scroll.scroll_vertical)
		_session_state["focus"] = String(button.name)
		challenge_replays_requested.emit(period, date, ruleset, record.duplicate(true)))
	return button

func _update_replays_button(button: Button) -> void:
	var lookup: Array = button.get_meta("challenge_lookup")
	var matches := ChallengeReplays.matching(_saved_replays, lookup[0], lookup[1], lookup[2])
	if not _replays_loaded:
		button.text = "읽는 중" if _replay_scan != null else "조회 실패"
		button.disabled = true
		button.tooltip_text = "읽기를 마치면 개수를 표시합니다. 조회 실패 시 보관 새로고침으로 다시 시도하세요."
	else:
		button.text = "전투 %d개" % matches.size() if not matches.is_empty() else "보관 없음"
		button.disabled = matches.is_empty()
		button.tooltip_text = "같은 날짜·버전의 전투와 버전 미상 전투를 엽니다. 최고 기록의 전투라고 단정하지 않습니다." if not matches.is_empty() else "읽을 수 있는 보관 전투가 없습니다. 저장 실패·자동 정리·삭제로 점수 기록만 남을 수 있습니다."

func _history_rows(history: Dictionary, filter: int, prefix: String) -> Array:
	var current := ServerStats.ruleset_id()
	var dates: Array = history.keys()
	dates.sort()
	dates.reverse()
	var rows: Array = []
	for date in dates:
		if not String(date).begins_with(prefix): continue
		var record: Dictionary = history[date]
		var versions: Dictionary = record.get("previous", {}).duplicate()
		versions[String(record.get("ruleset", "0"))] = record
		var rules: Array = versions.keys()
		rules.sort()
		if rules.has(current):
			rules.erase(current)
			rules.push_front(current)
		for rule in rules:
			if (filter == 1 and rule != current) or (filter == 2 and rule == current): continue
			rows.append({"date": date, "ruleset": rule, "record": versions[rule]})
	return rows

func _history_cell(text: String, index: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = HISTORY_WIDTHS[index]
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if index >= 3 else HORIZONTAL_ALIGNMENT_LEFT
	if index == 1:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.tooltip_text = text
	return label

func _cell(text: String, index: int, color: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = TABLE_WIDTHS[index]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if index < 3 else HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _card(title: String, tiles: Array) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "RecordsCard_" + title
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.SURFACE
	style.border_color = UIKit.EDGE_SOFT
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var heading := Label.new()
	heading.text = Localization.text(title)
	heading.add_theme_font_size_override("font_size", 15)
	heading.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	box.add_child(heading)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	for tile in tiles:
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		var value := Label.new()
		value.text = String(tile[0])
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.add_theme_font_size_override("font_size", 26)
		value.add_theme_color_override("font_color", tile[2])
		cell.add_child(value)
		var caption := Label.new()
		caption.text = Localization.text(String(tile[1]))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.add_theme_font_size_override("font_size", 12)
		caption.add_theme_color_override("font_color", UIKit.TEXT_DIM)
		cell.add_child(caption)
		row.add_child(cell)
	return card
