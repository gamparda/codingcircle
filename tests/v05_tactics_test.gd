extends SceneTree

var checks := 0
var failures := 0
const Network = preload("res://scripts/NetworkController.gd")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func fixture(side: int, stage: int) -> BattleModel:
	var model := BattleModel.new()
	model.configure_deck(side, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
	model.resources = [180.0, 180.0]
	return model

func enemy(model: BattleModel, ai_side: int, x: float, kind: String = "swordsman") -> void:
	model.spawn_cooldowns[1-ai_side].clear()
	model.spawn_unit(1-ai_side, kind)
	model.units.back().x = x
	model.units.back().speed = 0.0

func _initialize() -> void:
	var used := {}
	for stage in range(1,9):
		var model := fixture(1, stage)
		model.configure_base_health(1, 300.0 + stage * 20.0)
		check(model.base_hp[1] == model.base_max_hp[1], "AI stage %d starts full relative to its real maximum" % stage)
		check(Network.validate_deck_payload(model.unit_decks[1], model.structure_decks[1]), "stage %d has a legal three-unit/three-structure deck" % stage)
		check(Network.is_valid_snapshot(model.snapshot()), "stage %d base maxima pass the online schema" % stage)
		for kind in model.unit_decks[1]: used[kind] = true
		var ai := ServerAI.new(1, stage)
		ai._try_spawn(model)
		check(model.units.size() == 1, "stage %d can make its opening purchase" % stage)
	check(used.size() == BattleModel.UNIT_STATS.size(), "campaign decks cover all seven current purchasable units")
	var hp := fixture(1, 1)
	hp.configure_base_health(1,320.0); hp.base_hp[1]=250.0
	check(hp.snapshot().base_max_hp[1] == 320.0, "damage never changes the base maximum")
	hp.reset()
	check(hp.base_hp[1] == 320.0 and hp.base_max_hp[1] == 320.0, "reset restores full configured base health")
	var bad := hp.snapshot(); bad.base_hp[1]=321.0
	check(not Network.is_valid_snapshot(bad), "reject base current health above its own maximum")
	bad=hp.snapshot(); bad.base_max_hp=[500.0,0.0]
	check(not Network.is_valid_snapshot(bad), "reject zero maximum")
	bad=hp.snapshot(); bad.base_max_hp="wrong"
	check(not Network.is_valid_snapshot(bad), "reject non-array maxima")
	bad=hp.snapshot(); bad.erase("base_max_hp")
	check(Network.is_valid_snapshot(bad), "legacy online snapshots retain the 500 maximum fallback")
	var economy := fixture(1,6)
	var planner := ServerAI.new(1,6)
	economy.resources[1]=70.0
	planner._try_spawn(economy)
	check(economy.units.is_empty() and economy.resources[1]==70.0, "AI saves for a first necromancer rather than wasting the bank on cheap units")
	economy.resources[1]=100.0
	planner._try_spawn(economy)
	check(economy.units.size()==1 and economy.units[0].kind=="necromancer", "AI buys its saved summoner")
	economy.units[0].speed=0.0
	economy.tick(5.0)
	check(economy.units.any(func(unit): return unit.kind=="skeleton"), "AI summoner actually deploys skeletons")
	economy.resources[1]=50.0
	planner._try_place_structure(economy)
	check(economy.structures.size()==1 and economy.structures[0].kind=="generator" and economy.structures[0].x>=BattleModel.RED_REAR_MIN, "AI protects an early generator in its legal rear zone")
	var support := fixture(1,6)
	support.spawn_unit(1,"shield"); support.spawn_cooldowns[1].clear(); support.spawn_unit(1,"shield")
	support.resources[1]=180.0
	planner._try_spawn(support)
	check(support.units.back().kind=="healer", "AI prioritizes permanent speed support for an unbuffed formation")
	for unit in support.units:
		unit.support_stacks=BattleModel.SUPPORT_MAX_STACKS
	var state := planner.tactical_state(support)
	check(planner._unit_score("healer",state)<=8.0, "AI does not purchase redundant support for fully stacked troops")
	var counter := fixture(1,3)
	enemy(counter,1,700.0); enemy(counter,1,720.0)
	var counter_ai := ServerAI.new(1,3)
	counter_ai._try_spawn(counter)
	check(counter.units.back().kind=="warlock", "AI counters multiple melee enemies with the curse caster")
	var curse_caster: Dictionary=counter.units.back()
	curse_caster.x=900.0; curse_caster.speed=0.0; curse_caster.cooldown=0.0
	counter.tick(0.01)
	check(counter.curses.size()==1, "AI curse caster actually installs its current five-second damage debuff")
	for side in 2:
		var defense := fixture(side,8)
		var defense_ai := ServerAI.new(side,8)
		var position := 350.0 if side==0 else 1100.0
		enemy(defense,side,position); enemy(defense,side,position+10.0)
		defense.resources[side]=100.0
		defense_ai._try_spawn(defense)
		check(defense.units.back().side==side and defense.units.back().kind=="shield", "side %d stops saving and answers an immediate threat with a tank" % side)
		defense_ai._try_place_structure(defense)
		check(defense.structures.size()==1 and defense.structures[0].kind=="swamp" and absf(float(defense.structures[0].x)-position)<=BattleModel.STRUCTURE_STATS.swamp.radius, "side %d deploys its short-lived swamp on actual nearby enemies" % side)
		check(defense.structure_placement_error(side,"generator",BattleModel.BLUE_BUILD_MIN+35.0 if side==0 else BattleModel.RED_BUILD_MAX-35.0)=="" or defense.resources[side]<50.0, "side %d uses legal mirrored build coordinates" % side)
	var cap := fixture(1,8)
	for index in 32:
		cap.spawn_cooldowns[1].clear(); cap.resources[1]=180.0; cap.spawn_unit(1,"shield")
	var cap_ai := ServerAI.new(1,8)
	cap_ai._try_spawn(cap)
	check(cap.units.size()==32, "AI limits purchased army size instead of unnecessary late-battle spam")
	if failures==0: print("PASS: %d v0.5 AI tactics, health and wire checks" % checks)
	quit(0 if failures==0 else 1)
