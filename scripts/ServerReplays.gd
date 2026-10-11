extends RefCounted
## Server-side replay bookkeeping: one recorder per live match, saved to user://replays
## when the match ends. NetworkController only calls these hooks; it never touches the
## replay format.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ServerReplayShelf = preload("res://scripts/ServerReplayShelf.gd")

## Pause new battles during sustained storage outages; already running battles still finish.
const MAX_PENDING := 16
const MAX_PENDING_COMMANDS := 100000

var enabled := true
var recorders: Dictionary = {}
var saved_paths: Array = []
## Completed matches awaiting archive and/or public shelf persistence; independent of live models.
var pending: Array = []
var stats = null
var shelf = null

func pending_command_count() -> int:
	var count := 0
	for entry in pending:
		count += entry.replay.commands.size()
	return count

func backlog_full() -> bool:
	return pending.size() >= MAX_PENDING or pending_command_count() >= MAX_PENDING_COMMANDS

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
	var finished: Dictionary = recorder.finish(model)
	if finished.is_empty():
		print("REPLAY_SKIPPED match=%d reason=recording_limit" % match_id)
		return
	var text := BattleReplay.to_share_text(finished) if shelf != null else ""
	var skip_sharing := shelf == null or text.is_empty() or text.length() > ServerReplayShelf.MAX_TEXT
	if shelf != null and skip_sharing:
		print("REPLAY_SHARE_SKIPPED match=%d reason=sharing_limit" % match_id)
	var entry := {"match_id": match_id, "replay": finished, "text": text, "archived": false, "shared": skip_sharing}
	if not _persist(entry):
		pending.append(entry)
		printerr("REPLAY_SAVE_PENDING match=%d archive=%s shared=%s" % [match_id, entry.archived, entry.shared])

func _persist(entry: Dictionary) -> bool:
	if not entry.archived:
		var path := BattleReplay.save(entry.replay, "match%d" % int(entry.match_id))
		if not path.is_empty():
			entry.archived = true
			saved_paths.append(path)
			# Diagnostic history only; persistence retries use each entry's archived flag.
			while saved_paths.size() > BattleReplay.MAX_SAVED:
				saved_paths.pop_front()
			print("REPLAY_SAVED match=%d path=%s" % [entry.match_id, path])
	if not entry.shared and shelf != null:
		entry.shared = not shelf.add(entry.text, true).is_empty()
	return entry.archived and entry.shared

## Retries file writes only. Result statistics and recorder finalization never run twice.
func retry_pending() -> void:
	var remaining: Array = []
	for entry in pending:
		if _persist(entry):
			print("REPLAY_SAVE_RECOVERED match=%d" % int(entry.match_id))
		else:
			remaining.append(entry)
	pending = remaining

func drop(match_id: int) -> void:
	recorders.erase(match_id)
