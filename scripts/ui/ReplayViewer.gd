extends Control
## Full-screen replay player. Re-simulates a saved command log with BattleReplay.Player and draws it with
## the regular BattleView. Controls: play/pause, speed, restart, a scrub bar and exit.

signal closed
signal branch_requested(tick: int)
signal notes_changed(replay: Dictionary)
signal storage_requested

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const CombatSounds = preload("res://scripts/CombatSounds.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
const MomentumGraph = preload("res://scripts/ui/MomentumGraph.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")
const Report = preload("res://scripts/BattleReport.gd")
const ReportContent = preload("res://scripts/ui/BattleReportContent.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const JUMP_LEAD_TICKS := 30 # land a second before a highlight so the moment plays out
const SPEEDS := [0.5, 1.0, 2.0, 4.0, 8.0]

var replay: Dictionary = {}
var player = null
var view: BattleView
var speed_index := 1
var paused := false
var accumulator := 0.0
var finished_shown := false
var timer_label: Label
var blue_bar: HpBar
var red_bar: HpBar
var blue_label: Label
var red_label: Label
var progress: HSlider
var play_button: Button
var speed_button: Button
var headline: Label
var end_banner: Control
var report_button: Button
var report_overlay: Control
var end_matches_record := false
var sound_players: Array = []
var last_sound_msec := 0
var title_text := ""
var analysis: Dictionary = {}
var graph: MomentumGraph
var moment_toast: ToastLabel
var last_announced_tick := 0
var clip_finished := false
var note_input: LineEdit
var storage_path := ""
var notes_dirty := false
var storage_label: Label
var storage_button: Button
var discard_dialog: ConfirmationDialog
var loop_start := -1
var loop_end := -1
var loop_enabled := false
var loop_button: Button
var zoom_reset_button: Button
var unit_panel: PanelContainer
var inspected_id := -1
var panel_name: Label
var panel_side: Label
var panel_bar: HpBar
var panel_hp: Label
var panel_stats: Label

func open(replay_data: Dictionary, title: String = "") -> void:
	replay = replay_data
	title_text = title
	analysis = ReplayAnalysis.analyze(replay)
	name = "ReplayViewer"
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	_build()
	_restart()
	var clip := BattleReplay.clip_of(replay)
	if not clip.is_empty():
		moment_toast.text = "클립 ▸ %s" % String(clip.get("title", ""))

func _build() -> void:
	var background := ColorRect.new()
	background.color = Color("#070b13")
	background.size = size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	view = BattleView.new()
	view.position = Vector2(0, 88)
	view.size = Vector2(1280, 492)
	view.own_side = 0
	view.interpolate_positions = false
	view.inspect_mode = true
	view.clip_contents = true
	view.unit_clicked.connect(_on_unit_clicked)
	view.zoom_changed.connect(func(zoom): zoom_reset_button.visible = zoom > 1.001)
	add_child(view)
	_build_top_bar()
	_build_bottom_bar()
	_build_unit_panel()
	zoom_reset_button = _control_button(self, "ReplayZoomReset", "확대 해제", UIKit.GOLD_DEEP, false)
	zoom_reset_button.position = Vector2(1110, 96)
	zoom_reset_button.size = Vector2(124, 34)
	zoom_reset_button.custom_minimum_size = Vector2(124, 34)
	zoom_reset_button.visible = false
	zoom_reset_button.tooltip_text = "휠로 확대한 화면을 원래대로 돌립니다 (더블클릭도 같습니다)"
	zoom_reset_button.pressed.connect(view.reset_view)
	moment_toast = ToastLabel.new()
	moment_toast.name = "MomentToast"
	moment_toast.tone = UIKit.GOLD
	add_child(moment_toast)
	moment_toast.place_center(640.0, 100.0)
	_build_storage_controls()
	for i in 4:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		voice.volume_db = -8.0
		add_child(voice)
		sound_players.append(voice)

func _build_storage_controls() -> void:
	var panel := PanelContainer.new()
	panel.name = "ReplayStoragePanel"
	panel.position = Vector2(18, 96)
	panel.size = Vector2(510, 58)
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE, UIKit.SURFACE, UIKit.TEAL, 10), 10, 0))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	storage_label = Label.new()
	storage_label.name = "ReplayStorageStatus"
	storage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	storage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	storage_label.add_theme_font_size_override("font_size", 13)
	row.add_child(storage_label)
	storage_button = _control_button(row, "ReplaySaveLocal", "로컬 보관", UIKit.TEAL, false)
	storage_button.custom_minimum_size = Vector2(140, 58)
	storage_button.pressed.connect(func(): storage_requested.emit())
	panel.add_child(row)
	add_child(panel)
	set_storage_state("", false)

