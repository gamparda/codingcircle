extends SceneTree
## Server shelf of shared replays: codes, public listing, bounds and persistence.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ServerReplayShelf = preload("res://scripts/ServerReplayShelf.gd")
const Protocol = preload("res://scripts/NetworkProtocol.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _replay(seed_tick: int) -> Dictionary:
	var model := BattleModel.new()
	model.configure_deck(0, ["shield", "swordsman", "archer"], ["wall", "swamp", "turret"])
	model.configure_deck(1, ["berserker", "warlock", "necromancer"], ["wall", "turret", "generator"])
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 120 + seed_tick:
		if tick % 40 == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	model.winner = 0
	return recorder.finish(model)

## The shelf keeps its files in a subfolder; remove both levels.
func _clear(dir: String) -> void:
	var shelf_dir := dir.path_join("shared_replays")
	for file in DirAccess.get_files_at(shelf_dir):
		DirAccess.remove_absolute(shelf_dir.path_join(file))
	DirAccess.remove_absolute(shelf_dir)
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var dir := "user://replay_shelf_test"
	DirAccess.make_dir_recursive_absolute(dir)
	_clear(dir)
	var shelf := ServerReplayShelf.new()
	shelf.configure(dir)
	var text := BattleReplay.to_share_text(_replay(0))
	var code := shelf.add(text, false)
	check(Protocol.is_valid_room_code(code), "a replay gets a six-letter code")
	check(shelf.add(text, false) == code and shelf.entries.size() == 1, "the same replay always gets the same code")
	check(shelf.text_for(code) == text.strip_edges() and shelf.text_for("ZZZZZZ") == "", "the text comes back by code only")
	check(shelf.recent().is_empty(), "private uploads are not listed")
	check(shelf.add(text, true) == code and shelf.recent().size() == 1 and shelf.recent()[0].code == code, "making it public lists it once")
	check(shelf.add("garbage", false) == "" and shelf.add("x".repeat(ServerReplayShelf.MAX_TEXT + 1), false) == "", "garbage and oversized text are refused")
	var second := shelf.add(BattleReplay.to_share_text(_replay(30)), true)
	check(shelf.recent()[0].code == second and shelf.recent()[1].code == code, "recent battles list the newest first")
	check(shelf.recent()[0].units[1] == ["berserker", "warlock", "necromancer"] and int(shelf.recent()[0].winner) == 0, "summaries carry decks and winner")
	var reloaded := ServerReplayShelf.new()
	reloaded.configure(dir)
	check(reloaded.text_for(code) == text.strip_edges() and reloaded.recent().size() == 2, "the shelf survives a restart")
	# Bounded: the oldest entries fall off.
	var bounded := ServerReplayShelf.new()
	for i in ServerReplayShelf.MAX_STORED + 5:
		bounded.entries.append({"code": "AAAA%02d" % (i % 100), "public": false, "summary": {}, "text": "t%d" % i})
	bounded._trim()
	check(bounded.entries.size() == ServerReplayShelf.MAX_STORED, "the shelf is bounded")
	_clear(dir)
	print("replay_shelf_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
