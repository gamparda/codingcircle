class_name BattleView
extends Control

const Localization = preload("res://scripts/Localization.gd")

signal battlefield_clicked(world_x: float)
signal rage_started(unit_id: int)

const Motion = preload("res://scripts/BattleMotion.gd")

const BLUE := Color("#5b8cff")
const BLUE_LIGHT := Color("#8fb0ff")
const RED := Color("#ff627d")
const RED_LIGHT := Color("#ff9aad")
const GOLD := Color("#f6c85f")
const INK := Color("#080a10")
const UNIT_TEXTURES := {
	"shield": preload("res://assets/units/tanker.png"),
	"healer": preload("res://assets/units/healer.png"),
	"archer": preload("res://assets/units/archer.png"),
	"swordsman": preload("res://assets/units/swordsman.png"),
	"berserker": preload("res://assets/units/berserker.png"),
	"warlock": preload("res://assets/units/warlock.png"),
	"necromancer": preload("res://assets/units/necromancer.png"),
	"skeleton": preload("res://assets/units/skeleton.png"),
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
	"berserker": [preload("res://assets/units/animations/berserker/walk_0.png"), preload("res://assets/units/animations/berserker/walk_1.png"), preload("res://assets/units/animations/berserker/walk_2.png"), preload("res://assets/units/animations/berserker/walk_3.png"), preload("res://assets/units/animations/berserker/walk_4.png"), preload("res://assets/units/animations/berserker/walk_5.png")],
	"warlock": [preload("res://assets/units/animations/warlock/walk_0.png"), preload("res://assets/units/animations/warlock/walk_1.png"), preload("res://assets/units/animations/warlock/walk_2.png"), preload("res://assets/units/animations/warlock/walk_3.png"), preload("res://assets/units/animations/warlock/walk_4.png"), preload("res://assets/units/animations/warlock/walk_5.png")],
	"necromancer": [preload("res://assets/units/animations/necromancer/walk_0.png"), preload("res://assets/units/animations/necromancer/walk_1.png"), preload("res://assets/units/animations/necromancer/walk_2.png"), preload("res://assets/units/animations/necromancer/walk_3.png"), preload("res://assets/units/animations/necromancer/walk_4.png"), preload("res://assets/units/animations/necromancer/walk_5.png")],
	"skeleton": [preload("res://assets/units/animations/skeleton/walk_0.png"), preload("res://assets/units/animations/skeleton/walk_1.png"), preload("res://assets/units/animations/skeleton/walk_2.png"), preload("res://assets/units/animations/skeleton/walk_3.png"), preload("res://assets/units/animations/skeleton/walk_4.png"), preload("res://assets/units/animations/skeleton/walk_5.png")],
}
const UNIT_ATTACK_TEXTURES := {
	"berserker": [preload("res://assets/units/animations/berserker/attack_0.png"), preload("res://assets/units/animations/berserker/attack_1.png"), preload("res://assets/units/animations/berserker/attack_2.png")],
	"warlock": [preload("res://assets/units/animations/warlock/attack_0.png"), preload("res://assets/units/animations/warlock/attack_1.png"), preload("res://assets/units/animations/warlock/attack_2.png")],
	"necromancer": [preload("res://assets/units/animations/necromancer/attack_0.png"), preload("res://assets/units/animations/necromancer/attack_1.png"), preload("res://assets/units/animations/necromancer/attack_2.png")],
	"skeleton": [preload("res://assets/units/animations/skeleton/attack_0.png"), preload("res://assets/units/animations/skeleton/attack_1.png"), preload("res://assets/units/animations/skeleton/attack_2.png")],
}
const UNIT_SUMMON_TEXTURES := [
preload("res://assets/units/animations/necromancer/summon_0.png"), preload("res://assets/units/animations/necromancer/summon_1.png"), preload("res://assets/units/animations/necromancer/summon_2.png")
]
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
var visual_events: Array = []
var damage_lane_cursor := 0
const MAX_VISUAL_EVENTS := 96
var unit_actions: Dictionary = {}
var last_unit_x: Dictionary = {}
var moving_units: Dictionary = {}
var cursed_units: Dictionary = {}
var show_damage_numbers := true
var show_battle_effects := true
var effect_intensity := 0.65
var interpolate_positions := false
var motion = Motion.new()
var snapshot_age := 0.0
var rage_states: Dictionary = {}
var rage_flashes: Dictionary = {}
var walk_times: Dictionary = {}
var touch_preview_active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

