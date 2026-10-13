extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()

func read_bytes(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_buffer(file.get_length()) if file != null else PackedByteArray()

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var data := SaveData.default_data()
	SaveData.record_campaign(data, 3, true, 60.0, 450.0)
	data.last_deck = 2
	data.settings.fps_limit = 144
	var loaded := SaveData.sanitize(JSON.parse_string(JSON.stringify(data)))
	var ok: bool = loaded.campaign_unlocked == 4 and loaded.last_deck == 2 and loaded.settings.fps_limit == 144 and loaded.campaign_records[2].best_stars == 3 and loaded.stats.ai_wins == 1
	print("SAVE_JSON_ROUNDTRIP preserved=", ok, " unlocked=", loaded.campaign_unlocked, " stars=", loaded.campaign_records[2].best_stars)
	check(ok, "JSON roundtrip preserves progress and settings")
	var path := "user://save_roundtrip_test.json"
	check(SaveData.load_result(path).status == "missing", "first launch is distinct from a read failure")
	check(SaveData.save_data(data, path) and SaveData.load_data(path).stats.ai_wins == 1, "normal disk roundtrip preserves progress")
	check(not DirAccess.dir_exists_absolute(SaveData.recovery_dir(path)), "healthy profiles do not create recovery copies")
	var original := "{\"nickname\": \"원본\", \"stats\": ".to_utf8_buffer()
	write_bytes(path, original)
	var broken := SaveData.load_result(path)
	check(broken.status == "invalid" and not broken.warning.is_empty() and broken.data.stats.ai_wins == 0, "broken JSON starts with defaults and reports damage")
	check(not broken.backup.is_empty() and read_bytes(broken.backup) == original and read_bytes(path) == original, "loading keeps both the original and an exact recovery copy")
	check(SaveData.load_result(path).backup == broken.backup and DirAccess.get_files_at(SaveData.recovery_dir(path)).size() == 1, "repeated loads reuse the same verified recovery copy")
	check(SaveData.save_data(data, path) and SaveData.load_data(path).stats.ai_wins == 1 and read_bytes(broken.backup) == original, "new progress can be saved while the damaged original remains recoverable")
	# A valid JSON document with the wrong root is also preserved, even without loading first.
	write_bytes(path, "[]".to_utf8_buffer())
	check(SaveData.save_data(data, path) and DirAccess.get_files_at(SaveData.recovery_dir(path)).size() == 2, "direct saves preserve non-profile JSON rather than overwriting it")
	var blocked := "user://save_roundtrip_blocked.json"
	write_bytes(blocked, original)
	write_bytes(SaveData.recovery_dir(blocked), "blocked".to_utf8_buffer())
	check(SaveData.load_result(blocked).backup.is_empty() and not SaveData.save_data(data, blocked) and read_bytes(blocked) == original, "failure to preserve the original blocks replacement")
	DirAccess.remove_absolute(SaveData.recovery_dir(blocked))
	DirAccess.make_dir_absolute(blocked + ".tmp")
	check(not SaveData.save_data(data, blocked) and read_bytes(blocked) == original, "replacement write failure leaves the original untouched")
	DirAccess.remove_absolute(blocked + ".tmp")
	check(SaveData.save_data(data, blocked), "saving can be retried after storage recovers")
	var newer := data.duplicate(true)
	newer.save_version = SaveData.SAVE_VERSION + 1
	var future_bytes := JSON.stringify(newer).to_utf8_buffer()
	write_bytes(path, future_bytes)
	check(SaveData.load_result(path).status == "newer" and not SaveData.save_data(data, path) and read_bytes(path) == future_bytes, "newer save formats are reported and never overwritten by this version")
	var directory := "user://save_roundtrip_directory.json"
	DirAccess.make_dir_absolute(directory)
	check(SaveData.load_result(directory).status == "unreadable" and not SaveData.save_data(data, directory), "a directory at the profile path is a read failure, not a first launch")
	DirAccess.remove_absolute(directory)
	write_bytes(directory, JSON.stringify(newer).to_utf8_buffer())
	check(not SaveData.save_data(data, directory), "newer-version protection remains active after an unreadable path recovers")
	var recovered_original := JSON.stringify(data).to_utf8_buffer()
	write_bytes(directory, recovered_original)
	check(SaveData.save_data(SaveData.default_data(), directory), "fallback progress can be saved after read access recovers")
	var recovered_files := DirAccess.get_files_at(SaveData.recovery_dir(directory))
	check(recovered_files.size() == 1 and read_bytes(SaveData.recovery_dir(directory).path_join(recovered_files[0])) == recovered_original, "the recovered valid original is backed up before fallback progress replaces it")

	var malformed := data.duplicate(true)
	malformed.deck_presets[0].structures = [{}, "wall", "turret"]
	malformed.deck_presets[1].name = []
	malformed.settings.master_volume = NAN
	malformed.settings.effect_intensity = INF
	malformed.campaign_records[0].fastest_win = INF
	malformed.daily = {"20261011": {"score": 5, "won": [], "seconds": {}}}
	malformed.daily["20261011"].ruleset = []
	malformed.daily["20261011"].previous = {"older": {"won": true, "score": 1000, "seconds": 80.0}, "bad": {"score": []}, "../invalid": {"score": 500}, "wrong-type": []}
	malformed.weekly = {"20261005": {"score": 8, "seconds": "bad"}}
	malformed.pending_daily = {"20261011": {"score": 900, "seconds": []}, "20261010": {"score": 1000, "seconds": 0.0}, "w20261005": {"score": 3001, "seconds": 80.0}, "20261009": {"score": 1000, "seconds": 3601.0}, "20261008": {"score": 3000, "seconds": 3600.0}}
	malformed.pending_reports = [{"units": [], "structures": [], "result": 0, "mode": {}}]
	var safe := SaveData.sanitize(malformed)
	check(safe.deck_presets[0].structures == SaveData.default_data().deck_presets[0].structures and safe.deck_presets[1].name == SaveData.default_data().deck_presets[1].name, "malformed deck fields fall back safely")
	check(is_finite(safe.settings.master_volume) and is_finite(safe.settings.effect_intensity) and safe.campaign_records[0].fastest_win == 0.0, "non-finite profile numbers are rejected")
	check(safe.daily["20261011"].seconds == 80.0 and safe.daily["20261011"].won and safe.weekly.is_empty() and safe.pending_daily.size() == 2 and safe.pending_daily["20261010"].seconds == 0.0 and safe.pending_daily["20261008"].score == 3000 and safe.pending_reports.is_empty(), "invalid queued scores do not consume the queue limit or turn malformed times into zero, while legitimate boundary scores survive")
	check(safe.stats.ai_wins == 1, "unrelated valid progress survives malformed fields")
	check(safe.daily["20261011"].ruleset == "older" and safe.daily["20261011"].previous.is_empty() and safe.daily["20261011"].score == 1000, "valid version history survives malformed neighboring entries without treating unknown scores as current")

	# Startup shows the read failure even before an automatic save is attempted.
	write_bytes(path, original)
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	main.updater.enabled = false
	await process_frame
	main._load_profile(path)
	main._build_connect_screen()
	check(main.find_child("ProfileLoadWarning", true, false) != null and main.profile_load_details.contains("원본 보관"), "startup exposes damage and the recovery copy location")
	main._build_settings_screen()
	await process_frame
	check(main.find_child("ProfileLoadWarning", true, false) != null, "the warning survives screen navigation")
	main.profile_save_pending = true
	main.pending_battle_replays = [{"replay": {}, "hint": "layout only"}]
	main._refresh_save_warning(main.root_background)
	check(main.find_child("ProfileLoadWarning", true, false).position.y < main.find_child("ProfileSaveWarning", true, false).position.y and main.find_child("ProfileSaveWarning", true, false).position.y < main.find_child("ReplaySaveWarning", true, false).position.y, "read, write and replay failure notices occupy separate rows")
	main.find_child("DismissProfileLoadWarning", true, false).pressed.emit()
	check(main.find_child("ProfileLoadWarning", true, false) == null and main.profile_save_pending, "acknowledging the read warning does not dismiss unsaved-progress protection")
	main.pending_battle_replays.clear()
	check(SaveData.save_data(main.save_data, path), "startup defaults can be saved after original preservation")
	for target in [path, blocked, directory]:
		DirAccess.remove_absolute(target)
		for name in DirAccess.get_files_at(SaveData.recovery_dir(target)):
			DirAccess.remove_absolute(SaveData.recovery_dir(target).path_join(name))
		DirAccess.remove_absolute(SaveData.recovery_dir(target))
	main.queue_free()
	await process_frame
	print("save_roundtrip_test failures=%d" % failures)
	quit(0 if failures == 0 else 1)
