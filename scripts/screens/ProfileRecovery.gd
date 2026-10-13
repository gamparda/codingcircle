extends RefCounted
## Device-local recovery points, with an explicit preview before replacing progress.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CHALLENGE_PAGE_SIZE := 8

static func _label(text: String, color: Color = UIKit.TEXT_MUTED) -> Label:
	var label := MultiplayerUI.label(text, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func _summary(data: Dictionary) -> String:
	return "%s · 캠페인 %d단계 개방 · 별 %d개\nAI %d판 · 온라인 %d판 · 업적 %d개 · 일일 기록 %d일 · 주간 기록 %d주" % [String(data.nickname), int(data.campaign_unlocked), int(data.stats.total_stars), int(data.stats.ai_matches), int(data.stats.online_completed), data.achievements.size(), data.daily.size(), data.weekly.size()]

static func _deck_names(kinds: Array, units: bool) -> String:
	var structures := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
	var names: PackedStringArray = []
	for kind in kinds:
		names.append(String(BattleModel.UNIT_NAMES.get(kind, kind) if units else structures.get(kind, kind)))
	return " / ".join(names)

static func _challenge_versions(history: Dictionary, date: String) -> Dictionary:
	if not history.has(date): return {}
	var record: Dictionary = history[date]
	var versions: Dictionary = record.get("previous", {}).duplicate()
	# Main/previous placement is storage bookkeeping, not a change of the result.
	versions[String(record.ruleset)] = record
	return versions

static func _challenge_value(record: Dictionary) -> String:
	if record.is_empty(): return "기록 없음"
	return "%s · %d점 · %s초" % ["성공" if bool(record.won) else "실패", int(record.score), str(record.seconds)]

static func _challenge_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var rows: Array = []
	var summaries: PackedStringArray = []
	var lost := 0
	var lowered := 0
	for period in ["daily", "weekly"]:
		var before_history: Dictionary = live[period]
		var after_history: Dictionary = restored[period]
		var dates: Array = before_history.keys()
		for date in after_history:
			if not dates.has(date): dates.append(date)
		dates.sort()
		dates.reverse()
		var added := 0
		var removed := 0
		var changed := 0
		var unchanged := 0
		for date in dates:
			var before_versions := _challenge_versions(before_history, String(date))
			var after_versions := _challenge_versions(after_history, String(date))
			var rules: Array = before_versions.keys()
			for rule in after_versions:
				if not rules.has(rule): rules.append(rule)
			rules.sort()
			for rule in rules:
				var before: Dictionary = before_versions.get(rule, {})
				var after: Dictionary = after_versions.get(rule, {})
				# Ignore nested history and compare only the result restored for this date/version.
				if not before.is_empty() and not after.is_empty() and before.won == after.won and int(before.score) == int(after.score) and float(before.seconds) == float(after.seconds):
					unchanged += 1
					continue
				var risk := false
				var kind := "변경"
				if before.is_empty():
					kind = "추가"
					added += 1
				elif after.is_empty():
					kind = "사라짐"
					risk = true
					removed += 1
					lost += 1
				else:
					changed += 1
					# The best successful score uses time only to break a tied score.
					risk = bool(before.won) and (not bool(after.won) or int(after.score) < int(before.score) or (int(after.score) == int(before.score) and float(after.seconds) > float(before.seconds)))
					if risk:
						kind = "낮아짐"
						lowered += 1
				var day := String(date)
				var date_label := "%s-%s-%s" % [day.substr(0, 4), day.substr(4, 2), day.substr(6, 2)]
				var period_label := "일일" if period == "daily" else "주간 (주 시작일)"
				var version_label := "버전 미상" if rule == "0" else String(rule)
				var text := "%s · %s · %s · %s\n현재: %s\n사본: %s" % [period_label, date_label, version_label, kind, _challenge_value(before), _challenge_value(after)]
				rows.append({"text": text, "search": (text + " " + day + " " + String(rule)).to_lower(), "kind": kind, "risk": risk})
		var title := "일일" if period == "daily" else "주간"
		summaries.append("%s: 추가 %d개 · 변경 %d개 · 사라짐 %d개 · 동일 %d개" % [title, added, changed, removed, unchanged])
	var warning := ""
	if lost > 0 or lowered > 0:
		warning = "도전 기록 %d개가 사라지고 성공 기록 %d개가 실패·낮은 점수·동점의 느린 시간으로 바뀝니다. 다른 날짜·버전의 증가로 상쇄하지 않았습니다." % [lost, lowered]
	return {"rows": rows, "summary": "\n".join(summaries), "warning": warning}

static func _comparison(current: Dictionary, candidate: Dictionary) -> Dictionary:
	# Compare the normalized values restore_backup actually applies, without touching either profile.
	var live := SaveData.sanitize(current)
	var restored := SaveData.sanitize(candidate)
	var campaign: PackedStringArray = []
	var decks: PackedStringArray = []
	var warnings: PackedStringArray = []
	var lost_clears := 0
	var lost_stars := 0
	for index in live.campaign_records.size():
		var before: Dictionary = live.campaign_records[index]
		var after: Dictionary = restored.campaign_records[index]
		var changes: PackedStringArray = []
		if bool(before.cleared) != bool(after.cleared):
			changes.append("클리어 %s → %s" % ["완료" if before.cleared else "미완료", "완료" if after.cleared else "미완료"])
			if before.cleared: lost_clears += 1
		if int(before.best_stars) != int(after.best_stars):
			changes.append("별 %d → %d" % [int(before.best_stars), int(after.best_stars)])
			lost_stars += maxi(0, int(before.best_stars) - int(after.best_stars))
		if float(before.fastest_win) != float(after.fastest_win):
			changes.append("최단 승리 %s → %s" % [_win_time(before), _win_time(after)])
		if float(before.best_base_hp) != float(after.best_base_hp):
			changes.append("최고 기지 체력 %s → %s" % [str(before.best_base_hp), str(after.best_base_hp)])
		if int(before.attempts) != int(after.attempts) or int(before.wins) != int(after.wins):
			changes.append("시도 %d → %d · 승리 %d → %d" % [int(before.attempts), int(after.attempts), int(before.wins), int(after.wins)])
		if not changes.is_empty():
			campaign.append("%d단계 · %s\n%s" % [index + 1, ServerAI.stage_name(index + 1), "\n".join(changes)])
	for index in live.deck_presets.size():
		var before: Dictionary = live.deck_presets[index]
		var after: Dictionary = restored.deck_presets[index]
		var changes: PackedStringArray = []
		if String(before.name) != String(after.name):
			changes.append("이름: %s → %s" % [String(before.name), String(after.name)])
		# Array order is meaningful: it controls the battle buttons and keyboard slots.
		if before.units != after.units:
			changes.append("병력: %s → %s" % [_deck_names(before.units, true), _deck_names(after.units, true)])
		if before.structures != after.structures:
			changes.append("구조물: %s → %s" % [_deck_names(before.structures, false), _deck_names(after.structures, false)])
		if not changes.is_empty():
			decks.append("덱 슬롯 %d\n%s" % [index + 1, "\n".join(changes)])
	var summary := "변경: 캠페인 기록 %d단계 · 덱 구성 %d개\n개방 단계 %d → %d · 총 별 %d → %d" % [campaign.size(), decks.size(), int(live.campaign_unlocked), int(restored.campaign_unlocked), int(live.stats.total_stars), int(restored.stats.total_stars)]
	if int(restored.campaign_unlocked) < int(live.campaign_unlocked):
		warnings.append("개방 단계가 줄어 일부 캠페인이 다시 잠깁니다.")
	if lost_clears > 0 or lost_stars > 0:
		warnings.append("현재 기록 중 클리어 %d단계·별 %d개가 사본의 낮은 기록으로 바뀝니다. 다른 단계의 증가와 별도로 계산했습니다." % [lost_clears, lost_stars])
	var before_growth := SaveData.campaign_growth_level(live)
	var after_growth := SaveData.campaign_growth_level(restored)
	if before_growth != after_growth:
		var before_bonus := BattleModel.campaign_bonuses(before_growth)
		var after_bonus := BattleModel.campaign_bonuses(after_growth)
		summary += "\n성장 보상 %d → %d단계 · 병력 강화 +%d%% → +%d%%\n자원 수입 %s → %s/초 · 보유 한도 %d → %d · 시작 자원 %d → %d" % [before_growth, after_growth, roundi((float(before_bonus.stat_scale) - 1.0) * 100), roundi((float(after_bonus.stat_scale) - 1.0) * 100), str(before_bonus.income), str(after_bonus.income), int(before_bonus.capacity), int(after_bonus.capacity), int(before_bonus.starting_resources), int(after_bonus.starting_resources)]
	if int(live.last_deck) != int(restored.last_deck):
		summary += "\n최근 선택 덱: 슬롯 %d → 슬롯 %d" % [int(live.last_deck) + 1, int(restored.last_deck) + 1]
	var challenges := _challenge_comparison(live, restored)
	if not String(challenges.warning).is_empty(): warnings.append(String(challenges.warning))
	return {"summary": summary, "warning": "\n".join(warnings),
		"campaign": "\n\n".join(campaign) if not campaign.is_empty() else "단계별 기록 변경 없음",
		"decks": "\n\n".join(decks) if not decks.is_empty() else "세 덱의 이름·병력·구조물·배치 순서 변경 없음",
		"challenges": challenges}

static func _win_time(record: Dictionary) -> String:
	return str(record.fastest_win) + "초" if float(record.fastest_win) > 0.0 else "미기록 또는 0초"

static func _fill_comparison(parent: VBoxContainer, current: Dictionary, candidate: Dictionary) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	var comparison := _comparison(current, candidate)
	parent.add_child(_label("복구하면 바뀌는 내용 · 현재 → 사본", UIKit.GOLD))
	var summary := _label(String(comparison.summary), UIKit.TEXT)
	summary.name = "ProfileComparisonSummary"
	parent.add_child(summary)
	if not String(comparison.warning).is_empty():
		var warning := _label(String(comparison.warning), UIKit.DANGER)
		warning.name = "ProfileComparisonWarning"
		parent.add_child(warning)
	parent.add_child(_label("캠페인 · 변경된 단계", UIKit.GOLD))
	var campaign := _label(String(comparison.campaign), UIKit.TEXT)
	campaign.name = "ProfileCampaignChanges"
	parent.add_child(campaign)
	parent.add_child(_label("덱 · 슬롯별 변경 (병력·구조물은 전투 버튼 순서)", UIKit.GOLD))
	var decks := _label(String(comparison.decks), UIKit.TEXT)
	decks.name = "ProfileDeckChanges"
	parent.add_child(decks)
	_add_challenge_comparison(parent, comparison.challenges)
	parent.add_child(_label("기록을 합치거나 더 높은 기록을 고르는 복구가 아닙니다. 전적·업적·도전 기록을 포함한 진행도 전체가 사본으로 바뀝니다. 현재 설정·익명 ID·전송 대기 기록은 유지합니다."))

static func _add_challenge_comparison(parent: VBoxContainer, comparison: Dictionary) -> void:
	parent.add_child(_label("도전 · 날짜·버전별 변경", UIKit.GOLD))
	var summary := _label(String(comparison.summary), UIKit.TEXT)
	summary.name = "ProfileChallengeComparisonSummary"
	parent.add_child(summary)
	parent.add_child(_label("기기에 보관된 날짜·버전별 최고 기록을 비교합니다. 주간은 월요일 날짜이며 버전 미상은 동일한 규칙의 기록이라고 확정할 수 없습니다. 실패 전투의 시간 변화는 성공 기록 하락으로 세지 않습니다."))
	var rows: Array = comparison.rows
	if rows.is_empty():
		parent.add_child(_label("일일·주간 도전 기록 변경 없음", UIKit.TEXT))
		return
	var filters := HFlowContainer.new()
	filters.name = "ProfileChallengeComparisonFilters"
	filters.add_theme_constant_override("h_separation", 10)
	filters.add_theme_constant_override("v_separation", 10)
	parent.add_child(filters)
	var search := LineEdit.new()
	search.name = "ProfileChallengeComparisonSearch"
	search.placeholder_text = "도전 날짜 · 버전 검색"
	search.tooltip_text = "2026-10 또는 20261013, 버전, 일일·주간, 성공·실패로 변경된 기록을 검색합니다. 공백으로 나눈 검색어를 모두 포함한 기록을 표시합니다."
	search.max_length = 120
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(280, UIKit.TOUCH_MIN_HEIGHT)
	filters.add_child(search)
	var filter := OptionButton.new()
	filter.name = "ProfileChallengeComparisonFilter"
	filter.custom_minimum_size = Vector2(190, UIKit.TOUCH_MIN_HEIGHT)
	for title in ["전체 변경", "사라짐·낮아짐", "추가만", "변경만"]: filter.add_item(title)
	filters.add_child(filter)
	var count := _label("")
	count.name = "ProfileChallengeComparisonCount"
	parent.add_child(count)
	var details := _label("", UIKit.TEXT)
	details.name = "ProfileChallengeChanges"
	parent.add_child(details)
	var pages := HFlowContainer.new()
	pages.add_theme_constant_override("h_separation", 10)
	pages.add_theme_constant_override("v_separation", 10)
	parent.add_child(pages)
	var previous := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 15)
	previous.name = "ProfileChallengePreviousPage"
	previous.text = "이전 기록"
	previous.custom_minimum_size = Vector2(140, UIKit.TOUCH_MIN_HEIGHT)
	pages.add_child(previous)
	var next := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 15)
	next.name = "ProfileChallengeNextPage"
	next.text = "다음 기록"
	next.custom_minimum_size = Vector2(140, UIKit.TOUCH_MIN_HEIGHT)
	pages.add_child(next)
	var state := {"page": 0}
	var refresh := func():
		var terms := search.text.strip_edges().to_lower().split(" ", false)
		var selected: Array = []
		for row in rows:
			if filter.selected == 1 and not bool(row.risk): continue
			if filter.selected == 2 and row.kind != "추가": continue
			if filter.selected == 3 and row.kind not in ["변경", "낮아짐"]: continue
			var matches := true
			for term in terms:
				if not String(row.search).contains(term):
					matches = false
					break
			if matches: selected.append(row)
		var total_pages := maxi(1, ceili(float(selected.size()) / CHALLENGE_PAGE_SIZE))
		state.page = clampi(int(state.page), 0, total_pages - 1)
		var lines: PackedStringArray = []
		for row in selected.slice(int(state.page) * CHALLENGE_PAGE_SIZE, (int(state.page) + 1) * CHALLENGE_PAGE_SIZE):
			lines.append(String(row.text))
		details.text = "\n\n".join(lines) if not lines.is_empty() else "조건에 맞는 변경 기록이 없습니다. 검색어를 지우거나 전체 변경을 선택하세요."
		count.text = "표시 조건 %d개 / 전체 변경 %d개 · %d / %d페이지" % [selected.size(), rows.size(), int(state.page) + 1, total_pages]
		previous.disabled = int(state.page) == 0
		next.disabled = int(state.page) >= total_pages - 1
	search.text_changed.connect(func(_value: String): state.page = 0; refresh.call())
	filter.item_selected.connect(func(_index: int): state.page = 0; refresh.call())
	previous.pressed.connect(func(): state.page = int(state.page) - 1; refresh.call())
	next.pressed.connect(func(): state.page = int(state.page) + 1; refresh.call())
	refresh.call()

