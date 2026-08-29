class_name MenuBackdrop
extends Control

const DOTS := [
	Vector2(0.07, 0.13), Vector2(0.16, 0.35), Vector2(0.24, 0.18),
	Vector2(0.31, 0.72), Vector2(0.42, 0.09), Vector2(0.58, 0.16),
	Vector2(0.69, 0.78), Vector2(0.78, 0.27), Vector2(0.87, 0.11),
	Vector2(0.94, 0.61), Vector2(0.12, 0.84), Vector2(0.83, 0.89)
]

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#08090e"))
	# Sparse technical grid.
	for x in range(0, int(size.x) + 1, 64):
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1.0, 1.0, 1.0, 0.025), 1.0)
	for y in range(0, int(size.y) + 1, 64):
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.025), 1.0)

	# Cool opposing glows hint at the two battle factions.
	draw_circle(Vector2(size.x * 0.12, size.y * 0.46), 340.0, Color(0.20, 0.36, 0.95, 0.045))
	draw_circle(Vector2(size.x * 0.88, size.y * 0.55), 330.0, Color(0.94, 0.20, 0.44, 0.040))
	draw_circle(Vector2(size.x * 0.50, size.y * 0.52), 265.0, Color(0.43, 0.38, 0.95, 0.035))

	for point in DOTS:
		var center := Vector2(point.x * size.x, point.y * size.y)
		draw_circle(center, 2.0, Color(0.72, 0.78, 1.0, 0.44))
		draw_circle(center, 7.0, Color(0.48, 0.56, 1.0, 0.05))

	# Decorative orbit lines around the login card.
	var center := Vector2(size.x * 0.5, size.y * 0.5)
	draw_arc(center, 390.0, -2.7, 0.1, 80, Color(0.46, 0.50, 0.82, 0.10), 1.0)
	draw_arc(center, 430.0, 0.4, 2.6, 80, Color(0.82, 0.38, 0.57, 0.08), 1.0)
