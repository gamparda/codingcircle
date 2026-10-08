extends SceneTree
## Base-collapse finale: slow motion before the result when a base was destroyed, none for surrenders.

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func wait_until(predicate: Callable, seconds: float = 3.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.05, true, false, true).timeout
	return predicate.call()

func run() -> void:
	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	check(main.finale_seconds == 0.0, "headless runs skip the finale by default")
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main._start_local_ai_battle(1)
	main.set_process(false)
	# Without the finale the result appears at once.
	main.local_model.winner = 0
	main.local_model.base_hp[1] = 0.0
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.result_shown and not main.finale_active and not main.battle_view.finale_active(), "no finale when disabled")

	# With the finale: slow motion first, result afterwards.
	main._start_local_ai_battle(1)
	main.set_process(false)
	main.finale_seconds = 0.4
	main.local_model.winner = 0
	main.local_model.base_hp[1] = 0.0
	main._on_snapshot(main.local_model.snapshot())
	check(not main.result_shown and main.finale_active and main.battle_view.finale_active(), "a destroyed base starts the finale and holds the result")
	check(is_equal_approx(Engine.time_scale, 0.35) and main.battle_view.display_side(1) == main.battle_view.display_side(main.battle_view.finale_world_side), "time slows and the loser's base is the one collapsing")
	main._on_snapshot(main.local_model.snapshot())
	check(not main.result_shown, "further snapshots do not cut the finale short")
	for i in 5:
		main.battle_view.finale_age += 0.2
		main.battle_view.queue_redraw()
		await process_frame
	check(await wait_until(func(): return main.result_shown), "the result appears when the finale ends")
	check(is_equal_approx(Engine.time_scale, 1.0) and not main.finale_active, "time returns to normal")

	# Surrender: the base is intact, so there is nothing to collapse.
	main._start_local_ai_battle(1)
	main.set_process(false)
	main.local_model.winner = 1
	main._on_snapshot(main.local_model.snapshot())
	await process_frame
	check(main.result_shown and not main.finale_active and Engine.time_scale == 1.0, "a surrender shows the result immediately")
	Engine.time_scale = 1.0
	print("battle_finale_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
