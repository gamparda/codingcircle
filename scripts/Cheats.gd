extends RefCounted
## Cheat actions for super and hyper accounts, shared by solo battles (applied on the device) and online
## battles (the server checks the account's role, then applies them to its own battle). Toggles live in
## BattleModel.cheats and act every tick; the rest happen once.

const TOGGLES := ["resources", "cooldowns", "castle"]
const ACTIONS := ["resources", "cooldowns", "castle", "fill", "win", "lose"]

static func valid(action: Variant) -> bool:
	return action is String and action in ACTIONS

## Applies `action` for `side`; false when it does nothing (an unknown action, or a finished battle).
static func perform(model: BattleModel, side: int, action: String) -> bool:
	if not valid(action) or side < 0 or side > 1 or model.winner != -1:
		return false
	var on: Dictionary = model.cheats[side]
	match action:
		"resources", "cooldowns", "castle":
			if on.has(action): on.erase(action)
			else: on[action] = true
		"fill":
			model.resources[side] = model.resource_capacity(side)
		"win":
			if bool(model.invulnerable_bases[1 - side]):
				return false
			model.base_hp[1 - side] = 0.0
		"lose":
			on.erase("castle")
			model.base_hp[side] = 0.0
	return true
