extends Control
## "Who is winning" curve for the replay viewer: blue area above the midline, red below, a playhead and
## clickable highlight markers. Click or drag anywhere to jump to that moment.

signal seek_requested(tick: int)
signal highlight_hovered(text: String)

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MomentumCurve = preload("res://scripts/ui/MomentumCurve.gd")
const MARKER_COLORS := {"clash": Color("#ffd36a"), "structure": Color("#b9c2d6"), "base": Color("#ff6b81"), "swing": Color("#6dd5ff"), "finish": Color("#ffffff")}

var samples: Array = []
var highlights: Array = []
var notes: Array = []
var loop_start := -1
var loop_end := -1
var loop_on := false
var total_ticks := 1
var playhead := 0
var _dragging := false
var _curve: MomentumCurve

func _init() -> void:
	_curve = MomentumCurve.new()
	_curve.name = "MomentumCurve"
	_curve.show_behind_parent = true
	add_child(_curve)
	_curve.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func setup(analysis: Dictionary) -> void:
	samples = analysis.get("samples", [])
	highlights = analysis.get("highlights", [])
	total_ticks = maxi(1, int(analysis.get("ticks", 1)))
	mouse_filter = Control.MOUSE_FILTER_STOP
	_curve.setup(samples, total_ticks)
	queue_redraw()

func set_loop(start_tick: int, end_tick: int, enabled: bool) -> void:
	loop_start = start_tick
	loop_end = end_tick
	loop_on = enabled
	queue_redraw()

func set_notes(list: Array) -> void:
	notes = list
	queue_redraw()

func set_playhead(tick: int) -> void:
	if tick != playhead:
		playhead = tick
		queue_redraw()

func set_preparation_paused(paused: bool) -> void:
	_curve.set_preparation_paused(paused)

func _x_for(tick: int) -> float:
	return size.x * float(tick) / float(total_ticks)

func _tick_for(x: float) -> int:
	return clampi(roundi(x / maxf(size.x, 1.0) * float(total_ticks)), 0, total_ticks)

func _draw() -> void:
	var mid := size.y * 0.5
	for item in highlights:
		var hx := _x_for(int(item.tick))
		var color: Color = MARKER_COLORS.get(String(item.kind), Color.WHITE)
		draw_line(Vector2(hx, 2), Vector2(hx, size.y - 2), Color(color.r, color.g, color.b, 0.35), 1.0)
		var diamond := PackedVector2Array([Vector2(hx, 3), Vector2(hx + 5, 8), Vector2(hx, 13), Vector2(hx - 5, 8)])
		draw_colored_polygon(diamond, color)
	if loop_start >= 0:
		var band_end := _x_for(loop_end) if loop_end > loop_start else _x_for(loop_start) + 3.0
		var band_color := Color(UIKit.TEAL.r, UIKit.TEAL.g, UIKit.TEAL.b, 0.28 if loop_on else 0.14)
		draw_rect(Rect2(Vector2(_x_for(loop_start), 1.0), Vector2(maxf(band_end - _x_for(loop_start), 3.0), size.y - 2.0)), band_color)
		draw_line(Vector2(_x_for(loop_start), 1.0), Vector2(_x_for(loop_start), size.y - 1.0), UIKit.TEAL, 2.0)
		if loop_end > loop_start:
			draw_line(Vector2(_x_for(loop_end), 1.0), Vector2(_x_for(loop_end), size.y - 1.0), UIKit.TEAL, 2.0)
	for note in notes:
		var nx := _x_for(int(note.t))
		draw_colored_polygon(PackedVector2Array([Vector2(nx - 4, size.y - 2), Vector2(nx + 4, size.y - 2), Vector2(nx, size.y - 9)]), UIKit.TEAL)
	var px := _x_for(playhead)
	draw_line(Vector2(px, 0), Vector2(px, size.y), UIKit.GOLD, 2.0)
	draw_circle(Vector2(px, mid), 4.0, UIKit.GOLD)

func _note_at(x: float, tolerance: float = 7.0) -> Dictionary:
	for note in notes:
		if absf(_x_for(int(note.t)) - x) <= tolerance:
			return note
	return {}

func nearest_highlight(x: float, tolerance: float = 9.0) -> Dictionary:
	var best := {}
	var best_distance := tolerance
	for item in highlights:
		var distance := absf(_x_for(int(item.tick)) - x)
		if distance <= best_distance:
			best_distance = distance
			best = item
	return best

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			var marker := nearest_highlight(event.position.x)
			seek_requested.emit(int(marker.tick) if not marker.is_empty() else _tick_for(event.position.x))
	elif event is InputEventMouseMotion:
		if _dragging:
			seek_requested.emit(_tick_for(event.position.x))
		var hovered := nearest_highlight(event.position.x)
		var remark := _note_at(event.position.x)
		var hover_text := String(hovered.get("text", "")) if not hovered.is_empty() else ("메모 ▸ " + String(remark.text) if not remark.is_empty() else "")
		highlight_hovered.emit(hover_text)
		tooltip_text = hover_text
