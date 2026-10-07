extends VBoxContainer
## Deck simulator dialog content: pick a stage and match count, watch the progress bar, read the verdict.

const DeckSimulator = preload("res://scripts/DeckSimulator.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const Localization = preload("res://scripts/Localization.gd")
const MATCH_COUNTS := [6, 12, 24]
const SLICE_MSEC := 12

var run = null
var units: Array = []
var structures: Array = []
var stage_picker: OptionButton
var count_picker: OptionButton
var start_button: Button
var progress_bar: HpBar
var status: Label
var rate_label: Label
var rate_bar: HpBar
var chips: HBoxContainer
var tips_box: VBoxContainer

func setup(deck_units: Array, deck_structures: Array, default_stage: int = 3) -> void:
	units = deck_units.duplicate()
	structures = deck_structures.duplicate()
	name = "DeckSimulatorPanel"
	add_theme_constant_override("separation", 10)
	var names: Array = []
	for kind in units:
		names.append(String(BattleModel.UNIT_NAMES.get(kind, kind)))
	var deck_label := Label.new()
	deck_label.text = Localization.text("시험할 덱: %s") % " · ".join(names)
	deck_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	add_child(deck_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 10)
	add_child(controls)
	var stage_caption := Label.new()
	stage_caption.text = Localization.text("상대 단계")
	controls.add_child(stage_caption)
	stage_picker = OptionButton.new()
	stage_picker.name = "SimStagePicker"
	for stage in range(ServerAI.MIN_STAGE, ServerAI.MAX_STAGE + 1):
		stage_picker.add_item("%02d  %s" % [stage, ServerAI.stage_name(stage)], stage)
	stage_picker.select(clampi(default_stage, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE) - 1)
	stage_picker.custom_minimum_size.x = 190
	controls.add_child(stage_picker)
	var count_caption := Label.new()
	count_caption.text = Localization.text("판 수")
	controls.add_child(count_caption)
	count_picker = OptionButton.new()
	count_picker.name = "SimCountPicker"
	for count in MATCH_COUNTS:
		count_picker.add_item(Localization.text("%d판") % count, count)
	controls.add_child(count_picker)
	start_button = Button.new()
	start_button.name = "SimStartButton"
	start_button.text = Localization.text("시뮬레이션 시작")
	UIKit.style_button(start_button, UIKit.ACCENT, true, 16)
	start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	start_button.pressed.connect(start)
	controls.add_child(start_button)
	progress_bar = HpBar.new()
	progress_bar.name = "SimProgress"
	progress_bar.color = UIKit.TEAL
	progress_bar.pulse_below = 0.0
	progress_bar.show_ticks = false
	progress_bar.custom_minimum_size = Vector2(0, 14)
	progress_bar.max_value = 1.0
	add_child(progress_bar)
	status = Label.new()
	status.name = "SimStatus"
	status.text = Localization.text("선택한 단계의 AI와 자동으로 대전시켜 덱의 강점과 약점을 확인합니다.")
	status.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	rate_label = Label.new()
	rate_label.name = "SimWinRate"
	rate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.display(rate_label, 54, UIKit.GOLD)
	add_child(rate_label)
	rate_bar = HpBar.new()
	rate_bar.color = UIKit.SUCCESS
	rate_bar.pulse_below = 0.0
	rate_bar.show_ticks = true
	rate_bar.custom_minimum_size = Vector2(0, 16)
	rate_bar.max_value = 1.0
	add_child(rate_bar)
	chips = HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 10)
	add_child(chips)
	tips_box = VBoxContainer.new()
	tips_box.name = "SimTips"
	tips_box.add_theme_constant_override("separation", 6)
	add_child(tips_box)
	set_process(false)

func start() -> void:
	if not DeckSimulator.valid_selection(units, structures):
		status.text = Localization.text("유닛과 구조물을 각각 정확히 3종 선택해야 합니다.")
		return
	var stage := stage_picker.get_selected_id()
	var count := count_picker.get_selected_id()
	run = DeckSimulator.start(units, structures, stage, count)
	start_button.disabled = true
	stage_picker.disabled = true
	count_picker.disabled = true
	rate_label.text = ""
	rate_bar.value = 0.0
	for child in chips.get_children() + tips_box.get_children():
		child.queue_free()
	set_process(true)

func _process(_delta: float) -> void:
	if run == null:
		return
	var done: bool = run.step(SLICE_MSEC)
	progress_bar.value = run.progress()
	status.text = Localization.text("시뮬레이션 중...  %d / %d판") % [mini(run.results.size() + (0 if done else 1), run.total), run.total]
	if done:
		_show_result()

func _show_result() -> void:
	set_process(false)
	var summary: Dictionary = run.summary()
	run = null
	start_button.disabled = false
	stage_picker.disabled = false
	count_picker.disabled = false
	progress_bar.value = 1.0
	status.text = Localization.text("%02d단계 · %d판 결과") % [int(summary.stage), int(summary.matches)]
	rate_label.text = "%d%%" % roundi(float(summary.win_rate) * 100.0)
	var tone := UIKit.SUCCESS if float(summary.win_rate) >= 0.6 else (UIKit.GOLD if float(summary.win_rate) >= 0.35 else UIKit.DANGER)
	rate_label.add_theme_color_override("font_color", tone.lightened(0.2))
	rate_bar.color = tone
	rate_bar.value = float(summary.win_rate)
	for entry in [["승", str(summary.wins)], ["패", str(summary.losses)], ["무·미결", str(int(summary.draws) + int(summary.timeouts))],
			["평균 시간", "%d:%02d" % [int(summary.average_seconds) / 60, int(summary.average_seconds) % 60]]]:
		chips.add_child(_chip(Localization.text(String(entry[0])), String(entry[1]), tone))
	for tip in summary.tips:
		var line := Label.new()
		line.text = "▸ " + Localization.text(String(tip))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_color_override("font_color", UIKit.TEXT)
		tips_box.add_child(line)

func _chip(caption: String, value: String, tone: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(tone.r, tone.g, tone.b, 0.7), 10, 1.0, 0.0, Color(0, 0, 0, 0), 0.08), 14, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var cap := Label.new()
	cap.text = caption
	cap.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	row.add_child(cap)
	var val := Label.new()
	val.text = value
	val.add_theme_color_override("font_color", tone.lightened(0.4))
	row.add_child(val)
	return panel