func set_snapshot(data: Dictionary) -> void:
	if float(data.get("elapsed", 0.0)) < float(snapshot.get("elapsed", 0.0)):
		unit_actions.clear()
		rage_states.clear()
		rage_flashes.clear()
		walk_times.clear()
		visual_events.clear()
		last_unit_x.clear()
	snapshot = data
	snapshot_age = 0.0
	motion.enabled = interpolate_positions
	motion.ingest(data.get("units", []), float(data.get("elapsed", 0.0)))
	var positions := {}
	var current_rage := {}
	moving_units.clear()
	cursed_units.clear()
	for unit in data.get("units", []):
		positions[unit.id] = float(unit.x)
		var enraged := BattleModel.is_enraged(unit)
		current_rage[unit.id] = enraged
		if enraged and rage_states.has(unit.id) and not rage_states[unit.id]:
			rage_flashes[unit.id] = 0.5
			rage_started.emit(int(unit.id))
		moving_units[unit.id] = last_unit_x.has(unit.id) and absf(float(last_unit_x[unit.id]) - float(unit.x)) > 0.05
		for curse in data.get("curses", []):
			if curse.side != unit.side and absf(float(curse.x) - float(unit.x)) <= BattleModel.CURSE_RADIUS:
				cursed_units[unit.id] = true
	last_unit_x = positions
	rage_states = current_rage
	for id in walk_times.keys():
		if not positions.has(id): walk_times.erase(id)
	for id in unit_actions.keys():
		if not positions.has(id): unit_actions.erase(id)
	queue_redraw()

func push_combat_events(events: Array) -> void:
	for event in events:
		if event is Dictionary:
			var merged := false
			if String(event.get("type",""))=="DAMAGE":
				for existing in visual_events.slice(maxi(0,visual_events.size()-12)):
					if existing.get("type","")=="DAMAGE" and existing.get("target_id",-1)==event.get("target_id",-2) and float(existing.life)>=0.6:
						existing.amount = float(existing.amount)+float(event.get("amount",0.0)); merged = true; break
			if merged: continue
			var visual: Dictionary = event.duplicate(true)
			visual["life"] = 0.45 if String(event.get("type", "")) in ["DEATH", "STRUCTURE_DESTROYED"] else 0.7
			if String(event.get("type","")) in ["DAMAGE","HEAL","BASE_HIT"]:
				visual["text_lane"] = damage_lane_cursor % 4
				damage_lane_cursor += 1
			visual_events.append(visual)
			if visual_events.size()>MAX_VISUAL_EVENTS: visual_events.pop_front()
			if event.get("type") == "SUMMON":
				unit_actions[event.source_id] = {"type": "SUMMON", "started": animation_time}
			elif event.get("type") == "ATTACK" and UNIT_ATTACK_TEXTURES.has(String(event.get("attack_kind", ""))):
				unit_actions[event.attacker_id] = {"type": "ATTACK", "started": animation_time}
	queue_redraw()

func placement_error(kind: String, world_x: float) -> String:
	if not BattleModel.STRUCTURE_STATS.has(kind):
		return Localization.text("설치할 수 없는 구조물입니다.")
	var valid_zone := (own_side == 0 and world_x >= BattleModel.BLUE_BUILD_MIN and world_x <= BattleModel.BLUE_BUILD_MAX) or (own_side == 1 and world_x >= BattleModel.RED_BUILD_MIN and world_x <= BattleModel.RED_BUILD_MAX)
	if not valid_zone:
		return Localization.text("자신의 건설 구역에만 설치할 수 있습니다.")
	if kind == "generator" and not ((own_side == 0 and world_x <= BattleModel.BLUE_REAR_MAX) or (own_side == 1 and world_x >= BattleModel.RED_REAR_MIN)):
		return Localization.text("발전기는 후방에만 설치할 수 있습니다.")
	for structure in snapshot.get("structures", []):
		if int(structure.side) == own_side and float(structure.get("hp", 1.0)) > 0.0 and abs(float(structure.x) - world_x) < BattleModel.STRUCTURE_MIN_SPACING:
			return Localization.text("구조물이 너무 가깝습니다.")
	var owned: Array = snapshot.get("structures", []).filter(func(structure): return int(structure.side) == own_side and float(structure.get("hp", 1.0)) > 0.0)
	if owned.size() >= BattleModel.STRUCTURE_LIMIT:
		return Localization.text("구조물은 최대 3개까지 설치할 수 있습니다.")
	var same_count := owned.filter(func(structure): return String(structure.kind) == kind).size()
	if kind in ["turret", "generator"] and same_count >= 1:
		return (Localization.text("포탑") if kind == "turret" else Localization.text("발전기")) + Localization.text("은 1개만 설치할 수 있습니다.")
	if kind == "wall" and same_count >= 2:
		return Localization.text("방벽은 2개만 설치할 수 있습니다.")
	var resources: Array = snapshot.get("resources", [0.0, 0.0])
	if resources.size() <= own_side or float(resources[own_side]) < float(BattleModel.STRUCTURE_STATS[kind].cost):
		return Localization.text("자원이 부족합니다.")
	return ""

