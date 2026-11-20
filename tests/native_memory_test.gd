extends SceneTree
## The battle engine frees what it allocates: battles must not grow the process (godot-cpp 4.5's
## Dictionary move assignment leaks; battle_core.cpp avoids it, and this keeps it that way).

func battle() -> void:
	var model := BattleModel.new()
	var deck := ["shield", "archer", "swordsman", "king"]
	model.configure_deck(0, deck, ["wall", "swamp", "turret", "frost"])
	model.configure_deck(1, ["joker", "bomber", "general", "shaman"], ["wall", "swamp", "turret", "frost"])
	for step in 300:
		model.resources = [180.0, 180.0]
		if step % 15 == 0:
			for side in 2:
				model.spawn_cooldowns[side].clear()
				for kind in model.unit_decks[side]:
					model.spawn_unit(side, String(kind))
		model.tick(0.1)
		model.drain_combat_events()

func _init() -> void:
	if not BattleModel.native_available():
		printerr("FAIL: the battle engine is not available")
		quit(1)
		return
	battle() # warm caches (interned names, kind tables)
	var before := OS.get_static_memory_usage()
	for round in 3:
		battle()
	var grown := (OS.get_static_memory_usage() - before) / 3
	var ok := grown < 20000
	print("%s: %d bytes kept per battle" % ["PASS" if ok else "FAIL", grown])
	quit(0 if ok else 1)
