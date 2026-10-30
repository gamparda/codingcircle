extends Control
## The main menu's stage: a moonlit valley between two castles, the title carved on a hanging plank, a
## wooden menu board below it and a dragon circling on the right that now and then breathes fire at the
## plank, which catches, sways on its chains, chars and slowly cools again. Clouds drift, stars twinkle,
## castle windows flicker and embers float up. Fills its parent; the menu fills `menu_box`.

const BACKGROUND := preload("res://assets/lobby/lobby_bg.jpg")
const PLANK := preload("res://assets/lobby/lobby_plank.png")
const PANEL := preload("res://assets/lobby/lobby_panel.png")
const DRAGON := preload("res://assets/lobby/lobby_dragon.png")
## The title's lettering: a decorative Roman capital that suits the hanging sign (Latin only).
const TITLE_FONT := preload("res://assets/fonts/CinzelDecorative-Black.ttf")
const UIKit = preload("res://scripts/ui/UIKit.gd")

const PLANK_WIDTH := 520.0
const PANEL_SIZE := Vector2(470, 540)
const DRAGON_WIDTH := 330.0
## The wood inside the board's iron frame, as fractions of the board.
const PANEL_INNER := Rect2(0.1, 0.165, 0.8, 0.69)
## Where the dragon's mouth is in its picture, where on the plank the fire lands, and the plank's lantern.
const MOUTH := Vector2(0.08, 0.47)
const BURN_ORIGIN := Vector2(0.9, 0.5)
const LANTERN := Vector2(0.954, 0.75)
## One board of the plank between its iron bands: the grain behind the menu buttons.
const GRAIN_REGION := Rect2(260, 212, 560, 58)
## One breath cycle: wind-up, fire, the plank burning, cooling and the char fading.
const CYCLE := 14.0
const BREATH_START := 1.0
const BREATH_END := 2.8
## The fire reaches the plank this long after the breath starts and knocks it swinging.
const HIT_DELAY := 0.35
const SWAY_DEGREES := 2.6
const INTRO_SECONDS := 0.9
## Lit windows and torches in the background picture (fractions of it, and a size 1..3), found from its
## bright warm pixels.
const LIGHTS := [[0.8276, 0.5633, 3], [0.098, 0.8081, 2], [0.8904, 0.6031, 3], [0.7554, 0.6981, 1], [0.2216, 0.6596, 1],
	[0.8042, 0.7169, 2], [0.164, 0.6815, 2], [0.8409, 0.3864, 1], [0.8192, 0.5745, 1], [0.7408, 0.6417, 2], [0.9067, 0.7167, 1],
	[0.2786, 0.6619, 1], [0.0444, 0.6273, 2], [0.0501, 0.8049, 2], [0.7792, 0.5057, 1], [0.738, 0.8071, 1], [0.9383, 0.7289, 1],
	[0.8594, 0.627, 2], [0.6841, 0.7165, 1], [0.7539, 0.6359, 1], [0.8211, 0.6633, 1], [0.9149, 0.6893, 1], [0.8903, 0.5684, 1],
	[0.094, 0.6638, 1], [0.7865, 0.7233, 1], [0.9036, 0.4777, 1], [0.8224, 0.5184, 1], [0.2464, 0.5641, 1], [0.7738, 0.667, 1],
	[0.924, 0.685, 1], [0.0786, 0.5932, 1], [0.6839, 0.6835, 1]]
const STARS := 48

const BURN_SHADER := """
shader_type canvas_item;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float burn = 0.0;
uniform float heat = 0.0;
uniform float scorch = 0.0;
uniform vec2 origin = vec2(0.9, 0.5);
uniform float aspect = 2.1;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float n = texture(noise_tex, UV * vec2(2.6, 1.3)).r;
	float d = distance(UV * vec2(aspect, 1.0), origin * vec2(aspect, 1.0)) / aspect + (n - 0.5) * 0.16;
	float inside = smoothstep(burn + 0.02, burn - 0.06, d);
	c.rgb = mix(c.rgb, c.rgb * vec3(0.22, 0.18, 0.16), inside * scorch);
	float flicker = 0.75 + 0.25 * sin(TIME * 21.0 + n * 14.0);
	float rim = smoothstep(0.05, 0.0, abs(d - burn)) * heat * flicker;
	float embers = smoothstep(0.58, 0.78, n) * inside * heat * (0.6 + 0.4 * sin(TIME * 9.0 + n * 30.0));
	c.rgb += vec3(1.0, 0.46, 0.12) * (rim * 1.5 + embers) * c.a;
	COLOR = c;
}
"""

