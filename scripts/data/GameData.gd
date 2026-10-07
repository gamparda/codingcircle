extends RefCounted
## Loads unit/structure definitions from res://data into the plain dictionaries the
## battle model, UI and AI consume. File lists are explicit (not directory scans) so
## exported builds, which remap .tres files, load exactly the same set.

const UnitDef = preload("res://scripts/data/UnitDef.gd")
const StructureDef = preload("res://scripts/data/StructureDef.gd")

const UNIT_FILES := ["shield", "swordsman", "archer", "healer", "berserker", "warlock", "necromancer"]
const SUMMON_FILES := ["skeleton"]
const STRUCTURE_FILES := ["wall", "swamp", "turret", "generator"]

static func _load_defs(folder: String, names: Array) -> Array:
	var defs: Array = []
	for name in names:
		var def: Resource = load("res://data/%s/%s.tres" % [folder, name])
		assert(def != null and String(def.kind) == name, "bad definition: %s/%s" % [folder, name])
		defs.append(def)
	defs.sort_custom(func(a, b): return int(a.order) < int(b.order))
	return defs

static func unit_stats() -> Dictionary:
	var out := {}
	for def in _load_defs("units", UNIT_FILES):
		out[String(def.kind)] = def.to_stats()
	return out

static func summon_stats() -> Dictionary:
	var out := {}
	for def in _load_defs("units", SUMMON_FILES):
		out[String(def.kind)] = def.to_stats()
	return out

static func structure_stats() -> Dictionary:
	var out := {}
	for def in _load_defs("structures", STRUCTURE_FILES):
		out[String(def.kind)] = def.to_stats()
	return out

static func unit_names() -> Dictionary:
	var out := {}
	for def in _load_defs("units", UNIT_FILES + SUMMON_FILES):
		out[String(def.kind)] = String(def.display_name)
	return out
