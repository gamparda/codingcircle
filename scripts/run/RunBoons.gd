extends RefCounted
## Relics (expedition) and boons (endless defense): permanent run bonuses that become BattleModel modifiers.
## Each entry's "mods" uses BattleModel.modifier() keys; combine() merges any number of them (multipliers
## multiply, additions add), so taking the same boon twice in endless defense stacks.

## Keys that add; every other key multiplies.
const ADDITIVE := ["income", "capacity", "start", "skeleton_cap", "range:ranged", "first_strike"]

const RELICS := {
	"steel_plate": {"name": "강철 갑옷", "icon": "🛡", "rarity": "common", "text": "근접 유닛 체력 +15%", "mods": {"hp:melee": 1.15}},
	"eagle_eye": {"name": "독수리의 눈", "icon": "👁", "rarity": "common", "text": "원거리 유닛 사거리 +40", "mods": {"range:ranged": 40.0}},
	"barbed_tips": {"name": "가시 화살촉", "icon": "🏹", "rarity": "common", "text": "원거리 유닛 공격 +15%", "mods": {"damage:ranged": 1.15}},
	"granary": {"name": "군량 창고", "icon": "🌾", "rarity": "common", "text": "자원 수입 +1/초", "mods": {"income": 1.0}},
	"vault": {"name": "넓은 금고", "icon": "📦", "rarity": "common", "text": "자원 보유 한도 +60", "mods": {"capacity": 60.0}},
	"war_chest": {"name": "출정 자금", "icon": "💰", "rarity": "common", "text": "전투 시작 자원 +60", "mods": {"start": 60.0}},
	"recruiter": {"name": "징병관", "icon": "📜", "rarity": "rare", "text": "유닛 비용 -10%", "mods": {"cost:units": 0.9}},
	"grimoire": {"name": "마도서", "icon": "📖", "rarity": "rare", "text": "전술 마법 재사용 대기 -20%", "mods": {"spell_cooldown": 0.8}},
	"masons": {"name": "석공 길드", "icon": "🧱", "rarity": "common", "text": "구조물 체력 +30%", "mods": {"structure_hp": 1.3}},
	"anchor": {"name": "무거운 장화", "icon": "🥾", "rarity": "common", "text": "아군이 밀려나는 거리 -50%", "mods": {"knockback": 0.5}},
	"bone_urn": {"name": "뼈 항아리", "icon": "⚱", "rarity": "rare", "text": "네크로맨서 해골 한도 +1", "mods": {"skeleton_cap": 1.0}},
	"death_tome": {"name": "망자의 서", "icon": "💀", "rarity": "rare", "text": "네크로맨서 소환 대기 -25%", "mods": {"skill_cooldown:necromancer": 0.75}},
	"ambush": {"name": "기습", "icon": "⚡", "rarity": "rare", "text": "모든 유닛의 첫 공격 피해 2배", "mods": {"first_strike": 1.0}},
	"blood_oath": {"name": "피의 맹세", "icon": "🩸", "rarity": "common", "text": "광전사 공격 +30%", "mods": {"damage:berserker": 1.3}},
	"war_drum": {"name": "전쟁 북", "icon": "🥁", "rarity": "boss", "text": "모든 유닛 공격 +10%", "mods": {"damage:all": 1.1}},
	"aegis": {"name": "수호의 부적", "icon": "🔰", "rarity": "boss", "text": "모든 유닛 체력 +10%", "mods": {"hp:all": 1.1}},
}

## Modifiers of the relics `ids` (unknown ids are skipped), plus card upgrades `stars` ({kind: level}).
static func combine(ids: Array, stars: Dictionary = {}) -> Dictionary:
	var result := {}
	for id in ids:
		if not RELICS.has(id):
			continue
		var mods: Dictionary = RELICS[id].mods
		for key in mods:
			if key in ADDITIVE:
				result[key] = float(result.get(key, 0.0)) + float(mods[key])
			else:
				result[key] = float(result.get(key, 1.0)) * float(mods[key])
	for key in result.keys():
		if (key in ADDITIVE and is_zero_approx(float(result[key]))) or (not key in ADDITIVE and is_equal_approx(float(result[key]), 1.0)):
			result.erase(key)
	var levels := {}
	for kind in stars:
		if int(stars[kind]) > 0:
			levels[kind] = clampi(int(stars[kind]), 0, 2)
	if not levels.is_empty():
		result["stars"] = levels
	return result

## `count` different relic ids drawn with `rng` from those not in `owned`; boss relics only when `allow_boss`.
static func draw(rng: RandomNumberGenerator, count: int, owned: Array = [], allow_boss: bool = false) -> Array:
	var pool: Array = []
	for id in RELICS:
		if not owned.has(id) and (allow_boss or RELICS[id].rarity != "boss"):
			pool.append(id)
	pool.sort()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked

static func label(id: String) -> String:
	return "%s %s" % [RELICS[id].icon, RELICS[id].name] if RELICS.has(id) else id