func set_storage_state(path: String, dirty: bool) -> void:
	storage_path = path
	notes_dirty = dirty
	storage_button.visible = path.is_empty() or dirty
	storage_button.text = "메모 저장 재시도" if dirty else "로컬 보관"
	storage_label.text = "메모를 저장하지 못했습니다. 나가기 전에 재시도하세요." if dirty else ("공유 리플레이 · 메모를 남기면 이 기기에 보관됩니다." if path.is_empty() else "이 기기에 보관됨 · 메모 자동 저장")
	storage_label.add_theme_color_override("font_color", UIKit.GOLD if dirty else UIKit.TEXT_MUTED)

func _request_close() -> void:
	if not notes_dirty:
		closed.emit()
		return
	if not is_instance_valid(discard_dialog):
		discard_dialog = ConfirmationDialog.new()
		discard_dialog.name = "DiscardReplayNotes"
		discard_dialog.title = "저장하지 않은 메모"
		discard_dialog.dialog_text = "메모가 아직 저장되지 않았습니다.\n돌아가서 저장을 재시도하거나, 변경 내용을 버리고 나갈 수 있습니다."
		discard_dialog.ok_button_text = "저장하지 않고 나가기"
		discard_dialog.cancel_button_text = "돌아가기"
		discard_dialog.confirmed.connect(func(): closed.emit())
		add_child(discard_dialog)
	discard_dialog.popup_centered(Vector2i(520, 180))

func _build_top_bar() -> void:
	var top := ColorRect.new()
	top.color = Color("#090d17")
	top.size = Vector2(1280, 88)
	add_child(top)
	for side in 2:
		var color := UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
		var card := PanelContainer.new()
		card.position = Vector2(18 if side == 0 else 842, 12)
		card.size = Vector2(420, 64)
		card.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI.lerp(color, 0.10), UIKit.SURFACE.darkened(0.2), Color(color.r, color.g, color.b, 0.55), 12, 1.0, 0.6, Color(color.r, color.g, color.b, 0.35), 0.08))
		top.add_child(card)
		var inner := Control.new()
		inner.custom_minimum_size = Vector2(420, 64)
		card.add_child(inner)
		var caption := Label.new()
		caption.text = "블루 진영" if side == 0 else "레드 진영"
		caption.position = Vector2(16, 7)
		caption.add_theme_font_size_override("font_size", 13)
		caption.add_theme_color_override("font_color", color.lightened(0.25))
		inner.add_child(caption)
		var value := Label.new()
		value.position = Vector2(300, 5)
		value.size = Vector2(104, 24)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 16)
		inner.add_child(value)
		var bar := HpBar.new()
		bar.color = color
		bar.position = Vector2(16, 34)
		bar.size = Vector2(388, 16)
		inner.add_child(bar)
		if side == 0:
			blue_bar = bar
			blue_label = value
		else:
			red_bar = bar
			red_label = value
	var timer_card := PanelContainer.new()
	timer_card.position = Vector2(530, 12)
	timer_card.size = Vector2(220, 64)
	timer_card.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE.darkened(0.2), Color(1, 1, 1, 0.16), 14, 1.0, 0.6, Color(0, 0, 0, 0), 0.10))
	top.add_child(timer_card)
	var timer_inner := Control.new()
	timer_inner.custom_minimum_size = Vector2(220, 64)
	timer_card.add_child(timer_inner)
	timer_label = Label.new()
	timer_label.position = Vector2(0, 3)
	timer_label.size = Vector2(220, 40)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.display(timer_label, 30, UIKit.TEXT)
	timer_inner.add_child(timer_label)
	headline = Label.new()
	headline.position = Vector2(0, 41)
	headline.size = Vector2(220, 18)
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.text = "REPLAY"
	headline.add_theme_font_size_override("font_size", 11)
	headline.add_theme_color_override("font_color", UIKit.GOLD)
	timer_inner.add_child(headline)

