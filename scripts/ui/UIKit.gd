extends RefCounted
## Cat War look & feel: palette, gradient rounded boxes, the project-wide Theme and small
## interaction helpers. Everything is generated at runtime (no imported art needed) and cached.

# ---------------------------------------------------------------- palette
const BG_DEEP := Color("#070b13")
const BG := Color("#0c1220")
const SURFACE := Color("#121b2d")
const SURFACE_HI := Color("#1a2640")
const EDGE := Color("#2b3d5c")
const EDGE_SOFT := Color("#1f2d46")
const TEXT := Color("#eef2fb")
const TEXT_MUTED := Color("#93a2bd")
const TEXT_DIM := Color("#62708b")
const GOLD := Color("#f4d58d")
const GOLD_DEEP := Color("#c99a3c")
const ACCENT := Color("#6d7cff")
const TEAL := Color("#3ec6b0")
const DANGER := Color("#ff6b81")
const TEAM_BLUE := Color("#5b8cff")
const TEAM_RED := Color("#ff6b81")
const SUCCESS := Color("#6ee7a1")

const UNIT_COLORS := {"shield": Color("#5b8cff"), "swordsman": Color("#f0765f"), "archer": Color("#9b7cf0"),
	"healer": Color("#e6c25e"), "berserker": Color("#ef7a4f"), "warlock": Color("#b57cf0"),
	"necromancer": Color("#8e6fd8"), "skeleton": Color("#b9c2d6")}

static var _cache: Dictionary = {}

# ---------------------------------------------------------------- rounded gradient boxes
## Soft anti-aliased rounded rectangle with a vertical gradient, inner border, top highlight and
## drop shadow, as a 9-sliced StyleBoxTexture. `glow` tints the shadow (e.g. accent buttons).
static func box(top: Color, bottom: Color, border: Color = Color(1, 1, 1, 0.0), radius: int = 10, border_w: float = 1.0,
		shadow: float = 0.0, glow: Color = Color(0, 0, 0, 0), highlight: float = 0.10, pad_override: int = -1) -> StyleBoxTexture:
	var key := "box|%s|%s|%s|%d|%.1f|%.2f|%s|%.2f" % [top.to_html(), bottom.to_html(), border.to_html(), radius, border_w, shadow, glow.to_html(), highlight]
	if _cache.has(key):
		return _cache[key]
	var pad := pad_override if pad_override >= 0 else (10 if shadow > 0.0 else 0)
	var inner := radius * 2 + 4
	var side := inner + pad * 2
	var image := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var half := Vector2(inner, inner) * 0.5
	var center := Vector2(side, side) * 0.5
	var shadow_color := glow if glow.a > 0.0 else Color(0, 0, 0, 0.55)
	for y in side:
		for x in side:
			var p := Vector2(x + 0.5, y + 0.5) - center
			var d := _round_box_distance(p, half, radius)
			var out := Color(0, 0, 0, 0)
			if shadow > 0.0:
				var ds := _round_box_distance(p - Vector2(0, 3), half, radius)
				var falloff := exp(-pow(maxf(ds, 0.0) / (pad * 0.55), 2.0)) if ds > 0.0 else 1.0
				out = Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a * shadow * falloff * 0.9)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if cover > 0.0:
				var t := clampf((p.y + half.y) / maxf(inner, 1.0), 0.0, 1.0)
				var fill := top.lerp(bottom, t)
				if highlight > 0.0 and d < -border_w - 0.2 and d > -border_w - 1.6 and p.y < 0.0:
					fill = fill.lerp(Color(1, 1, 1, fill.a), highlight)
				if border.a > 0.0 and d > -border_w:
					fill = fill.lerp(Color(border.r, border.g, border.b, fill.a), border.a * clampf(d + border_w + 0.5, 0.0, 1.0))
				var a := fill.a * cover
				var out_a := a + out.a * (1.0 - a)
				if out_a > 0.0:
					out = Color((fill.r * a + out.r * out.a * (1.0 - a)) / out_a, (fill.g * a + out.g * out.a * (1.0 - a)) / out_a, (fill.b * a + out.b * out.a * (1.0 - a)) / out_a, out_a)
			image.set_pixel(x, y, out)
	var style := StyleBoxTexture.new()
	style.texture = ImageTexture.create_from_image(image)
	var margin := float(pad + radius + 1)
	style.texture_margin_left = margin
	style.texture_margin_right = margin
	style.texture_margin_top = margin
	style.texture_margin_bottom = margin
	style.expand_margin_left = pad
	style.expand_margin_right = pad
	style.expand_margin_top = pad
	style.expand_margin_bottom = pad
	# Texture margins are only for 9-slicing; content padding is chosen by the caller.
	style.content_margin_left = 0
	style.content_margin_right = 0
	style.content_margin_top = 0
	style.content_margin_bottom = 0
	_cache[key] = style
	return style

