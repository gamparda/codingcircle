extends "res://scripts/ui/SubMenuFrame.gd"
## Personal records with campaign and versioned challenge history. Footer actions stay outside the scroll area.

const TABLE_HEADERS := ["단계", "이름", "별", "도전", "승", "최단", "최고 기지 HP"]
const TABLE_WIDTHS := [56, 150, 96, 70, 70, 100, 140]
const ServerStats = preload("res://scripts/ServerStats.gd")
const HISTORY_HEADERS := ["날짜 (UTC)", "콘텐츠 버전", "결과", "최고 점수", "완료 시간"]
const HISTORY_WIDTHS := [170, 0, 70, 115, 115]

func populate(save_data: Dictionary) -> void:
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

	var tabs := HBoxContainer.new()
	tabs.name = "RecordsTabs"
	column.add_child(tabs)
	var filter := OptionButton.new()
	filter.name = "ChallengeHistoryFilter"
	filter.add_item("전체 버전", 0)
	filter.add_item("현재 버전", 1)
	filter.add_item("이전·미상 버전", 2)
	filter.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 40
	filter.visible = false
	column.add_child(filter)
	var scroll := ScrollContainer.new()
	scroll.name = "RecordsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	column.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	var panels := {}
	var buttons := {}
	var group := ButtonGroup.new()
	for entry in [["campaign", "캠페인"], ["daily", "일일 도전"], ["weekly", "주간 도전"]]:
		var page := VBoxContainer.new()
		page.name = "RecordsPage_" + entry[0]
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.visible = entry[0] == "campaign"
		pages.add_child(page)
		panels[entry[0]] = page
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
		buttons[id].pressed.connect(func():
			for key in panels: panels[key].visible = key == id
			filter.visible = id != "campaign"
			scroll.scroll_vertical = 0
		)
	# Keep a read-only snapshot so filtering does not modify best scores or pending submissions.
	var history := {"daily": save_data.daily.duplicate(true), "weekly": save_data.weekly.duplicate(true)}
	var refresh_history := func(_index: int = 0):
		for period in history:
			_populate_history(panels[period], history[period], period, filter.selected)
		scroll.scroll_vertical = 0
	filter.item_selected.connect(refresh_history)
	refresh_history.call()
	_populate_campaign(panels.campaign, save_data)

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

func _populate_history(page: VBoxContainer, history: Dictionary, period: String, filter: int) -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	var hint := Label.new()
	hint.text = "기기에 보관된 최고 기록 · %s · 버전이 다른 점수는 따로 표시합니다." % ("최근 %d주, 주 시작일 기준" % SaveData.WEEKLY_HISTORY if period == "weekly" else "최근 %d일" % SaveData.DAILY_HISTORY)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	page.add_child(hint)
	var table := GridContainer.new()
	table.name = "ChallengeHistoryTable_" + period
	table.columns = HISTORY_HEADERS.size()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("h_separation", 14)
	table.add_theme_constant_override("v_separation", 8)
	page.add_child(table)
	for index in HISTORY_HEADERS.size():
		table.add_child(_history_cell(HISTORY_HEADERS[index], index, UIKit.TEXT_DIM))
	var current := ServerStats.ruleset_id()
	var dates: Array = history.keys()
	dates.sort()
	dates.reverse()
	var count := 0
	for date in dates:
		var record: Dictionary = history[date]
		var versions: Dictionary = record.get("previous", {}).duplicate(true)
		versions[String(record.get("ruleset", "0"))] = record
		var rules: Array = versions.keys()
		rules.sort()
		if rules.has(current):
			rules.erase(current)
			rules.push_front(current)
		for rule in rules:
			if (filter == 1 and rule != current) or (filter == 2 and rule == current): continue
			var item: Dictionary = versions[rule]
			var won := bool(item.get("won", false))
			var status := "버전 미상" if rule == "0" else ("현재" if rule == current else "이전")
			var key := String(date)
			var cells := ["%s-%s-%s" % [key.substr(0, 4), key.substr(4, 2), key.substr(6, 2)],
				"%s · %s" % [status, rule], "성공" if won else "실패", "%d점" % int(item.get("score", 0)), "%.1f초" % float(item.get("seconds", 0.0))]
			for index in cells.size():
				var color := UIKit.GOLD if rule == current else UIKit.TEXT_MUTED
				if index == 2: color = UIKit.SUCCESS if won else UIKit.DANGER
				table.add_child(_history_cell(cells[index], index, color))
			count += 1
	if count == 0:
		var empty := Label.new()
		empty.name = "ChallengeHistoryEmpty_" + period
		empty.text = "저장된 %s 도전 기록이 없습니다." % ("주간" if period == "weekly" else "일일") if history.is_empty() else "선택한 버전의 기록이 없습니다. 다른 버전을 선택해 보세요."
		empty.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		page.add_child(empty)

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
