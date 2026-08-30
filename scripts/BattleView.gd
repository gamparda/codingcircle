class_name BattleView
extends Control

signal battlefield_clicked(world_x: float)

const BLUE := Color("#5b8cff")
const BLUE_LIGHT := Color("#8fb0ff")
const RED := Color("#ff627d")
const RED_LIGHT := Color("#ff9aad")
const GOLD := Color("#f6c85f")
const INK := Color("#080a10")
const HEAL_PAD_RADIUS := 80.0
const HEAL_PAD_DURATION := 4.0
const UNIT_TEXTURES := {
	"shield": preload("res://assets/units/tanker.png"),
	"healer": preload("res://assets/units/healer.png"),
	"archer": preload("res://assets/units/archer.png"),
	"swordsman": preload("res://assets/units/swordsman.png"),
}
const UNIT_WALK_TEXTURES := {
	"shield": [
		preload("res://assets/units/animations/tanker/walk_0.png"), preload("res://assets/units/animations/tanker/walk_1.png"),
		preload("res://assets/units/animations/tanker/walk_2.png"), preload("res://assets/units/animations/tanker/walk_3.png"),
		preload("res://assets/units/animations/tanker/walk_4.png"), preload("res://assets/units/animations/tanker/walk_5.png"),
	],
	"healer": [
		preload("res://assets/units/animations/healer/walk_0.png"), preload("res://assets/units/animations/healer/walk_1.png"),
		preload("res://assets/units/animations/healer/walk_2.png"), preload("res://assets/units/animations/healer/walk_3.png"),
		preload("res://assets/units/animations/healer/walk_4.png"), preload("res://assets/units/animations/healer/walk_5.png"),
	],
	"archer": [
		preload("res://assets/units/animations/archer/walk_0.png"), preload("res://assets/units/animations/archer/walk_1.png"),
		preload("res://assets/units/animations/archer/walk_2.png"), preload("res://assets/units/animations/archer/walk_3.png"),
		preload("res://assets/units/animations/archer/walk_4.png"), preload("res://assets/units/animations/archer/walk_5.png"),
	],
	"swordsman": [
		preload("res://assets/units/animations/swordsman/walk_0.png"), preload("res://assets/units/animations/swordsman/walk_1.png"),
		preload("res://assets/units/animations/swordsman/walk_2.png"), preload("res://assets/units/animations/swordsman/walk_3.png"),
		preload("res://assets/units/animations/swordsman/walk_4.png"), preload("res://assets/units/animations/swordsman/walk_5.png"),
	],
}
const STARS := [
	Vector2(0.08, 0.16), Vector2(0.15, 0.29), Vector2(0.23, 0.11),
	Vector2(0.34, 0.23), Vector2(0.43, 0.13), Vector2(0.57, 0.21),
	Vector2(0.66, 0.09), Vector2(0.76, 0.25), Vector2(0.87, 0.12),
	Vector2(0.93, 0.31), Vector2(0.49, 0.34), Vector2(0.29, 0.36)
]

var snapshot: Dictionary = {}
var own_side := 0
var selected_structure := ""
var mouse_position := Vector2.ZERO
var animation_time := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func set_snapshot(data: Dictionary) -> void:
	snapshot = data
	queue_redraw()

func _process(delta: float) -> void:
	animation_time += delta
	mouse_position = get_local_mouse_position()
	if not selected_structure.is_empty() or not snapshot.get("units", []).is_empty():
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var world_x: float = event.position.x / max(size.x, 1.0) * 1280.0
		battlefield_clicked.emit(world_x)

func _draw() -> void:
	var scale_x := size.x / 1280.0
	var lane_y := size.y * 0.72
	_draw_sky(lane_y)
	_draw_ground(lane_y)
	_draw_base(90.0 * scale_x, lane_y, 0)
	_draw_base(1190.0 * scale_x, lane_y, 1)

	for structure in snapshot.get("structures", []):
		_draw_structure(structure, scale_x, lane_y)
	for pad in snapshot.get("heal_pads", []):
		_draw_heal_pad(pad, scale_x, lane_y)
	for unit in snapshot.get("units", []):
		_draw_unit(unit, scale_x, lane_y)

	if not selected_structure.is_empty():
		_draw_build_preview(lane_y)

