extends RefCounted
## One key per battle card: the deck's units, then its tactic cards (BattleModel.DECK_SIZE each).
const DEFAULTS := [KEY_1,KEY_2,KEY_3,KEY_4,KEY_Q,KEY_W,KEY_E,KEY_R]
const LABELS := ["병력 1","병력 2","병력 3","병력 4","전술 1","전술 2","전술 3","전술 4"]
## Keys saved when decks had three cards of each kind: [unit 1-3, tactic 1-3].
const OLD_SIZE := 6
static func allowed(code: int) -> bool:
	return (code>=KEY_A and code<=KEY_Z) or (code>=KEY_0 and code<=KEY_9) or (code>=KEY_F1 and code<=KEY_F10) or code in [KEY_F12,KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT,KEY_HOME,KEY_END,KEY_PAGEUP,KEY_PAGEDOWN,KEY_INSERT,KEY_DELETE]
static func sanitize(value: Variant) -> Array:
	if value is Array and value.size()==OLD_SIZE:
		# Keep the player's six keys; the fourth unit and tactic get 4 and R unless those are taken.
		var grown: Array = value.slice(0,3) + [KEY_4] + value.slice(3,6) + [KEY_R]
		value = grown if value.count(KEY_4)==0 and value.count(KEY_R)==0 else DEFAULTS.duplicate()
	if not value is Array or value.size()!=DEFAULTS.size(): return DEFAULTS.duplicate()
	var result: Array = []
	for item in value:
		if not (item is int or item is float) or not is_finite(float(item)) or float(item)!=floor(float(item)) or float(item)<0 or float(item)>2147483647: return DEFAULTS.duplicate()
		var code := int(item)
		if not allowed(code) or result.has(code): return DEFAULTS.duplicate()
		result.append(code)
	return result
static func key_name(code: int) -> String:
	return {KEY_UP:"↑",KEY_DOWN:"↓",KEY_LEFT:"←",KEY_RIGHT:"→",KEY_PAGEUP:"PgUp",KEY_PAGEDOWN:"PgDn"}.get(code,OS.get_keycode_string(code))
static func assign(keys: Array, index: int, code: int) -> String:
	if index<0 or index>=DEFAULTS.size() or not allowed(code): return "문자·숫자·방향키·기능 키를 선택하세요. Esc·F11은 제외됩니다."
	var other := keys.find(code)
	if other>=0 and other!=index: return "%s에서 사용 중인 키입니다."%LABELS[other]
	keys[index]=code
	return ""
