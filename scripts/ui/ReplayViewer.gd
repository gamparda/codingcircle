extends Control
## Full-screen replay player. Re-simulates a saved command log with BattleReplay.Player and draws it with
## the regular BattleView. Controls: play/pause, speed, restart, a scrub bar and exit.

signal closed
signal branch_requested(tick: int)
signal notes_changed(replay: Dictionary)

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const CombatSounds = preload("res://scripts/CombatSounds.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
const MomentumGraph = preload("res://scripts/ui/MomentumGraph.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")
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
var sound_players: Array = []
var last_sound_msec := 0
var title_text := ""
var analysis: Dictionary = {}
var graph: MomentumGraph
var moment_toast: ToastLabel
var last_announced_tick := 0
var clip_finished := false
var note_input: LineEdit

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
	add_child(view)
	_build_top_bar()
	_build_bottom_bar()
	moment_toast = ToastLabel.new()
	moment_toast.name = "MomentToast"
	moment_toast.tone = UIKit.GOLD
	add_child(moment_toast)
	moment_toast.place_center(640.0, 100.0)
	for i in 4:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		voice.volume_db = -8.0
		add_child(voice)
		sound_players.append(voice)

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
	graph.size = Vector2(1200, 42)
	graph.setup(analysis)
	graph.set_notes(BattleReplay.notes_of(replay))
	graph.seek_requested.connect(func(tick): seek(tick))
	bar.add_child(graph)
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
		if player != null and not player.is_finished():
			branch_requested.emit(player.ticks))
	var close := _control_button(row, "ReplayClose", "나가기", UIKit.DANGER, false)
	close.custom_minimum_size.x = 90
	close.pressed.connect(func(): closed.emit())

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
	clip_finished = false
	player = BattleReplay.Player.new(replay)
	accumulator = 0.0
	finished_shown = false
	paused = false
	if is_instance_valid(end_banner):
		end_banner.queue_free()
	view.visual_events.clear()
	last_announced_tick = 0
	view.set_snapshot(player.model.snapshot())
	_refresh_hud()
	if play_button:
		play_button.text = "일시정지"
	var clip := BattleReplay.clip_of(replay)
	if not clip.is_empty() and int(clip.start) > 0:
		seek(int(clip.start))

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
	player = BattleReplay.Player.new(replay)
	while player.ticks < tick and player.step():
		pass
	player.model.drain_combat_events()
	view.visual_events.clear()
	finished_shown = false
	last_announced_tick = player.ticks
	if is_instance_valid(end_banner):
		end_banner.queue_free()
	view.set_snapshot(player.model.snapshot())
	_refresh_hud()

func _process(delta: float) -> void:
	if player == null or paused:
		return
	if player.is_finished():
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
	while accumulator >= player.dt and steps < 40 and not player.is_finished():
		player.step()
		events.append_array(player.model.drain_combat_events())
		accumulator -= player.dt
		steps += 1
	if steps > 0:
		_announce_between(last_announced_tick, player.ticks)
		view.set_snapshot(player.model.snapshot())
		if not events.is_empty():
			view.push_combat_events(events)
			_play_sounds(events)
		_refresh_hud()

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
	match event.keycode:
		KEY_SPACE: toggle_pause()
		KEY_RIGHT: seek(mini(int(replay.get("result", {}).get("ticks", 0)), player.ticks + 150))
		KEY_LEFT: seek(maxi(0, player.ticks - 150))
		KEY_N: jump_next_moment()
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
	graph.set_playhead(player.ticks)

func _show_end() -> void:
	if finished_shown:
		return
	finished_shown = true
	var winner: int = player.model.winner
	var banner := Label.new()
	banner.name = "ReplayEndBanner"
	banner.text = "무승부" if winner == 2 else ("블루 승리" if winner == 0 else "레드 승리")
	banner.size = Vector2(1280, 90)
	banner.position = Vector2(0, 250)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tone := UIKit.TEAM_BLUE if winner == 0 else (UIKit.TEAM_RED if winner == 1 else UIKit.TEXT_MUTED)
	UIKit.display(banner, 64, tone.lightened(0.35))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner.add_theme_constant_override("outline_size", 12)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.z_index = 30
	add_child(banner)
	end_banner = banner
	UIKit.reveal(banner, 0.4, 14.0)