func _draw_sky(lane_y: float) -> void:
	draw_rect(Rect2(0, 0, size.x, lane_y), Color("#090b13"))
	var bands := [Color("#0d1120"), Color("#11182a"), Color("#152039"), Color("#1a2944")]
	for i in bands.size():
		var top := lane_y * float(i) / float(bands.size())
		draw_rect(Rect2(0, top, size.x, lane_y / float(bands.size()) + 1.0), bands[i])

	# Territory lighting keeps the two sides readable without a hard split.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, lane_y), Vector2(size.x * 0.50, lane_y),
		Vector2(size.x * 0.40, 0), Vector2(0, 0)
	]), Color(0.16, 0.28, 0.60, 0.10))
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x, lane_y), Vector2(size.x * 0.50, lane_y),
		Vector2(size.x * 0.60, 0), Vector2(size.x, 0)
	]), Color(0.60, 0.16, 0.28, 0.10))

	for star in STARS:
		var point := Vector2(star.x * size.x, star.y * lane_y)
		draw_circle(point, 1.6, Color(0.80, 0.86, 1.0, 0.62))
		draw_circle(point, 4.5, Color(0.55, 0.66, 1.0, 0.08))

	var moon := Vector2(size.x * 0.5, lane_y * 0.32)
	draw_circle(moon, min(size.x, size.y) * 0.105, Color(0.43, 0.48, 0.72, 0.08))
	draw_circle(moon, min(size.x, size.y) * 0.078, Color(0.58, 0.62, 0.82, 0.10))
	draw_arc(moon, min(size.x, size.y) * 0.105, 0.0, TAU, 64, Color(0.64, 0.70, 1.0, 0.12), 1.0)

	# Distant city silhouettes.
	for i in 18:
		var building_x := float(i) * size.x / 17.0 - 15.0
		var height := 18.0 + float((i * 17) % 44)
		draw_rect(Rect2(building_x, lane_y - height, size.x / 19.0, height), Color("#111827"))
		if i % 3 == 0:
			draw_rect(Rect2(building_x + 9.0, lane_y - height + 10.0, 3.0, 5.0), Color(0.96, 0.78, 0.35, 0.38))

func _draw_ground(lane_y: float) -> void:
	draw_rect(Rect2(0, lane_y, size.x, size.y - lane_y), Color("#10141d"))
	draw_rect(Rect2(0, lane_y, size.x, 4.0), Color("#3d4658"))
	draw_rect(Rect2(0, lane_y + 5.0, size.x, 2.0), Color(0.45, 0.53, 0.70, 0.14))
	for i in 16:
		var x := float(i) * size.x / 15.0
		draw_line(Vector2(x, lane_y + 12.0), Vector2(x - 24.0, size.y), Color(0.42, 0.48, 0.62, 0.10), 1.0)
	draw_rect(Rect2(0, lane_y, size.x * 0.47, size.y - lane_y), Color(0.20, 0.36, 0.75, 0.05))
	draw_rect(Rect2(size.x * 0.53, lane_y, size.x * 0.47, size.y - lane_y), Color(0.80, 0.20, 0.34, 0.05))
	draw_line(Vector2(size.x * 0.5, lane_y - 28.0), Vector2(size.x * 0.5, size.y), Color(0.85, 0.88, 1.0, 0.16), 1.0)
	draw_circle(Vector2(size.x * 0.5, lane_y + 12.0), 5.0, Color("#79839a"))

