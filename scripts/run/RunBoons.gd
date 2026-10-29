extends RefCounted
const Localization = preload("res://scripts/Localization.gd")
## Relics (expedition) and boons (endless defense): permanent run bonuses that become BattleModel modifiers.
## Each entry's "mods" uses BattleModel.modifier() keys; combine() merges any number of them (multipliers
## multiply, additions add), so taking the same boon twice in endless defense stacks.

## Keys that add; every other key multiplies.
const ADDITIVE := ["income", "capacity", "start", "skeleton_cap", "range:ranged", "first_strike"]

const RELICS := {
	"steel_plate": {"name": "강철 갑옷", "icon": "🛡", "rarity": "common", "needs": "melee", "mods": {"hp:melee": 1.15}},
	"eagle_eye": {"name": "독수리의 눈", "icon": "👁", "rarity": "common", "needs": "ranged", "mods": {"range:ranged": 40.0}},
	"barbed_tips": {"name": "가시 화살촉", "icon": "🏹", "rarity": "common", "needs": "ranged", "mods": {"damage:ranged": 1.15}},
	"granary": {"name": "군량 창고", "icon": "🌾", "rarity": "common", "mods": {"income": 1.0}},
	"vault": {"name": "넓은 금고", "icon": "📦", "rarity": "common", "mods": {"capacity": 60.0}},
	"war_chest": {"name": "출정 자금", "icon": "💰", "rarity": "common", "mods": {"start": 60.0}},
	"recruiter": {"name": "징병관", "icon": "📜", "rarity": "rare", "mods": {"cost:units": 0.9}},
	"grimoire": {"name": "마도서", "icon": "📖", "rarity": "rare", "needs": "spell", "mods": {"spell_cooldown": 0.8}},
	"masons": {"name": "석공 길드", "icon": "🧱", "rarity": "common", "needs": "structure", "mods": {"structure_hp": 1.3}},
	"anchor": {"name": "무거운 장화", "icon": "🥾", "rarity": "common", "mods": {"knockback": 0.5}},
	"bone_urn": {"name": "뼈 항아리", "icon": "⚱", "rarity": "rare", "needs": "necromancer", "mods": {"skeleton_cap": 1.0}},
	"death_tome": {"name": "망자의 서", "icon": "💀", "rarity": "rare", "needs": "necromancer", "mods": {"skill_cooldown:necromancer": 0.75}},
	"ambush": {"name": "기습", "icon": "⚡", "rarity": "rare", "mods": {"first_strike": 1.0}},
	"blood_oath": {"name": "피의 맹세", "icon": "🩸", "rarity": "common", "needs": "berserker", "mods": {"damage:berserker": 1.3}},
	"war_drum": {"name": "전쟁 북", "icon": "🥁", "rarity": "boss", "mods": {"damage:all": 1.1}},
	"aegis": {"name": "수호의 부적", "icon": "🔰", "rarity": "boss", "mods": {"hp:all": 1.1}},
}

## Wording of each modifier key; the number comes from the relic's data.
const KEY_TEXT := {
	"hp:all": "모든 유닛 체력", "damage:all": "모든 유닛 공격", "hp:melee": "근접 유닛 체력", "damage:ranged": "원거리 유닛 공격",
	"range:ranged": "원거리 유닛 사거리", "income": "자원 수입", "capacity": "자원 보유 한도", "start": "전투 시작 자원",
	"cost:units": "유닛 비용", "spell_cooldown": "전술 마법 재사용 대기", "structure_hp": "구조물 체력",
	"knockback": "아군이 밀려나는 거리", "skeleton_cap": "네크로맨서 해골 한도", "skill_cooldown:necromancer": "네크로맨서 소환 대기",
}

## One line for relic `id`, built from its modifiers.
static func describe(id: String) -> String:
	if not RELICS.has(id):
		return ""
	var parts := PackedStringArray()
	var mods: Dictionary = RELICS[id].mods
	for key in mods:
		var value := float(mods[key])
		if key == "first_strike":
			parts.append(Localization.text("모든 유닛의 첫 공격 피해 두 배"))
			continue
		var subject := String(KEY_TEXT.get(key, ""))
		if subject.is_empty():
			var kind := String(key).get_slice(":", 1)
			subject = "%s %s" % [BattleModel.UNIT_NAMES.get(kind, kind), "체력" if String(key).begins_with("hp:") else "공격"]
		var amount := ""
		if key in ADDITIVE:
			amount = ("%+d/초" if key == "income" else "%+d") % roundi(value)
		else:
			amount = "%+d%%" % roundi((value - 1.0) * 100.0)
		parts.append("%s %s" % [Localization.text(subject), amount])
	return " · ".join(parts)

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

## Whether relic `id` does anything for a deck: "needs" names a unit kind, a unit scope ("melee", "ranged"),
## or a tactic type ("structure", "spell").
static func relevant(id: String, units: Array, structures: Array) -> bool:
	var need := String(RELICS[id].get("needs", ""))
	match need:
		"":
			return true
		"melee", "ranged":
			return units.any(func(kind): return BattleModel.unit_scope(String(kind)) == need)
		"structure":
			return structures.any(func(kind): return not BattleModel.is_spell(String(kind)))
		"spell":
			return structures.any(func(kind): return BattleModel.is_spell(String(kind)))
	return units.has(need)

## `count` different relic ids drawn with `rng` from those not in `owned`; boss relics only when `allow_boss`.
## With a deck (`units`), only relics that help it.
static func draw(rng: RandomNumberGenerator, count: int, owned: Array = [], allow_boss: bool = false, units: Array = [], structures: Array = []) -> Array:
	var pool: Array = []
	for id in RELICS:
		if not owned.has(id) and (allow_boss or RELICS[id].rarity != "boss") and (units.is_empty() or relevant(id, units, structures)):
			pool.append(id)
	pool.sort()
	var picked: Array = []
	while picked.size() < count and not pool.is_empty():
		picked.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	return picked

static func label(id: String) -> String:
	return "%s %s" % [RELICS[id].icon, RELICS[id].name] if RELICS.has(id) else id
