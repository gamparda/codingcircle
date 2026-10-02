extends SceneTree

const Motion = preload("res://scripts/BattleMotion.gd")
const Sound = preload("res://scripts/RageSound.gd")
const Network = preload("res://scripts/NetworkController.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var motion := Motion.new()
	motion.enabled=true
	var units := [{"id":1,"x":500.0}]
	motion.ingest(units,0.0)
	check(motion.position(1,500.0)==500.0,"first network position appears immediately")
	units[0].x=510.0
	motion.ingest(units,0.1)
	check(motion.position(1,510.0)==500.0,"new packet does not instantly teleport an existing unit")
	motion.advance(0.05)
	check(is_equal_approx(motion.position(1,510.0),505.0),"display moves halfway between packets")
	check(units[0].x==510.0,"interpolation never changes authoritative coordinates")
	units[0].x=520.0
	motion.ingest(units,0.2)
	check(is_equal_approx(motion.position(1,520.0),505.0),"a new packet continues from the currently displayed position")
	motion.advance(1.0)
	check(motion.position(1,520.0)==520.0,"display never extrapolates beyond the last known position")
	motion.ingest([],0.3)
	check(motion.targets.is_empty(),"dead units leave no interpolation ghosts")
	motion.ingest([{"id":1,"x":100.0}],0.0)
	check(motion.position(1,100.0)==100.0,"new match resets reused unit identifiers")
	motion.ingest([{"id":1,"x":600.0}],1.0)
	check(motion.position(1,600.0)==600.0,"long connection gaps snap instead of gliding across the field")
	motion.enabled=false
	check(motion.position(1,650.0)==650.0,"local battles have no interpolation delay")
	var sound=Sound.stream()
	check(sound.data.size()==5120 and is_equal_approx(sound.get_length(),0.16),"rage cue is a real short PCM audio stream")
	check(Sound.stream()==sound,"the cue is generated once and reused")
	var model := BattleModel.new()
	model.configure_deck(0,["berserker","warlock","necromancer"],["wall","swamp","generator"])
	model.resources[0]=180.0
	model.spawn_unit(0,"necromancer")
	check(model.units[0].summon_remaining==5.0,"summoner exposes the real independent five-second timer")
	model.tick(2.0)
	check(is_equal_approx(model.units[0].summon_remaining,3.0),"summon gauge follows the simulation timer")
	model.place_structure(0,"swamp",500.0)
	check(model.structures[0].expires_at==7.0,"swamp exposes its real lifetime")
	check(Network.is_valid_snapshot(model.snapshot()),"network accepts legal timer metadata")
	var bad=model.snapshot(); bad.units[0].summon_remaining=6.0
	check(not Network.is_valid_snapshot(bad),"reject timer values outside the summon interval")
	bad=model.snapshot(); bad.units[0].kind="berserker"
	check(not Network.is_valid_snapshot(bad),"reject summon metadata on a nonsummoner")
	bad=model.snapshot(); bad.structures[0].expires_at=NAN
	check(not Network.is_valid_snapshot(bad),"reject nonfinite structure timers")
	bad=model.snapshot(); bad.structures[0].kind="wall"
	check(not Network.is_valid_snapshot(bad),"reject expiry metadata on permanent structures")
	var legacy=model.snapshot()
	legacy.units[0].erase("summon_remaining"); legacy.structures[0].erase("expires_at")
	check(Network.is_valid_snapshot(legacy),"legacy timer-less snapshots remain supported")
	model.tick(3.0)
	check(model.units.size()==2 and model.units[0].summon_remaining==5.0,"timer resets exactly on the real summon")
	model.tick(2.0)
	check(model.structures.is_empty(),"swamp still expires after exactly five seconds")
	if failures==0: print("PASS: %d combat polish motion, sound and wire checks" % checks)
	quit(0 if failures==0 else 1)
