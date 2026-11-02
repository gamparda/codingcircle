extends RefCounted
## Progression shared by the server and the game: gold, daily and weekly quests, the free season pass, the
## cosmetics catalog (bought with gold; none changes how a battle plays), unit mastery and the codex. Only the
## server changes an account's progression, and only from play it saw itself or re-simulated (online matches,
## verified campaign / challenge / endless battles), so gold cannot be made up on a device.

## ---------- gold ----------
## Battle time pays GOLD_PER_MINUTE (at most BATTLE_GOLD_MAX a battle), wins add WIN_GOLD, and battle gold
## stops at DAILY_BATTLE_GOLD a day (UTC); quests and the pass are on top.
const GOLD_PER_MINUTE := 3.0
const BATTLE_GOLD_MAX := 30
const WIN_GOLD := {"campaign": 10, "daily": 15, "online": 10, "ranked": 20, "endless": 0}
const ENDLESS_WAVE_GOLD := 2
const ENDLESS_WAVE_GOLD_MAX := 60
const DAILY_BATTLE_GOLD := 400
const MODES := ["online", "ranked", "campaign", "daily", "endless"]

## ---------- quests ----------
## metric: "wins" | "battles" | "ranked_wins" | "online" | "endless_waves" (best wave count in one run) |
## "seconds" | "spawns:<unit>" | "kills:<unit>". "unit" in a template is filled with a unit kind.
const DAILY_QUESTS := [
	{"id": "win3", "text": "아무 모드에서 %d번 승리", "metric": "wins", "goal": 3},
	{"id": "play5", "text": "전투 %d판 하기", "metric": "battles", "goal": 5},
	{"id": "time20", "text": "전투 %d분 하기", "metric": "seconds", "goal": 1200},
	{"id": "online2", "text": "온라인·랭크 대전 %d판", "metric": "online", "goal": 2},
	{"id": "waves8", "text": "무한 방어에서 한 번에 %d웨이브 막기", "metric": "endless_waves", "goal": 8},
	{"id": "spawn", "text": "%s %d기 출전시키기", "metric": "spawns:unit", "goal": 25},
	{"id": "kills", "text": "%s로 적 %d명 처치", "metric": "kills:unit", "goal": 30},
]
const WEEKLY_QUESTS := [
	{"id": "w_win15", "text": "이번 주 %d번 승리", "metric": "wins", "goal": 15},
	{"id": "w_ranked5", "text": "이번 주 랭크 대전 %d승", "metric": "ranked_wins", "goal": 5},
	{"id": "w_time120", "text": "이번 주 전투 %d분", "metric": "seconds", "goal": 7200},
	{"id": "w_waves15", "text": "무한 방어에서 한 번에 %d웨이브 막기", "metric": "endless_waves", "goal": 15},
]
const DAILY_REWARDS := [40, 60, 80]
const WEEKLY_REWARD := 300

## ---------- season pass ----------
## Pass experience: one per PASS_SECONDS_PER_XP of battle, PASS_WIN_XP a win, PASS_QUEST_XP a quest.
const PASS_TIERS := 30
const PASS_XP_PER_TIER := 100
const PASS_SECONDS_PER_XP := 10.0
const PASS_WIN_XP := 20
const PASS_QUEST_XP := 50
const PASS_TIER_GOLD := 20
## Tier -> cosmetic slot given that season (a season item, "season:<YYYY-MM>:<slot>").
const PASS_ITEMS := {5: "emote", 10: "frame", 15: "palette", 20: "banner", 25: "castle", 30: "title"}

## ---------- mastery ----------
const MASTERY_LEVELS := [[50, "동"], [300, "은"], [1000, "금"]]