## The title's face: worn gold leaf. Bright along the top of the letters, darkening to old bronze at their
## foot, with a polished band, fine horizontal brush grain and dull worn patches. Positions are the label's own
## pixels; band_top/band_bottom are where the capitals sit in it.
const GILT_SHADER := """
shader_type canvas_item;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float band_top = 0.0;
uniform float band_bottom = 1.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	vec4 glyph = COLOR * texture(TEXTURE, UV);
	float t = clamp((local.y - band_top) / max(band_bottom - band_top, 1.0), 0.0, 1.0);
	vec3 light = vec3(1.0, 0.93, 0.66);
	vec3 gold = vec3(0.93, 0.66, 0.27);
	vec3 bronze = vec3(0.5, 0.29, 0.11);
	vec3 metal = mix(light, gold, smoothstep(0.05, 0.5, t));
	metal = mix(metal, bronze, smoothstep(0.55, 1.0, t));
	metal += vec3(1.0, 0.9, 0.7) * 0.28 * exp(-pow((t - 0.3) * 7.0, 2.0));
	float grain = texture(noise_tex, local * vec2(0.006, 0.12)).r;
	metal *= 0.82 + 0.32 * grain;
	float wear = smoothstep(0.62, 0.8, texture(noise_tex, local * 0.018 + vec2(0.37, 0.11)).r);
	metal = mix(metal, metal * vec3(0.62, 0.5, 0.42), wear * 0.75);
	COLOR = vec4(metal * glyph.rgb, glyph.a);
}
"""

## Thin clouds streaming across the upper sky.
const CLOUD_SHADER := """
shader_type canvas_item;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
void fragment() {
	float a = texture(noise_tex, vec2(UV.x * 0.55 + TIME * 0.006, UV.y * 2.2)).r;
	float b = texture(noise_tex, vec2(UV.x * 1.2 + TIME * 0.011, UV.y * 3.4 + 0.37)).r;
	float cloud = smoothstep(0.55, 0.85, a * 0.65 + b * 0.45);
	float band = smoothstep(0.62, 0.12, UV.y);
	COLOR = vec4(0.8, 0.8, 0.96, cloud * band * 0.17);
}
"""

var background: TextureRect
var clouds: ColorRect
var ambience: Control
var plank: TextureRect
var title: Label
var lantern: Sprite2D
var panel: TextureRect
## The menu's buttons go here (inside the board's frame).
var menu_box: VBoxContainer
var dragon: Sprite2D
var dragon_hitbox: Control
var breath: CPUParticles2D
var flames: CPUParticles2D
var embers: CPUParticles2D
var burn_material: ShaderMaterial
var clock := 0.0
var time := 0.0
## 0 → 1 as the plank drops in and the board rises on opening.
var intro := 0.0
## False keeps everything still (tests, the "battle effects" setting off).
var animated := true:
	set(value):
		animated = value
		if not value:
			intro = 1.0
## Fewer particles and no cloud layer (the low graphics presets).
var low_detail := false:
	set(value):
		low_detail = value
		_apply_detail()
var _stars: Array = []

