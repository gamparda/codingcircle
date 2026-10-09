extends "res://scripts/ui/SubMenuFrame.gd"
## Personal record screen: one summary card per mode and an aligned campaign table. The frame is scenes/ui/RecordsScreen.tscn.

const TABLE_HEADERS := ["단계", "이름", "별", "도전", "승", "최단", "최고 기지 HP"]
const TABLE_WIDTHS := [56, 150, 96, 70, 70, 100, 140]

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
	column.move_child(summary, 2)

	var heading := Label.new()
	heading.text = Localization.text("캠페인 기록")
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", UIKit.GOLD)
	column.add_child(heading)
	column.move_child(heading, 3)
	var table := GridContainer.new()
	table.name = "CampaignTable"
	table.columns = TABLE_HEADERS.size()
	table.add_theme_constant_override("h_separation", 10)
	table.add_theme_constant_override("v_separation", 3)
	column.add_child(table)
	column.move_child(table, 4)
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
