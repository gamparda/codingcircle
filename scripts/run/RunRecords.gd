extends RefCounted
## Records and the saved run of the offline run modes, stored in the profile under "runs":
##   "endless": {"best_wave", "best_seconds", "runs", "total_waves", "saved": {} or a run to resume}
## A saved endless run is the state at a wave break: {"wave" (next wave), "boons", "base_hp", "units",
## "structures", "seed", "seconds" (time survived so far)}; resuming starts that wave on a fresh field.

const RunBoons = preload("res://scripts/run/RunBoons.gd")

static func default_runs() -> Dictionary:
	return {"endless": {"best_wave": 0, "best_seconds": 0.0, "runs": 0, "total_waves": 0, "saved": {}}}

static func endless(data: Dictionary) -> Dictionary:
	if not data.get("runs") is Dictionary:
		data["runs"] = default_runs()
	return data.runs.endless

static func _count(value: Variant, limit: int = 1000000) -> int:
	return clampi(int(value), 0, limit) if (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) else 0

static func sanitize(raw: Variant) -> Dictionary:
	var clean := default_runs()
	if not raw is Dictionary or not raw.get("endless") is Dictionary:
		return clean
	var source: Dictionary = raw.endless
	var target: Dictionary = clean.endless
	target.best_wave = _count(source.get("best_wave"), 999)
	target.runs = _count(source.get("runs"))
	target.total_waves = _count(source.get("total_waves"), 100000000)
	var seconds = source.get("best_seconds")
	target.best_seconds = clampf(float(seconds), 0.0, 1000000.0) if (seconds is int or seconds is float) and is_finite(float(seconds)) else 0.0
	target.saved = sanitize_saved(source.get("saved"))
	return clean

static func sanitize_saved(raw: Variant) -> Dictionary:
	if not raw is Dictionary or raw.is_empty():
		return {}
	var wave := _count(raw.get("wave"), 999)
	var base = raw.get("base_hp")
	if wave < 1 or not (base is int or base is float) or not is_finite(float(base)) or float(base) <= 0.0:
		return {}
	if not raw.get("units") is Array or not raw.get("structures") is Array or not raw.get("boons") is Array:
		return {}
	for list in [raw.units, raw.structures, raw.boons]:
		for value in list:
			if not value is String:
				return {}
	if not BattleModel._valid_deck(raw.units, BattleModel.UNIT_STATS) or not BattleModel._valid_deck(raw.structures, BattleModel.STRUCTURE_STATS):
		return {}
	var boons: Array = raw.boons.filter(func(id): return RunBoons.RELICS.has(id)).slice(0, 200)
	return {"wave": wave, "base_hp": minf(float(base), 100000.0), "units": raw.units.duplicate(), "structures": raw.structures.duplicate(),
		"boons": boons, "seed": _count(raw.get("seed"), 2147483647), "seconds": float(_count(roundf(float(raw.get("seconds", 0.0))) if (raw.get("seconds") is int or raw.get("seconds") is float) and is_finite(float(raw.seconds)) else 0))}

## Records a finished endless run; returns true when it set a new best (more waves, then a longer stand).
static func record_endless(data: Dictionary, waves_cleared: int, seconds: float) -> bool:
	var record := endless(data)
	record.runs = int(record.runs) + 1
	record.total_waves = int(record.total_waves) + waves_cleared
	record.saved = {}
	var best := waves_cleared > int(record.best_wave) or (waves_cleared == int(record.best_wave) and waves_cleared > 0 and seconds > float(record.best_seconds))
	if best:
		record.best_wave = waves_cleared
		record.best_seconds = seconds
	return best
