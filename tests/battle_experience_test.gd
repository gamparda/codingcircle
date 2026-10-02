extends SceneTree
const Report=preload("res://scripts/BattleReport.gd")
const Sounds=preload("res://scripts/CombatSounds.gd")
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:
	var model:=BattleModel.new()
	check(model.spawn_unit(0,"swordsman"),"successful unit purchase")
	check(model.battle_report[0].resources_spent==30 and model.battle_report[0].units.swordsman.purchased==1,"actual purchases and resource spending recorded")
	check(not model.spawn_unit(0,"swordsman") and model.battle_report[0].units.swordsman.purchased==1,"rejected cooldown purchase never counted")
	check(NetworkController.is_valid_snapshot(model.snapshot()),"live cooldown snapshot accepted")
	check(not model.snapshot().has("battle_report"),"live snapshots omit detailed final report")
	var attacker:Dictionary=model.units[0]
	var target:Dictionary={"id":99,"kind":"shield","side":1,"hp":3.0,"speed":0.0,"x":500.0}
	model._damage_target(attacker,target,10.0)
	check(model.battle_report[0].damage==3 and model.battle_report[0].kills==1,"overkill only credits actual health and one unit kill")
	model._damage_target(attacker,target,10.0)
	check(model.battle_report[0].damage==3 and model.battle_report[0].kills==1,"already-dead target cannot yield duplicate credit")
	var skeleton:Dictionary={"id":100,"kind":"skeleton","side":0,"x":500.0}
	var enemy:Dictionary={"id":101,"kind":"archer","side":1,"hp":5.0,"speed":0.0,"x":510.0}
	model._damage_target(skeleton,enemy,10.0)
	check(model.battle_report[0].units.necromancer.damage==5 and model.battle_report[0].units.necromancer.kills==1,"summon performance credited to necromancer")
	model.resources[0]=180
	check(model.place_structure(0,"turret",BattleModel.BLUE_BUILD_MIN),"turret construction")
	check(model.battle_report[0].structures_built==1 and model.battle_report[0].resources_spent==80,"structure spending counted without inflating unit production")
	model.winner=0;var final:=model.snapshot()
	check(Report.valid(final.battle_report) and NetworkController.is_valid_snapshot(final),"final report passes strict wire validation")
	var bad:=final.duplicate(true);bad.battle_report[0].kills=99
	check(not NetworkController.is_valid_snapshot(bad),"inconsistent totals rejected")
	bad=final.duplicate(true);bad.spawn_cooldowns[0].swordsman=4.0
	check(not NetworkController.is_valid_snapshot(bad),"out-of-range purchase cooldown rejected")
	model.reset()
	check(model.battle_report[0].resources_spent==0 and model.battle_report[0].damage==0 and model.battle_report[0].kills==0,"new match resets every aggregate")
	for kind in Sounds.DURATIONS:
		var sound:=Sounds.stream(kind)
		check(sound!=null and sound.data.size()>0 and sound==Sounds.stream(kind),"generated sound cached: "+kind)
	check(Sounds.event_sound({"type":"ATTACK","attack_kind":"archer"})=="arrow" and Sounds.event_sound({"type":"ATTACK","attack_kind":"swordsman"})=="melee","ranged and melee hit sounds distinguished")
	check(Sounds.event_sound({"type":"DEATH"})=="death" and Sounds.event_sound({"type":"STRUCTURE_DESTROYED"})=="destroy","unit death and structure destruction sound categories")
	if failures==0:print("PASS: %d combat-report, cooldown, summon-credit and procedural-audio checks"%checks)
	quit(0 if failures==0 else 1)