func _build_bottom_bar() -> void:
	var bar := ColorRect.new()
	bar.color = Color("#090d17")
	bar.position = Vector2(0, 580)
	bar.size = Vector2(1280, 140)
	add_child(bar)
	graph = MomentumGraph.new()
	graph.name = "MomentumGraph"
	graph.position = Vector2(40, 6)
	graph.size = Vector2(950, 42)
	graph.setup(analysis)
	graph.set_notes(BattleReplay.notes_of(replay))
	graph.seek_requested.connect(func(tick): seek(tick))
	bar.add_child(graph)
	var loop_row := HBoxContainer.new()
	loop_row.name = "ReplayLoopRow"
	loop_row.position = Vector2(1000, 8)
	loop_row.size = Vector2(240, 34)
	loop_row.add_theme_constant_override("separation", 6)
	bar.add_child(loop_row)
	var mark_start := _control_button(loop_row, "ReplayLoopStart", "시작 [", UIKit.TEAL, false)
	mark_start.custom_minimum_size = Vector2(74, 34)
	mark_start.add_theme_font_size_override("font_size", 13)
	mark_start.tooltip_text = "지금 위치를 반복 구간의 시작으로 정합니다 ( [ 키 )"
	mark_start.pressed.connect(set_loop_start)
	var mark_end := _control_button(loop_row, "ReplayLoopEnd", "끝 ]", UIKit.TEAL, false)
	mark_end.custom_minimum_size = Vector2(74, 34)
	mark_end.add_theme_font_size_override("font_size", 13)
	mark_end.tooltip_text = "지금 위치를 반복 구간의 끝으로 정합니다 ( ] 키 )"
	mark_end.pressed.connect(set_loop_end)
	loop_button = _control_button(loop_row, "ReplayLoopToggle", "반복 L", UIKit.GOLD_DEEP, false)
	loop_button.custom_minimum_size = Vector2(74, 34)
	loop_button.add_theme_font_size_override("font_size", 13)
	loop_button.toggle_mode = true
	loop_button.tooltip_text = "정한 구간을 계속 반복합니다 ( L 키 )"
	loop_button.pressed.connect(toggle_loop)
	progress = HSlider.new()
	progress.name = "ReplayProgress"
	progress.position = Vector2(40, 50)
	progress.size = Vector2(1200, 24)
	progress.min_value = 0
	progress.max_value = maxf(1.0, float(replay.get("result", {}).get("ticks", 1)))
	progress.step = 1
	progress.value_changed.connect(_on_scrub)
	bar.add_child(progress)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 82)
	row.size = Vector2(1200, 52)
	row.add_theme_constant_override("separation", 10)
	bar.add_child(row)
	var previous := _control_button(row, "ReplayPreviousMoment", "◀ 이전 순간", UIKit.ACCENT, false)
	previous.custom_minimum_size.x = 110
	previous.pressed.connect(jump_previous_moment)
	play_button = _control_button(row, "ReplayPlayPause", "일시정지", UIKit.ACCENT, true)
	play_button.custom_minimum_size.x = 100
	play_button.pressed.connect(toggle_pause)
	var next := _control_button(row, "ReplayNextMoment", "다음 순간 ▶", UIKit.ACCENT, false)
	next.custom_minimum_size.x = 110
	next.pressed.connect(jump_next_moment)
	var restart := _control_button(row, "ReplayRestart", "처음부터", UIKit.TEAL, false)
	restart.custom_minimum_size.x = 90
	restart.pressed.connect(_restart)
	speed_button = _control_button(row, "ReplaySpeed", "1배속", UIKit.GOLD_DEEP, false)
	speed_button.custom_minimum_size.x = 80
	speed_button.pressed.connect(cycle_speed)
	note_input = LineEdit.new()
	note_input.name = "ReplayNoteInput"
	note_input.placeholder_text = "이 장면에 메모..."
	note_input.max_length = BattleReplay.MAX_NOTE_LENGTH
	note_input.tooltip_text = title_text
	note_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_input.custom_minimum_size.x = 120
	note_input.text_submitted.connect(func(_text): add_note())
	row.add_child(note_input)
	var note_button := _control_button(row, "ReplayNoteButton", "메모", UIKit.TEAL, false)
	note_button.custom_minimum_size.x = 64
	note_button.tooltip_text = "지금 장면에 메모를 남깁니다 (리플레이와 함께 저장·공유됩니다)"
	note_button.pressed.connect(add_note)
	var note_delete := _control_button(row, "ReplayNoteDeleteButton", "삭제", UIKit.DANGER, false)
	note_delete.custom_minimum_size.x = 64
	note_delete.tooltip_text = "재생 위치에서 가장 가까운 메모를 지웁니다"
	note_delete.pressed.connect(delete_note)
	var clip_button := _control_button(row, "ReplayClipButton", "클립 복사", UIKit.GOLD_DEEP, false)
	clip_button.custom_minimum_size.x = 96
	clip_button.tooltip_text = "지금 장면 전후 10초를 공유용 텍스트로 복사합니다"
	clip_button.pressed.connect(copy_clip)
	var branch := _control_button(row, "ReplayBranchButton", "여기서 해보기", UIKit.TEAL, false)
	branch.custom_minimum_size.x = 130
	branch.tooltip_text = "지금 장면에서 이어서 직접 조작해 보는 되감기 실험입니다"
	branch.pressed.connect(func():
		if player != null and not _playback_finished():
			if notes_dirty:
				_toast("메모 저장을 재시도한 뒤 여기서 해보기를 눌러주세요.")
			else:
				branch_requested.emit(player.ticks))
	var close := _control_button(row, "ReplayClose", "나가기", UIKit.DANGER, false)
	close.custom_minimum_size.x = 90
	close.pressed.connect(_request_close)

