extends SceneTree
## Re-simulates saved replays headlessly: balance analysis and bug reproduction.
##
##   godot --headless --path . --script res://tools/replay_tool.gd -- --file=user://replays/x.json
##   godot --headless --path . --script res://tools/replay_tool.gd -- --all          # every saved replay
##
## Prints one JSON line per replay: {path, ok, winner, seconds, ticks, commands, decks}.
## Exit code 1 if any replay no longer reproduces its recorded result (rules changed).

const BattleReplay = preload("res://scripts/BattleReplay.gd")

func _init() -> void:
	var paths: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			paths.append(arg.trim_prefix("--file="))
		elif arg == "--all":
			paths.append_array(BattleReplay.list_saved())
	if paths.is_empty():
		printerr("usage: -- --file=<replay.json> | --all")
		quit(2)
		return
	var mismatches := 0
	for path in paths:
		var replay := BattleReplay.load_file(path)
		if replay.is_empty():
			print(JSON.stringify({"path": path, "ok": false, "error": "unreadable or invalid"}))
			mismatches += 1
			continue
		var verdict := BattleReplay.verify(replay)
		mismatches += 0 if bool(verdict.ok) else 1
		print(JSON.stringify({
			"path": path, "ok": verdict.ok, "winner": verdict.played.winner,
			"seconds": snappedf(float(verdict.played.elapsed), 0.01), "ticks": verdict.played.ticks,
			"commands": replay.commands.size(), "decks": replay.setup.unit_decks, "meta": replay.get("meta", {}),
		}))
	quit(1 if mismatches > 0 else 0)