func _init() -> void:
	name = "LobbyScene"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clock = CYCLE - 2.0 # the first breath comes soon after the menu opens

	background = TextureRect.new()
	background.name = "LobbyBackground"
	background.texture = BACKGROUND
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var noise_texture := _noise(512, 256, 0.012)
	clouds = ColorRect.new()
	clouds.name = "LobbyClouds"
	clouds.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clouds.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cloud_material := ShaderMaterial.new()
	cloud_material.shader = _shader(CLOUD_SHADER)
	cloud_material.set_shader_parameter("noise_tex", noise_texture)
	clouds.material = cloud_material
	add_child(clouds)

	ambience = Control.new()
	ambience.name = "LobbyAmbience"
	ambience.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ambience.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ambience.material = _additive()
	ambience.draw.connect(_draw_ambience)
	add_child(ambience)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261030
	for i in STARS:
		_stars.append([rng.randf(), rng.randf_range(0.02, 0.36), rng.randf_range(0.6, 1.6), rng.randf() * TAU, rng.randf_range(0.6, 2.2)])

	embers = _fire_particles(26, 9.0)
	embers.name = "LobbyEmbers"
	embers.emitting = true
	embers.direction = Vector2(0, -1)
	embers.spread = 25.0
	embers.gravity = Vector2(0, -4)
	embers.initial_velocity_min = 10.0
	embers.initial_velocity_max = 28.0
	embers.scale_amount_min = 0.1
	embers.scale_amount_max = 0.22
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.preprocess = 9.0
	add_child(embers)

	dragon = Sprite2D.new()
	dragon.name = "LobbyDragon"
	dragon.texture = DRAGON
	dragon.scale = Vector2.ONE * DRAGON_WIDTH / float(DRAGON.get_width())
	add_child(dragon)
	dragon_hitbox = Control.new()
	dragon_hitbox.name = "DragonHitbox"
	dragon_hitbox.tooltip_text = ""
	dragon_hitbox.mouse_filter = Control.MOUSE_FILTER_STOP
	dragon_hitbox.gui_input.connect(func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
			breathe_now())
	add_child(dragon_hitbox)

	plank = TextureRect.new()
	plank.name = "TitlePlank"
	plank.texture = PLANK
	plank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plank.stretch_mode = TextureRect.STRETCH_SCALE
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plank.size = Vector2(PLANK_WIDTH, PLANK_WIDTH * PLANK.get_height() / PLANK.get_width())
	plank.pivot_offset = Vector2(plank.size.x * 0.5, 0.0) # hangs from its chains
	burn_material = ShaderMaterial.new()
	burn_material.shader = _shader(BURN_SHADER)
	burn_material.set_shader_parameter("noise_tex", _noise(256, 128, 0.02))
	burn_material.set_shader_parameter("origin", BURN_ORIGIN)
	burn_material.set_shader_parameter("aspect", plank.size.x / plank.size.y)
	plank.material = burn_material
	add_child(plank)
	lantern = Sprite2D.new()
	lantern.name = "LanternGlow"
	lantern.texture = _glow_texture(64)
	lantern.material = _additive()
	lantern.position = plank.size * LANTERN
	lantern.modulate = Color(1.0, 0.62, 0.25, 0.55)
	plank.add_child(lantern)

	title = Label.new()
	title.name = "GameTitle"
	title.text = "KEEPFALL"
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(0, 0, 0, 0)) # the gilt face (TitleFace) fills the letters
	title.add_theme_color_override("font_outline_color", Color("#2a1406"))
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The boards between the chains: about 25%..70% of the picture's height.
	title.position = Vector2(0, plank.size.y * 0.25)
	title.size = Vector2(plank.size.x, plank.size.y * 0.45)
	plank.add_child(title)
	# The letters themselves: the same text on top, without outline, painted by the gilt shader.
	var face := Label.new()
	face.name = "TitleFace"
	face.text = title.text
	face.add_theme_font_override("font", TITLE_FONT)
	face.add_theme_font_size_override("font_size", 58)
	face.add_theme_color_override("font_color", Color.WHITE)
	face.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	face.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gilt := ShaderMaterial.new()
	gilt.shader = _shader(GILT_SHADER)
	gilt.set_shader_parameter("noise_tex", _noise(256, 128, 0.03))
	# Capitals sit from the baseline up about 0.7 em, with the line centered in the label.
	var line_height := TITLE_FONT.get_ascent(58) + TITLE_FONT.get_descent(58)
	var baseline := (title.size.y - line_height) * 0.5 + TITLE_FONT.get_ascent(58)
	gilt.set_shader_parameter("band_top", baseline - 58.0 * 0.72)
	gilt.set_shader_parameter("band_bottom", baseline)
	face.material = gilt
	title.add_child(face)

	flames = _fire_particles(28, 0.7)
	flames.name = "PlankFlames"
	flames.direction = Vector2(0, -1)
	flames.spread = 18.0
	flames.gravity = Vector2(0, -60)
	flames.initial_velocity_min = 20.0
	flames.initial_velocity_max = 55.0
	flames.scale_amount_min = 0.25
	flames.scale_amount_max = 0.55
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	add_child(flames)

	# A dense jet that spreads as it goes and dies out on the plank (lifetime × speed ≈ the distance).
	breath = _fire_particles(220, 0.34)
	breath.name = "DragonBreath"
	breath.spread = 6.0
	breath.gravity = Vector2.ZERO
	breath.initial_velocity_min = 380.0
	breath.initial_velocity_max = 430.0
	breath.scale_amount_min = 0.55
	breath.scale_amount_max = 0.9
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 2.2))
	breath.scale_amount_curve = grow
	add_child(breath)

	panel = TextureRect.new()
	panel.name = "MenuBoard"
	panel.texture = PANEL
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.size = PANEL_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	menu_box = VBoxContainer.new()
	menu_box.name = "MenuColumn"
	menu_box.alignment = BoxContainer.ALIGNMENT_CENTER
	menu_box.add_theme_constant_override("separation", 9)
	menu_box.position = PANEL_SIZE * PANEL_INNER.position
	menu_box.size = PANEL_SIZE * PANEL_INNER.size
	panel.add_child(menu_box)