func _control_button(parent: Control, node_name: String, text: String, color: Color, primary: bool) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size = Vector2(140, 52)
	UIKit.style_button(button, color, primary, 16)
	parent.add_child(button)
	return button

# ---------------------------------------------------------------- playback
func _restart() -> void:
	_clear_end()
	clip_finished = false
	player = BattleReplay.Player.new(replay)
	accumulator = 0.0
	finished_shown = false
	paused = false
	view.visual_events.clear()
	last_announced_tick = 0
	view.set_snapshot(player.model.snapshot())
	_refresh_hud()
	if play_button:
		play_button.text = "일시정지"
	var clip := BattleReplay.clip_of(replay)
	if not clip.is_empty() and int(clip.start) > 0:
		seek(int(clip.start))
	elif _playback_finished():
		_show_end()

## The loop only runs between two marks with start before end.
func loop_ready() -> bool:
	return loop_start >= 0 and loop_end > loop_start

func _refresh_loop() -> void:
	graph.set_loop(loop_start, loop_end, loop_enabled and loop_ready())
	if is_instance_valid(loop_button):
		loop_button.set_pressed_no_signal(loop_enabled and loop_ready())

## Marks the current moment as the start of the repeat segment (an end that is no longer after it is dropped).
func set_loop_start() -> void:
	if player == null:
		return
	loop_start = player.ticks
	if loop_end <= loop_start:
		loop_end = -1
		loop_enabled = false
	_refresh_loop()

## Marks the current moment as the end of the segment; refused unless it lies after the start.
func set_loop_end() -> bool:
	if player == null or loop_start < 0 or player.ticks <= loop_start:
		_toast("끝 지점은 시작 지점보다 뒤여야 합니다")
		return false
	loop_end = player.ticks
	_refresh_loop()
	return true

## Turns repeating on or off; it only turns on once both marks exist.
func toggle_loop() -> bool:
	if loop_enabled:
		loop_enabled = false
	elif loop_ready():
		loop_enabled = true
		if player != null and (player.ticks < loop_start or player.ticks >= loop_end):
			seek(loop_start)
	else:
		_toast("반복하려면 시작과 끝 지점을 먼저 정하세요")
	_refresh_loop()
	return loop_enabled

