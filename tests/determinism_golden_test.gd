extends SceneTree
## Battle rules stay bit-for-bit the same: every scenario in golden_battles.gd must fold to the digest recorded
## in tests/golden/battle_digests.json (from the code before the optimizations). Run with `-- --record` to
## write the digests (only when a rule change is intended).

const GoldenBattles = preload("res://tests/golden/golden_battles.gd")
const DIGESTS := "res://tests/golden/battle_digests.json"

func _init() -> void:
	var record := OS.get_cmdline_user_args().has("--record")
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="): only = arg.trim_prefix("--only=")
	var expected: Dictionary = {}
	if not record:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIGESTS))
		expected = parsed if parsed is Dictionary else {}
	var digests := {}
	var failures := 0
	# Both engines: GDScript always, the native one when its library is here (CI builds it; locally see
	# tools/build_native.sh). Recording uses GDScript, the reference.
	var engines: Array = ["gdscript"]
	if not record and BattleModel.native_available():
		engines.append("native")
	elif not record and (OS.get_cmdline_user_args().has("--require-native") or OS.get_environment("CATWAR_REQUIRE_NATIVE") == "1"):
		printerr("FAIL: the native battle engine is not available")
		failures += 1
	for engine in engines:
		BattleModel.native_enabled = engine == "native"
		for scenario in GoldenBattles.scenarios():
			if not only.is_empty() and String(scenario.name) != only:
				continue
			var started := Time.get_ticks_msec()
			var digest := GoldenBattles.run(scenario)
			digests[scenario.name] = digest
			var ok := record or String(expected.get(scenario.name, "")) == digest
			if not ok:
				failures += 1
				printerr("FAIL: %s on %s changed (%s, expected %s)" % [scenario.name, engine, digest.substr(0, 12), String(expected.get(scenario.name, "?")).substr(0, 12)])
			print("%s %-8s %s %dms" % ["ok  " if ok else "FAIL", engine, scenario.name, Time.get_ticks_msec() - started])
	BattleModel.native_enabled = true
	if record:
		var file := FileAccess.open(DIGESTS, FileAccess.WRITE)
		file.store_string(JSON.stringify(digests, "  ", true))
		file.close()
		print("recorded %d digests" % digests.size())
	print("determinism_golden_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
