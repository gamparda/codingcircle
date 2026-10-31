extends RefCounted
## Server-side proof for titles earned offline. The client sends the battle's command log; the server builds
## the same battle from the rules alone (decks, AI stage, challenge twists, wave seeds), plays the logged
## commands through it and only believes what its own simulation shows. A result made up on the client, an
## easier opponent or a changed setup never matches. Simulation runs a slice at a time (step) so a long
## endless run never stalls the game server.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const WaveDirector = preload("res://scripts/run/WaveDirector.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")

const KINDS := ["campaign", "daily", "endless"]
## Upload size limit (characters of JSON).
const MAX_TEXT := 1_500_000
const MAX_SEGMENTS := 200
const MAX_SEGMENT_COMMANDS := 20000
const MAX_SEGMENT_TICKS := 30 * 3600 * 3
const DT := 1.0 / 30.0

var kind := ""
var account := ""
var peer := 0
## {"ok": bool, "error": String, ...facts}; empty while running.
var result: Dictionary = {}
var _steps: Callable
var _state: Dictionary = {}

## A job for `text` (JSON), or one that already failed.
static func create(job_kind: String, text: String, account_id: String, from_peer: int) -> RefCounted:
	var job = load("res://scripts/accounts/TitleVerifier.gd").new()
	job.kind = job_kind
	job.account = account_id
	job.peer = from_peer
	var parsed = JSON.parse_string(text) if text.length() <= MAX_TEXT else null
	match job_kind:
		"campaign", "daily":
			job._prepare_battle(parsed)
		"endless":
			job._prepare_endless(parsed)
		_:
			job.result = {"ok": false, "error": "invalid"}
	return job

func finished() -> bool:
	return not result.is_empty()

## Simulates for at most `budget_usec`; true once finished.
func step(budget_usec: int) -> bool:
	if finished():
		return true
	var deadline := Time.get_ticks_usec() + budget_usec
	while not finished() and Time.get_ticks_usec() < deadline:
		for i in 30:
			if finished() or not bool(_steps.call()):
				break
	return finished()

func _fail(error: String) -> void:
	result = {"ok": false, "error": error}

static func _canonical(value: Variant) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(value)), "", true)

# ---------- one battle (campaign stage, daily or weekly challenge) ----------

func _prepare_battle(replay: Variant) -> void:
	if not BattleReplay.valid(replay) or not replay.get("forced_end", {}).is_empty():
		_fail("invalid"); return
	var meta: Dictionary = replay.get("meta", {})
	var expected: BattleModel = null
	var stage := 0
	if kind == "campaign":
		if String(meta.get("mode", "")) != "campaign" or not meta.has("stage"):
			_fail("invalid"); return
		stage = int(meta.stage)
		var setup: Dictionary = replay.setup
		if not BattleModel._valid_deck(setup.unit_decks[0], BattleModel.UNIT_STATS) or not BattleModel._valid_deck(setup.structure_decks[0], BattleModel.STRUCTURE_STATS):
			_fail("invalid"); return
		expected = BattleModel.new()
		expected.configure_campaign_growth(0, int(setup.campaign_levels[0]))
		expected.configure_deck(0, setup.unit_decks[0], setup.structure_decks[0])
		expected.configure_deck(1, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
		expected.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(stage) * 10.0)
		expected.configure_base_health(1, 300.0 + float(stage) * 20.0)
	else:
		if String(meta.get("mode", "")) != "daily" or String(meta.get("ruleset", "")) != ServerStats.ruleset_id():
			_fail("invalid"); return
		var period := String(meta.get("period", "daily"))
		var key := String(meta.get("date", ""))
		var now := int(Time.get_unix_time_from_system())
		var recent: Array = [DailyChallenge.date_key(now), DailyChallenge.date_key(now - 86400)] if period == "daily" else [DailyChallenge.week_key(now), DailyChallenge.week_key(now - 7 * 86400)]
		if period not in ["daily", "weekly"] or not recent.has(key):
			_fail("expired"); return
		var built := DailyChallenge.build(DailyChallenge.for_week(key) if period == "weekly" else DailyChallenge.for_date(key))
		expected = built.model
		stage = int(built.stage)
		_state.day = ("w" if period == "weekly" else "") + key
	if _canonical(replay.get("ai", {})) != _canonical({"side": 1, "stage": stage}):
		_fail("mismatch"); return
	if _canonical(replay.setup) != _canonical(BattleReplay.Recorder.new(expected, BattleReplay.DEFAULT_HZ).replay.setup) or int(replay.hz) != BattleReplay.DEFAULT_HZ:
		_fail("mismatch"); return
	if replay.commands.any(func(entry): return int(entry.s) != 0):
		_fail("mismatch"); return
	_state.player = BattleReplay.Player.new(replay)
	_state.stage = stage
	_state.replay = replay
	_steps = _battle_step

