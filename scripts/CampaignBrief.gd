extends RefCounted
const GOALS := [
	"탱커로 전선을 지키고 궁수로 뒤에서 공격하세요.",
	"광전사가 격노하기 전에 집중 공격하세요.",
	"저주 장판을 피해 전선을 나누세요.",
	"지속 공속 지원을 받는 병력을 먼저 끊으세요.",
	"돌격 병력과 지원 병력을 분리하세요.",
	"해골보다 소환사를 우선 공격하세요.",
	"저주와 해골이 겹치기 전에 전선을 밀어내세요.",
	"발전기로 경제를 확보하고 복합 전술을 돌파하세요."
]
static func goal(stage: int) -> String:
	return GOALS[clampi(stage,1,8)-1]
static func enemy_deck(stage: int) -> String:
	var names: Array = []
	for kind in ServerAI.stage_unit_deck(stage): names.append(BattleModel.UNIT_NAMES[kind])
	var structures := {"wall":"방벽","swamp":"늪","turret":"포탑","generator":"발전기"}
	for kind in ServerAI.stage_structure_deck(stage): names.append(structures[kind])
	return " · ".join(names)
static func conditions(stage: int) -> String:
	var target: Dictionary = SaveData.CAMPAIGN_TARGETS[clampi(stage,1,8)-1]
	return "★ 승리   ★★ 기지 %d 이상   ★★★ 앞 조건 + %d초 이내" % [int(target.base_hp),int(target.time)]
static func result_conditions(stage: int, won: bool, elapsed: float, hp: float) -> String:
	var target: Dictionary = SaveData.CAMPAIGN_TARGETS[clampi(stage,1,8)-1]
	return "%s 승리 · %s 기지 %d/%d · %s 시간 %.0f/%d초" % ["✓" if won else "✕","✓" if won and hp>=float(target.base_hp) else "✕",roundi(hp),int(target.base_hp),"✓" if won and hp>=float(target.base_hp) and elapsed<=float(target.time) else "✕",elapsed,int(target.time)]
