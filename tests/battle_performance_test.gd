extends SceneTree
## Big battles stay cheap: targeting through the per-tick lane index, and supports looking only at allies that
## still need a buff, pick exactly what scanning every unit picks (same battle, same state hash), and a tick
## grows about linearly with the number of units.
const AutoPlayer = preload("res://scripts/AutoPlayer.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func battle(units_a: Array, units_b: Array, tactics: Array, seed_value: int, indexed: bool) -> String:
	BattleModel.targeting_index = indexed
	var model := BattleModel.new()
	model.configure_deck(0, units_a, tactics)
	model.configure_deck(1, units_b, tactics)
	model.base_max_hp = [4000.0, 4000.0]
	model.base_hp = [4000.0, 4000.0]
	var players := [AutoPlayer.new(0, "weighted", seed_value, units_a), AutoPlayer.new(1, "weighted", seed_value + 1, units_b)]
	for step in 30 * 150:
		for player in players:
			player.update(model, 1.0 / 30.0)
		model.resources[0] = minf(model.resource_capacity(0), model.resources[0] + 3.0) # crowd the field
		model.resources[1] = minf(model.resource_capacity(1), model.resources[1] + 3.0)
		model.tick(1.0 / 30.0)
		if model.winner != -1:
			break
	BattleModel.targeting_index = true
	return "%s units=%d t=%.1f" % [model.state_hash(), model.units.size(), model.elapsed]

func crowd(per_side: int) -> float:
	var model := BattleModel.new()
	var deck := ["shield", "archer", "swordsman", "healer"]
	model.configure_deck(0, deck, ["wall", "turret", "generator", "swamp"])
	model.configure_deck(1, deck, ["wall", "turret", "generator", "swamp"])
	model.base_max_hp = [999999.0, 999999.0]
	model.base_hp = [999999.0, 999999.0]
	for side in 2:
		for i in per_side:
			model.resources[side] = 9999.0
			model.spawn_cooldowns[side].clear()
			model.spawn_unit(side, String(deck[i % deck.size()]))
			var unit: Dictionary = model.units.back()
			unit.x = (500.0 + (i % 20) * 6.0) if side == 0 else (800.0 - (i % 20) * 6.0)
			unit.max_hp = 99999.0
			unit.hp = 99999.0
	for i in 10:
		model.tick(1.0 / 30.0)
	var started := Time.get_ticks_usec()
	for i in 40:
		model.tick(1.0 / 30.0)
	return float(Time.get_ticks_usec() - started) / 40.0

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var tactics := ["wall", "turret", "swamp", "fireball"]
	var matchups := [
		[["shield", "archer", "sniper", "swordsman"], ["zombie", "necromancer", "warlock", "berserker"]],
		[["paladin", "sniper", "warlock", "demon_lord"], ["shield", "archer", "swordsman", "necromancer"]],
		[["berserker", "zombie", "archer", "warlock"], ["sniper", "paladin", "swordsman", "shield"]],
		[["shield", "archer", "healer", "swordsman"], ["swordsman", "berserker", "healer", "warlock"]],
		[["healer", "paladin", "sniper", "zombie"], ["healer", "necromancer", "archer", "shield"]],
	]
	for index in matchups.size():
		var pair: Array = matchups[index]
		var indexed := battle(pair[0], pair[1], tactics, 40 + index, true)
		var scanned := battle(pair[0], pair[1], tactics, 40 + index, false)
		check(indexed == scanned, "the lane index picks what the scans pick (%d): %s vs %s" % [index, indexed, scanned])
	var small := crowd(32)
	var large := crowd(128)
	# Linear growth is 4x for 4x the units; the old all-pairs scans grew about 16x.
	check(large < small * 9.0, "a tick grows about linearly with the units (64: %.0f us, 256: %.0f us)" % [small, large])
	print("battle_performance_test failures=%d (64 units %.0f us, 256 units %.0f us per tick)" % [failures, small, large])
	quit(1 if failures > 0 else 0)