func _draw_base(x: float, lane_y: float, side: int) -> void:
	var color := BLUE if side == 0 else RED
	var light := BLUE_LIGHT if side == 0 else RED_LIGHT
	var facing := 1.0 if side == 0 else -1.0
	# Soft territory glow.
	draw_circle(Vector2(x, lane_y - 56.0), 82.0, Color(color.r, color.g, color.b, 0.08))
	# Fortress body and feet.
	draw_rect(Rect2(x - 43.0, lane_y - 92.0, 86.0, 92.0), Color("#171d2a"))
	draw_rect(Rect2(x - 43.0, lane_y - 92.0, 5.0, 92.0), color)
	draw_rect(Rect2(x - 54.0, lane_y - 12.0, 108.0, 12.0), Color("#242c3c"))
	# Cat ears make the base silhouette thematic.
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 42.0, lane_y - 92.0), Vector2(x - 27.0, lane_y - 123.0), Vector2(x - 8.0, lane_y - 92.0)
	]), Color("#242c3c"))
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 8.0, lane_y - 92.0), Vector2(x + 27.0, lane_y - 123.0), Vector2(x + 42.0, lane_y - 92.0)
	]), Color("#242c3c"))
	# Face, gate and banner.
	draw_circle(Vector2(x - 15.0, lane_y - 70.0), 3.0, light)
	draw_circle(Vector2(x + 15.0, lane_y - 70.0), 3.0, light)
	draw_line(Vector2(x, lane_y - 61.0), Vector2(x + 7.0 * facing, lane_y - 57.0), light, 2.0)
	draw_arc(Vector2(x, lane_y - 6.0), 22.0, PI, TAU, 20, Color("#090c12"), 10.0)
	draw_line(Vector2(x + 46.0 * facing, lane_y - 108.0), Vector2(x + 46.0 * facing, lane_y - 150.0), Color("#7d879b"), 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x + 46.0 * facing, lane_y - 149.0),
		Vector2(x + 46.0 * facing, lane_y - 132.0),
		Vector2(x + 72.0 * facing, lane_y - 140.0)
	]), color)

func _draw_unit(unit: Dictionary, scale_x: float, lane_y: float) -> void:
	var x := float(unit.x) * scale_x
	var side := int(unit.side)
	var facing := 1.0 if side == 0 else -1.0
	var color := BLUE if side == 0 else RED
	var kind := String(unit.kind)
	var texture: Texture2D = UNIT_TEXTURES.get(kind)
	var walk_frames: Array = UNIT_WALK_TEXTURES.get(kind, [])
	if not walk_frames.is_empty():
		var frame_rate: float = clamp(5.0 + float(unit.speed) / 20.0, 5.0, 10.0)
		var frame_index: int = (int(animation_time * frame_rate) + int(unit.id) * 2) % walk_frames.size()
		texture = walk_frames[frame_index]
	var sprite_height: float = 86.0
	if unit.kind == "shield":
		sprite_height = 92.0
	elif unit.kind == "healer":
		sprite_height = 90.0
	elif unit.kind == "archer":
		sprite_height = 86.0
	var sprite_width: float = sprite_height * float(texture.get_width()) / max(float(texture.get_height()), 1.0)

	# Team halo and contact shadow stay independent from the supplied artwork.
	draw_circle(Vector2(x, lane_y - 38.0), 43.0, Color(color.r, color.g, color.b, 0.08))
	draw_ellipse(Vector2(x, lane_y - 2.0), sprite_width * 0.37, 6.0, Color(0.0, 0.0, 0.0, 0.38))
	draw_set_transform(Vector2(x, lane_y), 0.0, Vector2(facing, 1.0))
	draw_texture_rect(texture, Rect2(-sprite_width * 0.5, -sprite_height, sprite_width, sprite_height), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Small faction pip remains visible when both teams use the same character art.
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 5.0, color)
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 2.0, Color("#f5f7fb"))
	if unit.kind == "healer" and unit.cooldown > unit.interval * 0.70:
		draw_circle(Vector2(x, lane_y - 50.0), 28.0, Color(0.42, 1.0, 0.67, 0.12))
		draw_line(Vector2(x - 6.0, lane_y - 50.0), Vector2(x + 6.0, lane_y - 50.0), Color("#86f7ad"), 3.0)
		draw_line(Vector2(x, lane_y - 56.0), Vector2(x, lane_y - 44.0), Color("#86f7ad"), 3.0)

	var hp_ratio: float = float(unit.hp) / max(float(unit.max_hp), 1.0)
	var bar_y: float = lane_y - 102.0 - float(int(unit.id) % 3) * 6.0
	draw_rect(Rect2(x - 21.0, bar_y, 42.0, 6.0), Color(0.02, 0.03, 0.06, 0.88))
	draw_rect(Rect2(x - 20.0, bar_y + 1.0, 40.0 * hp_ratio, 4.0), Color("#71e49a") if hp_ratio > 0.35 else Color("#ff6b72"))

