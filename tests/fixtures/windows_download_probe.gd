extends SceneTree

func _initialize() -> void:
	call_deferred("run_download")

func run_download() -> void:
	Engine.max_fps = 5
	var arguments := OS.get_cmdline_user_args()
	var updater = load("res://scripts/UpdateManager.gd").new()
	root.add_child(updater)
	updater.enabled = false
	updater.set_process(false)
	updater.safe_to_update = false
	updater.manifest = {"version": "999.0.0", "installer_url": arguments[0], "sha256": arguments[1]}
	create_timer(4.0).timeout.connect(func():
		printerr("Download stalled at low frame rate")
		quit(1))
	updater._begin_download()
	await updater.http.request_completed
	var expected_state := "failed" if arguments[2] == "corrupt" else "ready_to_install"
	var passed: bool = updater.state == expected_state
	if FileAccess.file_exists(updater.installer_path):
		DirAccess.remove_absolute(updater.installer_path)
	print("DOWNLOAD_STATE=", updater.state)
	updater.queue_free()
	quit(0 if passed else 1)
