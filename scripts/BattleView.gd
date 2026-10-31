class_name BattleView
extends Control

const Localization = preload("res://scripts/Localization.gd")
const StructureLifetime = preload("res://scripts/ui/StructureLifetime.gd")
const StructureInspection = preload("res://scripts/ui/StructureInspection.gd")

signal battlefield_clicked(world_x: float)
signal build_touch_cancelled
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
	"zombie": preload("res://assets/units/zombie.png"),
	"paladin": preload("res://assets/units/paladin.png"),
	"sniper": preload("res://assets/units/sniper.png"),
	"demon_lord": preload("res://assets/units/demon_lord.png"),
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
	"zombie": [preload("res://assets/units/animations/zombie/walk_0.png"), preload("res://assets/units/animations/zombie/walk_1.png"), preload("res://assets/units/animations/zombie/walk_2.png"), preload("res://assets/units/animations/zombie/walk_3.png"), preload("res://assets/units/animations/zombie/walk_4.png"), preload("res://assets/units/animations/zombie/walk_5.png"), preload("res://assets/units/animations/zombie/walk_6.png"), preload("res://assets/units/animations/zombie/walk_7.png")],
	"paladin": [preload("res://assets/units/animations/paladin/walk_0.png"), preload("res://assets/units/animations/paladin/walk_1.png"), preload("res://assets/units/animations/paladin/walk_2.png"), preload("res://assets/units/animations/paladin/walk_3.png"), preload("res://assets/units/animations/paladin/walk_4.png"), preload("res://assets/units/animations/paladin/walk_5.png"), preload("res://assets/units/animations/paladin/walk_6.png"), preload("res://assets/units/animations/paladin/walk_7.png")],
	"sniper": [preload("res://assets/units/animations/sniper/walk_0.png"), preload("res://assets/units/animations/sniper/walk_1.png"), preload("res://assets/units/animations/sniper/walk_2.png"), preload("res://assets/units/animations/sniper/walk_3.png"), preload("res://assets/units/animations/sniper/walk_4.png"), preload("res://assets/units/animations/sniper/walk_5.png"), preload("res://assets/units/animations/sniper/walk_6.png"), preload("res://assets/units/animations/sniper/walk_7.png")],
	"demon_lord": [preload("res://assets/units/animations/demon_lord/walk_0.png"), preload("res://assets/units/animations/demon_lord/walk_1.png"), preload("res://assets/units/animations/demon_lord/walk_2.png"), preload("res://assets/units/animations/demon_lord/walk_3.png"), preload("res://assets/units/animations/demon_lord/walk_4.png"), preload("res://assets/units/animations/demon_lord/walk_5.png"), preload("res://assets/units/animations/demon_lord/walk_6.png"), preload("res://assets/units/animations/demon_lord/walk_7.png")],
}
const UNIT_ATTACK_TEXTURES := {
	"paladin": [preload("res://assets/units/animations/paladin/attack_0.png"), preload("res://assets/units/animations/paladin/attack_1.png"), preload("res://assets/units/animations/paladin/attack_2.png"), preload("res://assets/units/animations/paladin/attack_3.png"), preload("res://assets/units/animations/paladin/attack_4.png")],
	"sniper": [preload("res://assets/units/animations/sniper/attack_0.png"), preload("res://assets/units/animations/sniper/attack_1.png"), preload("res://assets/units/animations/sniper/attack_2.png"), preload("res://assets/units/animations/sniper/attack_3.png")],
	"demon_lord": [preload("res://assets/units/animations/demon_lord/attack_0.png"), preload("res://assets/units/animations/demon_lord/attack_1.png"), preload("res://assets/units/animations/demon_lord/attack_2.png"), preload("res://assets/units/animations/demon_lord/attack_3.png"), preload("res://assets/units/animations/demon_lord/attack_4.png")],
	"zombie": [preload("res://assets/units/animations/zombie/attack_0.png"), preload("res://assets/units/animations/zombie/attack_1.png"), preload("res://assets/units/animations/zombie/attack_2.png"), preload("res://assets/units/animations/zombie/attack_3.png"), preload("res://assets/units/animations/zombie/attack_4.png")],
	"berserker": [preload("res://assets/units/animations/berserker/attack_0.png"), preload("res://assets/units/animations/berserker/attack_1.png"), preload("res://assets/units/animations/berserker/attack_2.png")],
	"warlock": [preload("res://assets/units/animations/warlock/attack_0.png"), preload("res://assets/units/animations/warlock/attack_1.png"), preload("res://assets/units/animations/warlock/attack_2.png")],
	"necromancer": [preload("res://assets/units/animations/necromancer/attack_0.png"), preload("res://assets/units/animations/necromancer/attack_1.png"), preload("res://assets/units/animations/necromancer/attack_2.png")],
	"skeleton": [preload("res://assets/units/animations/skeleton/attack_0.png"), preload("res://assets/units/animations/skeleton/attack_1.png"), preload("res://assets/units/animations/skeleton/attack_2.png")],
}
# A downed unit plays death, lies still, then plays revive before standing again.
const UNIT_DOWNED_TEXTURES := {
	"zombie": {"death": [preload("res://assets/units/animations/zombie/death_0.png"), preload("res://assets/units/animations/zombie/death_1.png"), preload("res://assets/units/animations/zombie/death_2.png"), preload("res://assets/units/animations/zombie/death_3.png"), preload("res://assets/units/animations/zombie/death_4.png")], "revive": [preload("res://assets/units/animations/zombie/revive_0.png"), preload("res://assets/units/animations/zombie/revive_1.png"), preload("res://assets/units/animations/zombie/revive_2.png"), preload("res://assets/units/animations/zombie/revive_3.png"), preload("res://assets/units/animations/zombie/revive_4.png"), preload("res://assets/units/animations/zombie/revive_5.png")]},
}
const DOWNED_FALL_SECONDS := 0.5
const UNIT_SKILL_TEXTURES := {
	"paladin": [preload("res://assets/units/animations/paladin/skill_0.png"), preload("res://assets/units/animations/paladin/skill_1.png"), preload("res://assets/units/animations/paladin/skill_2.png"), preload("res://assets/units/animations/paladin/skill_3.png"), preload("res://assets/units/animations/paladin/skill_4.png"), preload("res://assets/units/animations/paladin/skill_5.png"), preload("res://assets/units/animations/paladin/skill_6.png")],
	"demon_lord": [preload("res://assets/units/animations/demon_lord/skill_0.png"), preload("res://assets/units/animations/demon_lord/skill_1.png"), preload("res://assets/units/animations/demon_lord/skill_2.png"), preload("res://assets/units/animations/demon_lord/skill_3.png"), preload("res://assets/units/animations/demon_lord/skill_4.png"), preload("res://assets/units/animations/demon_lord/skill_5.png"), preload("res://assets/units/animations/demon_lord/skill_6.png")],
}
const HOLY_PILLAR_TEXTURES := [preload("res://assets/units/effects/holy_pillar_0.png"), preload("res://assets/units/effects/holy_pillar_1.png"), preload("res://assets/units/effects/holy_pillar_2.png"), preload("res://assets/units/effects/holy_pillar_3.png"), preload("res://assets/units/effects/holy_pillar_4.png"), preload("res://assets/units/effects/holy_pillar_5.png"), preload("res://assets/units/effects/holy_pillar_6.png"), preload("res://assets/units/effects/holy_pillar_7.png"), preload("res://assets/units/effects/holy_pillar_8.png")]
const DOWNED_RISE_SECONDS := 1.0
## The demon lord towers over the rest of the roster.
const DEMON_LORD_HEIGHT := 112.0
const DEMON_ROAR_TEXTURES := [preload("res://assets/units/effects/demon_roar_0.png"), preload("res://assets/units/effects/demon_roar_1.png"), preload("res://assets/units/effects/demon_roar_2.png"), preload("res://assets/units/effects/demon_roar_3.png"), preload("res://assets/units/effects/demon_roar_4.png"), preload("res://assets/units/effects/demon_roar_5.png"), preload("res://assets/units/effects/demon_roar_6.png"), preload("res://assets/units/effects/demon_roar_7.png")]
const DEMON_SOUL_TEXTURES := [preload("res://assets/units/effects/demon_soul_0.png"), preload("res://assets/units/effects/demon_soul_1.png"), preload("res://assets/units/effects/demon_soul_2.png"), preload("res://assets/units/effects/demon_soul_3.png"), preload("res://assets/units/effects/demon_soul_4.png"), preload("res://assets/units/effects/demon_soul_5.png")]
const DEMON_ABSORB_TEXTURES := [preload("res://assets/units/effects/demon_absorb_0.png"), preload("res://assets/units/effects/demon_absorb_1.png"), preload("res://assets/units/effects/demon_absorb_2.png"), preload("res://assets/units/effects/demon_absorb_3.png"), preload("res://assets/units/effects/demon_absorb_4.png"), preload("res://assets/units/effects/demon_absorb_5.png")]
const DEMON_AURA_TEXTURES := [preload("res://assets/units/effects/demon_aura_0.png"), preload("res://assets/units/effects/demon_aura_1.png"), preload("res://assets/units/effects/demon_aura_2.png"), preload("res://assets/units/effects/demon_aura_3.png"), preload("res://assets/units/effects/demon_aura_4.png"), preload("res://assets/units/effects/demon_aura_5.png")]
const UNIT_SUMMON_TEXTURES := [
preload("res://assets/units/animations/necromancer/summon_0.png"), preload("res://assets/units/animations/necromancer/summon_1.png"), preload("res://assets/units/animations/necromancer/summon_2.png")
]
var snapshot: Dictionary = {}
var own_side := 0
var structure_inspection := StructureInspection.new()
var selected_structure := "":
	set(value):
		if selected_structure == value: return
		selected_structure = value
		structure_inspection.cancel(self)
		keyboard_preview_active = false
		touch_preview_active = false
		reset_build_touch()
