extends Resource
## One placeable structure. Edit the .tres files in res://data/structures/.

@export var kind := ""
@export var display_name := ""
@export var order := 0
@export var cost := 0.0
@export var hp := 1.0
## Structure-specific numbers: damage/interval/range (turret), income (generator),
## speed_scale/radius/lifetime (swamp), max_count (wall, turret, generator).
@export var params := {}

func to_stats() -> Dictionary:
	var stats := {"cost": cost, "hp": hp}
	stats.merge(params)
	return stats
