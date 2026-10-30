extends Control
## The main menu's stage: a moonlit valley between two castles, the title carved on a hanging plank, a
## wooden menu board below it and a dragon circling on the right that now and then breathes fire at the
## plank, which catches, chars and slowly cools again. Fills its parent; the menu fills `menu_box`.

const BACKGROUND := preload("res://assets/lobby/lobby_bg.jpg")
const PLANK := preload("res://assets/lobby/lobby_plank.png")
const PANEL := preload("res://assets/lobby/lobby_panel.png")
const DRAGON := preload("res://assets/lobby/lobby_dragon.png")
const UIKit = preload("res://scripts/ui/UIKit.gd")

const PLANK_WIDTH := 520.0
const PANEL_SIZE := Vector2(470, 540)
const DRAGON_WIDTH := 330.0
## The wood inside the board's iron frame, as fractions of the board.
const PANEL_INNER := Rect2(0.1, 0.165, 0.8, 0.69)
## Where the dragon's mouth is in its picture, and where on the plank the fire lands.
const MOUTH := Vector2(0.08, 0.47)
const BURN_ORIGIN := Vector2(0.9, 0.5)
## One breath cycle: wind-up, fire, the plank burning, cooling and the char fading.
const CYCLE := 14.0
const BREATH_START := 1.0
const BREATH_END := 2.8

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

var background: TextureRect
var plank: TextureRect
var title: Label
var panel: TextureRect
## The menu's buttons go here (inside the board's frame).
var menu_box: VBoxContainer
var dragon: Sprite2D
var breath: CPUParticles2D
var flames: CPUParticles2D
var burn_material: ShaderMaterial
var clock := 0.0
## False keeps everything still (tests, the "no battle effects" setting).
var animated := true

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

	dragon = Sprite2D.new()
	dragon.name = "LobbyDragon"
	dragon.texture = DRAGON
	dragon.scale = Vector2.ONE * DRAGON_WIDTH / float(DRAGON.get_width())
	add_child(dragon)

	plank = TextureRect.new()
	plank.name = "TitlePlank"
	plank.texture = PLANK
	plank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plank.stretch_mode = TextureRect.STRETCH_SCALE
	plank.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plank.size = Vector2(PLANK_WIDTH, PLANK_WIDTH * PLANK.get_height() / PLANK.get_width())
	burn_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = BURN_SHADER
	burn_material.shader = shader
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var noise_texture := NoiseTexture2D.new()
	noise_texture.noise = noise
	noise_texture.seamless = true
	noise_texture.width = 256
	noise_texture.height = 128
	burn_material.set_shader_parameter("noise_tex", noise_texture)
	burn_material.set_shader_parameter("origin", BURN_ORIGIN)
	burn_material.set_shader_parameter("aspect", plank.size.x / plank.size.y)
	plank.material = burn_material
	add_child(plank)

	title = Label.new()
	title.name = "GameTitle"
	title.text = "KEEPFALL"
	UIKit.display(title, 64, Color("#f3c56a"))
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
	menu_box.add_theme_constant_override("separation", 8)
	menu_box.position = PANEL_SIZE * PANEL_INNER.position
	menu_box.size = PANEL_SIZE * PANEL_INNER.size
	panel.add_child(menu_box)

static func _fire_particles(amount: int, lifetime: float) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.emitting = false
	particles.local_coords = false
	var glow := GradientTexture2D.new()
	glow.width = 48
	glow.height = 48
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var soft := Gradient.new()
	soft.set_color(0, Color(1, 1, 1, 1))
	soft.set_color(1, Color(1, 1, 1, 0))
	glow.gradient = soft
	particles.texture = glow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.95, 0.7, 0.95))
	ramp.set_color(1, Color(0.25, 0.05, 0.02, 0.0))
	ramp.add_point(0.3, Color(1.0, 0.62, 0.18, 0.9))
	ramp.add_point(0.65, Color(0.85, 0.2, 0.05, 0.55))
	particles.color_ramp = ramp
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	particles.material = additive
	return particles

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_ENTER_TREE:
		_layout()

## Centered on the screen whatever its width: the plank hangs from the top edge, the board under it, the
## dragon to the right of the plank's end.
func _layout() -> void:
	var middle := size.x * 0.5
	plank.position = Vector2(middle - plank.size.x * 0.5, -36.0)
	panel.position = Vector2(middle - PANEL_SIZE.x * 0.5, maxf(160.0, size.y - PANEL_SIZE.y - 18.0) if size.y < 760.0 else 172.0)
	var dragon_size := Vector2(DRAGON.get_size()) * dragon.scale
	var rest := Vector2(plank.position.x + plank.size.x + 20.0 + dragon_size.x * 0.5, 150.0)
	dragon.set_meta("rest", rest)
	dragon.position = rest
	_pose(clock)

func mouth_position() -> Vector2:
	var dragon_size := Vector2(DRAGON.get_size()) * dragon.scale
	var local := (MOUTH - Vector2(0.5, 0.5)) * dragon_size
	return dragon.position + local.rotated(dragon.rotation)

func _process(delta: float) -> void:
	if not animated or not is_visible_in_tree():
		return
	clock = fmod(clock + delta, CYCLE)
	_pose(clock)

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

	# The plank: catches as the fire lands, burns hottest just after, then cools; the char lingers longer.
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