static func _shader(code: String) -> Shader:
	var shader := Shader.new()
	shader.code = code
	return shader

static func _noise(width: int, height: int, frequency: float) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = frequency
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = width
	texture.height = height
	return texture

static func _additive() -> CanvasItemMaterial:
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return additive

static func _glow_texture(size_px: int) -> GradientTexture2D:
	var glow := GradientTexture2D.new()
	glow.width = size_px
	glow.height = size_px
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = soft
	return glow

static func _fire_particles(amount: int, lifetime: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.local_coords = false
	particles.texture = _glow_texture(48)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 0.95))
	ramp.set_color(1, Color(0.25, 0.05, 0.02, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.62, 0.18, 0.9))
	ramp.add_point(0.65, Color(0.85, 0.2, 0.05, 0.55))
	particles.color_ramp = ramp
	particles.material = _additive()
	return particles

func _apply_detail() -> void:
	breath.amount = 120 if low_detail else 220
	flames.amount = 14 if low_detail else 28
	embers.amount = 10 if low_detail else 26
	clouds.visible = not low_detail

## The main menu's wooden look for a button: a dark wood plate (the plank's grain under a translucent
## face) in an iron rim with rivets; the primary one glows like embers.
static func dress_wood(button: Button, primary: bool = false) -> void:
	var tile := button.has_node("TileRow")
	var rim := Color("#f0a04a") if primary else Color("#8f8170")
	var glow := Color(1.0, 0.55, 0.15, 0.4) if primary else Color(0, 0, 0, 0)
	var face_top := Color(0.36, 0.22, 0.12, 0.72) if primary else Color(0.26, 0.16, 0.09, 0.7)
	var face_bottom := Color(0.2, 0.11, 0.05, 0.86)
	var normal := UIKit.box(face_top, face_bottom, rim, 8, 2.0, 0.6, glow, 0.08)
	var hover := UIKit.box(face_top.lightened(0.14), face_bottom.lightened(0.1), rim.lightened(0.3), 8, 2.0, 0.8, Color(1.0, 0.6, 0.2, 0.45), 0.12)
	var pressed := UIKit.box(face_bottom, face_top.darkened(0.25), rim.darkened(0.1), 8, 2.0, 0.1, Color(0, 0, 0, 0), 0.0)
	var disabled := UIKit.box(Color(0.16, 0.13, 0.11, 0.8), Color(0.11, 0.09, 0.08, 0.9), Color("#4a4038"), 8, 1.5, 0.0, Color(0, 0, 0, 0), 0.0)
	var margin := Vector2(18, 10) if tile else Vector2(10, 6)
	for entry in [["normal", normal], ["hover", hover], ["pressed", pressed], ["hover_pressed", pressed], ["disabled", disabled]]:
		button.add_theme_stylebox_override(entry[0], UIKit.with_margins(entry[1], margin.x, margin.y))
	button.add_theme_color_override("font_color", Color("#f1dcb3"))
	button.add_theme_color_override("font_hover_color", Color("#fff3d6"))
	button.add_theme_color_override("font_pressed_color", Color("#e2c792"))
	button.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.02, 0.9))
	button.add_theme_constant_override("outline_size", 3)
	if tile:
		var heading := button.find_child("Title", true, false) as Label
		if heading != null:
			heading.add_theme_color_override("font_color", Color("#f6d28b"))
			heading.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
			heading.add_theme_constant_override("outline_size", 4)
		var caption := button.find_child("Caption", true, false) as Label
		if caption != null:
			caption.add_theme_color_override("font_color", Color("#d4bc98"))
	var grain := TextureRect.new()
	grain.name = "WoodGrain"
	var atlas := AtlasTexture.new()
	atlas.atlas = PLANK
	atlas.region = GRAIN_REGION
	grain.texture = atlas
	grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	grain.stretch_mode = TextureRect.STRETCH_SCALE
	grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grain.show_behind_parent = true # under the translucent face, so it shows through it
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in [SIDE_LEFT, SIDE_TOP]:
		grain.set_offset(side, 3.0)
	for side in [SIDE_RIGHT, SIDE_BOTTOM]:
		grain.set_offset(side, -3.0)
	button.add_child(grain)
	button.move_child(grain, 0)
	var rivets := Control.new()
	rivets.name = "Rivets"
	rivets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rivets.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rivets.draw.connect(func():
		var inset := 7.0
		for corner in [Vector2(inset, inset), Vector2(rivets.size.x - inset, inset), Vector2(inset, rivets.size.y - inset), Vector2(rivets.size.x - inset, rivets.size.y - inset)]:
			rivets.draw_circle(corner, 2.6, Color("#2a2420"))
			rivets.draw_circle(corner - Vector2(0.6, 0.6), 1.5, Color("#b3a493")))
	button.add_child(rivets)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout()

