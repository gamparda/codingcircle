extends Control
## Main-menu hero stage: cycles through the roster with a glow, floating sprite, role line and
## live stat chips read from the unit data. Click to skip ahead.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const Localization = preload("res://scripts/Localization.gd")

const ORDER := ["shield", "archer", "berserker", "healer", "warlock", "swordsman", "necromancer"]
const TEXTURES := {"shield": "tanker", "swordsman": "swordsman", "archer": "archer", "healer": "healer",
	"berserker": "berserker", "warlock": "warlock", "necromancer": "necromancer"}
const ROLES := {
	"shield": "전열을 지키는 든든한 방패", "swordsman": "균형 잡힌 근접 전사", "archer": "먼 거리에서 쏘아 맞히는 사수",
	"healer": "아군의 공격 속도를 끌어올리는 지원가", "berserker": "상처 입을수록 사나워지는 돌격수",
	"warlock": "저주 장판으로 적을 약화시키는 술사", "necromancer": "해골 병사를 불러내는 흑마법사",
}
const INTERVAL := 3.6

var index := 0
var clock := 0.0
var sprite: TextureRect
var glow: Control
var name_label: Label
var role_label: Label
var chips: HBoxContainer
var dots: HBoxContainer
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(560, 560)
	glow = Control.new()
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(_draw_glow)
	add_child(glow)
	sprite = TextureRect.new()
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(sprite)
	name_label = Label.new()
	name_label.name = "HeroName"
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", UIKit.TEXT)
	name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	name_label.add_theme_constant_override("outline_size", 6)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(name_label)
	role_label = Label.new()
	role_label.add_theme_font_size_override("font_size", 16)
	role_label.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(role_label)
	chips = HBoxContainer.new()
	chips.add_theme_constant_override("separation", 10)
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(chips)
	dots = HBoxContainer.new()
	dots.add_theme_constant_override("separation", 8)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dots)
	resized.connect(_layout)
	_layout()
	_show_unit(0, false)

func _layout() -> void:
	var w := size.x
	glow.position = Vector2.ZERO
	glow.size = size
	sprite.size = Vector2(300, 330)
	sprite.position = Vector2((w - 300.0) * 0.5, 40)
	sprite.pivot_offset = sprite.size * 0.5
	name_label.position = Vector2(0, 392)
	name_label.size = Vector2(w, 54)
	role_label.position = Vector2(0, 446)
	role_label.size = Vector2(w, 26)
	chips.position = Vector2(0, 486)
	chips.size = Vector2(w, 36)
	dots.position = Vector2(0, 536)
	dots.size = Vector2(w, 14)

func _process(delta: float) -> void:
	clock += delta
	if clock >= INTERVAL:
		clock = 0.0
		_show_unit((index + 1) % ORDER.size(), true)
	var bob := sin(Time.get_ticks_msec() / 520.0) * 7.0
	sprite.position.y = 40.0 + bob
	glow.queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clock = 0.0
		_show_unit((index + 1) % ORDER.size(), true)

func _unit_color() -> Color:
	return UIKit.UNIT_COLORS.get(ORDER[index], UIKit.ACCENT)

func _draw_glow() -> void:
	var color := _unit_color()
	var center := Vector2(size.x * 0.5, 205.0)
	for i in 9:
		var t := float(i) / 8.0
		glow.draw_circle(center, 235.0 - t * 150.0, Color(color.r, color.g, color.b, 0.035 + t * 0.06))
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 700.0) * 0.03
	glow.draw_arc(center, 196.0 * pulse, 0.0, TAU, 96, Color(color.r, color.g, color.b, 0.35), 2.0, true)
	glow.draw_arc(center, 226.0 * pulse, 0.6, 3.2, 64, Color(1, 1, 1, 0.10), 1.5, true)
	# ground shadow
	var shadow_center := Vector2(size.x * 0.5, 372.0)
	for i in 5:
		var t := float(i) / 4.0
		_draw_ellipse(shadow_center, Vector2(120.0 - t * 60.0, 14.0 - t * 6.0), Color(0, 0, 0, 0.12 + t * 0.12))

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	glow.draw_colored_polygon(points, color)

func _show_unit(new_index: int, animate: bool) -> void:
	index = new_index
	var kind: String = ORDER[index]
	var color := _unit_color()
	sprite.texture = load("res://assets/units/%s.png" % TEXTURES[kind])
	name_label.text = Localization.text(String(BattleModel.UNIT_NAMES[kind]))
	name_label.add_theme_color_override("font_color", color.lightened(0.45))
	role_label.text = Localization.text(String(ROLES[kind]))
	for child in chips.get_children():
		chips.remove_child(child)
		child.queue_free()
	var stats: Dictionary = BattleModel.UNIT_STATS[kind]
	for entry in [["비용", stats.cost], ["체력", stats.hp], ["공격", stats.damage], ["사거리", stats.range]]:
		if kind == "healer" and entry[0] == "공격":
			continue
		chips.add_child(_chip(String(entry[0]), str(int(entry[1])), color))
	for child in dots.get_children():
		dots.remove_child(child)
		child.queue_free()
	for i in ORDER.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(26 if i == index else 8, 8)
		var style := StyleBoxFlat.new()
		style.bg_color = color if i == index else Color(1, 1, 1, 0.18)
		style.set_corner_radius_all(4)
		dot.add_theme_stylebox_override("panel", style)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dots.add_child(dot)
	if animate and is_inside_tree():
		if _tween and _tween.is_valid():
			_tween.kill()
		_tween = create_tween().set_parallel(true)
		for node in [sprite, name_label, role_label, chips]:
			node.modulate.a = 0.0
			_tween.tween_property(node, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		sprite.scale = Vector2(0.86, 0.86)
		_tween.tween_property(sprite, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _chip(caption: String, value: String, color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(color.r, color.g, color.b, 0.7), 9, 1.0, 0.0, Color(0, 0, 0, 0), 0.08), 12, 5))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)
	var cap := Label.new()
	cap.text = Localization.text(caption)
	cap.add_theme_font_size_override("font_size", 13)
	cap.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	row.add_child(cap)
	var val := Label.new()
	val.text = value
	val.add_theme_font_size_override("font_size", 16)
	val.add_theme_color_override("font_color", color.lightened(0.5))
	row.add_child(val)
	return panel
