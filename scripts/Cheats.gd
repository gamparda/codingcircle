extends RefCounted
## Cheat actions for super and hyper accounts, shared by solo battles (applied on the device) and online
## battles (the server checks the account's role, then applies them to its own battle). Toggles live in
## BattleModel.cheats and act every tick (BattleModel._apply_cheats); the rest happen once.

## Toggle id -> label, in panel order.
const TOGGLES := {
	"resources": "자원 무한",
	"cooldowns": "생산·주문 대기 없음",
	"castle": "내 성 무적",
	"immortal": "내 병력 무적",
	"one_hit": "내 병력 일격 필살",
	"haste": "내 병력 2배 빠르게",
	"freeze": "적 병력 얼리기",
	"no_cap": "마왕 등 1기 제한 없음",
}
## One-shot action id -> label, in panel order.
const ONE_SHOTS := {
	"fill": "자원 가득 채우기",
	"army": "내 덱 병력 3기씩 무료 소환",
	"heal": "내 병력 모두 회복",
	"repair": "내 성 수리",
	"wipe": "적 병력 전멸",
	"raze": "적 구조물 파괴",
	"siege": "적 성 체력 절반으로",
	"win": "즉시 승리",
	"lose": "즉시 패배",
}

static func valid(action: Variant) -> bool:
	return action is String and (TOGGLES.has(action) or ONE_SHOTS.has(action))

## Applies `action` for `side`; false when it does nothing (an unknown action, or a finished battle).
static func perform(model: BattleModel, side: int, action: String) -> bool:
	if not valid(action) or side < 0 or side > 1 or model.winner != -1:
		return false
	var on: Dictionary = model.cheats[side]
	var enemy := 1 - side
	if TOGGLES.has(action):
		if on.has(action):
			on.erase(action)
			_restore(model, side, action)
		else:
			on[action] = true
		return true
	match action:
		"fill":
			model.resources[side] = model.resource_capacity(side)
		"army":
			var saved := float(model.resources[side])
			for kind in model.unit_decks[side]:
				for i in 3:
					model.resources[side] = 100000.0
					model.spawn_cooldowns[side].erase(kind)
					model.spawn_unit(side, String(kind))
			model.resources[side] = saved
		"heal":
			for unit in model.units:
				if int(unit.side) == side and float(unit.hp) > 0.0:
					unit.hp = float(unit.max_hp)
		"repair":
			model.base_hp[side] = model.base_max_hp[side]
		"wipe":
			for unit in model.units:
				if int(unit.side) == enemy:
					unit.hp = 0.0
					model.revive_used[unit.id] = true # zombies stay down
		"raze":
			for structure in model.structures:
				if int(structure.side) == enemy:
					structure.hp = 0.0
		"siege":
			if bool(model.invulnerable_bases[enemy]):
				return false
			model.base_hp[enemy] = minf(float(model.base_hp[enemy]), float(model.base_max_hp[enemy]) * 0.5)
		"win":
			if bool(model.invulnerable_bases[enemy]):
				return false
			model.base_hp[enemy] = 0.0
		"lose":
			on.erase("castle")
			model.base_hp[side] = 0.0
	return true

## A toggle switched off gives units back what it changed.
static func _restore(model: BattleModel, side: int, action: String) -> void:
	var stat: String = {"one_hit": "damage", "haste": "speed"}.get(action, "")
	if stat.is_empty():
		return
	for unit in model.units:
		var saved: Dictionary = model.cheat_saved.get(unit.id, {})
		if int(unit.side) == side and saved.has(stat):
			unit[stat] = saved[stat]
			saved.erase(stat)
			if saved.is_empty():
				model.cheat_saved.erase(unit.id)