func _build_unit_panel() -> void:
	unit_panel = PanelContainer.new()
	unit_panel.name = "ReplayUnitPanel"
	unit_panel.visible = false
	unit_panel.custom_minimum_size = Vector2(250, 0)
	unit_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	unit_panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE.darkened(0.15), UIKit.EDGE, 12, 1.0, 0.5, Color(0, 0, 0, 0), 0.1), 12, 10))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	unit_panel.add_child(column)
	panel_name = Label.new()
	panel_name.add_theme_font_size_override("font_size", 17)
	column.add_child(panel_name)
	panel_side = Label.new()
	panel_side.add_theme_font_size_override("font_size", 12)
	column.add_child(panel_side)
	panel_bar = HpBar.new()
	panel_bar.show_ticks = false
	panel_bar.pulse_below = 0.0
	panel_bar.custom_minimum_size = Vector2(0, 10)
	column.add_child(panel_bar)
	panel_hp = Label.new()
	panel_hp.add_theme_font_size_override("font_size", 12)
	column.add_child(panel_hp)
	panel_stats = Label.new()
	panel_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_stats.custom_minimum_size.x = 226
	panel_stats.add_theme_font_size_override("font_size", 12)
	panel_stats.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	column.add_child(panel_stats)
	add_child(unit_panel)

func _on_unit_clicked(unit: Dictionary) -> void:
	inspected_id = int(unit.get("id", -1)) if not unit.is_empty() else -1
	_refresh_inspector()

func close_inspector() -> void:
	inspected_id = -1
	_refresh_inspector()

## Keeps the panel in step with the playhead: it follows its unit and closes when the unit is gone.
func _refresh_inspector() -> void:
	if not is_instance_valid(unit_panel):
		return
	var found := {}
	if inspected_id >= 0:
		for unit in view.snapshot.get("units", []):
			if int(unit.id) == inspected_id:
				found = unit
				break
	if found.is_empty():
		inspected_id = -1
		unit_panel.visible = false
		return
	var kind := String(found.kind)
	var own: bool = int(found.side) == 0
	panel_name.text = String(BattleModel.UNIT_NAMES.get(kind, kind))
	panel_side.text = "블루 진영" if own else "레드 진영"
	panel_side.add_theme_color_override("font_color", (UIKit.TEAM_BLUE if own else UIKit.TEAM_RED).lightened(0.25))
	panel_bar.color = UIKit.TEAM_BLUE if own else UIKit.TEAM_RED
	panel_bar.max_value = maxf(1.0, float(found.get("max_hp", found.hp)))
	panel_bar.value = float(found.hp)
	panel_hp.text = "체력 %d / %d" % [int(found.hp), int(maxf(1.0, float(found.get("max_hp", found.hp))))]
	panel_stats.text = BattleModel.unit_stat_summary(kind)
	unit_panel.visible = true
	var lane_y := view.size.y * 0.72
	var anchor: Vector2 = view.position + view._view_transform() * Vector2(view.world_to_screen_x(float(found.x)), lane_y - 110.0)
	unit_panel.position = Vector2(clampf(anchor.x - 125.0, 8.0, 1272.0 - 250.0), clampf(anchor.y - unit_panel.size.y, 96.0, 560.0 - unit_panel.size.y))

func toggle_pause() -> void:
	paused = not paused
	play_button.text = "재생" if paused else "일시정지"

func cycle_speed() -> void:
	speed_index = (speed_index + 1) % SPEEDS.size()
	speed_button.text = ("%s배속" % str(SPEEDS[speed_index]).trim_suffix(".0"))

func _on_scrub(value: float) -> void:
	seek(int(value))

## Re-simulates from the start up to `tick` (no drawing in between).
func seek(tick: int) -> void:
	_clear_end()
	player = BattleReplay.Player.new(replay)
	while player.ticks < tick and player.step():
		pass
	player.model.drain_combat_events()
	view.visual_events.clear()
	finished_shown = false
	last_announced_tick = player.ticks
	view.set_snapshot(player.model.snapshot())
	_refresh_hud()
	if _playback_finished():
		_show_end()

func _playback_finished() -> bool:
	if player == null: return false
	# A forced result at the last supported tick still needs one Player.step().
	return player.is_finished() or (player.ticks >= BattleReplay.MAX_TICKS and replay.get("forced_end", {}).is_empty())

func _clear_end() -> void:
	_close_report(false)
	if is_instance_valid(end_banner):
		remove_child(end_banner)
		end_banner.queue_free()
	end_banner = null
	report_button = null
	end_matches_record = false

