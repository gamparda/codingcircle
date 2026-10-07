extends RefCounted
## Authoritative battle simulation for the dedicated server: owns every live BattleModel,
## advances them at a fixed 30 Hz, records replays and reports what happened each tick.
## NetworkController turns the returned results into session updates and network traffic.

const ServerReplays = preload("res://scripts/ServerReplays.gd")

const TICK_RATE := 1.0 / 30.0
const SNAPSHOT_RATE := 1.0 / 12.0

var models: Dictionary = {}
var rematch_ready: Dictionary = {}
var replays := ServerReplays.new()
var tick_accumulator := 0.0
var snapshot_accumulator := 0.0

## Advances every match by the elapsed time. `is_paused` is a Callable(match_id) -> bool.
## Returns {"ticks": [{match_id, finished, events}], "snapshot_due": bool}; `finished` is true
## for every tick on which the match is over so the caller can finalize its session.
func advance(delta: float, is_paused: Callable) -> Dictionary:
	var ticks: Array = []
	tick_accumulator += delta
	snapshot_accumulator += delta
	while tick_accumulator >= TICK_RATE:
		for match_id in models.keys():
			var model: BattleModel = models[match_id]
			if not bool(is_paused.call(int(match_id))) and model.winner == -1:
				model.tick(TICK_RATE)
				replays.on_tick(int(match_id))
			replays.settle(int(match_id), model)
			ticks.append({"match_id": int(match_id), "finished": model.winner != -1, "events": model.drain_combat_events()})
		tick_accumulator -= TICK_RATE
	var snapshot_due := snapshot_accumulator >= SNAPSHOT_RATE
	if snapshot_due:
		snapshot_accumulator = 0.0
	return {"ticks": ticks, "snapshot_due": snapshot_due}

func drop(match_id: int) -> void:
	models.erase(match_id)
	rematch_ready.erase(match_id)
	replays.drop(match_id)
