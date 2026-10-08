extends RefCounted
## Achievements are judged from facts about one finished battle plus the save file's running totals.
## Unlocked ids are stored in save_data.achievements as {id: unix time}.

const DEFS := [
	{"id": "first_win", "icon": "★", "name": "첫 승리", "desc": "어떤 전투에서든 처음으로 이기기"},
	{"id": "flawless", "icon": "🛡", "name": "무피해 승리", "desc": "내 기지 체력을 하나도 잃지 않고 승리하기"},
	{"id": "comeback", "icon": "↺", "name": "역전승", "desc": "크게 밀리다가 뒤집어 승리하기"},
	{"id": "speed_win", "icon": "⚡", "name": "속전속결", "desc": "60초 안에 승리하기"},
	{"id": "marathon", "icon": "⏳", "name": "장기전의 달인", "desc": "5분 넘게 이어진 전투에서 승리하기"},
	{"id": "architect", "icon": "▤", "name": "건축가", "desc": "한 전투에서 구조물 3개 이상 설치하기"},
	{"id": "slayer", "icon": "⚔", "name": "학살자", "desc": "한 전투에서 적 30명 이상 처치하기"},
	{"id": "streak3", "icon": "🔥", "name": "3연승", "desc": "전투에서 3연승하기"},
	{"id": "veteran", "icon": "☗", "name": "온라인 단골", "desc": "온라인 전투 10판 완료하기"},
	{"id": "star_collector", "icon": "✦", "name": "만점 지휘관", "desc": "캠페인 모든 단계에서 별 3개 받기"},
	{"id": "daily_clear", "icon": "☀", "name": "오늘의 도전자", "desc": "일일 도전 승리하기"},
	{"id": "weekly_clear", "icon": "☾", "name": "주간 도전자", "desc": "주간 도전 승리하기"},
	{"id": "draft_win", "icon": "♟", "name": "드래프트 승자", "desc": "드래프트 대전에서 승리하기"},
	{"id": "ghost_buster", "icon": "👻", "name": "고스트 격파", "desc": "고스트 대전에서 승리하기"},
]

static func definition(id: String) -> Dictionary:
	for entry in DEFS:
		if String(entry.id) == id:
			return entry
	return {}

static func ids() -> Array:
	return DEFS.map(func(entry): return String(entry.id))

static func unlocked_count(save: Dictionary) -> int:
	var count := 0
	for id in ids():
		if save.get("achievements", {}).has(id):
			count += 1
	return count

## Updates the win streak. Experiments (practice tools, ghost, what-if) never call this.
static func record_outcome(save: Dictionary, won: bool, lost: bool) -> void:
	var stats: Dictionary = save.stats
	if won:
		stats.win_streak = int(stats.get("win_streak", 0)) + 1
		stats.best_streak = maxi(int(stats.get("best_streak", 0)), int(stats.win_streak))
	elif lost:
		stats.win_streak = 0

## `ctx`: mode ("campaign" | "practice" | "daily" | "online" | "ghost"), won, seconds, own_base, own_base_max,
## structures_built, kills, curve (blue-positive momentum samples), own_side.
## Returns the definitions unlocked just now (and stores them in `save`).
static func evaluate(save: Dictionary, ctx: Dictionary, now: int = -1) -> Array:
	if not save.has("achievements"):
		save["achievements"] = {}
	var stamp := int(Time.get_unix_time_from_system()) if now < 0 else now
	var won: bool = bool(ctx.get("won", false))
	var mode := String(ctx.get("mode", ""))
	var seconds := float(ctx.get("seconds", 0.0))
	var earned: Array = []
	var checks := {
		"first_win": won and mode != "ghost",
		"flawless": won and float(ctx.get("own_base", 0.0)) >= float(ctx.get("own_base_max", 1.0)) - 0.5,
		"comeback": won and _lowest_own(ctx) <= -0.3,
		"speed_win": won and seconds > 0.0 and seconds <= 60.0,
		"marathon": won and seconds >= 300.0,
		"architect": int(ctx.get("structures_built", 0)) >= 3 and mode != "ghost",
		"slayer": int(ctx.get("kills", 0)) >= 30 and mode != "ghost",
		"streak3": int(save.stats.get("win_streak", 0)) >= 3,
		"veteran": int(save.stats.get("online_completed", 0)) >= 10,
		"star_collector": save.get("campaign_records", []).size() >= 8 and save.campaign_records.all(func(record): return int(record.best_stars) >= 3),
		"daily_clear": won and mode == "daily",
		"weekly_clear": won and mode == "daily" and String(ctx.get("period", "daily")) == "weekly",
		"ghost_buster": won and mode == "ghost",
		"draft_win": won and mode == "draft",
	}
	for id in checks:
		if bool(checks[id]) and not save.achievements.has(id):
			save.achievements[id] = stamp
			earned.append(definition(id))
	return earned

static func _lowest_own(ctx: Dictionary) -> float:
	var curve: Array = ctx.get("curve", [])
	if curve.size() < 4:
		return 0.0
	var sign := 1.0 if int(ctx.get("own_side", 0)) == 0 else -1.0
	var lowest := 1.0
	for value in curve:
		lowest = minf(lowest, float(value) * sign)
	return lowest
