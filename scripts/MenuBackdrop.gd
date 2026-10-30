class_name MenuBackdrop
extends Control
## Animated background of the screens under the main menu: the lobby's valley, dimmed, with drifting embers.

const PARTICLES := 46
const BACKGROUND := preload("res://assets/lobby/lobby_bg.jpg")
const DIM := Color(0.02, 0.03, 0.07, 0.68)

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
	if size.x < 16.0 or size.y < 16.0:
		return
	# The lobby's valley, dimmed so the screen's panels read on it (cover: fills the screen, keeps its shape).
	var picture := Vector2(BACKGROUND.get_size())
	var cover := maxf(size.x / picture.x, size.y / picture.y)
	draw_texture_rect(BACKGROUND, Rect2((size - picture * cover) * 0.5, picture * cover), false)
	draw_rect(Rect2(Vector2.ZERO, size), DIM)

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