## ---------- cosmetics ----------
## slot: "palette" (tint of my units), "frame" (my battle cards), "banner" (profile card), "castle" (my castle),
## "emote" (battle emotes; four are worn at once). price 0 with "default": owned by everyone.
const SLOTS := ["palette", "frame", "banner", "castle", "emote"]
const EMOTE_SLOTS := 4
const CATALOG := {
	"palette_none": {"slot": "palette", "name": "기본 색", "default": true},
	"palette_crimson": {"slot": "palette", "name": "진홍", "price": 300, "color": Color("#ff6b6b")},
	"palette_frost": {"slot": "palette", "name": "서리", "price": 300, "color": Color("#8fd3ff")},
	"palette_gold": {"slot": "palette", "name": "황금", "price": 500, "color": Color("#ffd46b")},
	"palette_shadow": {"slot": "palette", "name": "그림자", "price": 400, "color": Color("#8a7ca8")},
	"palette_verdant": {"slot": "palette", "name": "새싹", "price": 300, "color": Color("#8ee08a")},
	"palette_royal": {"slot": "palette", "name": "왕실 보라", "price": 400, "color": Color("#c49bff")},
	"frame_bronze": {"slot": "frame", "name": "청동 테두리", "default": true},
	"frame_silver": {"slot": "frame", "name": "은 테두리", "price": 200, "color": Color("#d8dee8")},
	"frame_gold": {"slot": "frame", "name": "금 테두리", "price": 400, "color": Color("#f3c56a")},
	"frame_obsidian": {"slot": "frame", "name": "흑요석 테두리", "price": 300, "color": Color("#5a4a78")},
	"frame_jade": {"slot": "frame", "name": "비취 테두리", "price": 300, "color": Color("#5fc4a0")},
	"banner_ember": {"slot": "banner", "name": "불씨 깃발", "default": true, "color": Color("#d0803a"), "color2": Color("#3a2414"), "emblem": "shield"},
	"banner_night": {"slot": "banner", "name": "달밤 깃발", "price": 250, "color": Color("#3b4c8f"), "color2": Color("#0f1430"), "emblem": "moon"},
	"banner_blood": {"slot": "banner", "name": "핏빛 깃발", "price": 250, "color": Color("#a63a3a"), "color2": Color("#2a0d0d"), "emblem": "sword"},
	"banner_crown": {"slot": "banner", "name": "왕관 깃발", "price": 500, "color": Color("#e8b84a"), "color2": Color("#3d2a08"), "emblem": "crown"},
	"banner_forest": {"slot": "banner", "name": "숲 깃발", "price": 250, "color": Color("#3f8f5a"), "color2": Color("#0e2414"), "emblem": "star"},
	"castle_none": {"slot": "castle", "name": "기본 성", "default": true},
	"castle_ice": {"slot": "castle", "name": "얼음 성", "price": 400, "color": Color("#a8dcff")},
	"castle_ember": {"slot": "castle", "name": "불꽃 성", "price": 400, "color": Color("#ffb070")},
	"castle_moss": {"slot": "castle", "name": "이끼 성", "price": 350, "color": Color("#a6d88a")},
	"emote_nice": {"slot": "emote", "name": "좋은 수!", "default": true},
	"emote_thanks": {"slot": "emote", "name": "고마워요", "default": true},
	"emote_danger": {"slot": "emote", "name": "위험해!", "default": true},
	"emote_gg": {"slot": "emote", "name": "GG", "default": true},
	"emote_wow": {"slot": "emote", "name": "놀랍다!", "price": 100},
	"emote_again": {"slot": "emote", "name": "한 판 더?", "price": 100},
	"emote_oops": {"slot": "emote", "name": "아차…", "price": 100},
	"emote_hold": {"slot": "emote", "name": "막아라!", "price": 100},
	"emote_bye": {"slot": "emote", "name": "잘 가요~", "price": 150},
	"emote_king": {"slot": "emote", "name": "성은 내가 지킨다", "price": 200},
}
const DEFAULT_EQUIPPED := {"palette": "palette_none", "frame": "frame_bronze", "banner": "banner_ember", "castle": "castle_none", "emotes": ["emote_nice", "emote_thanks", "emote_danger", "emote_gg"]}
const SHOP_SIZE := 6

## ---------- codex ----------
const LORE := {
	"shield": "성문 앞을 지키는 고양이 기사. 같은 자리의 동료 대신 먼저 맞아 준다.",
	"swordsman": "골짜기 마을에서 모인 칼잡이. 싸고 빠르게 줄을 채운다.",
	"archer": "성벽 위에서 자란 사수. 앞줄 뒤에서 멀리 쏜다.",
	"healer": "달빛을 다루는 마법사. 곁의 동료가 점점 빨리 싸우게 한다.",
	"berserker": "상처가 깊을수록 날뛰는 광전사. 쓰러지기 직전이 가장 위험하다.",
	"warlock": "저주를 새기는 흑마법사. 맞은 자리에 느려지는 저주를 남긴다.",
	"necromancer": "무덤을 깨우는 네크로맨서. 해골 병사를 계속 불러낸다.",
	"zombie": "한 번 쓰러져도 다시 일어나는 시체. 성기사의 신성한 일격만은 견디지 못한다.",
	"paladin": "언데드와 마족을 심판하는 성기사. 신성한 일격으로 주변을 내리친다.",
	"sniper": "적진 맨 뒤를 노리는 저격수. 방벽 너머도 쏜다.",
	"demon_lord": "쓰러진 자의 영혼을 거두는 마왕. 영혼이 쌓일수록 강해진다.",
}

## ---------- helpers ----------

static func cosmetic(id: String) -> Dictionary:
	if CATALOG.has(id):
		return CATALOG[id]
	var parts := id.split(":")
	# Season pass items: "season:YYYY-MM:<slot>", coloured by the month.
	if parts.size() == 3 and parts[0] == "season" and String(parts[2]) in SLOTS:
		var hue := float(abs(String(parts[1]).hash()) % 360) / 360.0
		var slot := String(parts[2])
		var name := "%s 시즌 %s" % [String(parts[1]), {"palette": "색", "frame": "테두리", "banner": "깃발", "castle": "성", "emote": "인사"}[slot]]
		var entry := {"slot": slot, "name": name, "season": String(parts[1]), "color": Color.from_hsv(hue, 0.55, 1.0), "color2": Color.from_hsv(hue, 0.7, 0.25), "emblem": "star"}
		if slot == "emote":
			entry.name = "%s 시즌, 좋은 승부!" % String(parts[1])
		return entry
	return {}

