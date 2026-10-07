extends SceneTree

const Bot = preload("res://tools/BalanceBot.gd")
const POLICIES := ["cycle", "adaptive", "weighted"]
var options := {"suite":"pvp", "output":"user://balance.jsonl", "seeds":2, "dt":0.1, "timeout":600.0, "shard":0, "shards":1, "limit":0, "growth":"progression"}
var decks: Array = []
var structure_decks: Array = []
var output: FileAccess
var scheduled := 0
var completed := 0
var start_us := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() != 2 or not options.has(pair[0]):
			printerr("Unknown benchmark argument: ", arg); quit(1); return
		var key := String(pair[0])
		options[key] = float(pair[1]) if key in ["dt", "timeout"] else int(pair[1]) if key in ["seeds", "shard", "shards", "limit"] else String(pair[1])
	if options.suite not in ["pvp", "campaign", "mirror"] or options.growth not in ["progression", "none"] or options.seeds < 1 or options.shards < 1 or options.shard < 0 or options.shard >= options.shards or options.dt <= 0.0 or options.dt > 0.25 or options.timeout <= 0.0 or options.limit < 0:
		printerr("Invalid benchmark options"); quit(1); return
	decks = combinations(BattleModel.UNIT_STATS.keys(), 3)
	structure_decks = combinations(BattleModel.STRUCTURE_STATS.keys(), 3)
	output = FileAccess.open(options.output, FileAccess.WRITE)
	if output == null:
		printerr("Cannot write benchmark output: ", options.output); quit(1); return
	start_us = Time.get_ticks_usec()
	output.store_line(JSON.stringify({"type":"metadata", "engine":Engine.get_version_info().string, "options":options, "unit_stats":BattleModel.UNIT_STATS, "structure_stats":BattleModel.STRUCTURE_STATS, "summon_interval":BattleModel.SUMMON_INTERVAL, "ai_max_stage":ServerAI.MAX_STAGE, "deck_count":decks.size(), "policies":POLICIES, "model_sha256":FileAccess.get_sha256("res://scripts/BattleModel.gd"), "data_sha256":_data_hash(), "ai_sha256":FileAccess.get_sha256("res://scripts/ServerAI.gd"), "bot_sha256":FileAccess.get_sha256("res://scripts/AutoPlayer.gd")}))
	for repetition in options.seeds:
		for policy in POLICIES:
			for a in decks.size():
				if options.suite == "campaign":
					for stage in range(1, ServerAI.MAX_STAGE + 1):
						run_pair(a, stage, policy, repetition)
				elif options.suite == "mirror":
					run_pair(a, a, policy, repetition)
				else:
					for b in range(a + 1, decks.size()):
						run_pair(a, b, policy, repetition)
	output.store_line(JSON.stringify({"type":"completion", "matches":completed, "wall_seconds":float(Time.get_ticks_usec()-start_us)/1e6}))
	output.close()
	print("BENCHMARK_COMPLETE matches=%d wall_seconds=%.2f output=%s" % [completed, float(Time.get_ticks_usec()-start_us)/1e6, options.output])
	quit(0)

func run_pair(a: int, b: int, policy: String, repetition: int) -> void:
	var pair_id := scheduled
	scheduled += 1
	if pair_id % int(options.shards) != options.shard or (options.limit > 0 and completed >= options.limit):
		return
	var pair_seed := 104729 + repetition * 100003 + a * 977 + b * 37
	for swap in 2:
		var row := play(a, b, policy, pair_seed, swap)
		row["pair_id"] = pair_id
		row["seed"] = pair_seed
		row["repetition"] = repetition
		output.store_line(JSON.stringify(row))
		completed += 1
		if completed % 50 == 0:
			output.flush()
			print("BENCHMARK_PROGRESS suite=%s shard=%d matches=%d wall_seconds=%.1f" % [options.suite, options.shard, completed, float(Time.get_ticks_usec()-start_us)/1e6])