var mouse_position := Vector2.ZERO
var animation_time := 0.0
var visual_events: Array = []
var damage_lane_cursor := 0
const MAX_VISUAL_EVENTS := 96
## Above this many units the field drops per-unit decorations (glow, status words, buff pips): with hundreds
## of units they cost more than the units themselves and are unreadable anyway.
const CROWD_DETAIL_LIMIT := 60
## Units of one side and kind standing on the same spot (within CLUMP_PIXELS) are drawn at most this deep:
## the rest are hidden behind them.
const CLUMP_DEPTH := 3
const CLUMP_PIXELS := 6.0
## True while drawing a crowded field (see CROWD_DETAIL_LIMIT).
var crowded := false
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
var keyboard_preview_active := false
var keyboard_world_x := 0.0
const BUILD_CURSOR_STEP := 15.0
const BUILD_CURSOR_FINE_STEP := 3.0
var build_touch_index := -1
var build_touch_kind := ""
var finale_world_side := -1
## Replay-viewer extras, all inert unless `inspect_mode` is set: clicking a unit, wheel zoom, middle-drag pan.
var inspect_mode := false
var view_zoom := 1.0
var view_offset := Vector2.ZERO
var panning := false
const ZOOM_MIN := 1.0
const ZOOM_MAX := 3.0
signal unit_clicked(unit: Dictionary)
signal zoom_changed(zoom: float)
var finale_age := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)

## The base of `world_loser` has fallen: it collapses with a burst of debris while the rest keeps playing.
func start_finale(world_loser: int) -> void:
	structure_inspection.cancel(self)
	finale_world_side = world_loser
	finale_age = 0.0
	queue_redraw()

func _view_transform() -> Transform2D:
	return Transform2D(0.0, Vector2(view_zoom, view_zoom), 0.0, view_offset)

## Screen position inside this control -> position in the unzoomed drawing space.
func to_view(position: Vector2) -> Vector2:
	return (position - view_offset) / view_zoom

func _clamp_offset() -> void:
	view_offset = Vector2(clampf(view_offset.x, size.x * (1.0 - view_zoom), 0.0), clampf(view_offset.y, size.y * (1.0 - view_zoom), 0.0))

