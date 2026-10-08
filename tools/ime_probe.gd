extends SceneTree
## Diagnostic window for Korean (IME) typing problems. Run it with the Godot console binary:
##   godot --path . --script res://tools/ime_probe.gd
## It shows three inputs (a plain LineEdit, one with max_length like the game's fields, and a TextEdit) and writes
## every key event, IME update and text change to user://ime_probe.log so the behaviour can be inspected afterwards.

const LOG_PATH := "user://ime_probe.log"
var log_file: FileAccess
var started := 0
var shown: Label

class Probe extends Control:
	var report: Callable
	func _input(event: InputEvent) -> void:
		if event is InputEventKey:
			report.call("KEY %s keycode=%d unicode=%d pressed=%s echo=%s" % [OS.get_keycode_string(event.keycode), event.keycode, event.unicode, event.pressed, event.echo])
	func _notification(what: int) -> void:
		if what == NOTIFICATION_OS_IME_UPDATE:
			report.call("IME_UPDATE ime_text='%s' selection=%s focus=%s" % [DisplayServer.ime_get_text(), DisplayServer.ime_get_selection(), get_viewport().gui_get_focus_owner()])

func _initialize() -> void:
	call_deferred("run")

func log_line(text: String) -> void:
	var line := "%6d  %s" % [Time.get_ticks_msec() - started, text]
	log_file.store_line(line)
	log_file.flush()
	if shown != null:
		shown.text = line + "\n" + shown.text.left(600)

func run() -> void:
	log_file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	started = Time.get_ticks_msec()
	root.size = Vector2i(900, 640)
	root.title = "IME probe"
	var probe := Probe.new()
	probe.report = log_line
	probe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(probe)
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	probe.add_child(column)
	var intro := Label.new()
	intro.text = "각 입력창을 눌러 한글로 '한글입력테스트'를 천천히 입력해 보세요. (A, B, C 순서)"
	column.add_child(intro)
	var fields := {}
	for entry in [["A 기본", 0], ["B max_length=16", 16]]:
		var label := Label.new()
		label.text = String(entry[0])
		column.add_child(label)
		var edit := LineEdit.new()
		edit.max_length = int(entry[1])
		edit.custom_minimum_size.y = 40
		column.add_child(edit)
		fields[entry[0]] = edit
		var tag: String = String(entry[0]).left(1)
		edit.text_changed.connect(func(value): log_line("%s text_changed '%s' caret=%d" % [tag, value, edit.caret_column]))
		edit.focus_entered.connect(func(): log_line("%s focus_entered" % tag))
		edit.focus_exited.connect(func(): log_line("%s focus_exited" % tag))
	var area_label := Label.new()
	area_label.text = "C TextEdit"
	column.add_child(area_label)
	var area := TextEdit.new()
	area.custom_minimum_size.y = 70
	column.add_child(area)
	area.text_changed.connect(func(): log_line("C text_changed '%s'" % area.text))
	shown = Label.new()
	shown.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shown.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	column.add_child(shown)
	log_line("window_mode=%d ime_feature=%s screen_scale=%.2f max_fps=%d vsync=%d" % [DisplayServer.window_get_mode(), DisplayServer.has_feature(DisplayServer.FEATURE_IME), DisplayServer.screen_get_scale(), Engine.max_fps, DisplayServer.window_get_vsync_mode()])
	log_line("locale=%s version=%s" % [OS.get_locale(), Engine.get_version_info().string])
	root.gui_embed_subwindows = true
	root.add_child(preload("res://scripts/ImeFix.gd").new())
	log_line("ImeFix attached")
	create_timer(600.0).timeout.connect(func(): log_line("done"); quit(0))
