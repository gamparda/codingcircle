class_name MenuBackdrop
extends Control
## Animated menu background: vertical night gradient, faction glows, a faint grid and drifting embers.

const PARTICLES := 46
const TOP := Color("#060a12")
const BOTTOM := Color("#101b36")

var _seeds: Array = []
var _time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261008
	for i in PARTICLES:
		_seeds.append({"x": rng.randf(), "y": rng.randf(), "speed": rng.randf_range(6.0, 22.0), "size": rng.randf_range(1.2, 3.2),
			"phase": rng.randf() * TAU, "warm": rng.randf() < 0.35})

func _process(delta: float) -> void:
	_time += delta
	queue_redraw()

func _draw() -> void:
	# Gradient sky as stacked bands.
	var bands := 36
	for i in bands:
		var t := float(i) / float(bands - 1)
		draw_rect(Rect2(0.0, size.y * float(i) / bands, size.x, size.y / bands + 1.0), TOP.lerp(BOTTOM, t * t))
	for x in range(0, int(size.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1.0, 1.0, 1.0, 0.018), 1.0)
	for y in range(0, int(size.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.018), 1.0)

	# Opposing faction glows (soft radial falloff, slowly breathing).
	var breathe := 1.0 + sin(_time * 0.5) * 0.04
	_glow(Vector2(size.x * 0.10, size.y * 0.62), 520.0 * breathe, Color(0.25, 0.42, 1.0), 0.10)
	_glow(Vector2(size.x * 0.92, size.y * 0.30), 460.0 * breathe, Color(1.0, 0.26, 0.45), 0.08)
	_glow(Vector2(size.x * 0.68, size.y * 0.55), 380.0, Color(0.52, 0.45, 1.0), 0.07)

	# Horizon silhouette of the battlefield skyline.
	var ground := size.y * 0.86
	var points := PackedVector2Array([Vector2(0, size.y), Vector2(0, ground)])
	var x := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	while x < size.x + 40.0:
		var height := rng.randf_range(10.0, 46.0)
		var width := rng.randf_range(28.0, 70.0)
		points.append(Vector2(x, ground - height))
		points.append(Vector2(x + width, ground - height))
		x += width
	points.append(Vector2(size.x, size.y))
	draw_colored_polygon(points, Color(0.02, 0.035, 0.07, 0.85))

	# Embers drifting upward.
	for seed in _seeds:
		var py := fposmod(float(seed.y) * size.y - _time * float(seed.speed), size.y)
		var px := float(seed.x) * size.x + sin(_time * 0.6 + float(seed.phase)) * 14.0
		var twinkle := 0.45 + 0.55 * (0.5 + 0.5 * sin(_time * 1.7 + float(seed.phase)))
		var color := Color(1.0, 0.82, 0.55) if bool(seed.warm) else Color(0.66, 0.74, 1.0)
		draw_circle(Vector2(px, py), float(seed.size) * 3.2, Color(color.r, color.g, color.b, 0.05 * twinkle))
		draw_circle(Vector2(px, py), float(seed.size), Color(color.r, color.g, color.b, 0.55 * twinkle))

	# Vignette.
	for i in 6:
		var inset := float(i) * 18.0
		var alpha := 0.10 * (1.0 - float(i) / 6.0)
		draw_rect(Rect2(inset, inset, size.x - inset * 2.0, size.y - inset * 2.0), Color(0, 0, 0, alpha), false, 18.0)

func _glow(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for i in 14:
		var t := float(i) / 13.0
		draw_circle(center, radius * (1.0 - t * 0.85), Color(color.r, color.g, color.b, strength * 0.07 * (0.3 + t)))
