extends SceneTree
## In-game notices: the 📢 button counts unread notices, an important one opens by itself once, reading it
## clears the count, expired notices drop out, and the read list survives the save.

const Notices = preload("res://scripts/Notices.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void: call_deferred("run")
func run() -> void:
	var ids := {}
	for notice in Notices.NOTICES:
		check(not ids.has(notice.id) and String(notice.id).length() <= 40, "notice ids are unique and short")
		ids[notice.id] = true
		check(String(notice.date).length() == 10 and (String(notice.until).is_empty() or String(notice.until) >= String(notice.date)), "%s has sane dates" % notice.id)
		check(notice.link.is_empty() or String(notice.link[1]).begins_with("https://"), "%s links over https" % notice.id)
	check(Notices.active("2099-01-01").all(func(notice): return String(notice.until).is_empty()), "expired notices drop out")
	var bootstrap := Control.new(); bootstrap.name = "Bootstrap"; root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate(); bootstrap.add_child(main); main.updater.enabled = false
	main.save_data = SaveData.default_data(); main.save_data.tutorial_completed = true
	await process_frame
	main.link_enabled = false
	var unread := Notices.unread(main.save_data).size()
	var important := Notices.unread(main.save_data).filter(func(n): return bool(n.important))
	main._build_connect_screen()
	for i in 3: await process_frame
	var button: Button = main.root_background.find_child("NoticesButton", true, false)
	check(button != null and (unread == 0 or button.text.contains(str(unread))), "the menu shows the unread count")
	if not important.is_empty():
		check(is_instance_valid(main.action_overlay) and String(main.action_overlay.name) == "NoticeOverlay", "an important unread notice opens by itself")
		main.action_overlay.find_child("CloseNotice", true, false).pressed.emit()
		await process_frame
		check(Notices.is_read(main.save_data, String(important[0].id)), "opening a notice marks it read")
		main._build_connect_screen()
		for i in 3: await process_frame
		check(not is_instance_valid(main.action_overlay) or String(main.action_overlay.name) != "NoticeOverlay" or not Notices.unread(main.save_data).any(func(n): return bool(n.important)), "a read notice does not open again")
	var cleaned := SaveData.sanitize(JSON.parse_string(JSON.stringify(main.save_data)))
	check(cleaned.get("read_notices", []) == main.save_data.read_notices, "read notices survive the save")
	button = main.root_background.find_child("NoticesButton", true, false)
	button.pressed.emit()
	await process_frame
	check(is_instance_valid(main.action_overlay) and String(main.action_overlay.name) == "NoticesOverlay", "the button opens the notice list")
	print("notices_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
