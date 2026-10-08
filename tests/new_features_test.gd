extends SceneTree
## "새 기능" guidance: tags on menu buttons, the chip with a count, the list and persistence.

const NewFeatures = preload("res://scripts/NewFeatures.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var save := SaveData.default_data()
	check(NewFeatures.unseen(save).size() == NewFeatures.FEATURES.size(), "a fresh save has every feature unseen")
	NewFeatures.mark_seen(save, "draft")
	NewFeatures.mark_seen(save, "draft")
	check(save.seen_features == ["draft"] and NewFeatures.is_seen(save, "draft") and NewFeatures.unseen(save).size() == NewFeatures.FEATURES.size() - 1, "marking is idempotent")
	NewFeatures.mark_button_seen(save, "ReplaysButton")
	check(NewFeatures.is_seen(save, "replay_share"), "pressing a button marks the features behind it")
	var restored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(restored.seen_features.has("draft") and restored.seen_features.has("replay_share"), "seen features survive saving")
	var junk := SaveData.sanitize({"seen_features": ["draft", 5, "", "draft", "x".repeat(80)]})
	check(junk.seen_features == ["draft"], "junk entries are dropped")
	var ids := {}
	var buttons_ok := true
	for feature in NewFeatures.FEATURES:
		ids[feature.id] = true
		buttons_ok = buttons_ok and not String(feature.title).is_empty() and not String(feature.desc).is_empty()
	check(ids.size() == NewFeatures.FEATURES.size() and buttons_ok, "feature ids are unique and described")

	var bootstrap := Control.new()
	bootstrap.name = "Bootstrap"
	root.add_child(bootstrap)
	var main = load("res://scenes/Main.tscn").instantiate()
	bootstrap.add_child(main)
	main.updater.enabled = false
	await process_frame
	main.save_data = SaveData.default_data()
	main.save_data.tutorial_completed = true
	main._build_connect_screen()
	await process_frame
	var weekly = main.find_child("WeeklyButton", true, false)
	check(weekly.find_child("NewTag", false, false) != null and main.find_child("DraftButton", true, false).find_child("NewTag", false, false) != null, "unseen features get a NEW tag")
	check(main.find_child("NewFeaturesChip", true, false).text.contains(str(NewFeatures.FEATURES.size())), "the chip shows how many are new")
	main.find_child("NewFeaturesChip", true, false).pressed.emit()
	await process_frame
	check(main.find_child("NewFeatureList", true, false).get_child_count() == NewFeatures.FEATURES.size(), "the list has one row per feature")
	main.find_child("OpenFeature_draft", true, false).pressed.emit()
	await process_frame
	check(main.find_child("DraftPool", true, false) != null and NewFeatures.is_seen(main.save_data, "draft"), "opening a feature goes there and marks it seen")
	main._build_connect_screen()
	await process_frame
	check(main.find_child("DraftButton", true, false).find_child("NewTag", false, false) == null and main.find_child("WeeklyButton", true, false).find_child("NewTag", false, false) != null, "seen features lose their tag")
	main.find_child("WeeklyButton", true, false).pressed.emit()
	await process_frame
	check(NewFeatures.is_seen(main.save_data, "weekly"), "pressing the button itself also counts")
	for feature in NewFeatures.FEATURES:
		NewFeatures.mark_seen(main.save_data, String(feature.id))
	main._build_connect_screen()
	await process_frame
	check(main.find_child("NewFeaturesChip", true, false) == null, "no chip once everything has been seen")
	print("new_features_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
