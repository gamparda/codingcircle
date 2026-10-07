extends Control
## Full-screen replay player. Re-simulates a saved command log with BattleReplay.Player and draws it with
## the regular BattleView. Controls: play/pause, speed, restart, a scrub bar and exit.

signal closed

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const CombatSounds = preload("res://scripts/CombatSounds.gd")
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

func open(replay_data: Dictionary, title: String = "") -> void:
	replay = replay_data
	title_text = title
	name = "ReplayViewer"
	position = Vector2.ZERO
	size = Vector2(1280, 720)
	_build()
	_restart()

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
	progress = HSlider.new()
	progress.name = "ReplayProgress"
	progress.position = Vector2(40, 22)
	progress.size = Vector2(1200, 28)
	progress.min_value = 0
	progress.max_value = maxf(1.0, float(replay.get("result", {}).get("ticks", 1)))
	progress.step = 1
	progress.value_changed.connect(_on_scrub)
	bar.add_child(progress)
	var row := HBoxContainer.new()
	row.position = Vector2(40, 72)
	row.size = Vector2(1200, 52)
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	play_button = _control_button(row, "ReplayPlayPause", "일시정지", UIKit.ACCENT, true)
	play_button.pressed.connect(toggle_pause)
	var restart := _control_button(row, "ReplayRestart", "처음부터", UIKit.TEAL, false)
	restart.pressed.connect(_restart)
	speed_button = _control_button(row, "ReplaySpeed", "1배속", UIKit.GOLD_DEEP, false)
	speed_button.pressed.connect(cycle_speed)
	var info := Label.new()
	info.name = "ReplayInfo"
	info.text = title_text
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	row.add_child(info)
	var close := _control_button(row, "ReplayClose", "나가기", UIKit.DANGER, false)
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
	player = BattleReplay.Player.new(replay)
	accumulator = 0.0
	finished_shown = false
	paused = false
	if is_instance_valid(end_banner):
		end_banner.queue_free()
	view.visual_events.clear()
	view.set_snapshot(player.model.snapshot())
	_refresh_hud()
	if play_button:
		play_button.text = "일시정지"

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
	accumulator += minf(delta, 0.25) * float(SPEEDS[speed_index])
	var steps := 0
	var events: Array = []
	while accumulator >= player.dt and steps < 40 and not player.is_finished():
		player.step()
		events.append_array(player.model.drain_combat_events())
		accumulator -= player.dt
		steps += 1
	if steps > 0:
		view.set_snapshot(player.model.snapshot())
		if not events.is_empty():
			view.push_combat_events(events)
			_play_sounds(events)
		_refresh_hud()

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