func _battle_step() -> bool:
	var player = _state.player
	if player.step():
		return true
	var played: Dictionary = player.summary()
	var recorded: Dictionary = _state.replay.result
	if String(played.state_hash) != String(recorded.state_hash) or int(played.winner) != int(recorded.winner):
		_fail("mismatch"); return false
	var model: BattleModel = player.model
	var won := int(played.winner) == 0
	result = {"ok": true, "error": "", "won": won, "stage": int(_state.stage)}
	if kind == "campaign" and won:
		result.stars = SaveData.campaign_stars(int(_state.stage), true, float(model.elapsed), float(model.base_hp[0]))
		result.untouched = float(model.base_hp[0]) >= float(model.base_max_hp[0])
	if kind == "daily":
		result.day = String(_state.day)
	return false

# ---------- endless defense: a chain of segments ----------
## {"segments": [{"start": {"wave", "boons", "base_hp", "seed", "units", "structures"},
##   "commands": [{"t", "c": "spawn"|"place", "k", "x"?}], "choices": [{"t", "id"}], "end": "save"|"end", "ticks": int}]}
## A segment runs from a start (a new run, or a resume) to the run's end or to the save point its next segment
## resumes from. Each resume must start exactly where the previous segment's save point left the run.

func _prepare_endless(data: Variant) -> void:
	if not data is Dictionary or not data.get("segments") is Array or data.segments.is_empty() or data.segments.size() > MAX_SEGMENTS:
		_fail("invalid"); return
	for index in data.segments.size():
		if not _valid_segment(data.segments[index], index == data.segments.size() - 1):
			_fail("invalid"); return
	var first: Dictionary = data.segments[0].start
	if int(first.wave) != 1 or not first.boons.is_empty() or float(first.base_hp) != BattleModel.BASE_MAX_HP:
		_fail("mismatch"); return
	_state = {"segments": data.segments, "index": -1, "lowest": 1.0, "melee": not first.units.any(func(unit): return BattleModel.unit_scope(String(unit)) == "ranged")}
	_steps = _endless_step
	_begin_segment(0)

static func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func _valid_segment(segment: Variant, last: bool) -> bool:
	if not segment is Dictionary or not segment.get("start") is Dictionary or not segment.get("commands") is Array or not segment.get("choices") is Array:
		return false
	var start: Dictionary = segment.start
	if not _integer(start.get("wave")) or int(start.wave) < 1 or int(start.wave) > 1000 or not start.get("boons") is Array or not _integer(start.get("seed")):
		return false
	if not (start.get("base_hp") is float or start.get("base_hp") is int) or float(start.base_hp) <= 0.0 or float(start.base_hp) > BattleModel.BASE_MAX_HP:
		return false
	if not start.get("units") is Array or not start.get("structures") is Array or not BattleModel._valid_deck(start.units, BattleModel.UNIT_STATS) or not BattleModel._valid_deck(start.structures, BattleModel.STRUCTURE_STATS):
		return false
	if not start.boons.all(func(id): return id is String and preload("res://scripts/run/RunBoons.gd").RELICS.has(id)):
		return false
	if String(segment.get("end", "")) != ("end" if last else "save") or not _integer(segment.get("ticks")) or int(segment.ticks) < 0 or int(segment.ticks) > MAX_SEGMENT_TICKS:
		return false
	if segment.commands.size() > MAX_SEGMENT_COMMANDS or segment.choices.size() > 2000:
		return false
	var last_tick := 0
	for entry in segment.commands:
		if not entry is Dictionary or not _integer(entry.get("t")) or int(entry.t) < last_tick or int(entry.t) > int(segment.ticks) or not entry.get("k") is String:
			return false
		last_tick = int(entry.t)
		if String(entry.get("c", "")) == "spawn":
			if not BattleModel.UNIT_STATS.has(entry.k): return false
		elif String(entry.get("c", "")) == "place":
			if not BattleModel.STRUCTURE_STATS.has(entry.k) or not (entry.get("x") is float or entry.get("x") is int) or not is_finite(float(entry.x)): return false
		else:
			return false
	last_tick = 0
	for entry in segment.choices:
		if not entry is Dictionary or not _integer(entry.get("t")) or int(entry.t) < last_tick or int(entry.t) > int(segment.ticks) or not entry.get("id") is String:
			return false
		last_tick = int(entry.t)
	return true

