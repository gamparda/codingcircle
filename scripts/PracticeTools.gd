extends RefCounted
var paused := false
var speed := 1.0
var unlimited := false
var enemy_units: Array = []
var enemy_structures: Array = []
const SPEEDS := [0.5,1.0,2.0,4.0]
func cycle_speed() -> void:
	speed = SPEEDS[(SPEEDS.find(speed)+1)%SPEEDS.size()]
func valid_enemy_deck(units: Array, structures: Array) -> bool:
	return BattleModel._valid_deck(units,BattleModel.UNIT_STATS) and BattleModel._valid_deck(structures,BattleModel.STRUCTURE_STATS)
func set_enemy_deck(units: Array, structures: Array) -> bool:
	if not valid_enemy_deck(units,structures): return false
	enemy_units = units.duplicate(); enemy_structures = structures.duplicate(); return true
func reset_battle_state() -> void:
	paused = false
func refill(model: BattleModel, side: int) -> void:
	if unlimited and model.winner==-1: model.resources[side] = model.resource_capacity(side)
func advance(model: BattleModel, ai: ServerAI, delta: float, side: int) -> void:
	if paused or model.winner!=-1: return
	var remaining := clampf(delta,0.0,0.25)*speed
	while remaining>0.00001 and model.winner==-1:
		var step := minf(remaining,0.05)
		refill(model,side); ai.update(model,step); model.tick(step); remaining-=step
	refill(model,side)
