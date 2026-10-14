extends RefCounted
## Read-only forecasts from battle time. Never advance a stale/paused snapshot
## using wall time, or treat a forecast as permission to install a structure.

const WARNING_SECONDS := 2.0

static func remaining(structure: Dictionary, elapsed: float) -> float:
	if not structure.has("expires_at"): return -1.0
	return maxf(0.0, float(structure.expires_at) - elapsed)

static func countdown(seconds: float) -> String:
	# Ignore subtraction noise at exact tenths, but never show zero early.
	var tenths := maxf(1.0, ceilf(seconds * 10.0 - 0.000001)) if seconds > 0.0 else 0.0
	return "%.1f초" % (tenths / 10.0)

static func expiry_clock(structure: Dictionary) -> String:
	var tenths := ceili(maxf(0.0, float(structure.get("expires_at", 0.0))) * 10.0 - 0.000001)
	var seconds := tenths / 10
	return "%02d:%02d.%d" % [seconds / 60, seconds % 60, tenths % 10]

static func timed_structures(values: Array, side: int) -> Array:
	var timed: Array = []
	for structure in values:
		if int(structure.side) == side and float(structure.get("hp", 0.0)) > 0.0 and structure.has("expires_at"):
			timed.append(structure)
	timed.sort_custom(func(a: Dictionary, b: Dictionary):
		if float(a.expires_at) == float(b.expires_at): return int(a.id) < int(b.id)
		return float(a.expires_at) < float(b.expires_at))
	return timed

## Find the first expiration that clears BOTH total and kind limits. For
## example, an expiring swamp cannot clear a permanent turret's kind limit.
## -1 means expirations alone cannot clear the current limits.
static func limit_wait(timed: Array, kind: String, counts: Dictionary, elapsed: float) -> float:
	var total := int(counts.total)
	var amount := int(counts.kinds.get(kind, 0))
	var maximum := int(BattleModel.STRUCTURE_STATS[kind].get("max_count", BattleModel.STRUCTURE_LIMIT))
	if total < BattleModel.STRUCTURE_LIMIT and amount < maximum: return -1.0
	for structure in timed:
		total -= 1
		if String(structure.kind) == kind: amount -= 1
		if total < BattleModel.STRUCTURE_LIMIT and amount < maximum:
			return remaining(structure, elapsed)
	return -1.0
