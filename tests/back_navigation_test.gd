extends SceneTree
## Phone back button (BackNavigation), holding deck cards for their description (DeckScreen) and touch
## scrolling over buttons (TouchScroll).

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate(); bootstrap.add_child(main); main.updater.enabled = false
	main.save_data = SaveData.default_data(); main.save_data.tutorial_completed = true
	await process_frame
	main._build_connect_screen()
	await process_frame
	main._build_deck_screen()
	for i in 5: await process_frame
	var card: Button = main.find_child("DeckStructure_lightning", true, false)
	check(card != null, "the deck screen has tactic cards")
	var before := card.button_pressed
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = card.size / 2
	card.gui_input.emit(down)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 800: await process_frame
	check(main.find_child("DeckCardInfoOverlay", true, false) != null, "holding a card opens its description")
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false
	card.gui_input.emit(up)
	card.button_pressed = not before # what the button's own release would do
	for i in 3: await process_frame
	check(card.button_pressed == before, "the hold does not pick or drop the card")
	# back button closes the overlay
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(main.find_child("DeckCardInfoOverlay", true, false) == null or not main.find_child("DeckCardInfoOverlay", true, false).is_inside_tree(), "back closes the description")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	for i in 3: await process_frame
	check(main.find_child("DeckStructure_lightning", true, false) == null, "back leaves the deck screen")
	# In a solo battle back pauses, and again resumes.
	main._start_local_ai_battle(1)
	for i in 5: await process_frame
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	await process_frame
	check(is_instance_valid(main.local_pause_overlay), "back pauses a solo battle")
	main._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	for i in 2: await process_frame
	check(not is_instance_valid(main.local_pause_overlay) or not main.local_pause_overlay.is_inside_tree(), "back again resumes it")
	check(not quit_on_go_back, "the back button never closes the app by itself")
	# Buttons inside a scrolling list let a drag through to the list (touch scrolling) and press on release.
	var scroll := ScrollContainer.new()
	var list := VBoxContainer.new()
	var inside := Button.new()
	list.add_child(inside)
	scroll.add_child(list)
	var outside := Button.new()
	main.add_child(scroll)
	main.add_child(outside)
	for i in 2: await process_frame
	check(inside.mouse_filter == Control.MOUSE_FILTER_PASS and inside.action_mode == BaseButton.ACTION_MODE_BUTTON_RELEASE, "a button in a scrolling list passes drags to the list")
	check(outside.mouse_filter == Control.MOUSE_FILTER_STOP, "buttons outside lists are unchanged")
	print("back_navigation_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