## Centered on the screen whatever its width: the plank hangs from the top edge, the board under it, the
## dragon to the right of the plank's end.
func _layout() -> void:
	var dragon_size := Vector2(DRAGON.get_size()) * dragon.scale
	var rest := Vector2(size.x * 0.5 + plank.size.x * 0.5 + 20.0 + dragon_size.x * 0.5, 150.0)
	dragon.set_meta("rest", rest)
	dragon_hitbox.size = dragon_size * Vector2(0.75, 0.6)
	dragon_hitbox.position = rest - dragon_hitbox.size * 0.5
	embers.position = Vector2(size.x * 0.5, size.y + 10.0)
	embers.emission_rect_extents = Vector2(size.x * 0.5, 8.0)
	_place()
	_pose(clock)

## The plank and board at their resting places, offset while the intro plays.
func _place() -> void:
	var middle := size.x * 0.5
	var drop := 1.0 - _ease_out_back(intro)
	plank.position = Vector2(middle - plank.size.x * 0.5, -36.0 - 300.0 * drop)
	var board_y := maxf(160.0, size.y - PANEL_SIZE.y - 18.0) if size.y < 760.0 else 172.0
	var rise := 1.0 - _ease_out(clampf(intro * 1.25 - 0.2, 0.0, 1.0))
	panel.position = Vector2(middle - PANEL_SIZE.x * 0.5, board_y + 60.0 * rise)
	panel.modulate.a = 1.0 - rise

static func _ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)

static func _ease_out_back(t: float) -> float:
	var c := 1.4
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)

## The board's resting rectangle (after the intro).
func board_rect() -> Rect2:
	var board_y := maxf(160.0, size.y - PANEL_SIZE.y - 18.0) if size.y < 760.0 else 172.0
	return Rect2(Vector2(size.x * 0.5 - PANEL_SIZE.x * 0.5, board_y), PANEL_SIZE)

func mouth_position() -> Vector2:
	var dragon_size := Vector2(DRAGON.get_size()) * dragon.scale
	var local := (MOUTH - Vector2(0.5, 0.5)) * dragon_size
	return dragon.position + local.rotated(dragon.rotation)

## Clicking the dragon: it breathes right away (unless the plank is still burning).
func breathe_now() -> void:
	if clock >= BREATH_START - 0.5 and clock < 9.0:
		return
	clock = BREATH_START - 0.45

func _process(delta: float) -> void:
	if not animated or not is_visible_in_tree():
		return
	time += delta
	if intro < 1.0:
		intro = minf(1.0, intro + delta / INTRO_SECONDS)
		_place()
	clock = fmod(clock + delta, CYCLE)
	_pose(clock)
	ambience.queue_redraw()