func play(a: int, b: int, policy: String, pair_seed: int, swap: int) -> Dictionary:
	var model := BattleModel.new()
	var player_side := swap
	var opponent_side := 1 - swap
	var build_a: Array = structure_decks[posmod(pair_seed, structure_decks.size())]
	model.configure_deck(player_side, decks[a], build_a)
	var opponent
	if options.suite == "campaign":
		model.configure_campaign_growth(player_side, b - 1 if options.growth == "progression" else 0)
		model.configure_deck(opponent_side, ServerAI.stage_unit_deck(b), ServerAI.stage_structure_deck(b))
		model.resources[opponent_side] = minf(BattleModel.MAX_RESOURCE, 35.0 + b * 10.0)
		model.configure_base_health(opponent_side, 300.0 + b * 20.0)
		opponent = ServerAI.new(opponent_side, b)
	else:
		var build_b: Array = build_a if options.suite == "mirror" else structure_decks[posmod(pair_seed + 1, structure_decks.size())]
		model.configure_deck(opponent_side, decks[b], build_b)
		opponent = Bot.new(opponent_side, policy, pair_seed if options.suite == "mirror" else pair_seed + 17, decks[b])
	var player := Bot.new(player_side, policy, pair_seed, decks[a])
	var peak_units := 0
	var capped_steps := 0
	var owners := {}
	var observed_next_id := 1
	var event_counts: Array = [{"support_buffs":0,"curses":0,"summons":0,"structures":0},{"support_buffs":0,"curses":0,"summons":0,"structures":0}]
	var steps := int(ceil(float(options.timeout) / float(options.dt)))
	for step in steps:
		# Both match orientations keep logical player/opponent purchase order.
		player.update(model, options.dt)
		opponent.update(model, options.dt)
		# Keep IDs of newly bought casters even when they die in this same tick.
		if observed_next_id != model.next_unit_id:
			for unit in model.units: owners[unit.id] = int(unit.side)
			observed_next_id = model.next_unit_id
		model.tick(minf(float(options.dt), float(options.timeout) - model.elapsed))
		peak_units = maxi(peak_units, model.units.size())
		if model.units.size() >= BattleModel.MAX_ACTIVE_UNITS: capped_steps += 1
		if observed_next_id != model.next_unit_id:
			for unit in model.units: owners[unit.id] = int(unit.side)
			observed_next_id = model.next_unit_id
		for event in model.combat_events:
			var category := "support_buffs" if event.type == "SUPPORT_BUFF" else "curses" if event.type == "CURSE" else "summons" if event.type == "SUMMON" else ""
			if not category.is_empty() and owners.has(event.source_id):
				event_counts[int(owners[event.source_id])][category] += 1
		model.combat_events.clear()
		if model.winner != -1: break
		if not is_finite(float(model.resources[0])) or not is_finite(float(model.resources[1])) or model.resources[0] < 0.0 or model.resources[1] < 0.0 or model.base_hp[0] < 0.0 or model.base_hp[1] < 0.0:
			printerr("Invalid state at pair seed ", pair_seed); quit(1); return {}
	var result := "timeout" if model.winner == -1 else "draw" if model.winner == 2 else "win" if model.winner == player_side else "loss"
	for side in 2: event_counts[side].structures = int(model.battle_report[side].structures_built)
	return {"type":"match", "suite":options.suite, "deck_a":decks[a], "deck_b":model.unit_decks[opponent_side], "structures_a":build_a, "structures_b":model.structure_decks[opponent_side], "stage":b if options.suite == "campaign" else 0, "policy":policy, "side_a":player_side, "result_a":result, "winner":model.winner, "elapsed":model.elapsed, "base_a":model.base_hp[player_side], "base_b":model.base_hp[opponent_side], "peak_units":peak_units, "capped_steps":capped_steps, "report_a":model.battle_report[player_side], "report_b":model.battle_report[opponent_side], "events_a":event_counts[player_side], "events_b":event_counts[opponent_side]}

static func combinations(values: Array, count: int) -> Array:
	var result: Array = []
	if count == 0: return [[]]
	for i in range(values.size() - count + 1):
		for suffix in combinations(values.slice(i + 1), count - 1):
			result.append([values[i]] + suffix)
	return result

func _data_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for kind in ["units/" + "|".join(PackedStringArray(BattleModel.UNIT_STATS.keys() + BattleModel.SUMMON_STATS.keys())), "structures/" + "|".join(PackedStringArray(BattleModel.STRUCTURE_STATS.keys()))]:
		ctx.update(kind.to_utf8_buffer())
	ctx.update(JSON.stringify([BattleModel.UNIT_STATS, BattleModel.SUMMON_STATS, BattleModel.STRUCTURE_STATS]).to_utf8_buffer())
	return ctx.finish().hex_encode()