func _process(delta: float) -> void:
	animation_time += delta
	snapshot_age += delta
	motion.advance(delta)
	for unit in snapshot.get("units", []):
		if moving_units.get(unit.id, false):
			walk_times[unit.id] = float(walk_times.get(unit.id, 0.0)) + delta
	for id in rage_flashes.keys():
		rage_flashes[id] = float(rage_flashes[id]) - delta
		if float(rage_flashes[id]) <= 0.0: rage_flashes.erase(id)
	for id in unit_actions.keys():
		if animation_time - float(unit_actions[id].started) >= 0.7:
			unit_actions.erase(id)
	for event in visual_events:
		event.life = float(event.life) - delta
	visual_events = visual_events.filter(func(event): return float(event.life) > 0.0)
	if not touch_preview_active:
		mouse_position = get_local_mouse_position()
	if not selected_structure.is_empty() or not snapshot.get("units", []).is_empty() or not visual_events.is_empty():
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		touch_preview_active = false
		mouse_position = event.position
	elif event is InputEventScreenTouch:
		touch_preview_active = true
		mouse_position = event.position
		if not event.pressed:
			battlefield_clicked.emit(screen_to_world_x(event.position.x))
		if is_inside_tree(): accept_event()
	elif event is InputEventScreenDrag:
		touch_preview_active = true
		mouse_position = event.position
		if is_inside_tree(): accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		mouse_position = event.position
		var world_x: float = screen_to_world_x(event.position.x)
		battlefield_clicked.emit(world_x)
		if is_inside_tree(): accept_event()

func screen_to_world_x(screen_x: float) -> float:
	var x: float = screen_x / maxf(size.x, 1.0) * BattleModel.WORLD_WIDTH
	return BattleModel.WORLD_WIDTH - x if own_side == 1 else x

func world_to_screen_x(world_x: float) -> float:
	var x := BattleModel.WORLD_WIDTH - world_x if own_side == 1 else world_x
	return x / BattleModel.WORLD_WIDTH * size.x

func display_side(world_side: int) -> int:
	return 0 if world_side == own_side else 1

func _draw() -> void:
	var scale_x := size.x / BattleModel.WORLD_WIDTH
	var lane_y := size.y * 0.72
	_draw_sky(lane_y)
	_draw_ground(lane_y)
	_draw_base(world_to_screen_x(BattleModel.FIELD_LEFT), lane_y, display_side(0))
	_draw_base(world_to_screen_x(BattleModel.FIELD_RIGHT), lane_y, display_side(1))

	for curse in snapshot.get("curses", []):
		_draw_curse(curse, scale_x, lane_y)
	for structure in snapshot.get("structures", []):
		_draw_structure(structure, scale_x, lane_y)
	for unit in snapshot.get("units", []):
		_draw_unit(unit, scale_x, lane_y)
	if show_battle_effects or show_damage_numbers:
		_draw_combat_events(scale_x, lane_y)

	if not selected_structure.is_empty():
		_draw_build_preview(lane_y)