func _process(delta: float) -> void:
	if player == null or paused or is_instance_valid(report_overlay):
		return
	if _playback_finished():
		_show_end()
		return
	var clip := BattleReplay.clip_of(replay)
	if not clip.is_empty() and not clip_finished and player.ticks >= int(clip.end):
		clip_finished = true
		paused = true
		play_button.text = "재생"
		moment_toast.text = "클립 끝 ▸ 재생을 누르면 이어서 봅니다"
		return
	accumulator += minf(delta, 0.25) * float(SPEEDS[speed_index])
	var steps := 0
	var events: Array = []
	while accumulator >= player.dt and steps < 40 and not _playback_finished():
		player.step()
		events.append_array(player.model.drain_combat_events())
		accumulator -= player.dt
		steps += 1
		if loop_enabled and loop_ready() and player.ticks >= loop_end:
			seek(loop_start)
			accumulator = 0.0
			return
	if steps > 0:
		_announce_between(last_announced_tick, player.ticks)
		view.set_snapshot(player.model.snapshot())
		if not events.is_empty():
			view.push_combat_events(events)
			_play_sounds(events)
		_refresh_hud()
		if _playback_finished():
			_show_end()

## Shows a toast for every highlight the playhead just passed.
func _announce_between(from_tick: int, to_tick: int) -> void:
	for note in BattleReplay.notes_of(replay):
		if int(note.t) > from_tick and int(note.t) <= to_tick:
			_toast("메모 ▸ %s" % String(note.text))
	for item in analysis.get("highlights", []):
		if int(item.tick) > from_tick and int(item.tick) <= to_tick:
			moment_toast.text = String(item.text)
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(moment_toast) and moment_toast.text == String(item.text):
					moment_toast.text = "")
	last_announced_tick = to_tick

func _toast(text: String) -> void:
	moment_toast.text = text
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(moment_toast) and moment_toast.text == text:
			moment_toast.text = "")

## Pins the text in the input box to the current moment. Returns whether a note was added.
func add_note() -> bool:
	var text := note_input.text.strip_edges()
	if text.is_empty() or player == null:
		return false
	var updated := BattleReplay.with_note(replay, player.ticks, text)
	if updated == replay:
		_toast("메모를 더 남길 수 없습니다")
		return false
	replay = updated
	note_input.text = ""
	graph.set_notes(BattleReplay.notes_of(replay))
	_toast("메모를 남겼습니다 ▸ %s" % text)
	notes_changed.emit(replay)
	return true

## Removes the note nearest to the playhead. Returns whether one was removed.
func delete_note() -> bool:
	var note := BattleReplay.nearest_note(replay, player.ticks if player != null else 0)
	if note.is_empty():
		return false
	replay = BattleReplay.without_note(replay, int(note.t))
	graph.set_notes(BattleReplay.notes_of(replay))
	_toast("메모를 지웠습니다")
	notes_changed.emit(replay)
	return true

## Copies a shareable clip around the highlight nearest to the playhead (or the playhead itself).
func copy_clip() -> String:
	var center: int = player.ticks
	var title := "%d:%02d 부근" % [int(player.model.elapsed) / 60, int(player.model.elapsed) % 60]
	var best := 600
	for item in analysis.get("highlights", []):
		var distance := absi(int(item.tick) - player.ticks)
		if distance < best:
			best = distance
			center = int(item.tick)
			title = String(item.text)
	var text := BattleReplay.to_share_text(BattleReplay.make_clip(replay, center, title))
	DisplayServer.clipboard_set(text)
	moment_toast.text = "클립을 복사했습니다 ▸ %s" % title
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(moment_toast) and moment_toast.text.begins_with("클립을 복사했습니다"):
			moment_toast.text = "")
	return text

func jump_next_moment() -> void:
	var item := ReplayAnalysis.next_after(analysis.get("highlights", []), player.ticks + JUMP_LEAD_TICKS)
	if not item.is_empty():
		seek(maxi(0, int(item.tick) - JUMP_LEAD_TICKS))