func _draw_structure(structure: Dictionary, scale_x: float, lane_y: float) -> void:
	var x := float(structure.x) * scale_x
	var side := int(structure.side)
	var color := BLUE if side == 0 else RED
	match String(structure.kind):
		"wall":
			draw_rect(Rect2(x - 22.0, lane_y - 78.0, 44.0, 78.0), Color("#313a4a"))
			draw_rect(Rect2(x - 18.0, lane_y - 73.0, 36.0, 14.0), color.darkened(0.15))
			for i in 3:
				draw_line(Vector2(x - 18.0, lane_y - 51.0 + i * 20.0), Vector2(x + 18.0, lane_y - 51.0 + i * 20.0), Color("#596579"), 2.0)
			draw_circle(Vector2(x, lane_y - 66.0), 4.0, Color("#e8edf5"))
		"jump_pad":
			draw_ellipse(Vector2(x, lane_y - 3.0), 42.0, 9.0, Color(0.0, 0.0, 0.0, 0.35))
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 38.0, lane_y - 5.0), Vector2(x + 38.0, lane_y - 5.0),
				Vector2(x + 27.0, lane_y - 22.0), Vector2(x - 27.0, lane_y - 22.0)
			]), GOLD)
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - 8.0, lane_y - 18.0), Vector2(x + 1.0, lane_y - 35.0), Vector2(x + 10.0, lane_y - 18.0)
			]), Color("#fff0b8"))
		"swamp":
			draw_ellipse(Vector2(x, lane_y - 4.0), 64.0, 16.0, Color("#392f59"))
			draw_ellipse(Vector2(x - 12.0, lane_y - 7.0), 38.0, 8.0, Color("#7256a5"))
			for bubble in [Vector2(-31, -16), Vector2(16, -19), Vector2(35, -12)]:
				draw_circle(Vector2(x, lane_y) + bubble, 4.0, Color(0.62, 0.47, 0.86, 0.56))

func _draw_build_preview(lane_y: float) -> void:
	var world_x: float = mouse_position.x / max(size.x, 1.0) * 1280.0
	var valid: bool = (own_side == 0 and world_x >= 180.0 and world_x <= 600.0) or (own_side == 1 and world_x >= 680.0 and world_x <= 1100.0)

	var build_color := Color(0.30, 0.94, 0.60, 0.24) if valid else Color(1.0, 0.30, 0.40, 0.24)
	draw_circle(Vector2(mouse_position.x, lane_y - 28.0), 42.0, build_color)
	draw_arc(Vector2(mouse_position.x, lane_y - 28.0), 42.0, 0.0, TAU, 40, build_color.lightened(0.45), 2.0)
	draw_line(Vector2(mouse_position.x, lane_y - 70.0), Vector2(mouse_position.x, lane_y + 5.0), build_color.lightened(0.5), 1.0)

func _draw_heal_pad(pad: Dictionary, scale_x: float, lane_y: float, preview: bool = false) -> void:
	var x := float(pad.x) * scale_x
	var side := int(pad.side)
	var color := Color(0.30, 0.94, 0.60, 0.22) if side == 0 else Color(0.98, 0.42, 0.55, 0.20)
	var radius := HEAL_PAD_RADIUS * scale_x
	var remaining: float = float(pad.get("remaining", HEAL_PAD_DURATION))
	var ratio: float = clamp(remaining / HEAL_PAD_DURATION, 0.0, 1.0)
	draw_ellipse(Vector2(x, lane_y - 4.0), radius, radius * 0.22, Color(color.r, color.g, color.b, 0.18))
	draw_arc(Vector2(x, lane_y - 4.0), radius, 0.0, TAU, 48, Color(color.r, color.g, color.b, 0.55), 2.0)
	draw_arc(Vector2(x, lane_y - 4.0), radius * ratio, 0.0, TAU, 48, Color(0.55, 1.0, 0.74, 0.85), 3.0)
	if not preview:
		for i in 3:
			var t := float(i) / 3.0 + (animation_time * 0.25)
			var pulse := (sin(t * TAU) * 0.5 + 0.5) * 0.5 + 0.2
			draw_ellipse(Vector2(x, lane_y - 4.0), radius * pulse, radius * 0.22 * pulse, Color(0.55, 1.0, 0.74, 0.12))

