extends Resource
## One tactic card: a placeable structure, or a spell when params has "spell": true (then `hp` is unused).
## A structure with hp 0 (the swamp) has no health: nothing attacks it and it lasts until its lifetime ends.
## Edit the .tres files in res://data/structures/.

@export var kind := ""
@export var display_name := ""
@export var order := 0
@export var cost := 0.0
@export var hp := 1.0
## Structure-specific numbers: damage/interval/range (turret), income (generator),
## speed_scale/radius/lifetime (swamp), max_count (wall, turret, generator).
## Spells: effect (strike/blast/freeze/bless/resurrect), zone ("any" or "own"), cooldown, delay, radius,
## and per effect damage, speed (thrown from the base), duration, attack_speed, revive_count,
## revive_fraction, max_uses (per battle).
@export var params := {}

func to_stats() -> Dictionary:
	var stats := {"cost": cost, "hp": hp}
	stats.merge(params)
	return stats