static func _add_comparison(parent: Node, current: Dictionary, candidate: Dictionary) -> void:
	var comparison := VBoxContainer.new()
	comparison.name = "ProfileRecoveryComparison"
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_theme_constant_override("separation", 10)
	parent.add_child(comparison)
	_fill_comparison(comparison, current, candidate)

static func _stamp(seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(seconds).replace("T", " ") + " UTC"

static func _button(main, parent: Node, text: String, name: String, callback: Callable, primary: bool = false) -> Button:
	var button := MultiplayerUI.button(main, parent, text, name, callback, primary)
	button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	return button

static func _copy_text(status: Label, scroll: ScrollContainer, text: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	elif text.to_utf8_buffer().size() > SaveData.MAX_BACKUP_TRANSFER_BYTES:
		status.text = "사본이 너무 커서 클립보드로 옮길 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	else:
		DisplayServer.clipboard_set(text)
		if DisplayServer.clipboard_get().replace("\r\n", "\n") == text.replace("\r\n", "\n"):
			status.text = "진행도 JSON을 복사했습니다. 메모장 등에 붙여넣어 .json 파일로 저장하세요. 게임 삭제·전체 초기화 전에 게임 밖에 보관해야 합니다."
		else:
			status.text = "클립보드 복사를 확인하지 못했습니다. 다시 시도하거나 보관 폴더에서 사본을 복사하세요."
	scroll.ensure_control_visible.call_deferred(status)

static func _comparison_controls(parent: Node, controls: Array[Control]) -> void:
	for child in parent.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			controls.append(child)
		_comparison_controls(child, controls)

static func _dialog_navigation(scroll: ScrollContainer, confirm: Button, cancel: Button, close: Callable) -> void:
	scroll.focus_mode = Control.FOCUS_ALL
	var controls: Array[Control] = [scroll]
	_comparison_controls(scroll, controls)
	controls.append(confirm)
	controls.append(cancel)
	for index in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		# Preserve editing keys and the OptionButton's own arrow-key behavior.
		if control == scroll or (control is Button and not control is OptionButton):
			control.focus_neighbor_top = previous
			control.focus_neighbor_left = previous
			control.focus_neighbor_bottom = next
			control.focus_neighbor_right = next
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	scroll.gui_input.connect(func(event: InputEvent):
		if not event is InputEventKey or not event.pressed:
			return
		match event.keycode:
			KEY_UP: scroll.scroll_vertical -= 40
			KEY_DOWN: scroll.scroll_vertical += 40
			KEY_PAGEUP: scroll.scroll_vertical -= maxi(80, roundi(scroll.size.y * 0.85))
			KEY_PAGEDOWN: scroll.scroll_vertical += maxi(80, roundi(scroll.size.y * 0.85))
			KEY_HOME: scroll.scroll_vertical = 0
			KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			_: return
		scroll.accept_event())
	scroll.grab_focus.call_deferred()

static func _filtered_entries(source: Array, query: String, order: int) -> Array:
	var entries: Array = []
	var terms := query.to_lower().replace("\t", " ").replace("\n", " ").split(" ", false)
	for entry in source:
		var searchable := (_stamp(int(entry.modified)) + " " + String(entry.path).get_file() + " " + _summary(entry.data)).to_lower()
		var matches := true
		for term in terms:
			if not searchable.contains(term):
				matches = false
				break
		if matches:
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if order == 1 and int(a.modified) != int(b.modified):
			return int(a.modified) < int(b.modified)
		if order == 2 and int(a.data.stats.total_stars) != int(b.data.stats.total_stars):
			return int(a.data.stats.total_stars) > int(b.data.stats.total_stars)
		if order == 3 and int(a.data.campaign_unlocked) != int(b.data.campaign_unlocked):
			return int(a.data.campaign_unlocked) > int(b.data.campaign_unlocked)
		return int(a.modified) > int(b.modified) if int(a.modified) != int(b.modified) else String(a.path) < String(b.path))
	return entries

static func show(main, message: String = "", selected_path: String = "", browser_state: Dictionary = {}) -> void:
	# Screen-local state survives refresh/import/cleanup, without changing the save.
	var state := {"query": String(browser_state.get("query", "")), "order": clampi(int(browser_state.get("order", 0)), 0, 3), "selected_path": selected_path if not selected_path.is_empty() else String(browser_state.get("selected_path", ""))}
	var outer: VBoxContainer = main._submenu("진행도 보관·복구", "현재 진행도를 보관하거나, 읽을 수 있는 사본을 골라 복구합니다.")
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRecoveryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	column.add_child(_label("현재 진행도", UIKit.GOLD))
	column.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	column.add_child(_label("현재 진행도 사본은 전적·덱·저장된 설정을 보관합니다. 설정 화면에서 저장하지 않은 편집은 포함되지 않습니다."))
	var backup: Button = _button(main, column, "현재 진행도 사본 보관", "CreateProfileBackup", func():
		var path := SaveData.create_backup(main.save_data)
		if not path.is_empty(): state.query = ""
		show(main, "현재 진행도 사본을 보관했습니다." if not path.is_empty() else "사본을 보관하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요.", path, state))
	backup.tooltip_text = ProjectSettings.globalize_path(SaveData.recovery_dir())
	column.add_child(HSeparator.new())
	var candidates := SaveData.recovery_candidates()
	var entries: Array = []
	column.add_child(_label("복구할 사본 · 검색·정렬", UIKit.GOLD))
	var filters := HBoxContainer.new()
	filters.name = "ProfileRecoveryFilters"
	filters.add_theme_constant_override("separation", 10)
	column.add_child(filters)
	var search := LineEdit.new()
	search.name = "ProfileRecoverySearch"
	search.placeholder_text = "닉네임 · 보관 날짜 · 파일명 검색"
	search.tooltip_text = "UTC 보관 날짜(예: 2026-10)·닉네임·파일명·진행도 요약을 검색합니다. 공백으로 나눈 검색어를 모두 포함한 사본을 표시합니다."
	search.max_length = 120
	search.text = String(state.query)
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(search)
	var order := OptionButton.new()
	order.name = "ProfileRecoveryOrder"
	order.custom_minimum_size = Vector2(180, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44)
	for title in ["최근 보관순", "오래된 보관순", "별 많은 순", "캠페인 진행순"]:
		order.add_item(title)
	order.select(int(state.order))
	filters.add_child(order)
	var reset: Button = main._styled_button("초기화", UIKit.ACCENT, false)
	reset.name = "ResetProfileRecoveryFilters"
	reset.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(reset)
	var count := _label("")
	count.name = "ProfileRecoveryCount"
	column.add_child(count)
	var choice := OptionButton.new()
	choice.name = "ProfileRecoveryChoice"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	choice.fit_to_longest_item = false
	column.add_child(choice)
	var preview := _label("", UIKit.TEXT)
	preview.name = "ProfileRecoveryPreview"
	column.add_child(preview)
	var comparison := VBoxContainer.new()
	comparison.name = "ProfileRecoveryComparison"
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_theme_constant_override("separation", 10)
	column.add_child(comparison)
	column.add_child(_label("복구는 전적·진행도·덱·닉네임을 사본으로 되돌립니다. 현재 진행도와 디스크 원본을 먼저 별도 보관합니다.\n현재 설정, 익명 ID, 전송 대기 기록은 유지하며 과거 결과를 다시 보내지 않습니다. 리플레이와 서버 기록은 그대로 남습니다."))
	if int(candidates.excluded) > 0:
		column.add_child(_label("손상되었거나 지원하지 않는 사본 %d개는 목록에서 제외했습니다. 원본 파일은 복구 폴더에 남아 있습니다." % int(candidates.excluded)))
	var status := _label(message, UIKit.GOLD)
	status.name = "ProfileRecoveryStatus"
	if not String(candidates.error).is_empty():
		status.text = (message + "\n" if not message.is_empty() else "") + String(candidates.error)
	column.add_child(status)
	column.add_child(HSeparator.new())
	column.add_child(_label("게임 밖에 사본 보관·다른 기기에서 가져오기", UIKit.GOLD))
	column.add_child(_label("내보내기는 진행도를 JSON으로 복사합니다. 익명 ID와 전송 대기 기록은 제외합니다.\n가져오기는 내용을 확인해 사본만 보관합니다. 현재 진행도를 바꾸려면 아래의 복구 확인을 별도로 눌러야 합니다."))
	var transfer := HFlowContainer.new()
	transfer.name = "ProfileBackupTransfer"
	transfer.add_theme_constant_override("h_separation", 10)
	transfer.add_theme_constant_override("v_separation", 10)
	column.add_child(transfer)
	_button(main, transfer, "현재 진행도 내보내기", "ExportCurrentProfile", func():
		_copy_text(status, scroll, SaveData.to_backup_text(main.save_data)))
	var export_selected := _button(main, transfer, "선택한 사본 내보내기", "ExportSelectedProfile", func():
		if choice.selected < 0 or choice.selected >= entries.size():
			return
		var entry: Dictionary = entries[choice.selected]
		var result := SaveData.backup_export(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		_copy_text(status, scroll, String(result.text)))
	_button(main, transfer, "클립보드 사본 가져오기", "ImportProfileBackup", func():
		if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. JSON 사본을 보관 폴더에 복사한 뒤 새로고침하세요."
			scroll.ensure_control_visible.call_deferred(status)
			return
		_preview_import(main, DisplayServer.clipboard_get(), status, scroll, state))
	var delete_selected := _button(main, transfer, "선택한 사본 삭제 확인", "PreviewProfileBackupDelete", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm_delete(main, entries[choice.selected], state))
	delete_selected.tooltip_text = "내용과 파일명을 확인한 뒤 선택한 사본 하나만 삭제합니다. 마지막으로 읽을 수 있는 사본은 남깁니다."
	var folder := _label("보관 위치: " + ProjectSettings.globalize_path(SaveData.recovery_dir()))
	folder.add_theme_font_size_override("font_size", 13)
	column.add_child(folder)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_button(main, column, "보관 폴더 열기", "OpenProfileRecoveryFolder", func():
			var directory := SaveData.recovery_dir()
			if DirAccess.make_dir_recursive_absolute(directory) != OK or OS.shell_open(ProjectSettings.globalize_path(directory)) != OK:
				status.text = "보관 폴더를 열지 못했습니다. 표시된 보관 위치와 파일 권한을 확인하세요."
				scroll.ensure_control_visible.call_deferred(status))
	var footer := HBoxContainer.new()
	footer.name = "ProfileRecoveryFooter"
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	var restore: Button = _button(main, footer, "선택한 사본 복구 확인", "PreviewProfileRestore", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm(main, entries[choice.selected], state), true)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(main, footer, "새로고침", "RefreshProfileRecovery", func():
		show(main, "", "", state))
	_button(main, footer, "설정으로", "ProfileRecoveryBack", main._build_settings_screen)
	var update_preview := func(index: int):
		var valid := index >= 0 and index < entries.size()
		restore.disabled = not valid
		export_selected.disabled = not valid
		delete_selected.disabled = not valid or candidates.entries.size() < 2
		comparison.visible = valid
		preview.tooltip_text = ""
		if not valid:
			preview.text = "검색 조건에 맞는 사본이 없습니다. 검색어를 바꾸거나 초기화하세요." if not candidates.entries.is_empty() else "현재 진행도를 사본으로 보관하거나, 아래에서 외부 사본을 가져오세요. 손상된 원본은 수정하지 않고 보관합니다."
			if not entries.is_empty():
				preview.text = "선택했던 사본이 검색 결과에 없거나 더 이상 존재하지 않습니다. 복구·내보내기·삭제할 사본을 목록에서 직접 선택하세요."
			return
		state.selected_path = String(entries[index].path)
		preview.text = _stamp(int(entries[index].modified)) + "\n" + _summary(entries[index].data) + "\n파일: " + String(entries[index].path).get_file()
		if int(entries[index].get("excluded", 0)) > 0:
			preview.text += "\n잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entries[index].excluded)
		preview.tooltip_text = ProjectSettings.globalize_path(String(entries[index].path))
		_fill_comparison(comparison, main.save_data, entries[index].data)
	var rebuild := func():
		entries.clear()
		entries.append_array(_filtered_entries(candidates.entries, String(state.query), int(state.order)))
		choice.clear()
		var selected := -1
		for index in entries.size():
			var entry: Dictionary = entries[index]
			choice.add_item("%s · %s · 별 %d개 · 캠페인 %d단계" % [_stamp(int(entry.modified)), String(entry.data.nickname), int(entry.data.stats.total_stars), int(entry.data.campaign_unlocked)])
			choice.set_item_tooltip(index, ProjectSettings.globalize_path(String(entry.path)))
			if String(entry.path) == String(state.selected_path): selected = index
		if selected < 0 and String(state.selected_path).is_empty() and not entries.is_empty(): selected = 0
		choice.select(selected)
		choice.disabled = entries.is_empty()
		if selected < 0:
			choice.text = "복구할 사본을 선택하세요" if not entries.is_empty() else "검색 결과가 없습니다" if not candidates.entries.is_empty() else "복구할 수 있는 사본이 없습니다"
		count.text = "표시 %d개 / 읽을 수 있는 사본 %d개 · 마지막 사본은 삭제하지 않습니다." % [entries.size(), candidates.entries.size()]
		reset.disabled = String(state.query).is_empty() and int(state.order) == 0
		update_preview.call(selected)
	choice.item_selected.connect(update_preview)
	search.text_changed.connect(func(value: String): state.query = value; rebuild.call())
	order.item_selected.connect(func(index: int): state.order = index; rebuild.call())
	reset.pressed.connect(func():
		state.query = ""; state.order = 0
		search.set_text(""); order.select(0)
		rebuild.call(); search.grab_focus())
	rebuild.call()
	if not message.is_empty():
		scroll.ensure_control_visible.call_deferred(status)

static func _preview_import(main, text: String, screen_status: Label, screen_scroll: ScrollContainer, browser_state: Dictionary = {}) -> void:
	var preview := SaveData.preview_backup_text(text)
	if not preview.ok:
		screen_status.text = String(preview.error)
		screen_scroll.ensure_control_visible.call_deferred(screen_status)
		return
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 가져오기 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileImportConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("가져올 사본", UIKit.GOLD))
	details.add_child(_label(_summary(preview.data), UIKit.TEXT))
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	_add_comparison(details, main.save_data, preview.data)
	details.add_child(_label("이 단계에서는 사본만 보관합니다. 보관 후 선택한 사본 복구 확인을 눌러야 진행도를 되돌립니다.\n복구할 때도 현재 설정·익명 ID·전송 대기 기록을 유지합니다. 가져온 사본의 결과는 다시 보내지 않습니다."))
	if int(preview.excluded) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 가져온 JSON 원본은 그대로 보관합니다." % int(preview.excluded), UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileImportStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "사본만 보관", "ConfirmProfileImport", func():
		# Use the text that was previewed, even if the clipboard changed meanwhile.
		var result := SaveData.import_backup_text(text)
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		browser_state.query = ""
		show(main, "가져온 사본을 보관하고 선택했습니다. 현재 진행도는 그대로입니다. 되돌리려면 선택한 사본 복구 확인을 누르세요.", String(result.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileImport", close)
	_dialog_navigation(scroll, confirm, cancel, close)

static func _confirm_delete(main, entry: Dictionary, browser_state: Dictionary) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 삭제 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileBackupDeleteScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	details.add_child(_label("삭제할 파일: " + ProjectSettings.globalize_path(String(entry.path))))
	details.add_child(_label("선택한 사본 파일 하나를 영구 삭제합니다. 이 파일로는 더 이상 복구할 수 없습니다. 필요하면 취소하고 먼저 내보내세요.\n현재 진행도·다른 사본·리플레이·서버 기록은 유지합니다. 마지막으로 읽을 수 있는 사본은 삭제할 수 없습니다.", UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileBackupDeleteStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "이 사본만 영구 삭제", "ConfirmProfileBackupDelete", func():
		var result := SaveData.delete_backup(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		# Keep the missing path so another file is never silently selected after deletion.
		show(main, "선택한 사본 하나를 삭제했습니다. 현재 진행도는 그대로입니다. 다른 사본을 사용하려면 목록에서 직접 선택하세요.", "", browser_state))
	var cancel := _button(main, dialog, "취소", "CancelProfileBackupDelete", close)
	_dialog_navigation(scroll, confirm, cancel, close)
	# Destructive confirmation starts on cancel, including keyboard users.
	cancel.grab_focus.call_deferred()

static func _confirm(main, entry: Dictionary, browser_state: Dictionary = {}) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 복구 확인", Rect2(230, 120, 820, 470))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRestoreConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	details.add_child(_label("이 사본으로 진행도를 되돌립니다.", UIKit.GOLD))
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	_add_comparison(details, main.save_data, entry.data)
	if int(entry.get("excluded", 0)) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entry.excluded), UIKit.DANGER))
	details.add_child(_label("현재 진행도와 원본을 보관한 뒤 복구합니다. 보관이나 저장에 실패하면 현재 진행도를 유지합니다.\n현재 설정과 전송 대기 기록을 유지하며, 이미 전송한 과거 결과는 다시 보내지 않습니다."))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileRestoreStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "보관 후 복구", "ConfirmProfileRestore", func():
		var result := SaveData.restore_backup(main.save_data, String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		main.save_data = result.data
		main.profile_load_warning = ""
		main.profile_load_details = ""
		main.battle_preset = {}
		main.network.client_nickname = String(main.save_data.nickname)
		main._profile_saved()
		show(main, "진행도를 복구했습니다. 복구 전 진행도도 사본 목록에 보관했습니다.", String(entry.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileRestore", close)
	_dialog_navigation(scroll, confirm, cancel, close)
