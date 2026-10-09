extends SceneTree
## Run by the Linux updater as the unprivileged service account before a downloaded server pack is installed:
##   godot --headless --main-pack server.pck --script res://tests/pack_selfcheck.gd -- <expected commit>
## Without an argument (the normal test run) only the loading checks apply.

func _init() -> void:
	var failures := 0
	var info = JSON.parse_string(FileAccess.get_file_as_string("res://build_info.json"))
	var expected := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		expected = String(args[0]).strip_edges().to_lower()
	if not info is Dictionary:
		failures += 1
		printerr("PACK_SELFCHECK build_info.json is missing")
	elif not expected.is_empty() and String(info.get("commit", "")).to_lower() != expected:
		failures += 1
		printerr("PACK_SELFCHECK commit %s is not the expected %s" % [info.get("commit", ""), expected])
	for path in ["res://scenes/Main.tscn", "res://scripts/NetworkController.gd", "res://scripts/jobs/AssistHub.gd", "res://scripts/BattleModel.gd"]:
		if load(path) == null:
			failures += 1
			printerr("PACK_SELFCHECK cannot load %s" % path)
	print("PACK_SELFCHECK %s" % ("failed" if failures > 0 else "ok"))
	quit(1 if failures > 0 else 0)
