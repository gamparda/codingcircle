extends SceneTree

const Report = preload("res://scripts/BattleReport.gd")
const Network = preload("res://scripts/NetworkController.gd")
var failures := 0
var checks := 0

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func duel(reverse_order: bool) -> BattleModel:
	var model := BattleModel.new()
	model.resources = [180.0, 180.0]
	model.spawn_unit(0, "swordsman")
	model.spawn_unit(1, "swordsman")
	for side in 2:
		model.units[side].x = 700.0 + side * 30.0
		model.units[side].hp = 10.0
		model.units[side].cooldown = 0.0
	if reverse_order: model.units.reverse()
	return model

func _initialize() -> void:
	for reversed in [false, true]:
		var model := duel(reversed)
		model.tick(1.0/30.0)
		check(model.units.is_empty(), "both lethal melee attacks land regardless of array order")
		check(model.battle_report[0].kills == 1 and model.battle_report[1].kills == 1, "both sides receive their simultaneous kill")
		check(Report.valid(model.battle_report), "simultaneous report totals remain valid")
	var bases := duel(false)
	bases.base_hp = [10.0, 10.0]
	bases.units[0].x = BattleModel.FIELD_RIGHT
	bases.units[1].x = BattleModel.FIELD_LEFT
	bases.tick(1.0/30.0)
	check(bases.winner == 2 and bases.base_hp == [0.0, 0.0], "same-tick base destruction resolves as a draw")
	check(Network.is_valid_snapshot(bases.snapshot()), "draw with authoritative battle report passes the wire schema")
	var progress := SaveData.default_data()
	check(SaveData.record_campaign(progress,1,false,60.0,0.0,true)==0 and progress.stats.ai_matches==1 and progress.stats.ai_losses==0 and SaveData.campaign_growth_level(progress)==0,"campaign draw counts an attempt without a loss, clear or growth")
	SaveData.record_campaign(progress,1,false,60.0,0.0)
	check(progress.stats.ai_losses==1,"legacy five-argument defeat recording still counts a loss")
	var turret := BattleModel.new()
	turret.resources = [180.0,180.0]
	turret.place_structure(0,"turret",500.0)
	turret.spawn_unit(1,"swordsman")
	turret.structures[0].hp = 10.0
	turret.structure_cooldowns[turret.structures[0].id] = 0.0
	turret.units[0].hp = 8.0
	turret.units[0].x = 530.0
	turret.units[0].cooldown = 0.0
	turret.tick(1.0/30.0)
	check(turret.units.is_empty() and turret.structures.is_empty(), "turret and melee unit can trade lethal attacks")
	check(Report.valid(turret.battle_report), "turret trade records effective damage once")
	var mirror := BattleModel.new()
	mirror.resources = [180.0,180.0]
	for kind in ["shield","swordsman","archer"]:
		mirror.spawn_unit(0,kind)
		mirror.spawn_unit(1,kind)
	for step in 1200:
		mirror.tick(1.0/30.0)
		mirror.combat_events.clear()
		var blue: Array = mirror.units.filter(func(unit): return unit.side == 0)
		var red: Array = mirror.units.filter(func(unit): return unit.side == 1)
		if blue.size() != red.size():
			check(false,"mirrored formations retain equal live counts"); break
		for i in blue.size():
			if not is_equal_approx(float(blue[i].hp),float(red[i].hp)) or not is_equal_approx(float(blue[i].x) + float(red[i].x),BattleModel.FIELD_LEFT+BattleModel.FIELD_RIGHT):
				check(false,"mirrored formations retain reflected positions and equal health"); break
	check(mirror.base_hp[0] == mirror.base_hp[1], "mirrored formation has no side advantage")
	print("%s: %d simultaneous combat checks" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
