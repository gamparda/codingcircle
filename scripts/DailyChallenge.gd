extends RefCounted
## One shared challenge per UTC day: fixed decks, a campaign-AI stage and one rule twist, all derived from
## the date so every player faces exactly the same thing. Results are scored and kept per day.

const MODIFIERS := [
	{"id": "empty_hands", "name": "빈손 출발", "desc": "시작 자원이 20으로 줄어듭니다."},
	{"id": "iron_fortress", "name": "철벽 요새", "desc": "적 기지 체력이 최대치(500)까지 늘어납니다."},
	{"id": "rich_enemy", "name": "부자 적", "desc": "적이 자원을 가득 채운 채 시작합니다."},
	{"id": "fragile_base", "name": "약한 기지", "desc": "내 기지 체력이 300으로 줄어듭니다."},
	{"id": "elite_foe", "name": "정예 적", "desc": "적이 두 단계 더 강합니다."},
]
const MIN_STAGE := 2
const MAX_BASE_STAGE := 6

## "YYYYMMDD" in UTC. `unix < 0` means now.
static func date_key(unix: int = -1) -> String:
	var stamp := int(Time.get_unix_time_from_system()) if unix < 0 else unix
	var date := Time.get_date_dict_from_unix_time(stamp)
	return "%04d%02d%02d" % [int(date.year), int(date.month), int(date.day)]

static func for_date(key: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("catwar-daily-" + key)
	var units := BattleModel.UNIT_STATS.keys()
	var structures := BattleModel.STRUCTURE_STATS.keys()
	var unit_deck: Array = []
	while unit_deck.size() < 3:
		var pick: String = String(units[rng.randi_range(0, units.size() - 1)])
		if not unit_deck.has(pick):
			unit_deck.append(pick)
	var structure_deck: Array = []
	while structure_deck.size() < 3:
		var structure_pick: String = String(structures[rng.randi_range(0, structures.size() - 1)])
		if not structure_deck.has(structure_pick):
			structure_deck.append(structure_pick)
	var modifier: Dictionary = MODIFIERS[rng.randi_range(0, MODIFIERS.size() - 1)]
	var stage := rng.randi_range(MIN_STAGE, MAX_BASE_STAGE)
	return {"key": key, "stage": stage, "units": unit_deck, "structures": structure_deck, "modifier": String(modifier.id)}

static func modifier_info(id: String) -> Dictionary:
	for entry in MODIFIERS:
		if String(entry.id) == id:
			return entry
	return {}

static func effective_stage(challenge: Dictionary) -> int:
	return mini(ServerAI.MAX_STAGE, int(challenge.stage) + (2 if String(challenge.modifier) == "elite_foe" else 0))

## Builds the battle: {"model": BattleModel, "ai": ServerAI, "stage": int}.
static func build(challenge: Dictionary) -> Dictionary:
	var stage := effective_stage(challenge)
	var model := BattleModel.new()
	model.configure_deck(0, challenge.units, challenge.structures)
	model.configure_campaign_growth(0, stage - 1)
	model.configure_deck(1, ServerAI.stage_unit_deck(stage), ServerAI.stage_structure_deck(stage))
	model.resources[1] = minf(BattleModel.MAX_RESOURCE, 35.0 + float(stage) * 10.0)
	model.configure_base_health(1, 300.0 + float(stage) * 20.0)
	match String(challenge.modifier):
		"empty_hands": model.resources[0] = 20.0
		"iron_fortress": model.configure_base_health(1, BattleModel.BASE_MAX_HP)
		"rich_enemy": model.resources[1] = BattleModel.MAX_RESOURCE
		"fragile_base": model.configure_base_health(0, 300.0)
	return {"model": model, "ai": ServerAI.new(1, stage), "stage": stage}

## Winners score 100..3000: remaining base health and speed both pay.
static func score(won: bool, own_base: float, seconds: float) -> int:
	if not won:
		return 0
	return clampi(roundi(1000.0 + own_base * 2.0 - seconds * 2.0), 100, 3000)

## Stores the result (best score per day). Returns {"score", "best", "new_best"}.
static func record(save: Dictionary, challenge: Dictionary, won: bool, own_base: float, seconds: float) -> Dictionary:
	if not save.has("daily"):
		save["daily"] = {}
	var key := String(challenge.key)
	var points := score(won, own_base, seconds)
	var previous: Dictionary = save.daily.get(key, {})
	var best := int(previous.get("score", 0))
	var new_best := points > best
	if won and not bool(previous.get("won", false)):
		save.stats.daily_completed = int(save.stats.get("daily_completed", 0)) + 1
	if new_best or previous.is_empty():
		save.daily[key] = {"won": won or bool(previous.get("won", false)), "score": maxi(points, best), "seconds": seconds if new_best or previous.is_empty() else float(previous.get("seconds", seconds))}
	return {"score": points, "best": maxi(points, best), "new_best": new_best and won}

## Consecutive days (ending today or yesterday) with a win.
static func streak(save: Dictionary, today: String) -> int:
	var days := 0
	var cursor := _to_unix(today)
	if not _won_on(save, cursor) and _won_on(save, cursor - 86400):
		cursor -= 86400
	while _won_on(save, cursor):
		days += 1
		cursor -= 86400
	return days

static func _won_on(save: Dictionary, unix: int) -> bool:
	return bool(save.get("daily", {}).get(date_key(unix), {}).get("won", false))

static func _to_unix(key: String) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": int(key.substr(0, 4)), "month": int(key.substr(4, 2)), "day": int(key.substr(6, 2)), "hour": 12, "minute": 0, "second": 0}))

static func result_note(challenge: Dictionary, save: Dictionary, won: bool) -> String:
	var entry: Dictionary = save.get("daily", {}).get(String(challenge.key), {})
	if not won:
		return "일일 도전에 실패했습니다. 오늘 안에 다시 도전할 수 있습니다."
	return "일일 도전 성공! 오늘의 최고 점수 %d점" % int(entry.get("score", 0))