## Everything as a function of the time in the cycle, so the scene can be posed for screenshots and tests.
func _pose(t: float) -> void:
	var rest: Vector2 = dragon.get_meta("rest", dragon.position)
	# Hovering: a slow bob and sway; rearing back just before the breath.
	var rear := smoothstep(0.0, BREATH_START, t) * (1.0 - smoothstep(BREATH_END, BREATH_END + 0.8, t))
	dragon.position = rest + Vector2(14.0 * rear, sin(t * TAU / 3.5) * 8.0 - 10.0 * rear)
	dragon.rotation = deg_to_rad(sin(t * TAU / 7.0) * 2.0 + 5.0 * rear)
	var breathe := 1.0 + 0.012 * sin(t * TAU / 1.6)
	dragon.scale = Vector2(DRAGON_WIDTH / float(DRAGON.get_width()), DRAGON_WIDTH / float(DRAGON.get_width()) * breathe)

	var fire_on := t >= BREATH_START and t < BREATH_END
	breath.position = mouth_position()
	var target := plank.position + plank.size * BURN_ORIGIN
	breath.direction = (target - breath.position).normalized()
	breath.emitting = fire_on and animated

	# The plank: knocked swinging on its chains when the fire lands, catches, burns hottest just after, then
	# cools; the char lingers longer.
	var since_hit := t - BREATH_START - HIT_DELAY
	var swing := SWAY_DEGREES * exp(-since_hit * 0.9) * sin(since_hit * 4.2) if since_hit > 0.0 else 0.0
	plank.rotation = deg_to_rad(swing + sin(t * TAU / 5.0) * 0.35)
	var catch := smoothstep(BREATH_START + 0.25, BREATH_END + 0.6, t)
	var cool := 1.0 - smoothstep(BREATH_END + 1.5, 8.5, t)
	var fade := 1.0 - smoothstep(9.0, 12.5, t)
	var heat := catch * cool
	burn_material.set_shader_parameter("burn", 0.06 + 0.3 * catch)
	burn_material.set_shader_parameter("heat", heat)
	burn_material.set_shader_parameter("scorch", catch * fade)
	flames.emission_rect_extents = Vector2(plank.size.x * (0.02 + 0.22 * catch), plank.size.y * 0.15)
	flames.position = plank.position + plank.size * Vector2(BURN_ORIGIN.x - 0.1 * catch, BURN_ORIGIN.y)
	flames.emitting = heat > 0.25 and animated
	title.modulate = Color(1, 1, 1).lerp(Color(1.25, 0.85, 0.6), heat * 0.6)
	var flicker := 0.5 + 0.25 * sin(t * 13.0) * sin(t * 7.3 + 1.1) + 0.1 * sin(t * 31.0)
	lantern.modulate.a = clampf(flicker + heat * 0.3, 0.2, 1.0)
	lantern.scale = Vector2.ONE * (1.2 + 0.15 * flicker)

## Twinkling stars and flickering windows and torches, placed on the background as it is drawn (cover).
func _draw_ambience() -> void:
	var picture := Vector2(BACKGROUND.get_size())
	var cover := maxf(size.x / picture.x, size.y / picture.y)
	var origin := (size - picture * cover) * 0.5
	for star in _stars:
		var point: Vector2 = origin + Vector2(float(star[0]), float(star[1])) * picture * cover
		var twinkle := 0.35 + 0.65 * (0.5 + 0.5 * sin(time * float(star[4]) + float(star[3])))
		ambience.draw_circle(point, float(star[2]), Color(0.85, 0.88, 1.0, 0.55 * twinkle))
	for index in LIGHTS.size():
		var light: Array = LIGHTS[index]
		var point: Vector2 = origin + Vector2(float(light[0]), float(light[1])) * picture * cover
		var phase := float(index) * 1.7
		var flicker := 0.6 + 0.25 * sin(time * (5.0 + float(index % 4)) + phase) + 0.15 * sin(time * 17.0 + phase * 2.3)
		var radius := (3.0 + 3.0 * float(light[2])) * cover * 1.6
		for ring in 3:
			ambience.draw_circle(point, radius * (1.0 + float(ring) * 0.8), Color(1.0, 0.55, 0.2, 0.09 * flicker / (1.0 + float(ring))))
