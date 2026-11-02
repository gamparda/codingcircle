extends SceneTree
## The 성장 screen: pressing each tab button really switches the page, and quest rows keep their progress bars
## in one column.

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void: call_deferred("run")
func run() -> void:
	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; root.add_child(bootstrap)
	bootstrap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var main = load("res://scenes/Main.tscn").instantiate(); bootstrap.add_child(main); main.updater.enabled = false
	main.save_data = SaveData.default_data(); main.save_data.tutorial_completed = true
	await process_frame
	main.link_enabled = false
	var store = load("res://scripts/accounts/AccountStore.gd").new(); store.configure("")
	var id: String = store.create("s", "탭검사", int(Time.get_unix_time_from_system())).id
	main.account.state = "signed_in"; main.account.session = "x".repeat(64); main.account.nickname = "탭검사"
	main.account.meta = store.meta_state(id)
	load("res://scripts/screens/MetaHub.gd").show(main, "quests")
	await process_frame
	var hub: Node = main.root_background.find_child("MetaHub", true, false)
	check(hub != null, "the hub opens")
	var expect := {"shop": "ShopItem_", "wardrobe": "Wear_", "codex": "Codex_", "profile": "ProfileLookup", "quests": "Quest_"}
	for tab in ["shop", "wardrobe", "codex", "profile", "quests"]:
		var button: Button = hub.find_child("MetaTab_" + tab, true, false)
		check(button != null, "tab button %s exists" % tab)
		if button == null: continue
		button.pressed.emit()
		await process_frame
		await process_frame
		var body: Node = hub.find_child("MetaBody", true, false)
		var found := false
		for node in body.find_children(String(expect[tab]) + "*", "", true, false):
			if not node.is_queued_for_deletion(): found = true
		check(found, "pressing the %s tab shows its page" % tab)
	# Quest rows: the bars start at the same x in every row.
	await process_frame
	var lefts := {}
	for bar in hub.find_children("*", "ProgressBar", true, false):
		if not bar.is_queued_for_deletion() and String(bar.get_parent().get_parent().name).begins_with("Quest_"):
			lefts[roundi(bar.global_position.x)] = true
	check(lefts.size() == 1, "quest progress bars line up (%s)" % str(lefts.keys()))
	print("meta_hub_ui_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