func _draw_sky(lane_y: float) -> void:
	var top_color := Color("#070a14")
	var horizon_color := Color("#1d2f52")
	var steps := 40
	for i in steps:
		var t := float(i) / float(steps - 1)
		draw_rect(Rect2(0, lane_y * float(i) / steps, size.x, lane_y / steps + 1.0), top_color.lerp(horizon_color, t * t * 0.95 + t * 0.05))

	# Territory lighting keeps the two sides readable without a hard split.
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, lane_y), Vector2(size.x * 0.50, lane_y),
		Vector2(size.x * 0.40, 0), Vector2(0, 0)
	]), Color(0.16, 0.28, 0.60, 0.10))
	draw_colored_polygon(PackedVector2Array([
		Vector2(size.x, lane_y), Vector2(size.x * 0.50, lane_y),
		Vector2(size.x * 0.60, 0), Vector2(size.x, 0)
	]), Color(0.60, 0.16, 0.28, 0.10))

	var clock := float(Time.get_ticks_msec()) / 1000.0
	for index in STARS.size():
		var star: Vector2 = STARS[index]
		var point := Vector2(star.x * size.x, star.y * lane_y)
		var twinkle := 0.55 + 0.45 * sin(clock * 1.4 + float(index) * 1.7)
		draw_circle(point, 1.5, Color(0.80, 0.86, 1.0, 0.60 * twinkle))
		draw_circle(point, 4.5, Color(0.55, 0.66, 1.0, 0.08 * twinkle))

	var moon := Vector2(size.x * 0.5, lane_y * 0.32)
	var moon_radius := minf(size.x, size.y) * 0.078
	for i in 6:
		draw_circle(moon, moon_radius * (2.4 - float(i) * 0.27), Color(0.55, 0.62, 0.95, 0.018 + float(i) * 0.006))
	draw_circle(moon, moon_radius, Color(0.84, 0.88, 1.0, 0.92))
	draw_circle(moon + Vector2(-moon_radius * 0.28, -moon_radius * 0.12), moon_radius * 0.22, Color(0.72, 0.77, 0.92, 0.55))
	draw_circle(moon + Vector2(moon_radius * 0.30, moon_radius * 0.26), moon_radius * 0.15, Color(0.72, 0.77, 0.92, 0.5))
	draw_circle(moon + Vector2(moon_radius * 0.05, -moon_radius * 0.48), moon_radius * 0.10, Color(0.72, 0.77, 0.92, 0.45))

	# Drifting cloud banks.
	for i in 4:
		var cx := fposmod(float(i) * size.x * 0.31 + clock * (5.0 + float(i) * 2.0), size.x + 400.0) - 200.0
		var cy := lane_y * (0.22 + 0.13 * float(i % 3))
		for puff in 5:
			draw_circle(Vector2(cx + float(puff) * 34.0, cy + sin(float(puff) * 1.9) * 6.0), 30.0 - float(puff % 3) * 6.0, Color(0.5, 0.6, 0.9, 0.035))

	# Haze where the city meets the battlefield.
	for i in 8:
		var t := float(i) / 7.0
		draw_rect(Rect2(0, lane_y - 110.0 + t * 110.0, size.x, 110.0 / 8.0 + 1.0), Color(0.34, 0.42, 0.78, 0.010 + t * 0.020))

	# Distant city: two parallax layers.
	for i in 14:
		var building_x := float(i) * size.x / 13.0 - 30.0
		var height := 40.0 + float((i * 29) % 70)
		draw_rect(Rect2(building_x, lane_y - height, size.x / 13.0 - 6.0, height), Color(0.11, 0.15, 0.27, 0.9))
	for i in 18:
		var building_x := float(i) * size.x / 17.0 - 15.0
		var height := 18.0 + float((i * 17) % 44)
		draw_rect(Rect2(building_x, lane_y - height, size.x / 19.0, height), Color("#0e1524"))
		draw_rect(Rect2(building_x, lane_y - height, size.x / 19.0, 2.0), Color(0.4, 0.5, 0.8, 0.12))
		if i % 3 == 0:
			var lit := 0.30 + 0.20 * sin(clock * 0.7 + float(i))
			draw_rect(Rect2(building_x + 9.0, lane_y - height + 10.0, 3.0, 5.0), Color(0.96, 0.78, 0.35, lit))

