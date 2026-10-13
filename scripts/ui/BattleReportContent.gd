extends RefCounted
## The same report presentation for confirmed match results and replay checkpoints.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const Report = preload("res://scripts/BattleReport.gd")

static func populate(parent: VBoxContainer, reports: Array, names: Array) -> void:
	if not Report.valid(reports) or names.size() != 2:
		return
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation",28); parent.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",14); columns.add_child(column)
		var data: Dictionary = reports[side]
		var heading := MultiplayerUI.label(("파랑 · " if side == 0 else "빨강 · ") + String(names[side]),22,UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(heading)
		column.add_child(MultiplayerUI.label("사용 자원 %d · 건설 %d
처치 %d · 실제 피해 %d" % [roundi(float(data.resources_spent)),int(data.structures_built),int(data.kills),roundi(float(data.damage))],16,MultiplayerUI.GOLD))
	_add_unit_comparison(parent, reports)
	var report_note := MultiplayerUI.label("피해는 병력·구조물·기지에서 실제로 감소시킨 체력이고, 처치는 병력을 쓰러뜨린 횟수입니다. 해골의 처치·피해는 네크로맨서에 합산합니다. 치유·방어·자원 생산 효과는 이 공격 집계에 포함되지 않습니다.",12,MultiplayerUI.MUTED)
	report_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(report_note)

static func _add_unit_comparison(parent: VBoxContainer, data: Array) -> void:
	parent.add_child(HSeparator.new())
	parent.add_child(MultiplayerUI.label("병력별 기여도", 18, MultiplayerUI.GOLD))
	var controls := HBoxContainer.new()
	controls.name = "BattleReportMetricControls"
	controls.add_theme_constant_override("separation", 12)
	parent.add_child(controls)
	var hint := MultiplayerUI.label("", 13, MultiplayerUI.MUTED)
	hint.name = "BattleReportComparisonHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)
	var rows := VBoxContainer.new()
	rows.name = "BattleReportUnitRows"
	rows.add_theme_constant_override("separation", 12)
	parent.add_child(rows)
	# Freeze the selected report for metric changes; never read later playback or another match.
	var reports: Array = data.duplicate(true)
	var group := ButtonGroup.new()
	for entry in [["damage", "실제 피해"], ["kills", "처치"]]:
		var metric := String(entry[0])
		var button := Button.new()
		button.name = "BattleReportMetric_" + metric
		button.text = String(entry[1])
		UIKit.style_button(button, Color("#3d647d"), false, 16)
		button.pressed.connect(func(): _render_unit_comparison(rows, hint, reports, metric))
		controls.add_child(button)
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(150, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44)
		button.set_pressed_no_signal(metric == "damage")
		button.tooltip_text = "양 진영 합계가 큰 병력부터 정렬합니다. 비중은 각 진영의 전체 집계 기준입니다."
	_render_unit_comparison(rows, hint, reports, "damage")

static func _render_unit_comparison(parent: VBoxContainer, hint: Label, reports: Array, metric: String) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	var rows := Report.comparison_rows(reports, metric)
	var caption := "처치" if metric == "kills" else "실제 피해"
	var largest := 0.0
	for row in rows:
		largest = maxf(largest, maxf(float(row.amounts[0]), float(row.amounts[1])))
	hint.text = "%s · 양 진영 합계 순. 막대는 양쪽 공통 눈금, %%는 자기 진영 전체에서 차지하는 비중입니다." % caption
	if largest <= 0.0:
		hint.text += "\n아직 기록된 %s가 없어 모든 비중을 0%%로 표시합니다." % caption
	if rows.is_empty():
		parent.add_child(MultiplayerUI.label("양 진영 모두 생산·소환·공격 기록이 없습니다.", 14, MultiplayerUI.MUTED))
		return
	for row in rows:
		var card := PanelContainer.new()
		card.name = "BattleReportUnit_" + String(row.kind)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(UIKit.EDGE_SOFT, 8, 0.0), 12, 8))
		parent.add_child(card)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		card.add_child(box)
		box.add_child(MultiplayerUI.label(String(row.name), 16, UIKit.TEXT))
		var sides := HBoxContainer.new()
		sides.add_theme_constant_override("separation", 28)
		box.add_child(sides)
		for side in 2:
			var column := VBoxContainer.new()
			column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			column.size_flags_stretch_ratio = 1.0
			sides.add_child(column)
			var tone := UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
			var amount := float(row.amounts[side])
			var value_text := str(roundi(amount)) if metric == "kills" or amount >= 1.0 or amount == 0.0 else "1 미만"
			var value_label := MultiplayerUI.label("%s · %s %s · %.1f%%" % ["파랑" if side == 0 else "빨강", caption, value_text, float(row.shares[side]) * 100.0], 14, tone)
			value_label.name = "BattleReportValue%d" % side
			value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(value_label)
			# A plain, static bar keeps small shares proportional and needs no per-frame animation.
			var bar := ProgressBar.new()
			bar.name = "BattleReportContribution%d" % side
			bar.custom_minimum_size = Vector2(0, 10)
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bar.show_percentage = false
			bar.max_value = maxf(largest, 1.0)
			bar.step = 0.0
			bar.value = amount
			var track := StyleBoxFlat.new()
			track.bg_color = UIKit.BG_DEEP
			track.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("background", track)
			var fill := StyleBoxFlat.new()
			fill.bg_color = tone
			fill.set_corner_radius_all(3)
			bar.add_theme_stylebox_override("fill", fill)
			column.add_child(bar)
			var production := "%s %d" % ["건설" if row.kind == "turret" else "생산", int(row.purchased[side])]
			if int(row.summoned[side]) > 0: production += " · 해골 소환 %d" % int(row.summoned[side])
			var production_label := MultiplayerUI.label(production, 12, MultiplayerUI.MUTED)
			production_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			column.add_child(production_label)