func jump_previous_moment() -> void:
	var item := ReplayAnalysis.previous_before(analysis.get("highlights", []), player.ticks + JUMP_LEAD_TICKS)
	seek(maxi(0, int(item.tick) - JUMP_LEAD_TICKS) if not item.is_empty() else 0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if is_instance_valid(report_overlay):
		if event.keycode == KEY_ESCAPE:
			_close_report()
		get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_RIGHT: seek(mini(int(replay.get("result", {}).get("ticks", 0)), player.ticks + 150))
		KEY_LEFT: seek(maxi(0, player.ticks - 150))
		KEY_N: jump_next_moment()
		KEY_BRACKETLEFT: set_loop_start()
		KEY_BRACKETRIGHT: set_loop_end()
		KEY_L: toggle_loop()
		KEY_ESCAPE: close_inspector()
		KEY_P: jump_previous_moment()

func _play_sounds(events: Array) -> void:
	var now := Time.get_ticks_msec()
	if now - last_sound_msec < 45 or float(SPEEDS[speed_index]) > 2.0:
		return
	for event in events:
		var kind := CombatSounds.event_sound(event)
		if kind == "":
			continue
		for voice in sound_players:
			if not voice.playing:
				voice.stream = CombatSounds.stream(kind)
				voice.play()
				last_sound_msec = now
				return

func _refresh_hud() -> void:
	var model: BattleModel = player.model
	var seconds := int(model.elapsed)
	timer_label.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	blue_bar.max_value = float(model.base_max_hp[0])
	red_bar.max_value = float(model.base_max_hp[1])
	blue_bar.value = float(model.base_hp[0])
	red_bar.value = float(model.base_hp[1])
	blue_label.text = "%d / %d" % [int(model.base_hp[0]), int(model.base_max_hp[0])]
	red_label.text = "%d / %d" % [int(model.base_hp[1]), int(model.base_max_hp[1])]
	progress.set_value_no_signal(float(player.ticks))
	_refresh_inspector()
	graph.set_playhead(player.ticks)

func _show_end() -> void:
	if finished_shown or not _playback_finished():
		return
	finished_shown = true
	var winner: int = player.model.winner
	var recorded: Dictionary = replay.get("result", {})
	end_matches_record = winner == int(recorded.get("winner", -2)) and player.model.state_hash() == String(recorded.get("state_hash", ""))
	var panel := Control.new()
	panel.name = "ReplayEndPanel"
	panel.position = Vector2(0, 230)
	panel.size = Vector2(1280, 220)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 30
	add_child(panel)
	end_banner = panel
	var banner := Label.new()
	banner.name = "ReplayEndBanner"
	banner.text = "기록 한도 도달" if winner < 0 else ("무승부" if winner == 2 else ("블루 승리" if winner == 0 else "레드 승리"))
	banner.size = Vector2(1280, 90)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tone := UIKit.TEAM_BLUE if winner == 0 else (UIKit.TEAM_RED if winner == 1 else UIKit.TEXT_MUTED)
	UIKit.display(banner, 64, tone.lightened(0.35))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner.add_theme_constant_override("outline_size", 12)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(banner)
	UIKit.reveal(banner, 0.4, 14.0)
	var status := MultiplayerUI.label(_end_status(), 14, UIKit.TEXT_MUTED if end_matches_record else UIKit.GOLD)
	status.name = "ReplayResultStatus"
	status.position = Vector2(200, 94)
	status.size = Vector2(880, 40)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(status)
	report_button = _control_button(panel, "ReplayBattleReportButton", "전투 요약", UIKit.TEAL, true)
	report_button.position = Vector2(540, 142)
	report_button.custom_minimum_size = Vector2(200, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 52)
	report_button.size = report_button.custom_minimum_size
	report_button.disabled = not Report.valid(player.model.battle_report)
	report_button.pressed.connect(_show_report)

func _end_status() -> String:
	return "재생 결과가 저장된 전투 결과와 일치합니다." if end_matches_record else "저장된 결과와 다릅니다. 규칙 변경이나 기록 차이가 있을 수 있으며, 요약은 현재 재생의 집계입니다."

func _show_report() -> void:
	if not _playback_finished() or not Report.valid(player.model.battle_report) or is_instance_valid(report_overlay):
		return
	close_inspector()
	var overlay := ColorRect.new()
	overlay.name = "ReplayBattleReportOverlay"
	overlay.color = Color(0.02, 0.03, 0.05, 0.97)
	overlay.size = size
	overlay.z_index = 100
	add_child(overlay)
	report_overlay = overlay
	var content := MultiplayerUI.panel(null, overlay, "ReplayBattleReportPanel", Rect2(80, 40, 1120, 640))
	content.add_child(MultiplayerUI.label("리플레이 전투 요약", 28, UIKit.GOLD))
	var status := MultiplayerUI.label(_end_status(), 14, UIKit.TEXT_MUTED if end_matches_record else UIKit.GOLD)
	status.name = "ReplayReportStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.name = "ReplayBattleReportScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.gui_input.connect(_on_report_scroll_input.bind(scroll))
	content.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	scroll.add_child(body)
	_add_report_graph(body)
	ReportContent.populate(body, player.model.battle_report.duplicate(true), ["블루 진영", "레드 진영"])
	var close := _control_button(content, "CloseReplayBattleReportButton", "닫기", UIKit.TEAL, false)
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	close.pressed.connect(_close_report)
	var focus_controls: Array[Control] = [scroll,
		body.find_child("BattleReportMetric_damage", true, false),
		body.find_child("BattleReportMetric_kills", true, false), close]
	for index in focus_controls.size():
		var control := focus_controls[index]
		var next := control.get_path_to(focus_controls[(index + 1) % focus_controls.size()])
		var previous := control.get_path_to(focus_controls[(index + focus_controls.size() - 1) % focus_controls.size()])
		control.focus_next = next
		control.focus_previous = previous
		control.focus_neighbor_top = previous
		control.focus_neighbor_bottom = next
		control.focus_neighbor_left = previous
		control.focus_neighbor_right = next
	scroll.grab_focus.call_deferred()

func _add_report_graph(parent: VBoxContainer) -> void:
	parent.add_child(MultiplayerUI.label("전세 흐름 · 기지와 생존 병력의 체력 기준", 16, UIKit.GOLD))
	parent.add_child(MultiplayerUI.label("▲ 블루 진영 · ▼ 레드 진영", 14, UIKit.TEXT_MUTED))
	var report_graph := MomentumGraph.new()
	report_graph.name = "ReplayReportMomentumGraph"
	report_graph.custom_minimum_size = Vector2(0, 88)
	report_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(report_graph)
	# Reuse the completed analysis pass; opening a report never simulates again.
	var samples: Array = analysis.get("samples", []).duplicate(true)
	var damage := float(player.model.battle_report[0].damage) + float(player.model.battle_report[1].damage)
	var momentum := ReplayAnalysis.momentum_from_snapshot(player.model.snapshot()) if damage > 0.0 else 0.0
	if samples.is_empty():
		samples.append({"t": 0, "momentum": 0.0})
	if int(samples.back().t) == player.ticks:
		samples.back().momentum = momentum
	else:
		samples.append({"t": player.ticks, "momentum": momentum})
	report_graph.setup({"samples": samples, "ticks": maxi(1, player.ticks)})
	report_graph.set_playhead(player.ticks)
	report_graph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seconds := int(player.model.elapsed)
	parent.add_child(MultiplayerUI.label("00:00 → %02d:%02d · 전체 재생 집계" % [seconds / 60, seconds % 60], 12, UIKit.TEXT_MUTED))
	var note := MultiplayerUI.label("클립으로 열었어도 집계는 전체 전투 기준입니다. 치유·방어·자원 효과는 공격 기여도에 포함되지 않습니다.", 12, UIKit.TEXT_MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)

func _close_report(restore_focus: bool = true) -> void:
	if not is_instance_valid(report_overlay): return
	remove_child(report_overlay)
	report_overlay.queue_free()
	report_overlay = null
	if restore_focus and is_instance_valid(report_button):
		report_button.grab_focus()

func _on_report_scroll_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return
	var bar := scroll.get_v_scroll_bar()
	var target := scroll.scroll_vertical
	match event.keycode:
		KEY_UP: target -= 48
		KEY_DOWN: target += 48
		KEY_PAGEUP: target -= maxi(48, int(bar.page))
		KEY_PAGEDOWN: target += maxi(48, int(bar.page))
		KEY_HOME: target = 0
		KEY_END: target = int(bar.max_value - bar.page)
		_: return
	scroll.scroll_vertical = clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
	scroll.accept_event()
