extends Resource
## One purchasable (or summon-only) unit. Edit the .tres files in res://data/units/;
## BattleModel, the deck UI, the AI and the balance tools all read these same values.

@export var kind := ""
@export var display_name := ""
## Sort position in deck/battle UI (lower first).
@export var order := 0
@export var summon_only := false
@export var cost := 0.0
@export var hp := 1.0
@export var damage := 0.0
@export var interval := 1.5
@export var speed := 40.0
@export var range := 40.0
## Optional keys that only some units carry (e.g. "heal").
@export var extra := {}

func to_stats() -> Dictionary:
	var stats := {"cost": cost, "hp": hp, "damage": damage, "interval": interval, "speed": speed, "range": range}
	stats.merge(extra)
	return stats
