extends SceneTree
## The thin launcher (Bootstrap.gd, frozen in each APK) and the pack-side updater (ContentUpdater.gd): the
## launcher preloads nothing, rolls back a pack that never confirmed a start or fails its checksum, and hands
## over to the updater through `begin`.

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/Bootstrap.gd")
	check(not source.contains("preload("), "the launcher preloads nothing, so the pack's scripts are the ones that run")
	var Launcher = load("res://scripts/Bootstrap.gd")
	var Updater = load("res://scripts/ContentUpdater.gd")
	check(Updater.new().has_method("begin"), "the updater takes over through begin()")
	var dir := ProjectSettings.globalize_path(Launcher.CONTENT_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var write := func(path: String, text: String):
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
	# A pack whose checksum does not match is dropped for the previous one.
	write.call(ProjectSettings.globalize_path(Launcher.ACTIVE_PACK), "broken")
	write.call(ProjectSettings.globalize_path(Launcher.ACTIVE_METADATA), JSON.stringify({"version": "9.9.9", "commit": "a".repeat(40), "sha256": "b".repeat(64), "pending_boot": false}))
	write.call(ProjectSettings.globalize_path(Launcher.PREVIOUS_PACK), "older")
	write.call(ProjectSettings.globalize_path(Launcher.PREVIOUS_METADATA), JSON.stringify({"version": "1.0.0", "commit": "c".repeat(40), "sha256": "d".repeat(64), "pending_boot": false}))
	var launcher = Launcher.new()
	launcher.bundled_version = "0.0.1"
	launcher._load_installed_pack()
	check(FileAccess.get_file_as_string(ProjectSettings.globalize_path(Launcher.ACTIVE_PACK)) == "older" and not FileAccess.file_exists(ProjectSettings.globalize_path(Launcher.PREVIOUS_PACK)), "a corrupt pack is replaced by the previous one")
	check(not launcher.active_pack_loaded, "a pack that failed its check is not loaded")
	# Rolling back with nothing before it leaves the APK's own data.
	launcher.rollback_pack()
	check(not FileAccess.file_exists(ProjectSettings.globalize_path(Launcher.ACTIVE_PACK)) and not FileAccess.file_exists(ProjectSettings.globalize_path(Launcher.ACTIVE_METADATA)), "rolling back without a previous pack falls back to the APK's data")
	launcher.free()
	check(Launcher._is_newer("0.8.0", "0.7.9") and not Launcher._is_newer("0.7.1", "0.7.1"), "launcher version comparison")
	print("launcher_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