func _draw_ground(lane_y: float) -> void:
	var rows := 14
	for i in rows:
		var t := float(i) / float(rows - 1)
		draw_rect(Rect2(0, lane_y + (size.y - lane_y) * float(i) / rows, size.x, (size.y - lane_y) / rows + 1.0), Color("#141b2b").lerp(Color("#080b13"), t))
	# Team-tinted build zones fade toward the centre.
	for i in 10:
		var t := float(i) / 9.0
		var w := size.x * 0.47 * (1.0 - t * 0.85)
		draw_rect(Rect2(0, lane_y, w, size.y - lane_y), Color(0.20, 0.36, 0.85, 0.012 + t * 0.010))
		draw_rect(Rect2(size.x - w, lane_y, w, size.y - lane_y), Color(0.90, 0.22, 0.38, 0.012 + t * 0.010))
	# Lane edge glows blue to red.
	var segments := 64
	for i in segments:
		var t := float(i) / float(segments - 1)
		var color := BLUE.lerp(RED, smoothstep(0.35, 0.65, t))
		var x0 := size.x * float(i) / segments
		draw_rect(Rect2(x0, lane_y, size.x / segments + 1.0, 3.0), Color(color.r, color.g, color.b, 0.55))
		draw_rect(Rect2(x0, lane_y + 3.0, size.x / segments + 1.0, 14.0), Color(color.r, color.g, color.b, 0.05))
	draw_rect(Rect2(0, lane_y - 1.0, size.x, 1.0), Color(1, 1, 1, 0.10))
	for i in 16:
		var x := float(i) * size.x / 15.0
		draw_line(Vector2(x, lane_y + 16.0), Vector2(x - 40.0, size.y), Color(0.42, 0.50, 0.70, 0.09), 1.0)
	for j in 4:
		var y := lane_y + 24.0 + float(j) * float(j) * 9.0 + float(j) * 12.0
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(0.42, 0.50, 0.70, 0.05), 1.0)
	draw_line(Vector2(size.x * 0.5, lane_y - 28.0), Vector2(size.x * 0.5, size.y), Color(0.85, 0.88, 1.0, 0.14), 1.0)
	draw_circle(Vector2(size.x * 0.5, lane_y + 12.0), 7.0, Color(0.5, 0.56, 0.78, 0.35))
	draw_circle(Vector2(size.x * 0.5, lane_y + 12.0), 4.0, Color("#aab4d2"))

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
	var x := world_to_screen_x(motion.position(int(unit.id), float(unit.x)))
	var side := display_side(int(unit.side))
	var facing := 1.0 if side == 0 else -1.0
	var color := BLUE if side == 0 else RED
	var kind := String(unit.kind)
	var texture: Texture2D = UNIT_TEXTURES.get(kind)
	var walk_frames: Array = UNIT_WALK_TEXTURES.get(kind, [])
	if not walk_frames.is_empty():
		var frame_rate: float = clamp(5.0 + float(unit.speed) / 20.0, 5.0, 10.0)
		if UNIT_ATTACK_TEXTURES.has(kind):
			frame_rate = clampf(float(unit.speed) / 8.0, 4.0, 6.0)
		var frame_index: int = (int(float(walk_times.get(unit.id, 0.0)) * frame_rate) + int(unit.id) * 2) % walk_frames.size()
		texture = walk_frames[frame_index]
	var walk_texture := texture
	var action_blend := 0.0
	if unit_actions.has(unit.id) and UNIT_ATTACK_TEXTURES.has(kind):
		var action: Dictionary = unit_actions[unit.id]
		var frames: Array = UNIT_SUMMON_TEXTURES if action.type == "SUMMON" and kind == "necromancer" else UNIT_ATTACK_TEXTURES[kind]
		var index := clampi(int((animation_time - float(action.started)) / 0.7 * frames.size()), 0, frames.size() - 1)
		texture = frames[index]
		action_blend = action_opacity(animation_time - float(action.started))
	var sprite_height: float = 86.0
	if unit.kind == "shield":
		sprite_height = 92.0
	elif unit.kind == "healer":
		sprite_height = 90.0
	elif unit.kind == "archer":
		sprite_height = 86.0
	if UNIT_ATTACK_TEXTURES.has(kind):
		sprite_height *= float(texture.get_height()) / float(UNIT_TEXTURES[kind].get_height())
	var sprite_width: float = sprite_height * float(texture.get_width()) / max(float(texture.get_height()), 1.0)

	# Team halo and contact shadow stay independent from the supplied artwork.
	draw_circle(Vector2(x, lane_y - 38.0), 43.0, Color(color.r, color.g, color.b, 0.08))
	draw_ellipse(Vector2(x, lane_y - 2.0), sprite_width * 0.37, 6.0, Color(0.0, 0.0, 0.0, 0.38))
	draw_set_transform(Vector2(x, lane_y), 0.0, Vector2(facing, 1.0))
	var tint := Color.WHITE.lerp(Color("#ffb37a"), 0.25) if BattleModel.is_enraged(unit) else Color.WHITE
	if texture != walk_texture and action_blend < 1.0:
		var walk_height := 86.0 * float(walk_texture.get_height()) / float(UNIT_TEXTURES[kind].get_height())
		var walk_width := walk_height * float(walk_texture.get_width()) / float(walk_texture.get_height())
		draw_texture_rect(walk_texture, Rect2(-walk_width * 0.5, -walk_height, walk_width, walk_height), false, Color(tint.r, tint.g, tint.b, 1.0-action_blend))
	draw_texture_rect(texture, Rect2(-sprite_width * 0.5, -sprite_height, sprite_width, sprite_height), false, Color(tint.r, tint.g, tint.b, action_blend if texture != walk_texture else 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Small faction pip remains visible when both teams use the same character art.
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 5.0, color)
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 2.0, Color("#f5f7fb"))
	if unit.kind == "healer" and unit.cooldown > unit.interval * 0.70:
		draw_circle(Vector2(x, lane_y - 50.0), 28.0, Color(0.42, 1.0, 0.67, 0.12))
		draw_string(ThemeDB.fallback_font, Vector2(x - 8.0, lane_y - 46.0), "▲", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("#86f7ad"))

	var hp_ratio: float = float(unit.hp) / max(float(unit.max_hp), 1.0)
	var bar_y: float = lane_y - 102.0 - float(int(unit.id) % 3) * 6.0
	_draw_unit_bar(Rect2(x - 22.0, bar_y, 44.0, 7.0), hp_ratio, color)
	if show_battle_effects and rage_flashes.has(unit.id):
		draw_arc(Vector2(x, lane_y - 43.0), 42.0, 0.0, TAU, 24, Color(1.0, 0.48, 0.20, float(rage_flashes[unit.id]) * effect_intensity), 3.0)
	if kind == "necromancer" and unit.has("summon_remaining"):
		var remaining := maxf(0.0, float(unit.summon_remaining) - minf(snapshot_age, 0.25))
		draw_rect(Rect2(x - 20.0, bar_y + 16.0, 40.0, 3.0), Color("#242038"))
		draw_rect(Rect2(x - 20.0, bar_y + 16.0, 40.0 * (1.0 - remaining / BattleModel.SUMMON_INTERVAL), 3.0), Color("#b591ef"))
	if BattleModel.is_enraged(unit):
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 18.0), "광폭", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff9a61"))
	if cursed_units.has(unit.id):
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 4.0), "▼30%", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c592ff"))
	if show_battle_effects and kind != "healer":
		var stacks := int(unit.get("support_stacks", 0))
		if stacks > 0:
			for dot in BattleModel.SUPPORT_MAX_STACKS:
				draw_circle(Vector2(x - 18.0 + dot * 4.0, bar_y + 10.0), 1.3, Color("#86f7ad") if dot < stacks else Color("#293d39"))
			draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - (32.0 if cursed_units.has(unit.id) else 4.0)), "▲%d%%" % (mini(stacks, 10) * 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#86f7ad"))

func _draw_unit_bar(rect: Rect2, ratio: float, team: Color) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.02, 0.03, 0.06, 0.92)
	back.border_color = Color(team.r, team.g, team.b, 0.75)
	back.set_border_width_all(1)
	back.set_corner_radius_all(4)
	back.anti_aliasing = true
	draw_style_box(back, rect)
	if ratio <= 0.0:
		return
	var tone := Color("#6ee7a1") if ratio > 0.35 else Color("#ff6b81")
	var inner := rect.grow(-1.5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = tone.darkened(0.2)
	fill.set_corner_radius_all(3)
	fill.anti_aliasing = true
	draw_style_box(fill, Rect2(inner.position, Vector2(maxf(inner.size.y, inner.size.x * ratio), inner.size.y)))
	draw_rect(Rect2(inner.position + Vector2(1.5, 0.0), Vector2(maxf(0.0, inner.size.x * ratio - 3.0), inner.size.y * 0.45)), Color(1, 1, 1, 0.28))

func _draw_curse(curse: Dictionary, scale_x: float, lane_y: float) -> void:
	var x := world_to_screen_x(float(curse.x))
	var radius := BattleModel.CURSE_RADIUS * scale_x
	var team := BLUE if display_side(int(curse.side)) == 0 else RED
	draw_ellipse(Vector2(x, lane_y - 2.0), radius, 11.0, Color(0.43, 0.18, 0.66, 0.58))
	draw_arc(Vector2(x, lane_y - 3.0), radius, PI, TAU, 20, Color("#b483ef"), 2.0)
	draw_circle(Vector2(x, lane_y + 3.0), 3.0, team)
	var remaining := effect_remaining(curse)
	draw_rect(Rect2(x - radius, lane_y + 12.0, radius * 2.0 * remaining / BattleModel.CURSE_DURATION, 3.0), Color("#b483ef"))
	draw_string(ThemeDB.fallback_font, Vector2(x - 13.0, lane_y + 30.0), "%.1fs" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8a9ef"))

static func action_opacity(age: float) -> float:
	return minf(clampf(age / 0.10, 0.0, 1.0), clampf((0.7 - age) / 0.10, 0.0, 1.0))

func effect_remaining(effect: Dictionary) -> float:
	return maxf(0.0, float(effect.get("expires_at", 0.0)) - float(snapshot.get("elapsed", 0.0)) - minf(snapshot_age, 0.25))

func _draw_structure(structure: Dictionary, scale_x: float, lane_y: float) -> void:
	var x := world_to_screen_x(float(structure.x))
	var side := display_side(int(structure.side))
	var color := BLUE if side == 0 else RED
	match String(structure.kind):
		"wall":
			draw_rect(Rect2(x - 22.0, lane_y - 78.0, 44.0, 78.0), Color("#313a4a"))
			draw_rect(Rect2(x - 18.0, lane_y - 73.0, 36.0, 14.0), color.darkened(0.15))
			for i in 3:
				draw_line(Vector2(x - 18.0, lane_y - 51.0 + i * 20.0), Vector2(x + 18.0, lane_y - 51.0 + i * 20.0), Color("#596579"), 2.0)
			draw_circle(Vector2(x, lane_y - 66.0), 4.0, Color("#e8edf5"))
		"swamp":
			draw_circle(Vector2(x, lane_y - 4.0), float(BattleModel.STRUCTURE_STATS.swamp.radius) * scale_x, Color(0.42, 0.28, 0.70, 0.10))
			draw_arc(Vector2(x, lane_y - 4.0), float(BattleModel.STRUCTURE_STATS.swamp.radius) * scale_x, 0.0, TAU, 48, Color(0.62, 0.47, 0.86, 0.35), 1.0)
			draw_ellipse(Vector2(x, lane_y - 4.0), 64.0, 16.0, Color("#392f59"))
			draw_ellipse(Vector2(x - 12.0, lane_y - 7.0), 38.0, 8.0, Color("#7256a5"))
			for bubble in [Vector2(-31, -16), Vector2(16, -19), Vector2(35, -12)]:
				draw_circle(Vector2(x, lane_y) + bubble, 4.0, Color(0.62, 0.47, 0.86, 0.56))
		"turret":
			draw_rect(Rect2(x - 24.0, lane_y - 38.0, 48.0, 38.0), Color("#303847"))
			draw_circle(Vector2(x, lane_y - 43.0), 20.0, color.darkened(0.18))
			var facing := 1.0 if side == 0 else -1.0
			draw_line(Vector2(x, lane_y - 45.0), Vector2(x + 38.0 * facing, lane_y - 52.0), Color("#e8edf5"), 7.0)
			if fmod(animation_time, 1.5) < 0.16:
				draw_circle(Vector2(x + 41.0 * facing, lane_y - 53.0), 8.0, Color("#ffd36a"))
		"generator":
			draw_rect(Rect2(x - 27.0, lane_y - 58.0, 54.0, 58.0), Color("#263d3b"))
			draw_rect(Rect2(x - 20.0, lane_y - 50.0, 40.0, 32.0), Color("#3d8f83"))
			var pulse := 5.0 + sin(animation_time * 4.0) * 2.0
			draw_circle(Vector2(x, lane_y - 34.0), pulse, Color("#8dffd8"))
			draw_line(Vector2(x, lane_y - 58.0), Vector2(x, lane_y - 78.0), Color("#8dffd8"), 2.0)
	if structure.kind == "swamp" and structure.has("expires_at"):
		var remaining := effect_remaining(structure)
		draw_rect(Rect2(x - 35.0, lane_y + 17.0, 70.0 * remaining / float(BattleModel.STRUCTURE_STATS.swamp.lifetime), 3.0), Color("#b094de"))
		draw_string(ThemeDB.fallback_font, Vector2(x - 13.0, lane_y + 34.0), "%.1fs" % remaining, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("#c8a9ef"))

func _draw_combat_events(scale_x: float, lane_y: float) -> void:
	for event in visual_events:
		var event_type := String(event.get("type", ""))
		var x := world_to_screen_x(float(event.get("x", 640.0)))
		var life := float(event.life)
		if show_battle_effects:
			if event_type in ["ATTACK", "DAMAGE", "BASE_HIT"]:
				draw_circle(Vector2(x, lane_y - 55.0), 9.0 + life * 10.0, Color(1.0, 0.72, 0.28, life * effect_intensity))
			elif event_type in ["CURSE", "SUMMON"]:
				draw_circle(Vector2(x, lane_y - 28.0), 22.0, Color(0.66, 0.28, 1.0, life * effect_intensity))
			elif event_type == "SUPPORT_BUFF":
				draw_circle(Vector2(x, lane_y - 60.0), 18.0, Color(0.35, 1.0, 0.58, life * effect_intensity))
			elif event_type in ["DEATH", "STRUCTURE_DESTROYED"]:
				draw_circle(Vector2(x, lane_y - 35.0), 32.0 * (1.0 - life), Color(0.8, 0.84, 0.92, life * effect_intensity))
			elif event_type == "JUMP":
				draw_arc(Vector2(x, lane_y - 28.0), 34.0, PI, TAU, 24, Color(1.0, 0.82, 0.32, life), 4.0)
		if show_damage_numbers and event_type in ["DAMAGE", "HEAL", "BASE_HIT"]:
			var amount := int(event.get("amount", 0))
			var text := "+%d" % amount if event_type == "HEAL" else "-%d" % amount
			var color := Color("#75f0a4") if event_type == "HEAL" else Color("#ff8a96")
			draw_string(ThemeDB.fallback_font, Vector2(x - 14.0 + (float(event.get("text_lane",0))-1.5)*8.0, lane_y - 95.0 - float(event.get("text_lane",0))*20.0 - (0.7 - life) * 34.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, color)

func build_preview(world_x: float) -> Dictionary:
	var kind := selected_structure
	var lower := BattleModel.BLUE_BUILD_MIN if own_side == 0 else BattleModel.RED_BUILD_MIN
	var upper := BattleModel.BLUE_BUILD_MAX if own_side == 0 else BattleModel.RED_BUILD_MAX
	if kind == "generator":
		if own_side == 0: upper = BattleModel.BLUE_REAR_MAX
		else: lower = BattleModel.RED_REAR_MIN
	var stats: Dictionary = BattleModel.STRUCTURE_STATS.get(kind, {})
	return {"error": placement_error(kind, world_x), "lower": lower, "upper": upper,
		"radius": float(stats.get("radius", stats.get("range", 0.0))), "x": world_x}

func _draw_build_preview(lane_y: float) -> void:
	var preview := build_preview(screen_to_world_x(mouse_position.x))
	var valid: bool = preview.error.is_empty()
	var build_color := Color(0.30, 0.94, 0.60, 0.24) if valid else Color(1.0, 0.30, 0.40, 0.24)
	var left := world_to_screen_x(float(preview.lower))
	var right := world_to_screen_x(float(preview.upper))
	draw_rect(Rect2(minf(left, right), lane_y - 9.0, absf(right-left), 32.0), Color(0.30, 0.94, 0.60, 0.10))
	draw_line(Vector2(left,lane_y-8.0), Vector2(left,lane_y+24.0), Color("#86f7ad"), 2.0)
	draw_line(Vector2(right,lane_y-8.0), Vector2(right,lane_y+24.0), Color("#86f7ad"), 2.0)
	var radius := float(preview.radius) / BattleModel.WORLD_WIDTH * size.x
	if radius > 0.0:
		draw_ellipse(Vector2(mouse_position.x, lane_y), radius, 21.0, build_color)
		draw_line(Vector2(mouse_position.x-radius,lane_y+4.0), Vector2(mouse_position.x+radius,lane_y+4.0), build_color.lightened(0.4), 2.0)
	draw_rect(Rect2(mouse_position.x-23.0,lane_y-60.0,46.0,60.0), build_color)
	draw_rect(Rect2(mouse_position.x-23.0,lane_y-60.0,46.0,60.0), build_color.lightened(0.4), false, 2.0)
	if not valid:
		var label_x := clampf(mouse_position.x-150.0, 12.0, maxf(12.0,size.x-320.0))
		draw_string(ThemeDB.fallback_font, Vector2(label_x,minf(lane_y+56.0,size.y-12.0)), String(preview.error), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff8a96"))