static func valid_cosmetic(id: Variant) -> bool:
	return id is String and String(id).length() <= 40 and not cosmetic(String(id)).is_empty()

static func defaults() -> Array:
	var owned: Array = []
	for id in CATALOG:
		if bool(CATALOG[id].get("default", false)):
			owned.append(id)
	return owned

static func price(id: String) -> int:
	return int(CATALOG.get(id, {}).get("price", 0))

## The UTC day key "YYYYMMDD" and the Monday that starts its week.
static func day_key(unix: int) -> String:
	var date := Time.get_date_dict_from_unix_time(unix)
	return "%04d%02d%02d" % [int(date.year), int(date.month), int(date.day)]

static func week_key(unix: int) -> String:
	var days := int(floor(float(unix) / 86400.0))
	return day_key((days - (days + 3) % 7) * 86400)

## Quests of `day` for `account`: three daily (and the week's one), the same on every server start.
static func daily_quests(account: String, day: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("keepfall-quests-" + account + "-" + day)
	var pool := range(DAILY_QUESTS.size())
	var picked: Array = []
	var units: Array = BattleModel.UNIT_STATS.keys()
	while picked.size() < 3:
		var index: int = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var quest := _fill(DAILY_QUESTS[index], units[rng.randi_range(0, units.size() - 1)])
		quest.reward = DAILY_REWARDS[picked.size()]
		picked.append(quest)
	return picked

static func weekly_quest(account: String, week: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("keepfall-weekly-" + account + "-" + week)
	var quest := _fill(WEEKLY_QUESTS[rng.randi_range(0, WEEKLY_QUESTS.size() - 1)], "")
	quest.reward = WEEKLY_REWARD
	return quest

static func _fill(template: Dictionary, unit: String) -> Dictionary:
	var quest := template.duplicate()
	var metric := String(template.metric)
	if metric.ends_with(":unit"):
		quest.metric = metric.replace(":unit", ":" + unit)
		quest.id = String(template.id) + "_" + unit
		quest.text = String(template.text) % [String(BattleModel.UNIT_NAMES.get(unit, unit)), int(template.goal)]
	else:
		quest.text = String(template.text) % (int(template.goal) / 60 if metric == "seconds" else int(template.goal))
	quest.progress = 0
	quest.done = false
	return quest

## How much one battle moves a quest metric.
static func metric_amount(metric: String, event: Dictionary) -> int:
	match metric:
		"wins": return 1 if bool(event.won) else 0
		"battles": return 1
		"ranked_wins": return 1 if bool(event.won) and String(event.mode) == "ranked" else 0
		"online": return 1 if String(event.mode) in ["online", "ranked"] else 0
		"seconds": return int(event.seconds)
	if metric.begins_with("spawns:"):
		return int(event.units.get(metric.trim_prefix("spawns:"), {}).get("spawned", 0))
	if metric.begins_with("kills:"):
		return int(event.units.get(metric.trim_prefix("kills:"), {}).get("kills", 0))
	return 0

## Gold one battle earns before the daily cap.
static func battle_gold(event: Dictionary) -> int:
	var gold := mini(BATTLE_GOLD_MAX, int(float(event.seconds) / 60.0 * GOLD_PER_MINUTE))
	if bool(event.won):
		gold += int(WIN_GOLD.get(String(event.mode), 0))
	if String(event.mode) == "endless":
		gold += mini(ENDLESS_WAVE_GOLD_MAX, int(event.get("waves", 0)) * ENDLESS_WAVE_GOLD)
	return gold

static func mastery_level(spawned: int) -> String:
	var level := ""
	for step in MASTERY_LEVELS:
		if spawned >= int(step[0]):
			level = String(step[1])
	return level

## A battle summary the server builds from a model it ran: seconds, whether `side` won, and per unit how many
## `side` fielded and how many enemies they took down.
static func event_from_model(model: BattleModel, side: int, mode: String, extra: Dictionary = {}) -> Dictionary:
	var units := {}
	var rows: Dictionary = model.battle_report[side].units
	for kind in rows:
		if BattleModel.UNIT_STATS.has(kind):
			var spawned := int(rows[kind].purchased)
			var kills := int(rows[kind].kills)
			if spawned > 0 or kills > 0:
				units[kind] = {"spawned": spawned, "kills": kills}
	var event := {"mode": mode, "seconds": float(model.elapsed), "won": model.winner == side, "units": units}
	event.merge(extra, true)
	return event
