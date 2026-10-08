extends RefCounted
## Auto-battles a deck against a campaign stage's AI to estimate how well it does.
## Matches run in small time slices (`Run.step(budget_msec)`) so the UI stays responsive.
## Same setup as the balance benchmark's campaign suite: growth = stage - 1, AI at its stage strength.

const AutoPlayer = preload("res://scripts/AutoPlayer.gd")
const DT := 0.05
const TIMEOUT := 420.0
const EARLY_LOSS_SECONDS := 90.0
const LATE_LOSS_SECONDS := 240.0
const FRONTLINE := ["shield", "berserker", "swordsman"]
const RANGED := ["archer", "warlock"]

class Run extends RefCounted:
	var unit_deck: Array
	var structure_deck: Array
	var stage := 1
	var total := 0
	var first_index := 0 # matches are seeded by index; a chunk of a bigger experiment starts at its own offset
	var results: Array = []
	var _model: BattleModel = null
	var _player = null
	var _opponent: ServerAI = null

	func _init(units: Array, structures: Array, target_stage: int, matches: int, offset: int = 0) -> void:
		first_index = maxi(0, offset)
		unit_deck = units.duplicate()
		structure_deck = structures.duplicate()
		stage = clampi(target_stage, ServerAI.MIN_STAGE, ServerAI.MAX_STAGE)
		total = maxi(1, matches)

	func is_done() -> bool:
		return results.size() >= total

	func progress() -> float:
		var partial := 0.0
		if _model != null:
			partial = clampf(_model.elapsed / 180.0, 0.0, 0.95)
		return clampf((float(results.size()) + partial) / float(total), 0.0, 1.0)

	## Runs for roughly `budget_msec` of wall time. Returns true once every match is finished.
	func step(budget_msec: int = 10) -> bool:
		var started := Time.get_ticks_msec()
		while not is_done():
			if _model == null:
				_begin(first_index + results.size())
			while _model.winner == -1 and _model.elapsed < TIMEOUT:
				_player.update(_model, DT)
				_opponent.update(_model, DT)
				_model.tick(DT)
				if Time.get_ticks_msec() - started >= budget_msec:
					return false
			_finish()
		return true

	func _begin(index: int) -> void:
		_model = BattleModel.new()
		_model.configure_deck(0, unit_deck, structure_deck)
		_model.configure_campaign_growth(0, stage - 1)
		_model.configure_deck(1, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
		_model.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(stage) * 10.0)
		_model.configure_base_health(1, 300.0 + float(stage) * 20.0)
		_opponent = ServerAI.new(1, stage)
		_player = AutoPlayer.new(0, "weighted", 1000 + index * 7919, unit_deck)

	func _finish() -> void:
		var outcome := "timeout"
		if _model.winner == 0:
			outcome = "win"
		elif _model.winner == 1:
			outcome = "loss"
		elif _model.winner == 2:
			outcome = "draw"
		var report: Dictionary = _model.battle_report[0]
		results.append({"result": outcome, "seconds": _model.elapsed, "base": float(_model.base_hp[0]), "enemy_base": float(_model.base_hp[1]),
			"kills": int(report.get("kills", 0)), "damage": float(report.get("damage", 0.0))})
		_model = null
		_player = null
		_opponent = null

	func summary() -> Dictionary:
		return DeckSimulatorSummary.build(results, unit_deck, stage)

## Statistics and advice, kept separate so tests can feed it hand-made results.
class DeckSimulatorSummary extends RefCounted:
	static func build(results: Array, unit_deck: Array, stage: int) -> Dictionary:
		var wins := 0
		var losses := 0
		var draws := 0
		var timeouts := 0
		var early_losses := 0
		var late_losses := 0
		var seconds := 0.0
		var win_base := 0.0
		for entry in results:
			seconds += float(entry.seconds)
			match String(entry.result):
				"win":
					wins += 1
					win_base += float(entry.base)
				"loss":
					losses += 1
					if float(entry.seconds) < EARLY_LOSS_SECONDS:
						early_losses += 1
					elif float(entry.seconds) >= LATE_LOSS_SECONDS:
						late_losses += 1
				"draw": draws += 1
				_: timeouts += 1
		var count := maxi(1, results.size())
		var summary := {"matches": results.size(), "wins": wins, "losses": losses, "draws": draws, "timeouts": timeouts,
			"win_rate": float(wins) / float(count), "average_seconds": seconds / float(count),
			"average_base_on_win": win_base / float(maxi(1, wins)), "early_losses": early_losses, "late_losses": late_losses, "stage": stage}
		summary["tips"] = tips(summary, unit_deck)
		return summary

	static func tips(summary: Dictionary, unit_deck: Array) -> Array:
		var out: Array = []
		if int(summary.matches) == 0:
			return out
		if not unit_deck.any(func(kind): return FRONTLINE.has(kind)):
			out.append("앞줄을 버텨 줄 유닛(탱커·광전사·검사)이 없습니다.")
		if not unit_deck.any(func(kind): return RANGED.has(kind)):
			out.append("원거리 화력(궁수·흑마법사)이 없어 먼 거리 교전에서 불리합니다.")
		var losses := int(summary.losses)
		if losses > 0 and int(summary.early_losses) * 2 >= losses:
			out.append("초반에 밀립니다. 값싼 앞줄과 방벽·포탑으로 초반 방어를 강화해 보세요.")
		elif losses > 0 and int(summary.late_losses) * 2 >= losses:
			out.append("장기전에서 밀립니다. 발전기나 네크로맨서처럼 후반에 강한 구성을 고려해 보세요.")
		if int(summary.timeouts) > 0:
			out.append("결판이 나지 않은 판이 있습니다. 공격력이 높은 유닛을 더해 마무리 힘을 키워 보세요.")
		if float(summary.win_rate) >= 0.8:
			out.insert(0, "이 단계에서는 이 덱이 안정적입니다. 더 높은 단계로 시험해 보세요.")
		elif float(summary.win_rate) <= 0.2 and out.is_empty():
			out.append("이 단계에는 아직 벅찹니다. 낮은 단계에서 조합을 다듬어 보세요.")
		return out.slice(0, 3)

static func start(unit_deck: Array, structure_deck: Array, stage: int, matches: int) -> Run:
	return Run.new(unit_deck, structure_deck, stage, matches)

static func valid_selection(unit_deck: Array, structure_deck: Array) -> bool:
	return BattleModel._valid_deck(unit_deck, BattleModel.UNIT_STATS) and BattleModel._valid_deck(structure_deck, BattleModel.STRUCTURE_STATS)
