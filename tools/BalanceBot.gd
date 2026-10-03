extends RefCounted

# Benchmark players use legal purchases and no ServerAI stat/income bonuses.
var side: int
var policy: String
var rng := RandomNumberGenerator.new()
var tactics: ServerAI
var timer := 0.0
var build_timer := 0.0
var cursor := 0
var order: Array
var weights := {}

func _init(player_side: int, player_policy: String, player_seed: int, deck: Array) -> void:
	side = player_side
	policy = player_policy
	rng.seed = player_seed
	tactics = ServerAI.new(side, 8)
	order = deck.duplicate()
	for kind in order:
		weights[kind] = rng.randf_range(0.6, 1.4)
	# A seeded opening and reaction delay, mirrored unchanged on side swaps.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var previous = order[i]
		order[i] = order[j]
		order[j] = previous
	timer = rng.randf_range(0.0, 0.3)

func update(model: BattleModel, delta: float) -> void:
	timer -= delta
	build_timer -= delta
	if timer > 0.0:
		return
	timer = rng.randf_range(0.35, 0.65)
	var state := tactics.tactical_state(model)
	if build_timer <= 0.0:
		build_timer = 3.0
		tactics._try_place_structure(model)
	# Reserve an early generator after establishing a small defending force.
	if model.elapsed > 8.0 and model.elapsed < 100.0 and state.own >= 2 and not state.danger and model.structure_decks[side].has("generator") and model._owned_structure_count(side, "generator") == 0:
		var x := BattleModel.BLUE_BUILD_MIN + 35.0 if side == 0 else BattleModel.RED_BUILD_MAX - 35.0
		var error := model.structure_placement_error(side, "generator", x)
		if error.is_empty() or error == "자원이 부족합니다.":
			model.place_structure(side, "generator", x)
			return
	if state.own >= 32:
		return
	var candidates := order.duplicate()
	if policy == "cycle":
		var first := cursor % candidates.size()
		candidates = candidates.slice(first) + candidates.slice(0, first)
	else:
		candidates.sort_custom(func(a, b): return score(a, state) > score(b, state))
	var preferred := String(candidates[0])
	# Rotation means saving for the next card, rather than always replacing it
	# with whichever cheap card is currently affordable.
	if policy == "cycle" and not state.danger:
		if model.spawn_unit(side, preferred): cursor += 1
		return
	var key_purchase: bool = (preferred == "necromancer" and int(state.counts.get(preferred, 0)) == 0) or (preferred == "healer" and state.buff_need >= 2 and int(state.counts.get(preferred, 0)) == 0) or (preferred == "shield" and state.frontline == 0 and state.own > 0)
	var clear_preference: bool = state.own >= 2 and score(preferred, state) >= score(String(candidates[1]), state) + 8.0
	if not state.danger and (key_purchase or clear_preference) and model.resources[side] < BattleModel.UNIT_STATS[preferred].cost:
		return
	for kind in candidates:
		if policy != "cycle" and kind == "healer" and tactics._unit_score(kind, state) <= 8.0:
			continue
		if model.spawn_unit(side, kind):
			cursor += 1
			return

func score(kind: String, state: Dictionary) -> float:
	return tactics._unit_score(kind, state) * (float(weights[kind]) if policy == "weighted" else 1.0)
