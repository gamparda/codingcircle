extends Label
## Pill-shaped status text. The pill only exists while there is text, and pops in when it appears.
## Anchored by its centre (or an edge) so the pill hugs the text instead of a fixed box.

const UIKit = preload("res://scripts/ui/UIKit.gd")

var tone := Color("#ff6b81")
var _shown := ""
var _dirty := true

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 15)
	add_theme_color_override("font_color", tone.lightened(0.55))
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)

func _process(_delta: float) -> void:
	if text == _shown and not _dirty:
		return
	var was_empty := _shown.is_empty()
	_shown = text
	_dirty = false
	if text.is_empty():
		add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		return
	add_theme_stylebox_override("normal", UIKit.with_margins(UIKit.box(Color(tone.r, tone.g, tone.b, 0.30).darkened(0.35), Color(0.03, 0.04, 0.08, 0.92), Color(tone.r, tone.g, tone.b, 0.85), 14, 1.0, 0.5, Color(tone.r, tone.g, tone.b, 0.45), 0.08), 18, 6))
	if was_empty:
		scale = Vector2(0.9, 0.9)
		create_tween().tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Re-applies the pill after `tone` changed.
func refresh_style() -> void:
	_dirty = true

## Centre-anchor at (x, y) in the 1280x720 field; width follows the text.
func place_center(x: float, y: float) -> void:
	_place(x, y, Control.GROW_DIRECTION_BOTH)

func place_edge(x: float, y: float, grows_left: bool) -> void:
	_place(x, y, Control.GROW_DIRECTION_BEGIN if grows_left else Control.GROW_DIRECTION_END)

func _place(x: float, y: float, direction: Control.GrowDirection) -> void:
	anchor_left = 0.0
	anchor_right = 0.0
	offset_left = x
	offset_right = x
	offset_top = y
	offset_bottom = y
	grow_horizontal = direction
