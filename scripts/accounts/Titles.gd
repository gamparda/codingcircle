extends RefCounted
## Titles (칭호): names an account earns and can wear beside its nickname. Only the server grants them, from
## its own records (ranked games) or from battles it re-simulated itself (campaign, daily challenges,
## endless defense), so a title another player sees was really earned. The catalog is shared by both sides.

## id -> {"name", "how" (shown in the titles list), "group", "hidden" (condition shown only once earned)}
const CATALOG := {
	"endless_10": {"name": "성문지기", "how": "무한 방어 10웨이브 돌파", "group": "무한 방어"},
	"endless_20": {"name": "불침의 성벽", "how": "무한 방어 20웨이브 돌파", "group": "무한 방어"},
	"endless_30": {"name": "끝나지 않는 밤", "how": "무한 방어 30웨이브 돌파", "group": "무한 방어"},
	"endless_flawless": {"name": "흠집 없는 성", "how": "무한 방어에서 성 체력이 한 번도 절반 아래로 내려가지 않고 15웨이브 돌파", "group": "무한 방어"},
	"endless_melee": {"name": "맨손의 수비대", "how": "원거리 병력이 없는 덱으로 무한 방어 15웨이브 돌파", "group": "무한 방어"},
	"campaign_clear": {"name": "골짜기의 주인", "how": "AI 캠페인 8단계를 모두 클리어", "group": "AI 캠페인"},
	"campaign_stars": {"name": "완벽한 지휘관", "how": "AI 캠페인 모든 단계에서 별 3개", "group": "AI 캠페인"},
	"campaign_flawless": {"name": "무혈 입성", "how": "AI 캠페인 8단계를 기지 피해 없이 승리", "group": "AI 캠페인"},
	"ranked_1200": {"name": "견습 기사", "how": "랭크 점수 1200 달성", "group": "랭크 대전"},
	"ranked_1400": {"name": "기사단장", "how": "랭크 점수 1400 달성", "group": "랭크 대전"},
	"ranked_1600": {"name": "성주", "how": "랭크 점수 1600 달성", "group": "랭크 대전"},
	"ranked_streak": {"name": "꺼지지 않는 불씨", "how": "랭크 대전 10연승", "group": "랭크 대전"},
	"ranked_veteran": {"name": "백전노장", "how": "랭크 대전 100판", "group": "랭크 대전"},
	"ranked_season_top": {"name": "시즌의 영웅", "how": "랭크 시즌을 10위 안에서 마감", "group": "랭크 대전"},
	"necro_lord": {"name": "망자의 군주", "how": "랭크 대전에서 네크로맨서로 해골 300마리 소환(누적)", "group": "랭크 대전", "hidden": true},
	"daily_30": {"name": "성실한 파수꾼", "how": "일일·주간 도전을 서로 다른 30일에 완료", "group": "도전"},
	"founder": {"name": "성을 세운 자", "how": "특별히 받은 칭호", "group": "특별", "hidden": true},
	"warden": {"name": "성의 수호자", "how": "특별히 받은 칭호", "group": "특별", "hidden": true},
}
## Ranked rating thresholds and their titles.
const RANKED_TIERS := [[1200, "ranked_1200"], [1400, "ranked_1400"], [1600, "ranked_1600"]]
const STREAK := 10
const VETERAN_GAMES := 100
const SEASON_TOP := 10
const NECRO_SUMMONS := 300
const DAILY_DAYS := 30
const ENDLESS_TIERS := [[10, "endless_10"], [20, "endless_20"], [30, "endless_30"]]
const ENDLESS_FEAT_WAVES := 15
## Roles: a hyper account appoints super accounts; both may use cheats in solo modes.
const ROLES := ["", "super", "hyper"]

static func valid_id(id: Variant) -> bool:
	return id is String and CATALOG.has(id)

static func name_of(id: String) -> String:
	return String(CATALOG[id].name) if CATALOG.has(id) else ""

## "[성주]" for a worn title, "" for none. (Plain brackets: CJK corner brackets make some Android fonts drop the
## Hangul right after them.)
static func badge(id: String) -> String:
	return "[%s]" % name_of(id) if CATALOG.has(id) else ""

## "[성주] 닉네임", or just the nickname without a title.
static func titled(id: String, nickname: String) -> String:
	return badge(id) + " " + nickname if CATALOG.has(id) else nickname

static func can_cheat(role: String) -> bool:
	return role in ["super", "hyper"]

## Titles a role brings with it (kept while the role lasts).
static func role_titles(role: String) -> Array:
	return ["founder"] if role == "hyper" else (["warden"] if role == "super" else [])
