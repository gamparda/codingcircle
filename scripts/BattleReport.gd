extends RefCounted

const KINDS := ["shield","swordsman","archer","healer","berserker","warlock","necromancer","turret"]
static func empty_side() -> Dictionary:
	var rows: Dictionary = {}
	for kind in KINDS: rows[kind] = {"purchased":0,"summoned":0,"kills":0,"damage":0.0}
	return {"resources_spent":0.0,"structures_built":0,"damage":0.0,"kills":0,"units":rows}

static func credit_kind(kind: String) -> String:
	return "necromancer" if kind == "skeleton" else kind

static func valid_number(value: Variant, integral: bool = false) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=0.0 and float(value)<=1e12 and (not integral or float(value)==floor(float(value)))

static func valid(data: Variant) -> bool:
	if not data is Array or data.size()!=2: return false
	for side in data:
		if not side is Dictionary or side.size()!=5 or not side.has_all(["resources_spent","structures_built","damage","kills","units"]): return false
		if not valid_number(side.resources_spent) or not valid_number(side.damage) or not valid_number(side.structures_built,true) or not valid_number(side.kills,true): return false
		if not side.units is Dictionary or side.units.size()!=KINDS.size() or not side.units.has_all(KINDS): return false
		var damage := 0.0; var kills := 0
		for row in side.units.values():
			if not row is Dictionary or row.size()!=4 or not row.has_all(["purchased","summoned","kills","damage"]): return false
			if not valid_number(row.purchased,true) or not valid_number(row.summoned,true) or not valid_number(row.kills,true) or not valid_number(row.damage): return false
			damage+=float(row.damage); kills+=int(row.kills)
		if not is_equal_approx(damage,float(side.damage)) or kills!=int(side.kills): return false
	return true

static func lines(side: Dictionary) -> PackedStringArray:
	var output := PackedStringArray()
	for kind in KINDS:
		var row: Dictionary = side.units[kind]
		if int(row.purchased)==0 and int(row.summoned)==0 and int(row.kills)==0 and float(row.damage)<=0.0: continue
		var name := "포탑" if kind=="turret" else String(BattleModel.UNIT_NAMES[kind])
		output.append("%s  ·  생산 %d  ·  처치 %d  ·  피해 %d" % [name,int(row.purchased),int(row.kills),roundi(float(row.damage))])
	if output.is_empty(): output.append("생산한 병력이 없습니다.")
	return output
