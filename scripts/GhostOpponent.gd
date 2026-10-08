extends RefCounted
## Plays back one player's recorded commands as a scripted opponent ("ghost").
## It does not react to the live battle: it buys and builds at the recorded moments, nothing more.
## Used for ghost battles (play against a replay's other player) and what-if branches (red continues its script).

const BattleReplay = preload("res://scripts/BattleReplay.gd")

var side := 1
var commands: Array = []
var cursor := 0
var ticks := 0
var mirror := false

## `replay_side` is whose commands to play. With `mirror` the ghost is flipped onto the red side
## (build positions mirror around the field centre) so a blue player's script can face the human on blue.
func _init(replay: Dictionary, replay_side: int, mirror_to_red: bool, from_tick: int = 0) -> void:
	mirror = mirror_to_red
	ticks = from_tick
	for entry in replay.get("commands", []):
		if int(entry.s) == replay_side and int(entry.t) >= from_tick:
			commands.append(entry)

## The side with the most recorded commands is the "player" worth challenging.
static func pick_side(replay: Dictionary) -> int:
	var counts := [0, 0]
	for entry in replay.get("commands", []):
		counts[int(entry.s)] += 1
	return 0 if counts[0] > counts[1] else 1

static func command_count(replay: Dictionary, replay_side: int) -> int:
	var count := 0
	for entry in replay.get("commands", []):
		if int(entry.s) == replay_side:
			count += 1
	return count

## A replay is worth challenging when its busiest side actually did something.
static func playable(replay: Dictionary) -> bool:
	return command_count(replay, pick_side(replay)) >= 3

## Same signature as ServerAI.update; call once per fixed simulation step, before BattleModel.tick.
func update(model: BattleModel, _delta: float) -> void:
	while cursor < commands.size() and int(commands[cursor].t) <= ticks:
		var entry: Dictionary = commands[cursor]
		if String(entry.c) == "spawn":
			model.spawn_unit(side, String(entry.k))
		else:
			var x := float(entry.x)
			model.place_structure(side, String(entry.k), BattleModel.WORLD_WIDTH - x if mirror else x)
		cursor += 1
	ticks += 1