static func _round_box_distance(p: Vector2, half: Vector2, radius: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - (half - Vector2(radius, radius))
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius

static func with_margins(style: StyleBox, horizontal: float, vertical: float) -> StyleBox:
	var copy: StyleBox = style.duplicate()
	copy.content_margin_left = horizontal
	copy.content_margin_right = horizontal
	copy.content_margin_top = vertical
	copy.content_margin_bottom = vertical
	return copy

## Card used for panels: dark glassy gradient with a faint tinted border.
static func panel_box(tint: Color = EDGE, radius: int = 14, shadow: float = 0.9) -> StyleBoxTexture:
	return box(SURFACE_HI.lerp(tint, 0.06), SURFACE.darkened(0.12), Color(tint.r, tint.g, tint.b, 0.85), radius, 1.0, shadow, Color(0, 0, 0, 0), 0.07)

# ---------------------------------------------------------------- buttons
## kind: "primary" (filled accent), "secondary" (quiet), "danger". `accent` colors the border/glow.
static func button_styles(accent: Color, primary: bool) -> Dictionary:
	var normal: StyleBox
	var hover: StyleBox
	var pressed: StyleBox
	var disabled: StyleBox
	if primary:
		normal = box(accent.lightened(0.10), accent.darkened(0.28), accent.lightened(0.35), 10, 1.0, 0.55, Color(accent.r, accent.g, accent.b, 0.55), 0.22)
		hover = box(accent.lightened(0.24), accent.darkened(0.12), accent.lightened(0.55), 10, 1.0, 0.85, Color(accent.r, accent.g, accent.b, 0.7), 0.30)
		pressed = box(accent.darkened(0.2), accent.darkened(0.42), accent.lightened(0.15), 10, 1.0, 0.25, Color(accent.r, accent.g, accent.b, 0.4), 0.0)
	else:
		var tint := Color(accent.r, accent.g, accent.b, 0.75)
		normal = box(SURFACE_HI, SURFACE.darkened(0.08), tint, 10, 1.0, 0.4, Color(0, 0, 0, 0), 0.08)
		hover = box(SURFACE_HI.lightened(0.08), SURFACE.lightened(0.04), accent.lightened(0.3), 10, 1.0, 0.6, Color(accent.r, accent.g, accent.b, 0.35), 0.14)
		pressed = box(SURFACE.darkened(0.12), BG_DEEP, accent, 10, 1.0, 0.0, Color(0, 0, 0, 0), 0.0)
	disabled = box(Color("#141c2b"), Color("#0f1623"), Color("#27324a"), 10, 1.0, 0.0, Color(0, 0, 0, 0), 0.0)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = GOLD
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(11)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	return {"normal": with_margins(normal, 16, 8), "hover": with_margins(hover, 16, 8), "pressed": with_margins(pressed, 16, 8), "disabled": with_margins(disabled, 16, 8), "focus": focus}

static func style_button(button: Button, accent: Color, primary: bool = false, font_size: int = 16) -> Button:
	var styles := button_styles(accent, primary)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		button.add_theme_stylebox_override(state, styles[state])
	button.add_theme_stylebox_override("hover_pressed", styles["pressed"])
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", TEXT_DIM)
	button.focus_mode = Control.FOCUS_ALL
	juice(button)
	return button

# ---------------------------------------------------------------- interaction polish
## Hover lift + press squish. Safe to call on any Control; ignores disabled buttons.
static func juice(control: Control, hover_scale: float = 1.025) -> void:
	if control.has_meta("juiced"):
		return
	control.set_meta("juiced", true)
	var update_pivot := func(): control.pivot_offset = control.size * 0.5
	control.resized.connect(update_pivot)
	update_pivot.call()
	var animate := func(target: float, duration: float):
		if not control.is_inside_tree():
			return
		var existing = control.get_meta("juice_tween") if control.has_meta("juice_tween") else null
		if existing is Tween and existing.is_valid():
			existing.kill()
		var tween := control.create_tween()
		tween.tween_property(control, "scale", Vector2(target, target), duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		control.set_meta("juice_tween", tween)
	control.mouse_entered.connect(func():
		if not (control is BaseButton and control.disabled): animate.call(hover_scale, 0.12))
	control.mouse_exited.connect(func(): animate.call(1.0, 0.16))
	if control is BaseButton:
		control.button_down.connect(func(): animate.call(0.97, 0.06))
		control.button_up.connect(func(): animate.call(hover_scale if control.is_hovered() else 1.0, 0.1))

## Fade + slight rise when a screen appears.
static func reveal(node: CanvasItem, duration: float = 0.28, rise: float = 10.0) -> void:
	if not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tween := node.create_tween().set_parallel(true)
	tween.tween_property(node, "modulate:a", 1.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if node is Control and rise != 0.0:
		var control := node as Control
		var rest := control.position
		control.position = rest + Vector2(0, rise)
		tween.tween_property(control, "position", rest, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ---------------------------------------------------------------- procedural icons
static func _circle_icon(diameter: int, fill: Color, ring: Color, ring_w: float) -> ImageTexture:
	var key := "circle|%d|%s|%s|%.1f" % [diameter, fill.to_html(), ring.to_html(), ring_w]
	if _cache.has(key):
		return _cache[key]
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var c := Vector2(diameter, diameter) * 0.5
	var r := diameter * 0.5 - 1.0
	for y in diameter:
		for x in diameter:
			var d := (Vector2(x + 0.5, y + 0.5) - c).length() - r
			var cover := clampf(0.5 - d, 0.0, 1.0)
			var color := fill
			if d > -ring_w:
				color = fill.lerp(ring, clampf(d + ring_w + 0.5, 0.0, 1.0))
			var t := clampf((y + 0.5) / diameter, 0.0, 1.0)
			color = color.lerp(color.darkened(0.18), t * 0.6)
			image.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * cover))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func _switch_icon(on: bool, disabled: bool = false) -> ImageTexture:
	var key := "switch|%s|%s" % [on, disabled]
	if _cache.has(key):
		return _cache[key]
	var w := 48
	var h := 26
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var track := (ACCENT if on else Color("#2a3750")).darkened(0.25 if disabled else 0.0)
	var knob_x := w - 13.0 if on else 13.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d_track := _round_box_distance(p - Vector2(w, h) * 0.5, Vector2(w, h) * 0.5 - Vector2(1, 1), h * 0.5 - 1.0)
			var color := Color(0, 0, 0, 0)
			var cover := clampf(0.5 - d_track, 0.0, 1.0)
			if cover > 0.0:
				var base := track.lerp(track.lightened(0.18), 1.0 - float(y) / h)
				if d_track > -1.2:
					base = base.lerp(Color(1, 1, 1, 1), 0.18)
				color = Color(base.r, base.g, base.b, cover)
			var d_knob := (p - Vector2(knob_x, h * 0.5)).length() - 9.0
			var kc := clampf(0.5 - d_knob, 0.0, 1.0)
			if kc > 0.0:
				var knob := Color("#f4f7ff") if not disabled else Color("#8b95a8")
				color = color.lerp(knob, kc)
				color.a = maxf(color.a, kc)
			image.set_pixel(x, y, color)
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func _check_icon(checked: bool) -> ImageTexture:
	var key := "check|%s" % checked
	if _cache.has(key):
		return _cache[key]
	var s := 22
	var image := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _round_box_distance(p - Vector2(s, s) * 0.5, Vector2(s, s) * 0.5 - Vector2(1, 1), 5.0)
			var cover := clampf(0.5 - d, 0.0, 1.0)
			if cover <= 0.0:
				continue
			var fill := ACCENT if checked else SURFACE_HI
			var color := fill
			if d > -1.4:
				color = fill.lerp(ACCENT.lightened(0.3) if checked else EDGE, 0.9)
			if checked:
				# check mark: two thick segments
				var a := Vector2(6, 11.5)
				var b := Vector2(9.5, 15)
				var c := Vector2(16, 7.5)
				var dist := minf(_segment_distance(p, a, b), _segment_distance(p, b, c))
				color = color.lerp(Color.WHITE, clampf(1.6 - dist, 0.0, 1.0))
			image.set_pixel(x, y, Color(color.r, color.g, color.b, cover))
	var texture := ImageTexture.create_from_image(image)
	_cache[key] = texture
	return texture

static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return (p - (a + ab * t)).length()

# ---------------------------------------------------------------- the Theme
static func build_theme() -> Theme:
	if _cache.has("theme"):
		return _cache["theme"]
	var theme := Theme.new()
	theme.default_font_size = 16

	# Labels & text colours.
	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	# Buttons (the code-built game buttons override per instance; this covers dialogs etc.).
	var styles := button_styles(ACCENT, false)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "Button", styles[state])
	theme.set_stylebox("hover_pressed", "Button", styles["pressed"])
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", TEXT_DIM)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "OptionButton", styles[state])
	theme.set_stylebox("hover_pressed", "OptionButton", styles["pressed"])
	theme.set_color("font_color", "OptionButton", TEXT)
	theme.set_color("font_hover_color", "OptionButton", Color.WHITE)

	# Text fields.
	var field := with_margins(box(Color("#0d1626"), Color("#0a111e"), EDGE, 9, 1.0, 0.0, Color(0, 0, 0, 0), 0.0), 12, 8)
	var field_focus := with_margins(box(Color("#101b30"), Color("#0b1322"), ACCENT.lightened(0.15), 9, 1.5, 0.0, Color(0, 0, 0, 0), 0.0), 12, 8)
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_DIM)
	theme.set_color("caret_color", "LineEdit", GOLD)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45))

	# Popup menus (option button drop-downs).
	var popup := with_margins(box(SURFACE_HI, SURFACE, EDGE, 10, 1.0, 0.8, Color(0, 0, 0, 0), 0.06), 8, 8)
	theme.set_stylebox("panel", "PopupMenu", popup)
	var popup_hover := with_margins(box(ACCENT.darkened(0.2), ACCENT.darkened(0.4), Color(1, 1, 1, 0), 7, 0.0, 0.0, Color(0, 0, 0, 0), 0.1), 10, 6)
	theme.set_stylebox("hover", "PopupMenu", popup_hover)
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	theme.set_constant("v_separation", "PopupMenu", 8)

	# Toggles.
	theme.set_icon("checked", "CheckButton", _switch_icon(true))
	theme.set_icon("unchecked", "CheckButton", _switch_icon(false))
	theme.set_icon("checked_disabled", "CheckButton", _switch_icon(true, true))
	theme.set_icon("unchecked_disabled", "CheckButton", _switch_icon(false, true))
	theme.set_icon("checked_mirrored", "CheckButton", _switch_icon(true))
	theme.set_icon("unchecked_mirrored", "CheckButton", _switch_icon(false))
	theme.set_color("font_color", "CheckButton", TEXT)
	theme.set_color("font_hover_color", "CheckButton", Color.WHITE)
	theme.set_icon("checked", "CheckBox", _check_icon(true))
	theme.set_icon("unchecked", "CheckBox", _check_icon(false))
	theme.set_color("font_color", "CheckBox", TEXT)
	var empty := StyleBoxEmpty.new()
	for kind in ["CheckButton", "CheckBox"]:
		for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
			theme.set_stylebox(state, kind, empty)

	# Sliders.
	var track := StyleBoxFlat.new()
	track.bg_color = Color("#0b1220")
	track.border_color = EDGE_SOFT
	track.set_border_width_all(1)
	track.set_corner_radius_all(6)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 5
	fill.content_margin_bottom = 5
	var fill_hi := fill.duplicate()
	fill_hi.bg_color = ACCENT.lightened(0.18)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	theme.set_icon("grabber", "HSlider", _circle_icon(22, Color("#f4f7ff"), ACCENT.lightened(0.35), 2.5))
	theme.set_icon("grabber_highlight", "HSlider", _circle_icon(24, Color.WHITE, GOLD, 2.5))
	theme.set_icon("grabber_disabled", "HSlider", _circle_icon(22, Color("#7a869c"), Color("#4a5670"), 2.0))
	theme.set_constant("center_grabber", "HSlider", 0)

	# Scroll bars.
	var scroll_bg := StyleBoxFlat.new()
	scroll_bg.bg_color = Color(1, 1, 1, 0.04)
	scroll_bg.set_corner_radius_all(6)
	var scroll_grab := StyleBoxFlat.new()
	scroll_grab.bg_color = Color("#3b4d70")
	scroll_grab.set_corner_radius_all(6)
	var scroll_grab_hi := scroll_grab.duplicate()
	scroll_grab_hi.bg_color = Color("#5668a0")
	for kind in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", kind, scroll_bg)
		theme.set_stylebox("grabber", kind, scroll_grab)
		theme.set_stylebox("grabber_highlight", kind, scroll_grab_hi)
		theme.set_stylebox("grabber_pressed", kind, scroll_grab_hi)

	# Progress bars.
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color("#0a101c")
	bar_bg.border_color = EDGE_SOFT
	bar_bg.set_border_width_all(1)
	bar_bg.set_corner_radius_all(7)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = ACCENT
	bar_fill.set_corner_radius_all(7)
	theme.set_stylebox("background", "ProgressBar", bar_bg)
	theme.set_stylebox("fill", "ProgressBar", bar_fill)
	theme.set_color("font_color", "ProgressBar", TEXT)

	# Separators & panels.
	var line := StyleBoxLine.new()
	line.color = Color(1, 1, 1, 0.08)
	line.thickness = 1
	theme.set_stylebox("separator", "HSeparator", line)
	var vline := StyleBoxLine.new()
	vline.color = Color(1, 1, 1, 0.08)
	vline.thickness = 1
	vline.vertical = true
	theme.set_stylebox("separator", "VSeparator", vline)
	theme.set_stylebox("panel", "PanelContainer", with_margins(panel_box(), 16, 14))
	theme.set_stylebox("panel", "TooltipPanel", with_margins(box(SURFACE_HI, SURFACE, EDGE, 8, 1.0, 0.0, Color(0, 0, 0, 0), 0.0), 10, 6))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_stylebox("panel", "AcceptDialog", with_margins(panel_box(), 18, 16))
	theme.set_stylebox("panel", "Window", with_margins(panel_box(), 18, 16))
	_cache["theme"] = theme
	return theme
