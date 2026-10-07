extends SceneTree
## Deck simulator: legal auto-battles, deterministic results and sensible advice.

const DeckSimulator = preload("res://scripts/DeckSimulator.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func finish(run) -> void:
	var guard := 0
	while not run.step(50) and guard < 100000:
		guard += 1

func _init() -> void:
	var units := ["shield", "swordsman", "archer"]
	var structures := ["wall", "swamp", "turret"]
	check(DeckSimulator.valid_selection(units, structures), "valid deck accepted")
	check(not DeckSimulator.valid_selection(["shield", "shield", "archer"], structures), "duplicate units rejected")
	var run = DeckSimulator.start(units, structures, 1, 3)
	check(run.progress() == 0.0 and not run.is_done(), "starts at zero")
	finish(run)
	check(run.is_done() and run.results.size() == 3 and run.progress() == 1.0, "all matches run")
	var summary: Dictionary = run.summary()
	check(summary.wins + summary.losses + summary.draws + summary.timeouts == 3, "every match is accounted for")
	check(float(summary.win_rate) >= 0.0 and float(summary.win_rate) <= 1.0, "win rate is a fraction")
	check(summary.average_seconds > 5.0, "battles take real time (%.1fs)" % summary.average_seconds)
	check(summary.wins >= 2, "a balanced deck beats the easiest stage most of the time (%d/3)" % summary.wins)
	var again = DeckSimulator.start(units, structures, 1, 3)
	finish(again)
	check(JSON.stringify(again.results) == JSON.stringify(run.results), "simulation is deterministic")
	# Time slicing: a tiny budget makes progress without finishing.
	var sliced = DeckSimulator.start(units, structures, 2, 1)
	check(not sliced.step(1) and sliced.progress() >= 0.0, "a 1 ms slice does not finish a battle")
	finish(sliced)
	check(sliced.is_done(), "sliced run completes")
	# Advice from hand-made results.
	var Summary = DeckSimulator.DeckSimulatorSummary
	var all_lost: Array = []
	for i in 4:
		all_lost.append({"result": "loss", "seconds": 60.0, "base": 0.0, "enemy_base": 200.0, "kills": 1, "damage": 10.0})
	var weak: Dictionary = Summary.build(all_lost, ["healer", "necromancer", "generator" if false else "warlock"], 5)
	check(weak.win_rate == 0.0 and weak.early_losses == 4, "early losses are counted")
	check(weak.tips.any(func(tip): return tip.contains("앞줄")) and weak.tips.any(func(tip): return tip.contains("초반")), "advice mentions missing frontline and early defence")
	var strong: Array = []
	for i in 5:
		strong.append({"result": "win", "seconds": 120.0, "base": 400.0, "enemy_base": 0.0, "kills": 9, "damage": 900.0})
	var good: Dictionary = Summary.build(strong, units, 3)
	check(good.win_rate == 1.0 and good.tips[0].contains("안정적"), "a perfect record suggests a harder stage")
	check(Summary.build([], units, 1).tips.is_empty(), "no results means no advice")
	print("deck_simulator_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