## Zooms around `anchor` (a position in this control), keeping the point under it fixed.
func zoom_at(anchor: Vector2, target: float) -> void:
	var next := clampf(target, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(next, view_zoom):
		return
	view_offset = anchor - (anchor - view_offset) * (next / view_zoom)
	view_zoom = next
	_clamp_offset()
	zoom_changed.emit(view_zoom)
	queue_redraw()

func reset_view() -> void:
	var changed := view_zoom != 1.0
	view_zoom = 1.0
	view_offset = Vector2.ZERO
	panning = false
	if changed:
		zoom_changed.emit(view_zoom)
	queue_redraw()

## Nearest unit within `radius` pixels of a click, or {}. Works at any zoom.
func unit_at(position: Vector2, radius: float = 38.0) -> Dictionary:
	var local := to_view(position)
	var lane_y := size.y * 0.72
	var best := {}
	var best_distance := radius
	for unit in snapshot.get("units", []):
		var centre := Vector2(world_to_screen_x(motion.position(int(unit.id), float(unit.x))), lane_y - 40.0)
		var distance := local.distance_to(centre)
		if distance <= best_distance:
			best_distance = distance
			best = unit
	return best

func _inspect_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					zoom_at(event.position, view_zoom * 1.15)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_at(event.position, view_zoom / 1.15)
				return true
			MOUSE_BUTTON_MIDDLE:
				panning = event.pressed
				return true
			MOUSE_BUTTON_LEFT:
				if event.double_click:
					reset_view()
				elif not event.pressed:
					unit_clicked.emit(unit_at(event.position))
				return true
	elif event is InputEventMouseMotion and panning:
		view_offset += event.relative
		_clamp_offset()
		queue_redraw()
		return true
	return false

func finale_active() -> bool:
	return finale_world_side >= 0

func set_snapshot(data: Dictionary) -> void:
	if float(data.get("elapsed", 0.0)) < float(snapshot.get("elapsed", 0.0)):
		structure_inspection.cancel(self)
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
	# Curse centers by the side that cast them, sorted, so each unit checks only the nearest ones.
	var curse_xs: Array = [PackedFloat64Array(), PackedFloat64Array()]
	for curse in data.get("curses", []):
		curse_xs[int(curse.side)].append(float(curse.x))
	for xs in curse_xs:
		xs.sort()
	for unit in data.get("units", []):
		positions[unit.id] = float(unit.x)
		var enraged := BattleModel.is_enraged(unit)
		current_rage[unit.id] = enraged
		if enraged and rage_states.has(unit.id) and not rage_states[unit.id]:
			rage_flashes[unit.id] = 0.5
			rage_started.emit(int(unit.id))
		moving_units[unit.id] = last_unit_x.has(unit.id) and absf(float(last_unit_x[unit.id]) - float(unit.x)) > 0.05
		var enemy_curses: PackedFloat64Array = curse_xs[1 - int(unit.side)]
		var at := enemy_curses.bsearch(float(unit.x), true)
		if (at < enemy_curses.size() and absf(enemy_curses[at] - float(unit.x)) <= BattleModel.CURSE_RADIUS) or (at > 0 and absf(enemy_curses[at - 1] - float(unit.x)) <= BattleModel.CURSE_RADIUS):
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
			visual["life"] = 0.45 if String(event.get("type", "")) in ["DEATH", "STRUCTURE_DESTROYED"] else (1.0 if String(event.get("type", "")) in ["SKILL", "SOUL", "SPELL_LAND"] else 0.7)
			if String(event.get("type","")) in ["DAMAGE","HEAL","BASE_HIT"]:
				visual["text_lane"] = damage_lane_cursor % 4
				damage_lane_cursor += 1
			visual_events.append(visual)
			if visual_events.size()>MAX_VISUAL_EVENTS: visual_events.pop_front()
			if event.get("type") == "SUMMON":
				unit_actions[event.source_id] = {"type": "SUMMON", "started": animation_time}
			elif event.get("type") == "SKILL":
				unit_actions[event.source_id] = {"type": "SKILL", "started": animation_time}
			elif event.get("type") == "ATTACK" and UNIT_ATTACK_TEXTURES.has(String(event.get("attack_kind", ""))):
				unit_actions[event.attacker_id] = {"type": "ATTACK", "started": animation_time}
	queue_redraw()

const SpellArt = preload("res://scripts/ui/SpellArt.gd")
const BattlefieldArt = preload("res://scripts/ui/BattlefieldArt.gd")
## Ring colors for spell areas on the ground.
const SPELL_COLORS := {"lightning": Color(0.62, 0.8, 1.0), "fireball": Color(1.0, 0.5, 0.18), "frost": Color(0.6, 0.9, 1.0), "blessing": Color(1.0, 0.84, 0.36), "seraph": Color(1.0, 0.95, 0.8)}

## Draws `texture` standing on `ground_y`, centered on `x`, `width` wide (height keeps the aspect).
func _draw_art(texture: Texture2D, x: float, ground_y: float, width: float, alpha: float = 1.0, flip: bool = false) -> void:
	var height := width * float(texture.get_height()) / maxf(1.0, float(texture.get_width()))
	if flip:
		draw_set_transform_matrix(_view_transform() * Transform2D(0.0, Vector2(-1.0, 1.0), 0.0, Vector2(x, 0.0)))
		draw_texture_rect(texture, Rect2(-width * 0.5, ground_y - height, width, height), false, Color(1, 1, 1, alpha))
		draw_set_transform_matrix(_view_transform())
	else:
		draw_texture_rect(texture, Rect2(x - width * 0.5, ground_y - height, width, height), false, Color(1, 1, 1, alpha))

## Endless defense's spawn zone: a violet haze from the edge `depth` into the field, with a shimmering rim.
func _draw_spawn_zone(world_side: int, depth: float, lane_y: float) -> void:
	var edge := BattleModel.FIELD_LEFT if world_side == 0 else BattleModel.FIELD_RIGHT
	var inner := edge + depth if world_side == 0 else edge - depth
	var a := world_to_screen_x(edge)
	var b := world_to_screen_x(inner)
	var left := minf(a, b)
	var width := absf(a - b)
	var top := lane_y - 170.0
	var bands := 8
	for band in bands:
		# Thicker toward the edge, fading toward the rim.
		var share := float(band) / float(bands)
		var x0 := lerpf(a, b, share)
		var x1 := lerpf(a, b, share + 1.0 / float(bands))
		draw_rect(Rect2(minf(x0, x1), top, absf(x1 - x0), lane_y + 24.0 - top), Color(0.45, 0.25, 0.75, 0.22 * (1.0 - share)))
	var pulse := 0.5 + 0.5 * sin(animation_time * 3.0)
	draw_line(Vector2(b, top), Vector2(b, lane_y + 24.0), Color(0.78, 0.6, 1.0, 0.35 + 0.35 * pulse), 2.0)
	for spark in 6:
		var phase := fmod(animation_time * 0.4 + float(spark) * 0.37, 1.0)
		var sx := left + width * fmod(float(spark) * 0.618, 1.0)
		draw_circle(Vector2(sx, lane_y + 10.0 - phase * 170.0), 2.0, Color(0.85, 0.7, 1.0, 0.6 * (1.0 - phase)))

## A cast waiting to land: its area on the ground, the first frames of its effect, and a thrown fireball.
func _draw_spell_cast(cast: Dictionary, scale_x: float, lane_y: float) -> void:
	var kind := String(cast.kind)
	var color: Color = SPELL_COLORS.get(kind, Color.WHITE)
	var x := world_to_screen_x(float(cast.x))
	var stats: Dictionary = BattleModel.STRUCTURE_STATS.get(kind, {})
	var radius := float(stats.get("radius", 40.0)) * scale_x
	var pulse := 0.5 + 0.5 * sin(animation_time * 10.0)
	var remaining := maxf(0.0, float(cast.lands_at) - (float(snapshot.get("elapsed", 0.0)) + snapshot_age))
	draw_arc(Vector2(x, lane_y + 4.0), radius, 0.0, TAU, 40, Color(color.r, color.g, color.b, 0.35 + 0.3 * pulse), 2.0)
	match kind:
		"lightning":
			_draw_art(SpellArt.LIGHTNING[0], x, lane_y + 10.0, 180.0, 0.6 + 0.4 * pulse)
		"frost":
			_draw_art(SpellArt.FROST[0], x, lane_y + 10.0, radius * 2.4, 0.6 + 0.4 * pulse)
		"fireball":
			var origin := BattleModel.FIELD_LEFT if int(cast.side) == 0 else BattleModel.FIELD_RIGHT
			var direction := signf(float(cast.x) - origin)
			var ball_x := world_to_screen_x(float(cast.x) - direction * remaining * float(stats.get("speed", 900.0)))
			# The artwork flies right; screen direction depends on the viewer's side.
			var screen_direction := signf(x - world_to_screen_x(origin))
			_draw_art(SpellArt.loop(SpellArt.FIREBALL, animation_time, 12.0), ball_x, lane_y - 30.0 - remaining * 70.0, 110.0, 1.0, screen_direction < 0.0)
		"seraph":
			var delay := maxf(0.01, float(stats.get("delay", 1.0)))
			_draw_art(SpellArt.frame(SpellArt.SERAPH_DESCEND, 1.0 - remaining / delay), x, lane_y + 6.0, 170.0)

## A landed spell.
func _draw_spell_land(event: Dictionary, x: float, life: float, scale_x: float, lane_y: float) -> void:
	var kind := String(event.get("kind", ""))
	var radius := float(event.get("radius", 40.0)) * scale_x
	var progress := clampf(1.0 - life, 0.0, 1.0)
	var alpha := effect_intensity
	match kind:
		"lightning":
			_draw_art(SpellArt.frame(SpellArt.LIGHTNING.slice(1), progress), x, lane_y + 10.0, 240.0, alpha)
		"fireball":
			_draw_art(SpellArt.frame(SpellArt.FIREBALL_BURST, progress), x, lane_y + 10.0, radius * 2.8, alpha)
		"frost":
			_draw_art(SpellArt.frame(SpellArt.FROST.slice(1), progress), x, lane_y + 10.0, radius * 2.4, alpha)
		"blessing":
			_draw_art(SpellArt.frame(SpellArt.BLESSING, progress), x, lane_y + 10.0, radius * 2.0, alpha)
		"seraph":
			_draw_art(SpellArt.frame(SpellArt.SERAPH_CAST, progress), x, lane_y + 6.0, 170.0, alpha)
			for unit in snapshot.get("units", []):
				if Array(event.get("targets", [])).has(unit.id):
					_draw_art(SpellArt.frame(SpellArt.SERAPH_REVIVE, progress), world_to_screen_x(motion.position(int(unit.id), float(unit.x))), lane_y + 8.0, 90.0, alpha)

func placement_error(kind: String, world_x: float) -> String:
	if not BattleModel.STRUCTURE_STATS.has(kind):
		return Localization.text("설치할 수 없는 구조물입니다.")
	if BattleModel.is_spell(kind):
		var zone := BattleModel.tactic_zone(own_side, kind)
		if world_x < float(zone[0]) or world_x > float(zone[1]):
			return Localization.text("자신의 진영에만 쓸 수 있습니다.") if String(BattleModel.STRUCTURE_STATS[kind].get("zone", "any")) == "own" else Localization.text("전장 안에만 쓸 수 있습니다.")
		var cooldowns: Array = snapshot.get("spell_cooldowns", [{}, {}])
		var uses: Array = snapshot.get("spell_uses", [{}, {}])
		var spell_problem := BattleModel.spell_error(kind, cooldowns[own_side] if cooldowns.size() > own_side else {}, uses[own_side] if uses.size() > own_side else {})
		if not spell_problem.is_empty():
			return spell_problem
		var spell_resources: Array = snapshot.get("resources", [0.0, 0.0])
		if spell_resources.size() <= own_side or float(spell_resources[own_side]) < float(BattleModel.STRUCTURE_STATS[kind].cost):
			return Localization.text("자원이 부족합니다.")
		return ""
	var valid_zone := (own_side == 0 and world_x >= BattleModel.BLUE_BUILD_MIN and world_x <= BattleModel.BLUE_BUILD_MAX) or (own_side == 1 and world_x >= BattleModel.RED_BUILD_MIN and world_x <= BattleModel.RED_BUILD_MAX)
	if not valid_zone:
		return Localization.text("자신의 건설 구역에만 설치할 수 있습니다.")
	if kind == "generator" and not ((own_side == 0 and world_x <= BattleModel.BLUE_REAR_MAX) or (own_side == 1 and world_x >= BattleModel.RED_REAR_MIN)):
		return Localization.text("발전기는 후방에만 설치할 수 있습니다.")
	for structure in snapshot.get("structures", []):
		if int(structure.side) == own_side and float(structure.get("hp", 1.0)) > 0.0 and abs(float(structure.x) - world_x) < BattleModel.STRUCTURE_MIN_SPACING:
			return Localization.text("구조물이 너무 가깝습니다.")
	var limit_error := BattleModel.structure_limit_error(kind, BattleModel.structure_counts(snapshot.get("structures", []), own_side))
	if not limit_error.is_empty():
		return limit_error
	var resources: Array = snapshot.get("resources", [0.0, 0.0])
	if resources.size() <= own_side or float(resources[own_side]) < float(BattleModel.STRUCTURE_STATS[kind].cost):
		return Localization.text("자원이 부족합니다.")
	return ""

func _process(delta: float) -> void:
	animation_time += delta
	snapshot_age += delta
	if finale_world_side >= 0:
		finale_age += delta / maxf(0.05, Engine.time_scale) # real seconds, even in slow motion
		queue_redraw()
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
	if keyboard_preview_active:
		mouse_position = Vector2(world_to_screen_x(keyboard_world_x), size.y * 0.7)
	elif not touch_preview_active:
		mouse_position = get_local_mouse_position()
	if not selected_structure.is_empty() or not snapshot.get("units", []).is_empty() or not visual_events.is_empty():
		queue_redraw()

func reset_build_touch() -> void:
	build_touch_index = -1
	build_touch_kind = ""
	queue_redraw()

func update_build_touch(index: int, position_value: Vector2) -> bool:
	if index != build_touch_index or build_touch_index < 0:
		return false
	if selected_structure != build_touch_kind:
		reset_build_touch()
		return false
	keyboard_preview_active = false
	touch_preview_active = true
	mouse_position = position_value
	queue_redraw()
	return true

func finish_build_touch(index: int, position_value: Vector2, canceled: bool = false) -> bool:
	if not update_build_touch(index, position_value):
		return false
	reset_build_touch()
	if canceled or not Rect2(Vector2.ZERO, size).has_point(position_value):
		build_touch_cancelled.emit()
	else:
		battlefield_clicked.emit(screen_to_world_x(position_value.x))
	return true

func _gui_input(event: InputEvent) -> void:
	if inspect_mode and _inspect_input(event):
		if is_inside_tree(): accept_event()
		return
	# Placement uses the original touch event; its emulated mouse event must
	# neither move another finger's preview nor repeat the release action.
	if not inspect_mode and (event is InputEventMouseMotion or event is InputEventMouseButton) and event.device == InputEvent.DEVICE_ID_EMULATION:
		if is_inside_tree(): accept_event()
		return
	if structure_inspection.begin_gui_input(self, event):
		if is_inside_tree(): accept_event()
		return
	if event is InputEventMouseMotion:
		if build_touch_index >= 0:
			return
		# A real pointer movement takes over; stationary mouse coordinates must
		# not overwrite a position chosen with the keyboard on the next frame.
		if event.relative.is_zero_approx(): return
		keyboard_preview_active = false
		touch_preview_active = false
		mouse_position = event.position
	elif event is InputEventScreenTouch:
		if event.pressed and build_touch_index < 0 and not selected_structure.is_empty() and Rect2(Vector2.ZERO, size).has_point(event.position):
			build_touch_index = event.index
			build_touch_kind = selected_structure
			update_build_touch(event.index, event.position)
		elif not event.pressed:
			finish_build_touch(event.index, event.position, event.canceled)
		if is_inside_tree(): accept_event()
	elif event is InputEventScreenDrag:
		update_build_touch(event.index, event.position)
		if is_inside_tree(): accept_event()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if build_touch_index >= 0:
			if is_inside_tree(): accept_event()
			return
		keyboard_preview_active = false
		touch_preview_active = false
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
	if view_zoom != 1.0 or view_offset != Vector2.ZERO:
		draw_set_transform_matrix(_view_transform())
	var scale_x := size.x / BattleModel.WORLD_WIDTH
	var lane_y := size.y * 0.72
	_draw_sky(lane_y)
	_draw_ground(lane_y)
	_draw_base(world_to_screen_x(BattleModel.FIELD_LEFT), lane_y, 0)
	_draw_base(world_to_screen_x(BattleModel.FIELD_RIGHT), lane_y, 1)
	var shelter = snapshot.get("shelter", [])
	if shelter is Array and shelter.size() == 2:
		for world_side in 2:
			if float(shelter[world_side]) > 0.0:
				_draw_spawn_zone(world_side, float(shelter[world_side]), lane_y)

	for curse in snapshot.get("curses", []):
		_draw_curse(curse, scale_x, lane_y)
	for cast in snapshot.get("spells", []):
		_draw_spell_cast(cast, scale_x, lane_y)
	for structure in snapshot.get("structures", []):
		_draw_structure(structure, scale_x, lane_y)
	var field_units: Array = snapshot.get("units", [])
	crowded = field_units.size() > CROWD_DETAIL_LIMIT
	var clumps := {}
	for unit in field_units:
		if crowded:
			var spot := "%d|%s|%d" % [int(unit.side), String(unit.kind), int(motion.position(int(unit.id), float(unit.x)) / CLUMP_PIXELS)]
			var depth := int(clumps.get(spot, 0))
			if depth >= CLUMP_DEPTH:
				continue
			clumps[spot] = depth + 1
		_draw_unit(unit, scale_x, lane_y)
	if show_battle_effects or show_damage_numbers:
		_draw_combat_events(scale_x, lane_y)
	_draw_structure_lifetimes(lane_y)

	if finale_world_side >= 0:
		_draw_finale(lane_y)
	if not selected_structure.is_empty():
		_draw_build_preview(lane_y)
	structure_inspection.draw(self)

func _draw_sky(lane_y: float) -> void:
	# The painted sky covers the width; its far scenery ends just above the ruins.
	var sky: Texture2D = BattlefieldArt.SKY
	var horizon := lane_y - 34.0
	var sky_scale := maxf(size.x / float(sky.get_width()), (horizon + position.y) / (BattlefieldArt.SKY_HORIZON * float(sky.get_height())))
	var sky_size := Vector2(sky.get_width(), sky.get_height()) * sky_scale
	# The sky runs up to the screen top, behind the health bars the HUD draws over it.
	var sky_rect := Rect2((size.x - sky_size.x) * 0.5, horizon - BattlefieldArt.SKY_HORIZON * sky_size.y, sky_size.x, sky_size.y)
	var visible := sky_rect.intersection(Rect2(0.0, -position.y, size.x, size.y + position.y))
	var source := Rect2((visible.position - sky_rect.position) / sky_scale, visible.size / sky_scale)
	draw_texture_rect_region(sky, visible, source, Color(0.80, 0.82, 0.92))
	# Drifting haze keeps the backdrop alive.
	var clock := float(Time.get_ticks_msec()) / 1000.0
	for i in 3:
		var cx := fposmod(float(i) * size.x * 0.37 + clock * (4.0 + float(i) * 2.0), size.x + 400.0) - 200.0
		var cy := lane_y * (0.30 + 0.12 * float(i))
		for puff in 5:
			draw_circle(Vector2(cx + float(puff) * 34.0, cy + sin(float(puff) * 1.9) * 6.0), 30.0 - float(puff % 3) * 6.0, Color(0.5, 0.6, 0.9, 0.03))
	# Ruins in front of the far scenery, a little darker so units stay readable.
	var ruins_height := clampf(size.y * 0.21, 110.0, 190.0)
	_draw_strip(BattlefieldArt.RUINS, _ground_top(lane_y) + _ground_height() * 0.26 - ruins_height, ruins_height, Color(0.66, 0.70, 0.84), 0.37)

## The ground strip is placed so the lane runs along the upper part of its dirt road.
func _ground_height() -> float:
	return clampf(size.y * 0.32, 160.0, 300.0)

func _ground_top(lane_y: float) -> float:
	return lane_y - _ground_height() * BattlefieldArt.GROUND_LANE

## Repeats a seamless strip across the battlefield width.
func _draw_strip(texture: Texture2D, top: float, height: float, tint: Color = Color.WHITE, offset: float = 0.0) -> void:
	var width := float(texture.get_width()) * height / maxf(1.0, float(texture.get_height()))
	var x := -fposmod(offset * width, width)
	while x < size.x:
		draw_texture_rect(texture, Rect2(x, top, width + 1.0, height), false, tint)
		x += width

func _draw_ground(lane_y: float) -> void:
	# Below the strip, its darkest stone colour continues to the screen edge.
	draw_rect(Rect2(0, lane_y, size.x, size.y - lane_y), Color("#0a0b14"))
	_draw_strip(BattlefieldArt.GROUND, _ground_top(lane_y), _ground_height(), Color(0.86, 0.88, 0.98))
	# Team-tinted build zones fade toward the centre.
	for i in 10:
		var t := float(i) / 9.0
		var w := size.x * 0.47 * (1.0 - t * 0.85)
		draw_rect(Rect2(0, lane_y, w, size.y - lane_y), Color(0.20, 0.36, 0.85, 0.010 + t * 0.008))
		draw_rect(Rect2(size.x - w, lane_y, w, size.y - lane_y), Color(0.90, 0.22, 0.38, 0.010 + t * 0.008))
	draw_line(Vector2(size.x * 0.5, lane_y + 6.0), Vector2(size.x * 0.5, size.y), Color(0.85, 0.88, 1.0, 0.10), 1.0)
	draw_circle(Vector2(size.x * 0.5, lane_y + 12.0), 6.0, Color(0.5, 0.56, 0.78, 0.30))
	draw_circle(Vector2(size.x * 0.5, lane_y + 12.0), 3.0, Color("#aab4d2"))

func _draw_base(x: float, lane_y: float, world_side: int) -> void:
	var side := display_side(world_side)
	var color := BLUE if side == 0 else RED
	var collapsing := finale_world_side >= 0 and world_side == finale_world_side
	if collapsing:
		var facing := 1.0 if side == 0 else -1.0
		var progress := minf(finale_age / 1.2, 1.0)
		var pivot := Vector2(x, lane_y)
		var tilt := 0.22 * progress * -facing
		var shake := Vector2(sin(finale_age * 70.0) * 4.0 * maxf(0.0, 1.0 - finale_age), 0.0)
		var local := Transform2D(tilt, Vector2.ZERO)
		local.origin = pivot - local.basis_xform(pivot) + Vector2(0.0, 36.0 * progress) + shake
		draw_set_transform_matrix(_view_transform() * local)
	# Soft territory glow.
	for i in 6:
		draw_circle(Vector2(x, lane_y - 56.0), 100.0 - float(i) * 12.0, Color(color.r, color.g, color.b, 0.025 + float(i) * 0.012))
	var hp: Array = snapshot.get("base_hp", [1.0, 1.0])
	var max_hp: Array = snapshot.get("base_max_hp", [1.0, 1.0])
	var state := 2 if collapsing else BattlefieldArt.base_state(float(hp[world_side]), float(max_hp[world_side]))
	_draw_art(BattlefieldArt.BASES[side][state], x, lane_y + 10.0, 196.0, 1.0, side == 1)
	if collapsing:
		draw_set_transform_matrix(_view_transform())

## Debris, a shock ring and a white flash over the fallen base.
func _draw_finale(lane_y: float) -> void:
	var x := world_to_screen_x(BattleModel.FIELD_LEFT if finale_world_side == 0 else BattleModel.FIELD_RIGHT)
	var centre := Vector2(x, lane_y - 52.0)
	var fade := clampf(1.0 - finale_age / 1.3, 0.0, 1.0)
	for i in 28:
		var angle := float(i) * 0.7 + float(i % 3) * 0.4
		var speed := 80.0 + float((i * 37) % 90)
		var position := centre + Vector2(cos(angle) * speed * finale_age, sin(angle) * speed * finale_age + 150.0 * finale_age * finale_age)
		var tone := Color("#ffd36a") if i % 3 == 0 else (Color("#ff8a4c") if i % 3 == 1 else Color("#d8deee"))
		draw_rect(Rect2(position - Vector2(2.0 + float(i % 4), 2.0 + float(i % 4)), Vector2(4.0 + float(i % 4) * 2.0, 4.0 + float(i % 4) * 2.0)), Color(tone.r, tone.g, tone.b, fade))
	draw_arc(centre, 24.0 + finale_age * 260.0, 0.0, TAU, 48, Color(1.0, 0.95, 0.8, 0.8 * fade), maxf(1.0, 8.0 * fade))
	var flash := maxf(0.0, 0.5 - finale_age * 1.8)
	if flash > 0.0:
		draw_rect(Rect2(-view_offset / view_zoom, size / view_zoom), Color(1, 1, 1, flash))

func _draw_unit(unit: Dictionary, scale_x: float, lane_y: float) -> void:
	if unit.has("revive_remaining") and UNIT_DOWNED_TEXTURES.has(String(unit.kind)):
		_draw_downed_unit(unit, lane_y)
		return
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
		var frames: Array = UNIT_SUMMON_TEXTURES if action.type == "SUMMON" and kind == "necromancer" else (UNIT_SKILL_TEXTURES[kind] if action.type == "SKILL" and UNIT_SKILL_TEXTURES.has(kind) else UNIT_ATTACK_TEXTURES[kind])
		var index := clampi(int((animation_time - float(action.started)) / 0.7 * frames.size()), 0, frames.size() - 1)
		texture = frames[index]
		action_blend = action_opacity(animation_time - float(action.started))
	var sprite_height: float = 86.0
	if unit.kind == "demon_lord":
		sprite_height = DEMON_LORD_HEIGHT
	elif unit.kind == "shield":
		sprite_height = 92.0
	elif unit.kind == "healer":
		sprite_height = 90.0
	elif unit.kind == "archer":
		sprite_height = 86.0
	if UNIT_ATTACK_TEXTURES.has(kind):
		sprite_height *= float(texture.get_height()) / float(UNIT_TEXTURES[kind].get_height())
	var sprite_width: float = sprite_height * float(texture.get_width()) / max(float(texture.get_height()), 1.0)

	# Team halo and contact shadow stay independent from the supplied artwork.
	if not crowded:
		draw_circle(Vector2(x, lane_y - 38.0), 43.0, Color(color.r, color.g, color.b, 0.08))
	draw_ellipse(Vector2(x, lane_y - 2.0), sprite_width * 0.37, 6.0, Color(0.0, 0.0, 0.0, 0.38))
	var souls := int(unit.get("souls", 0))
	if souls > 0 and show_battle_effects:
		# The aura brightens with every harvested soul.
		var aura: Texture2D = DEMON_AURA_TEXTURES[int(animation_time * 8.0) % DEMON_AURA_TEXTURES.size()]
		var aura_width := 120.0
		var aura_height := aura_width * float(aura.get_height()) / float(aura.get_width())
		var soul_max := maxf(1.0, float(BattleModel.trait_value(kind, "soul_max", 1)))
		draw_texture_rect(aura, Rect2(x - aura_width * 0.5, lane_y + 8.0 - aura_height, aura_width, aura_height), false, Color(1, 1, 1, (0.35 + 0.55 * souls / soul_max) * effect_intensity))
	draw_set_transform_matrix(_view_transform() * Transform2D(0.0, Vector2(facing, 1.0), 0.0, Vector2(x, lane_y)))
	var tint := Color.WHITE.lerp(Color("#ffb37a"), 0.25) if BattleModel.is_enraged(unit) else Color.WHITE
	if texture != walk_texture and action_blend < 1.0:
		var walk_height := (DEMON_LORD_HEIGHT if kind == "demon_lord" else 86.0) * float(walk_texture.get_height()) / float(UNIT_TEXTURES[kind].get_height())
		var walk_width := walk_height * float(walk_texture.get_width()) / float(walk_texture.get_height())
		draw_texture_rect(walk_texture, Rect2(-walk_width * 0.5, -walk_height, walk_width, walk_height), false, Color(tint.r, tint.g, tint.b, 1.0-action_blend))
	draw_texture_rect(texture, Rect2(-sprite_width * 0.5, -sprite_height, sprite_width, sprite_height), false, Color(tint.r, tint.g, tint.b, action_blend if texture != walk_texture else 1.0))
	draw_set_transform_matrix(_view_transform())
	# Small faction pip remains visible when both teams use the same character art.
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 5.0, color)
	draw_circle(Vector2(x - 25.0, lane_y - 74.0), 2.0, Color("#f5f7fb"))
	if unit.kind == "healer" and unit.cooldown > unit.interval * 0.70 and not crowded:
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
	# Spell feedback stays in a crowd; the status words and pips below are for small fights.
	if unit.has("frozen_remaining"):
		_draw_art(SpellArt.FROST[3], x, lane_y + 6.0, 74.0, 0.85)
	if unit.has("blessed_remaining"):
		_draw_art(SpellArt.loop(SpellArt.BLESSING_AURA, animation_time, 8.0), x, lane_y + 8.0, 64.0, 0.9)
	if crowded:
		return
	if souls > 0:
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 18.0), "영혼 %d" % souls, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff6b5a"))
	if BattleModel.is_enraged(unit):
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 18.0), "광폭", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ff9a61"))
	if cursed_units.has(unit.id):
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 4.0), "공속▼%d%%" % roundi((1.0 - BattleModel.CURSE_SPEED_SCALE) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#c592ff"))
	if unit.has("frozen_remaining"):
		draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - 32.0), "빙결", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#a8e6ff"))
	if unit.get("revived", false):
		draw_circle(Vector2(x, lane_y - 82.0), 3.0, Color(1.0, 0.95, 0.75, 0.9))
	if show_battle_effects and kind != "healer":
		var stacks := mini(int(unit.get("support_stacks", 0)), BattleModel.SUPPORT_MAX_STACKS)
		if stacks > 0:
			for dot in BattleModel.SUPPORT_MAX_STACKS:
				draw_circle(Vector2(x - 18.0 + dot * 4.0, bar_y + 10.0), 1.3, Color("#86f7ad") if dot < stacks else Color("#293d39"))
		# One attack-speed figure: support stacks and a blessing multiply, as in BattleModel.support_attack_speed.
		var boost := (1.0 + stacks * BattleModel.SUPPORT_INCREMENT) * (float(BattleModel.STRUCTURE_STATS.blessing.attack_speed) if unit.has("blessed_remaining") else 1.0)
		if boost > 1.0001:
			draw_string(ThemeDB.fallback_font, Vector2(x - 20.0, bar_y - (32.0 if cursed_units.has(unit.id) else 4.0)), "▲%d%%" % roundi((boost - 1.0) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("#ffd75e") if unit.has("blessed_remaining") else Color("#86f7ad"))

func _draw_downed_unit(unit: Dictionary, lane_y: float) -> void:
	var kind := String(unit.kind)
	var x := world_to_screen_x(motion.position(int(unit.id), float(unit.x)))
	var color := BLUE if display_side(int(unit.side)) == 0 else RED
	var delay := float(BattleModel.trait_value(kind, "revive_delay", 1.0))
	var remaining := maxf(0.0, float(unit.revive_remaining) - minf(snapshot_age, 0.25))
	var down_for := delay - remaining
	var frames: Dictionary = UNIT_DOWNED_TEXTURES[kind]
	var death: Array = frames.death
	var revive: Array = frames.revive
	var texture: Texture2D = death.back()
	if down_for < DOWNED_FALL_SECONDS:
		texture = death[clampi(int(down_for / DOWNED_FALL_SECONDS * death.size()), 0, death.size() - 1)]
	elif remaining < DOWNED_RISE_SECONDS:
		texture = revive[clampi(int((1.0 - remaining / DOWNED_RISE_SECONDS) * revive.size()), 0, revive.size() - 1)]
	var height := 86.0 * float(texture.get_height()) / float(UNIT_TEXTURES[kind].get_height())
	var width := height * float(texture.get_width()) / maxf(float(texture.get_height()), 1.0)
	var facing := 1.0 if display_side(int(unit.side)) == 0 else -1.0
	draw_ellipse(Vector2(x, lane_y - 2.0), width * 0.37, 6.0, Color(0.0, 0.0, 0.0, 0.38))
	draw_set_transform_matrix(_view_transform() * Transform2D(0.0, Vector2(facing, 1.0), 0.0, Vector2(x, lane_y)))
	draw_texture_rect(texture, Rect2(-width * 0.5, -height, width, height), false, Color(1, 1, 1, 0.92))
	draw_set_transform_matrix(_view_transform())
	var bar_y := lane_y - 40.0
	draw_rect(Rect2(x - 20.0, bar_y, 40.0, 3.0), Color("#242038"))
	draw_rect(Rect2(x - 20.0, bar_y, 40.0 * clampf(down_for / maxf(delay, 0.01), 0.0, 1.0), 3.0), Color("#9fd18b"))
	draw_circle(Vector2(x - 25.0, bar_y - 4.0), 4.0, color)

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
	var flip := side == 1
	match String(structure.kind):
		"wall":
			var broken := float(structure.get("hp", 1.0)) < float(structure.get("max_hp", 1.0)) * 0.5
			_draw_art((BattlefieldArt.WALL_BROKEN if broken else BattlefieldArt.WALL)[side], x, lane_y + 6.0, 96.0, 1.0, flip)
		"swamp":
			var radius := float(BattleModel.STRUCTURE_STATS.swamp.radius) * scale_x
			draw_arc(Vector2(x, lane_y - 4.0), radius, 0.0, TAU, 48, Color(0.62, 0.47, 0.86, 0.30), 1.0)
			_draw_art(BattlefieldArt.SWAMP, x, lane_y + 14.0, radius * 1.7, 0.95, fmod(float(structure.get("id", 0)), 2.0) == 1.0)
		"turret":
			var width := 86.0
			_draw_art(BattlefieldArt.TURRET[side], x, lane_y + 6.0, width, 1.0, flip)
			if fmod(animation_time, 1.5) < 0.16:
				var facing := 1.0 if side == 0 else -1.0
				var height := width * float(BattlefieldArt.TURRET[side].get_height()) / float(BattlefieldArt.TURRET[side].get_width())
				draw_circle(Vector2(x + width * 0.5 * facing, lane_y + 6.0 - height * 0.78), 7.0, Color("#ffd36a"))
		"generator":
			var pulse := 0.85 + sin(animation_time * 4.0) * 0.15
			draw_circle(Vector2(x, lane_y - 40.0), 26.0 * pulse, Color(0.55, 1.0, 0.85, 0.08))
			_draw_art(BattlefieldArt.GENERATOR, x, lane_y + 6.0, 70.0, 1.0, flip)

func _draw_structure_lifetimes(lane_y: float) -> void:
	var elapsed := float(snapshot.get("elapsed", 0.0))
	var timed: Array = StructureLifetime.timed_structures(snapshot.get("structures", []), 0)
	timed.append_array(StructureLifetime.timed_structures(snapshot.get("structures", []), 1))
	timed.sort_custom(func(a: Dictionary, b: Dictionary): return world_to_screen_x(float(a.x)) < world_to_screen_x(float(b.x)))
	var row_ends: Array[float] = []
	for structure in timed:
		var x := world_to_screen_x(float(structure.x))
		var left := clampf(x - 48.0, 4.0, maxf(4.0, size.x - 100.0))
		var row := 0
		while row < row_ends.size() and left < row_ends[row] + 4.0: row += 1
		if row == row_ends.size(): row_ends.append(0.0)
		row_ends[row] = left + 96.0
		var top := lane_y + 33.0 + row * 23.0
		var remaining := StructureLifetime.remaining(structure, elapsed)
		var imminent := remaining <= StructureLifetime.WARNING_SECONDS
		var team := BLUE if display_side(int(structure.side)) == 0 else RED
		var tone := GOLD if imminent else Color("#c8a9ef")
		# Draw after units/events, below curse timers and above the HUD at y=520.
		# Stagger nearby timers so adjacent swamps keep readable countdowns.
		draw_line(Vector2(x, lane_y + 18.0), Vector2(x, top), Color(team.r, team.g, team.b, 0.55), 1.0)
		draw_rect(Rect2(left, top, 96.0, 22.0), Color(0.02, 0.03, 0.06, 0.94))
		draw_rect(Rect2(left, top, 96.0, 22.0), team, false, 1.0)
		var text := "만료 대기" if remaining <= 0.0 else ("! 늪 " if imminent else "늪 ") + StructureLifetime.countdown(remaining)
		draw_string(ThemeDB.fallback_font, Vector2(left + 4.0, top + 15.0), text, HORIZONTAL_ALIGNMENT_CENTER, 88.0, 14, tone)
		var lifetime := maxf(0.001, float(BattleModel.STRUCTURE_STATS[String(structure.kind)].get("lifetime", 1.0)))
		draw_rect(Rect2(left + 3.0, top + 18.0, 90.0 * clampf(remaining / lifetime, 0.0, 1.0), 3.0), tone)

func _draw_combat_events(scale_x: float, lane_y: float) -> void:
	for event in visual_events:
		var event_type := String(event.get("type", ""))
		var x := world_to_screen_x(float(event.get("x", 640.0)))
		var life := float(event.life)
		if show_battle_effects:
			if event_type == "ATTACK" and String(event.get("attack_kind", "")) == "castle":
				# A bolt from the castle's battlements to its target.
				var to := Vector2(world_to_screen_x(float(event.get("target_x", event.get("x", 640.0)))), lane_y - 40.0)
				var from := Vector2(x, lane_y - 120.0)
				var head := from.lerp(to, clampf((1.0 - life) * 2.2, 0.0, 1.0))
				draw_line(from.lerp(head, 0.6), head, Color(1.0, 0.86, 0.45, life * effect_intensity), 3.0)
				draw_circle(head, 4.0, Color(1.0, 0.95, 0.75, life * effect_intensity))
			elif event_type in ["ATTACK", "DAMAGE", "BASE_HIT"]:
				draw_circle(Vector2(x, lane_y - 55.0), 18.0 + life * 20.0, Color(1.0, 0.55, 0.2, life * effect_intensity * 0.18))
				draw_circle(Vector2(x, lane_y - 55.0), 9.0 + life * 10.0, Color(1.0, 0.72, 0.28, life * effect_intensity))
				draw_circle(Vector2(x, lane_y - 55.0), 4.0 + life * 4.0, Color(1.0, 0.96, 0.8, life * effect_intensity))
			elif event_type in ["CURSE", "SUMMON"]:
				draw_circle(Vector2(x, lane_y - 28.0), 22.0, Color(0.66, 0.28, 1.0, life * effect_intensity))
			elif event_type == "SUPPORT_BUFF":
				draw_circle(Vector2(x, lane_y - 60.0), 18.0, Color(0.35, 1.0, 0.58, life * effect_intensity))
			elif event_type in ["DEATH", "STRUCTURE_DESTROYED"]:
				draw_circle(Vector2(x, lane_y - 35.0), 32.0 * (1.0 - life), Color(0.8, 0.84, 0.92, life * effect_intensity))
			elif event_type == "SKILL" and String(event.get("kind", "")) == "demon_lord":
				var roar: Texture2D = DEMON_ROAR_TEXTURES[clampi(int((1.0 - life) * DEMON_ROAR_TEXTURES.size()), 0, DEMON_ROAR_TEXTURES.size() - 1)]
				var roar_width := float(event.get("radius", 0.0)) * scale_x * 2.6
				var roar_height := roar_width * float(roar.get_height()) / maxf(1.0, float(roar.get_width()))
				draw_texture_rect(roar, Rect2(x - roar_width * 0.5, lane_y + 14.0 - roar_height, roar_width, roar_height), false, Color(1, 1, 1, clampf(life * 2.0, 0.0, 1.0) * effect_intensity))
			elif event_type == "SOUL":
				# The fallen soul flies to the harvester, then bursts into it.
				var progress := 1.0 - life
				if progress < 0.5:
					var wisp: Texture2D = DEMON_SOUL_TEXTURES[int(animation_time * 12.0) % DEMON_SOUL_TEXTURES.size()]
					var from_x := world_to_screen_x(float(event.get("from_x", event.get("x", 640.0))))
					var wisp_x := lerpf(from_x, x, progress * 2.0)
					var wisp_width := 54.0
					var wisp_height := wisp_width * float(wisp.get_height()) / maxf(1.0, float(wisp.get_width()))
					# The artwork flies leftward; mirror it when the soul travels right.
					var flip := -1.0 if x > from_x else 1.0
					draw_set_transform_matrix(_view_transform() * Transform2D(0.0, Vector2(flip, 1.0), 0.0, Vector2(wisp_x, lane_y - 58.0)))
					draw_texture_rect(wisp, Rect2(-wisp_width * 0.5, -wisp_height * 0.5, wisp_width, wisp_height), false, Color(1, 1, 1, effect_intensity))
					draw_set_transform_matrix(_view_transform())
				else:
					var absorb: Texture2D = DEMON_ABSORB_TEXTURES[clampi(int((progress - 0.5) * 2.0 * DEMON_ABSORB_TEXTURES.size()), 0, DEMON_ABSORB_TEXTURES.size() - 1)]
					var absorb_width := 92.0
					var absorb_height := absorb_width * float(absorb.get_height()) / maxf(1.0, float(absorb.get_width()))
					draw_texture_rect(absorb, Rect2(x - absorb_width * 0.5, lane_y - 58.0 - absorb_height * 0.5, absorb_width, absorb_height), false, Color(1, 1, 1, clampf(life * 3.0, 0.0, 1.0) * effect_intensity))
			elif event_type == "SKILL":
				var pillar: Texture2D = HOLY_PILLAR_TEXTURES[clampi(int((1.0 - life) * HOLY_PILLAR_TEXTURES.size()), 0, HOLY_PILLAR_TEXTURES.size() - 1)]
				var pillar_height := 150.0
				var pillar_width := pillar_height * float(pillar.get_width()) / maxf(1.0, float(pillar.get_height()))
				draw_texture_rect(pillar, Rect2(x - pillar_width * 0.5, lane_y + 6.0 - pillar_height, pillar_width, pillar_height), false, Color(1, 1, 1, clampf(life * 2.0, 0.0, 1.0) * effect_intensity))
				var radius := float(event.get("radius", 0.0)) * scale_x
				draw_arc(Vector2(x, lane_y - 2.0), radius, 0.0, TAU, 32, Color(1.0, 0.86, 0.36, life * 0.6 * effect_intensity), 2.0)
			elif event_type == "SPELL_LAND":
				_draw_spell_land(event, x, life, scale_x, lane_y)
			elif event_type == "KNOCKBACK":
				# Dust where the thrown unit lands.
				for puff in 4:
					var spread := (float(puff) - 1.5) * 12.0 * (1.6 - life)
					draw_circle(Vector2(x + spread, lane_y - 6.0 - float(puff % 2) * 5.0), 7.0 + (1.0 - life) * 9.0, Color(0.72, 0.66, 0.58, life * 0.55 * effect_intensity))
			elif event_type == "JUMP":
				draw_arc(Vector2(x, lane_y - 28.0), 34.0, PI, TAU, 24, Color(1.0, 0.82, 0.32, life), 4.0)
		if show_damage_numbers and event_type in ["DAMAGE", "HEAL", "BASE_HIT"]:
			var amount := int(event.get("amount", 0))
			var text := "+%d" % amount if event_type == "HEAL" else "-%d" % amount
			var color := Color("#75f0a4") if event_type == "HEAL" else (Color("#ffd36a") if event_type == "BASE_HIT" else Color("#ff8a96"))
			color.a = clampf(life * 2.2, 0.0, 1.0)
			var font_size := 17 + mini(amount, 30) / 3 + (6 if event_type == "BASE_HIT" else 0)
			var text_position := Vector2(x - 14.0 + (float(event.get("text_lane",0))-1.5)*8.0, lane_y - 95.0 - float(event.get("text_lane",0))*20.0 - (0.7 - life) * 34.0)
			var display: Font = preload("res://assets/fonts/BlackHanSans-Regular.ttf")
			draw_string_outline(display, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, Color(0.02, 0.03, 0.07, color.a * 0.9))
			draw_string(display, text_position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _build_limits() -> Array:
	return BattleModel.tactic_zone(own_side, selected_structure)

## Vector2 stores float32; use _build_limits() wherever the exact rule constants matter.
func _build_bounds() -> Vector2:
	var limits := _build_limits()
	return Vector2(limits[0], limits[1])

## The cursor stays in world coordinates through the existing screen transform.
## Pick the nearest legal starting point, including exact spacing boundaries.
func begin_keyboard_build() -> void:
	if selected_structure.is_empty() or inspect_mode: return
	var bounds := _build_bounds()
	var desired := screen_to_world_x(mouse_position.x)
	if not Rect2(Vector2.ZERO, size).has_point(mouse_position) or desired < bounds.x or desired > bounds.y:
		desired = (bounds.x + bounds.y) * 0.5
	var candidates: Array = [desired, bounds.x, bounds.y]
	for structure in snapshot.get("structures", []):
		if int(structure.side) != own_side or float(structure.get("hp", 1.0)) <= 0.0: continue
		candidates.append(float(structure.x) - BattleModel.STRUCTURE_MIN_SPACING)
		candidates.append(float(structure.x) + BattleModel.STRUCTURE_MIN_SPACING)
	var chosen := desired
	var distance := INF
	for candidate in candidates:
		var x := float(candidate)
		if x < bounds.x or x > bounds.y or not placement_error(selected_structure, x).is_empty(): continue
		if absf(x - desired) < distance:
			chosen = x
			distance = absf(x - desired)
	reset_build_touch()
	touch_preview_active = false
	keyboard_preview_active = true
	_set_keyboard_build_x(chosen)

func _set_keyboard_build_x(world_x: float) -> void:
	var bounds := _build_bounds()
	keyboard_world_x = clampf(world_x, bounds.x, bounds.y)
	mouse_position = Vector2(world_to_screen_x(keyboard_world_x), size.y * 0.7)
	queue_redraw()

func move_keyboard_build(direction: int, fine: bool = false) -> void:
	if not keyboard_preview_active: begin_keyboard_build()
	if not keyboard_preview_active: return
	var step := BUILD_CURSOR_FINE_STEP if fine else BUILD_CURSOR_STEP
	var world_direction := direction if own_side == 0 else -direction
	_set_keyboard_build_x(keyboard_world_x + float(world_direction) * step)

func jump_keyboard_build(to_front: bool) -> void:
	if not keyboard_preview_active: begin_keyboard_build()
	if not keyboard_preview_active: return
	var bounds := _build_bounds()
	_set_keyboard_build_x(bounds.y if to_front == (own_side == 0) else bounds.x)

func build_preview(world_x: float) -> Dictionary:
	var kind := selected_structure
	var bounds := _build_limits()
	var stats: Dictionary = BattleModel.STRUCTURE_STATS.get(kind, {})
	var error := placement_error(kind, world_x)
	if build_touch_index >= 0 and not Rect2(Vector2.ZERO, size).has_point(mouse_position):
		error = Localization.text("전장 밖에서 손을 떼면 설치하지 않습니다.")
	return {"error": error, "lower": bounds[0], "upper": bounds[1],
		"radius": float(stats.get("radius", stats.get("range", 0.0))), "x": world_x}

func _draw_build_preview(lane_y: float) -> void:
	var preview := build_preview(keyboard_world_x if keyboard_preview_active else screen_to_world_x(mouse_position.x))
	var valid: bool = preview.error.is_empty()
	var build_color := Color(0.30, 0.94, 0.60, 0.24) if valid else Color(1.0, 0.30, 0.40, 0.24)
	var left := world_to_screen_x(float(preview.lower))
	var right := world_to_screen_x(float(preview.upper))
	draw_rect(Rect2(minf(left, right), lane_y - 9.0, absf(right-left), 32.0), Color(0.30, 0.94, 0.60, 0.10))
	# Only living friendly structures exclude placement, just as in the model.
	# Clip their spacing bands to this kind's build zone (rear-only for generators). Spells ignore spacing.
	for structure in ([] if BattleModel.is_spell(selected_structure) else snapshot.get("structures", [])):
		if int(structure.side) != own_side or float(structure.get("hp", 1.0)) <= 0.0: continue
		var start := maxf(float(preview.lower), float(structure.x) - BattleModel.STRUCTURE_MIN_SPACING)
		var end := minf(float(preview.upper), float(structure.x) + BattleModel.STRUCTURE_MIN_SPACING)
		if end <= start: continue
		var start_x := world_to_screen_x(start)
		var end_x := world_to_screen_x(end)
		var excluded := Rect2(minf(start_x, end_x), lane_y - 9.0, absf(end_x - start_x), 32.0)
		draw_rect(excluded, Color(1.0, 0.30, 0.40, 0.25))
		draw_rect(excluded, Color(1.0, 0.45, 0.50, 0.65), false, 1.0)
		# Hatching keeps the spacing cue distinct from the valid zone by shape.
		var stripe_x := excluded.position.x
		while stripe_x + 10.0 <= excluded.end.x:
			draw_line(Vector2(stripe_x, lane_y + 15.0), Vector2(stripe_x + 10.0, lane_y - 1.0), Color(1.0, 0.55, 0.60, 0.65), 1.0)
			stripe_x += 16.0
	draw_line(Vector2(left,lane_y-8.0), Vector2(left,lane_y+24.0), Color("#86f7ad"), 2.0)
	draw_line(Vector2(right,lane_y-8.0), Vector2(right,lane_y+24.0), Color("#86f7ad"), 2.0)
	var radius := float(preview.radius) / BattleModel.WORLD_WIDTH * size.x
	if radius > 0.0:
		draw_ellipse(Vector2(mouse_position.x, lane_y), radius, 21.0, build_color)
		draw_line(Vector2(mouse_position.x-radius,lane_y+4.0), Vector2(mouse_position.x+radius,lane_y+4.0), build_color.lightened(0.4), 2.0)
	draw_rect(Rect2(mouse_position.x-23.0,lane_y-60.0,46.0,60.0), build_color)
	draw_rect(Rect2(mouse_position.x-23.0,lane_y-60.0,46.0,60.0), build_color.lightened(0.4), false, 2.0)
	if keyboard_preview_active:
		var cursor := Vector2(mouse_position.x, lane_y - 70.0)
		draw_line(cursor + Vector2(-7, -5), cursor, GOLD, 2.0)
		draw_line(cursor, cursor + Vector2(7, -5), GOLD, 2.0)
		if valid:
			var label_x := clampf(mouse_position.x - 75.0, 12.0, maxf(12.0, size.x - 180.0))
			draw_rect(Rect2(label_x - 6.0, lane_y - 185.0, 180.0, 26.0), Color(0.02, 0.03, 0.06, 0.94))
			draw_string(ThemeDB.fallback_font, Vector2(label_x, lane_y - 166.0), "Enter · 설치", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, GOLD)
	if not valid:
		var label_x := clampf(mouse_position.x-150.0, 12.0, maxf(12.0,size.x-320.0))
		draw_rect(Rect2(label_x - 6.0, lane_y - 185.0, 320.0, 26.0), Color(0.02, 0.03, 0.06, 0.94))
		draw_string(ThemeDB.fallback_font, Vector2(label_x, lane_y - 166.0), String(preview.error), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("#ff8a96"))
