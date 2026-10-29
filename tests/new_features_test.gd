extends SceneTree
## "새 기능" guidance: tags on menu buttons (solo modes tag the 혼자 하기 tile on the main menu), the list
## from the patch notes screen, and persistence.

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
	NewFeatures.mark_seen(save, "endless")
	NewFeatures.mark_seen(save, "endless")
	check(save.seen_features == ["endless"] and NewFeatures.is_seen(save, "endless") and NewFeatures.unseen(save).size() == NewFeatures.FEATURES.size() - 1, "marking is idempotent")
	NewFeatures.mark_button_seen(save, "ExpeditionButton")
	check(NewFeatures.is_seen(save, "expedition"), "pressing a button marks the features behind it")
	var restored := SaveData.sanitize(JSON.parse_string(JSON.stringify(save)))
	check(restored.seen_features.has("endless") and restored.seen_features.has("expedition"), "seen features survive saving")
	var junk := SaveData.sanitize({"seen_features": ["endless", 5, "", "endless", "x".repeat(80)]})
	check(junk.seen_features == ["endless"], "junk entries are dropped")
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
	check(main.find_child("SoloButton", true, false).find_child("NewTag", false, false) != null, "new solo modes tag the 혼자 하기 tile")
	check(main.find_child("NewFeaturesChip", true, false) == null, "the main menu stays free of a feature chip")
	main._build_solo_screen()
	await process_frame
	check(main.find_child("EndlessButton", true, false).find_child("NewTag", false, false) != null and main.find_child("ExpeditionButton", true, false).find_child("NewTag", false, false) != null, "the modes themselves carry the tag")
	main._build_patch_notes_screen()
	await process_frame
	main.find_child("NewFeaturesButton", true, false).pressed.emit()
	await process_frame
	check(main.find_child("NewFeatureList", true, false).get_child_count() == NewFeatures.FEATURES.size(), "the list has one row per feature")
	main.find_child("OpenFeature_endless", true, false).pressed.emit()
	await process_frame
	check(main.find_child("EndlessBriefOverlay", true, false) != null and NewFeatures.is_seen(main.save_data, "endless"), "opening a feature goes there and marks it seen")
	main._build_solo_screen()
	await process_frame
	check(main.find_child("EndlessButton", true, false).find_child("NewTag", false, false) == null and main.find_child("ExpeditionButton", true, false).find_child("NewTag", false, false) != null, "seen features lose their tag")
	main.find_child("ExpeditionButton", true, false).pressed.emit()
	await process_frame
	check(NewFeatures.is_seen(main.save_data, "expedition"), "pressing the button itself also counts")
	for feature in NewFeatures.FEATURES:
		NewFeatures.mark_seen(main.save_data, String(feature.id))
	main._build_connect_screen()
	await process_frame
	check(main.find_child("SoloButton", true, false).find_child("NewTag", false, false) == null, "no tags once everything has been seen")
	print("new_features_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
