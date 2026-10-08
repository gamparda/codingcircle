extends RefCounted
## Server-side replay bookkeeping: one recorder per live match, saved to user://replays
## when the match ends. NetworkController only calls these hooks; it never touches the
## replay format.

const BattleReplay = preload("res://scripts/BattleReplay.gd")

var enabled := true
var recorders: Dictionary = {}
var saved_paths: Array = []
var stats = null

func begin(match_id: int, model: BattleModel, meta: Dictionary = {}) -> void:
	if enabled:
		recorders[match_id] = BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, meta)

func on_tick(match_id: int) -> void:
	if recorders.has(match_id):
		recorders[match_id].on_tick()

func on_spawn(match_id: int, side: int, kind: String) -> void:
	if recorders.has(match_id):
		recorders[match_id].on_spawn(side, kind)

func on_place(match_id: int, side: int, kind: String, x: float) -> void:
	if recorders.has(match_id):
		recorders[match_id].on_place(side, kind, x)

## Call whenever a match may have ended; saves exactly once per battle.
func settle(match_id: int, model: BattleModel) -> void:
	if not recorders.has(match_id) or model.winner == -1:
		return
	var recorder = recorders[match_id]
	recorders.erase(match_id)
	if stats != null:
		stats.record_model(model)
	var path := BattleReplay.save(recorder.finish(model), "match%d" % match_id)
	if path != "":
		saved_paths.append(path)
		print("REPLAY_SAVED match=%d path=%s" % [match_id, path])

func drop(match_id: int) -> void:
	recorders.erase(match_id)
