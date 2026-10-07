extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	var GameData = load("res://scripts/data/GameData.gd")
	var stats: Dictionary = BattleModel.UNIT_STATS
	check(stats.keys() == ["shield", "swordsman", "archer", "healer", "berserker", "warlock", "necromancer"], "unit order comes from the data 'order' field: %s" % [stats.keys()])
	check(BattleModel.SUMMON_STATS.keys() == ["skeleton"], "skeleton is summon-only data")
	check(BattleModel.STRUCTURE_STATS.keys() == ["wall", "swamp", "turret", "generator"], "structure order comes from data")
	for kind in stats:
		var unit: Dictionary = stats[kind]
		for key in ["cost", "hp", "damage", "interval", "speed", "range"]:
			check(unit.has(key) and typeof(unit[key]) == TYPE_FLOAT, "%s.%s is a float" % [kind, key])
		check(float(unit.cost) > 0.0 and float(unit.hp) > 0.0 and float(unit.speed) > 0.0 and float(unit.range) > 0.0, "%s has positive numbers" % kind)
		check(BattleModel.UNIT_NAMES.has(kind) and String(BattleModel.UNIT_NAMES[kind]) != "", "%s has a display name" % kind)
	check(float(stats.healer.interval) == BattleModel.SUPPORT_COOLDOWN and stats.healer.has("heal"), "mage cooldown data matches the support constant")
	check(BattleModel.UNIT_NAMES.has("skeleton"), "skeleton name is available to reports")
	for kind in BattleModel.STRUCTURE_STATS:
		check(float(BattleModel.STRUCTURE_STATS[kind].cost) > 0.0 and float(BattleModel.STRUCTURE_STATS[kind].hp) > 0.0, "%s structure numbers are positive" % kind)
	# Every .tres on disk must be registered, so a new data file cannot be silently ignored.
	for folder in ["units", "structures"]:
		var listed: Array = (GameData.UNIT_FILES + GameData.SUMMON_FILES) if folder == "units" else GameData.STRUCTURE_FILES
		var on_disk: Array = []
		for file in DirAccess.get_files_at("res://data/" + folder):
			if file.ends_with(".tres"):
				on_disk.append(file.get_basename())
		on_disk.sort()
		var expected := listed.duplicate()
		expected.sort()
		check(on_disk == expected, "%s data files match GameData lists: %s vs %s" % [folder, on_disk, expected])
	# AI and balance tooling read the same dictionaries, not private copies.
	var ServerAI = load("res://scripts/ServerAI.gd")
	check(ServerAI.stage_unit_deck(1).all(func(kind): return stats.has(kind)), "AI decks only use data-defined units")
	print("unit_data_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
