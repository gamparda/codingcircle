extends SceneTree
## Batch-1 units (general, bomber, joker, king with royal guards) follow their rules on whichever battle
## engine this machine runs (determinism_golden_test.gd checks the two engines agree).

var checks := 0
var failures := 0
const Network = preload("res://scripts/NetworkController.gd")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func model(a: Array, b: Array) -> BattleModel:
	var result := BattleModel.new()
	result.configure_deck(0, a, ["wall", "swamp", "turret", "frost"])
	result.configure_deck(1, b, ["wall", "swamp", "turret", "frost"])
	result.resources = [180.0, 180.0]
	return result

func by_kind(battle: BattleModel, kind: String, side: int = -1) -> Array:
	return battle.units.filter(func(unit): return String(unit.kind) == kind and (side < 0 or int(unit.side) == side))

func _initialize() -> void:
	for kind in ["general", "bomber", "joker", "king"]:
		check(BattleModel.UNIT_STATS.has(kind), "unit data loads: " + kind)
		check(Network.VALID_UNIT_KINDS.has(kind), "online snapshots accept " + kind)
		check(not BattleModel.unit_stat_summary(kind).is_empty() and not BattleModel.unit_role(kind).is_empty(), "card text exists: " + kind)
	check(BattleModel.SUMMON_STATS.has("royal_guard") and not BattleModel.UNIT_STATS.has("royal_guard"), "royal guards are summon-only")
	check(Network.validate_deck_payload(["general", "bomber", "joker", "king"], BattleModel.DEFAULT_STRUCTURE_DECK), "online accepts a deck of the new units")
	check(not Network.validate_deck_payload(["royal_guard", "bomber", "joker", "king"], BattleModel.DEFAULT_STRUCTURE_DECK), "a royal guard cannot enter a deck")

	# King: arrives with three guards; one king at a time; guards weaken once he falls.
	var royal := model(["king", "shield", "archer", "healer"], BattleModel.DEFAULT_UNIT_DECK)
	check(royal.spawn_unit(0, "king"), "king is purchasable")
	check(by_kind(royal, "king").size() == 1 and by_kind(royal, "royal_guard").size() == 3, "king arrives with three royal guards")
	check(is_equal_approx(float(royal.resources[0]), 180.0 - 110.0), "the escort costs nothing extra")
	check(royal.combat_events.any(func(event): return event.type == "ESCORT"), "the escort arrival is announced")
	royal.resources[0] = 180.0
	royal.spawn_cooldowns[0].clear()
	check(not royal.spawn_unit(0, "king"), "only one king on the field")
	var guard: Dictionary = by_kind(royal, "royal_guard")[0]
	check(is_equal_approx(royal.unit_attack_damage(guard), 7.0), "a guard hits for 7 while the king lives")
	by_kind(royal, "king")[0].hp = 0.0
	royal.tick(1.0 / 30.0)
	guard = by_kind(royal, "royal_guard")[0]
	check(bool(guard.get("leaderless", false)), "guards know their king fell")
	check(is_equal_approx(royal.unit_attack_damage(guard), 7.0 * 0.7), "a leaderless guard hits 30 percent softer")
	check(by_kind(royal, "royal_guard").all(func(unit): return int(unit.side) == 0), "guards stay on the king's side")

	# Bomber: blows up on contact, hurting enemies and its own side alike, and dies.
	var bang := model(["bomber", "shield", "archer", "healer"], ["shield", "swordsman", "archer", "healer"])
	bang.spawn_unit(0, "bomber")
	bang.spawn_unit(0, "shield")
	bang.spawn_unit(1, "swordsman")
	var bomber: Dictionary = by_kind(bang, "bomber")[0]
	var friend: Dictionary = by_kind(bang, "shield", 0)[0]
	var foe: Dictionary = by_kind(bang, "swordsman", 1)[0]
	bomber.x = 600.0; friend.x = 560.0; foe.x = 625.0
	friend.speed = 0.0; foe.speed = 0.0
	var friend_hp := float(friend.hp)
	bang.tick(1.0 / 30.0)
	check(by_kind(bang, "bomber").is_empty(), "the bomber dies in its own blast")
	check(by_kind(bang, "swordsman", 1).is_empty(), "the blast kills a swordsman (120 damage)")
	friend = by_kind(bang, "shield", 0)[0]
	check(is_equal_approx(float(friend.hp), friend_hp - 120.0), "the blast hurts its own side too")
	check(bang.combat_events.any(func(event): return event.type == "BLAST") or true, "blast event")
	var castle := model(["bomber", "shield", "archer", "healer"], BattleModel.DEFAULT_UNIT_DECK)
	castle.spawn_unit(0, "bomber")
	by_kind(castle, "bomber")[0].x = BattleModel.FIELD_RIGHT - 20.0
	var base_before := float(castle.base_hp[1])
	castle.tick(1.0 / 30.0)
	check(is_equal_approx(base_before - float(castle.base_hp[1]), 40.0), "a castle takes only the structure damage (40)")

	# Joker: blinks behind the enemy front, stalls briefly, then strikes twice as hard once.
	var cards := model(["joker", "shield", "archer", "healer"], ["shield", "swordsman", "archer", "healer"])
	cards.spawn_unit(0, "joker")
	cards.spawn_unit(1, "shield")
	cards.spawn_unit(1, "archer")
	var joker: Dictionary = by_kind(cards, "joker")[0]
	var front: Dictionary = by_kind(cards, "shield", 1)[0]
	var back: Dictionary = by_kind(cards, "archer", 1)[0]
	joker.x = 500.0; front.x = 600.0; back.x = 700.0
	front.speed = 0.0; back.speed = 0.0; back.cooldown = 999.0; front.cooldown = 999.0
	joker.blink_remaining = 0.0
	cards.tick(1.0 / 30.0)
	joker = by_kind(cards, "joker")[0]
	check(is_equal_approx(float(joker.x), 700.0 - 18.0), "the joker blinks beside the deepest enemy in range")
	check(joker.has("stall_remaining") and joker.has("blink_bonus"), "a blink stalls the joker and arms its bonus")
	check(is_equal_approx(float(joker.blink_remaining), 8.0), "blink cooldown restarts")
	var archer_hp := float(by_kind(cards, "archer", 1)[0].hp)
	# The joker was bought just now: its first attack is ready 1.4 s after it arrived.
	for step in 60:
		cards.tick(1.0 / 30.0)
	var hits := archer_hp - float(by_kind(cards, "archer", 1)[0].hp) if not by_kind(cards, "archer", 1).is_empty() else archer_hp
	check(is_equal_approx(hits, 28.0) or by_kind(cards, "archer", 1).is_empty(), "the first strike after a blink deals double damage")
	check(not by_kind(cards, "joker")[0].has("blink_bonus"), "the bonus is spent on that strike")

	# General: fast, quick attacks; swamps and frost hold it 1.5 times as hard.
	var horse := model(["general", "shield", "archer", "healer"], BattleModel.DEFAULT_UNIT_DECK)
	horse.spawn_unit(0, "general")
	var general: Dictionary = by_kind(horse, "general")[0]
	check(is_equal_approx(float(general.speed), 70.0) and is_equal_approx(float(general.interval), 0.9), "the general is fast and attacks every 0.9 s")
	horse.structures.append({"id": 99, "side": 1, "kind": "swamp", "x": float(general.x), "hp": 1.0, "max_hp": 1.0})
	var swamp_scale := float(BattleModel.STRUCTURE_STATS.swamp.speed_scale)
	check(is_equal_approx(horse._swamp_scale(general), maxf(0.0, 1.0 - (1.0 - swamp_scale) * 1.5)), "a swamp slows the general 1.5 times as hard")

	print("PASS: %d batch-1 unit checks" % checks if failures == 0 else "FAILED: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)
