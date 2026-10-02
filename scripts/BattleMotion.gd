class_name BattleMotion
extends RefCounted

# Display-only interpolation: never write interpolated values into game snapshots.
var enabled := false
var starts: Dictionary = {}
var targets: Dictionary = {}
var age := 0.0
var duration := 1.0 / 12.0
var last_elapsed := -1.0

func reset() -> void:
	starts.clear()
	targets.clear()
	age = 0.0
	last_elapsed = -1.0

func position(id: int, fallback: float) -> float:
	if not enabled or not targets.has(id): return fallback
	return lerpf(float(starts.get(id, targets[id])), float(targets[id]), clampf(age / duration, 0.0, 1.0))

func ingest(units: Array, elapsed: float) -> void:
	var interval := elapsed - last_elapsed
	var discontinuity := last_elapsed < 0.0 or interval < 0.0 or interval > 0.5
	var new_starts := {}
	var new_targets := {}
	for unit in units:
		var id := int(unit.id)
		var x := float(unit.x)
		new_starts[id] = x if discontinuity or not targets.has(id) else position(id, x)
		new_targets[id] = x
	starts = new_starts
	targets = new_targets
	duration = clampf(interval, 0.04, 0.18) if interval > 0.0 else 1.0 / 12.0
	age = 0.0
	last_elapsed = elapsed

func advance(delta: float) -> void:
	age += maxf(0.0, delta)