## Sets up segment `index` the way EndlessFlow.start does.
func _begin_segment(index: int) -> void:
	var segment: Dictionary = _state.segments[index]
	var start: Dictionary = segment.start
	var first: Dictionary = _state.segments[0].start
	if index > 0 and (int(start.seed) != int(first.seed) or _canonical(start.units) != _canonical(first.units) or _canonical(start.structures) != _canonical(first.structures)):
		_fail("mismatch"); return
	var model := BattleModel.new()
	model.configure_deck(0, start.units, start.structures)
	var boons: Array = start.boons.map(func(id): return String(id))
	var director := WaveDirector.new(int(start.seed) + int(start.wave) * 7919, int(start.wave), boons)
	director.setup(model)
	if index > 0:
		model.base_hp[0] = minf(float(model.base_max_hp[0]), float(start.base_hp))
	_state.index = index
	_state.model = model
	_state.director = director
	_state.ticks = 0
	_state.command = 0
	_state.choice = 0

func _endless_step() -> bool:
	var segment: Dictionary = _state.segments[int(_state.index)]
	var model: BattleModel = _state.model
	var director = _state.director
	var ticks := int(_state.ticks)
	if String(segment.end) == "end" and ticks >= int(segment.ticks):
		# The run ended here: its base fell (checked below) or the player gave up.
		return _segment_over(segment, false)
	if director.awaiting_choice:
		var choices: Array = segment.choices
		if int(_state.choice) >= choices.size() or int(choices[int(_state.choice)].t) != ticks:
			# The log stops at a wave break: a save point, or a run left unfinished.
			return _segment_over(segment, false)
		director.choose(model, String(choices[int(_state.choice)].id))
		_state.choice = int(_state.choice) + 1
		if String(segment.end) == "save" and int(_state.choice) == choices.size() and ticks == int(segment.ticks):
			return _segment_over(segment, true)
	var commands: Array = segment.commands
	while int(_state.command) < commands.size() and int(commands[int(_state.command)].t) <= ticks:
		var entry: Dictionary = commands[int(_state.command)]
		if String(entry.c) == "spawn":
			model.spawn_unit(0, String(entry.k))
		else:
			model.place_structure(0, String(entry.k), float(entry.x))
		_state.command = int(_state.command) + 1
	if model.winner != -1 or ticks >= MAX_SEGMENT_TICKS:
		return _segment_over(segment, false)
	director.update(model, DT)
	model.tick(DT)
	_state.ticks = ticks + 1
	_state.lowest = minf(float(_state.lowest), float(model.base_hp[0]) / float(model.base_max_hp[0]))
	return true

## Closes the segment: a save point hands its state to the next segment, the end settles the run.
func _segment_over(segment: Dictionary, saved: bool) -> bool:
	var model: BattleModel = _state.model
	var director = _state.director
	var index := int(_state.index)
	if saved:
		var next: Dictionary = _state.segments[index + 1].start
		if int(next.wave) != director.wave + 1 or _canonical(next.boons) != _canonical(director.boons) or float(next.base_hp) != float(model.base_hp[0]):
			_fail("mismatch"); return false
		_begin_segment(index + 1)
		return not finished()
	if String(segment.end) != "end" or int(_state.ticks) != int(segment.ticks):
		_fail("mismatch"); return false
	var waves: int = director.waves_cleared()
	result = {"ok": true, "error": "", "waves": waves, "flawless": float(_state.lowest) >= 0.5, "melee": bool(_state.melee)}
	return false
