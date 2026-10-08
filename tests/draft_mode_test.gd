extends SceneTree
## Draft mode: alternating picks from one pool, the AI's taste, the battle setup and the screen flow.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const DraftMatch = preload("res://scripts/DraftMatch.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var pool := DraftMatch.pool()
	check(pool.size() >= DraftMatch.PICKS_PER_SIDE * 2 + 1, "the pool is big enough that picks matter (%d units)" % pool.size())
	var draft := DraftMatch.Draft.new(3, 7)
	var first := String(pool[0])
	var reply := draft.human_pick(first)
	check(draft.mine == [first] and draft.theirs == [reply] and reply != "" and reply != first, "the AI answers each pick with a different unit")
	check(draft.human_pick(first) == "" and draft.mine.size() == 1, "a unit cannot be picked twice")
	for kind in draft.available.duplicate():
		if not draft.done():
			draft.human_pick(String(kind))
	var all: Array = draft.mine + draft.theirs
	var unique := {}
	for kind in all:
		unique[kind] = true
	check(draft.done() and draft.mine.size() == 3 and draft.theirs.size() == 3 and unique.size() == 6, "three picks each, no overlap")
	check(draft.human_pick(String(draft.available[0])) == "" and draft.mine.size() == 3, "no picks after the draft is complete")
	var a := DraftMatch.Draft.new(5, 99)
	var b := DraftMatch.Draft.new(5, 99)
	a.human_pick(first)
	b.human_pick(first)
	check(a.theirs == b.theirs, "the same seed drafts the same way")
	var rng := RandomNumberGenerator.new()
	check(DraftMatch.choose([], [], [], 3, rng) == "", "nothing to choose from gives nothing")
	# Taste: with no noise advantage the AI covers different roles.
	var covered := {}
	var ai_draft := DraftMatch.Draft.new(8, 3)
	while ai_draft.theirs.size() < 3:
		ai_draft.ai_pick()
	for kind in ai_draft.theirs:
		covered[DraftMatch.GROUPS.get(kind, "")] = true
	check(covered.size() >= 2, "a late-stage AI does not stack one role: %s" % [ai_draft.theirs])

	var setup := DraftMatch.build(["shield", "archer", "healer"], ["wall", "swamp", "turret"], ["berserker", "warlock", "necromancer"], ["wall", "turret", "generator"], 4)
	check(setup.model.unit_decks[0] == ["shield", "archer", "healer"] and setup.model.unit_decks[1] == ["berserker", "warlock", "necromancer"] and setup.stage == 4, "the battle uses the drafted decks")
	check(setup.model.base_hp[1] == 380.0 and setup.ai is ServerAI, "the opponent is set up like a practice battle of that stage")

	BattleReplay.save_dir = "user://draft_mode_test"
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	check(main.find_child("DraftButton", true, false) != null, "the main menu offers the draft")
	main._build_draft_screen()
	await process_frame
	var cards: Array = main.find_children("DraftCard_*", "Button", true, false)
	check(cards.size() == pool.size(), "one card per unit")
	var start: Button = main.find_child("DraftStart", true, false)
	check(start.disabled, "the battle cannot start before the draft is done")
	for round in 3:
		for card in main.find_children("DraftCard_*", "Button", true, false):
			if not card.disabled:
				card.pressed.emit()
				break
	check(not start.disabled, "the draft completes after three of my picks")
	check(main.find_children("DraftCard_*", "Button", true, false).filter(func(card): return card.disabled).size() >= 5, "picked units are crossed out for both sides")
	start.pressed.emit()
	await process_frame
	check(not main.draft_context.is_empty() and main.local_recorder != null and main.local_model.unit_decks[0].size() == 3, "starting begins a recorded drafted battle")
	var mine: Array = main.local_model.unit_decks[0].duplicate()
	main.set_process(false)
	for i in 60:
		main._process(0.1)
	var matches_before: int = main.save_data.stats.ai_matches
	main.local_model.winner = 0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	await process_frame
	check(main.save_data.stats.ai_matches == matches_before and main.save_data.stats.win_streak == 0, "drafts never touch statistics or streaks")
	check(main.save_data.achievements.has("draft_win"), "winning a draft earns its badge")
	var replay := BattleReplay.load_file(main.last_replay_path)
	check(not replay.is_empty() and replay.meta.mode == "draft" and replay.setup.unit_decks[0] == mine and bool(BattleReplay.verify(replay).ok), "the replay verifies with the drafted decks")
	check(load("res://scripts/screens/ReplayScreens.gd").describe(replay).title.begins_with("드래프트"), "the list names it a draft")
	var again: Button = main.result_overlay.find_children("*", "Button", true, false).filter(func(button): return button.text == "다시 도전")[0]
	again.pressed.emit()
	await process_frame
	check(main.find_child("DraftPool", true, false) != null, "rematch goes back to a fresh draft")
	for path in BattleReplay.list_saved():
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute("user://draft_mode_test")
	print("draft_mode_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
