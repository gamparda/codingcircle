extends ProgressBar
## Glossy health/resource bar with a trailing "damage ghost", quarter ticks and a low-value pulse.
## It is still a ProgressBar (value / max_value), only the drawing is custom.

const UIKit = preload("res://scripts/ui/UIKit.gd")

var color := Color("#5b8cff")
var ghost := -1.0
var pulse_below := 0.25 # fraction under which the fill pulses (0 disables)
var show_ticks := true

func _init() -> void:
	# Must happen before the owner assigns `size`, or the default percentage text enforces a taller minimum.
	show_percentage = false
	custom_minimum_size = Vector2.ZERO
	var empty := StyleBoxEmpty.new()
	add_theme_stylebox_override("background", empty)
	add_theme_stylebox_override("fill", empty)

func _process(delta: float) -> void:
	if ghost < 0.0:
		ghost = value
	if ghost > value:
		ghost = maxf(value, ghost - delta * max_value * 0.28)
	else:
		ghost = value
	queue_redraw()

func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var radius := minf(rect.size.y * 0.5, 8.0)
	_rounded(rect, radius, Color("#070b14"))
	_rounded(rect.grow(-0.5), radius, Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.09), 1.0)
	var inner := rect.grow(-2.0)
	var fraction := clampf(value / maxf(max_value, 0.001), 0.0, 1.0)
	var ghost_fraction := clampf(ghost / maxf(max_value, 0.001), 0.0, 1.0)
	if ghost_fraction > fraction + 0.002:
		_rounded(Rect2(inner.position, Vector2(inner.size.x * ghost_fraction, inner.size.y)), radius - 2.0, Color(1.0, 0.92, 0.75, 0.55))
	if fraction > 0.0:
		var width := maxf(inner.size.y, inner.size.x * fraction)
		var fill_rect := Rect2(inner.position, Vector2(width, inner.size.y))
		var tone := color
		if pulse_below > 0.0 and fraction < pulse_below:
			tone = color.lerp(Color.WHITE, 0.25 + 0.25 * sin(Time.get_ticks_msec() / 130.0))
		_rounded(fill_rect, radius - 2.0, tone.darkened(0.25))
		var top_half := Rect2(fill_rect.position, Vector2(fill_rect.size.x, fill_rect.size.y * 0.55))
		_rounded(top_half, radius - 2.0, tone.lightened(0.18))
		draw_line(fill_rect.position + Vector2(radius, 1.5), fill_rect.position + Vector2(fill_rect.size.x - radius, 1.5), Color(1, 1, 1, 0.35), 1.0)
	if show_ticks:
		for i in range(1, 4):
			var x := inner.position.x + inner.size.x * float(i) / 4.0
			draw_line(Vector2(x, inner.position.y + 1), Vector2(x, inner.end.y - 1), Color(0, 0, 0, 0.35), 1.0)

func _rounded(rect: Rect2, radius: float, fill: Color, border: Color = Color(0, 0, 0, 0), border_w: float = 0.0) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.draw_center = fill.a > 0.0
	style.set_corner_radius_all(int(maxf(radius, 0.0)))
	if border_w > 0.0:
		style.border_color = border
		style.set_border_width_all(int(border_w))
	style.anti_aliasing = true
	draw_style_box(style, rect)
