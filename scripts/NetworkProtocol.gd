extends RefCounted
## Wire-protocol limits and the pure validators that gate every network payload.
## NetworkController keeps same-name aliases/delegators so callers and tests are unchanged.

const SessionStore = preload("res://scripts/RoomSessions.gd")

const RECONNECT_GRACE := 20.0
const MAX_SNAPSHOT_UNITS := 256
const MAX_SNAPSHOT_STRUCTURES := 16
const TRANSPORT_MAX_PEERS := 4095 # ENet protocol ceiling, not an application admission quota.
const VALID_UNIT_KINDS := ["shield", "swordsman", "archer", "healer", "berserker", "warlock", "necromancer", "skeleton"]
const VALID_STRUCTURE_KINDS := ["wall", "swamp", "turret", "generator"]
const ROOM_LIST_PAGE_SIZE := 12
const ROOM_NAME_LENGTH := 24
const ROOM_CODE_LENGTH := 6
const ROOM_CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

static func is_safe_command_text(value: String) -> bool:
	return not value.is_empty() and value.length() <= 32 and value == value.to_lower() and value.is_valid_identifier()

static func is_valid_room_code(value: String) -> bool:
	if value.length() != ROOM_CODE_LENGTH:
		return false
	for character in value:
		if not ROOM_CODE_ALPHABET.contains(character):
			return false
	return true

static func is_safe_position(value: float) -> bool:
	return is_finite(value)

static func is_valid_match_side(side: int) -> bool:
	return side == 0 or side == 1

static func _is_finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _has_exact_keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size():
		return false
	for key in expected:
		if not value.has(key):
			return false
	return true

static func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return _is_finite_number(value) and float(value) >= minimum and float(value) <= maximum

static func is_valid_snapshot(data: Dictionary) -> bool:
	if not _has_required_optional_keys(data, ["resources", "base_hp", "units", "structures", "winner", "elapsed"], ["curses", "base_max_hp", "spawn_cooldowns", "battle_report", "network"]):
		return false
	if data.has("network") and not valid_recovery_state(data.network): return false
	if data.has("battle_report") and (int(data.get("winner",-1)) == -1 or not preload("res://scripts/BattleReport.gd").valid(data.battle_report)): return false
	if data.has("spawn_cooldowns"):
		if not data.spawn_cooldowns is Array or data.spawn_cooldowns.size()!=2: return false
		for side in data.spawn_cooldowns:
			if not side is Dictionary or side.size()>BattleModel.UNIT_STATS.size(): return false
			for kind in side:
				if not BattleModel.UNIT_STATS.has(kind) or not _number_in_range(side[kind],0.0,0.35): return false
	var resources = data.resources
	var base_hp = data.base_hp
	var units = data.units
	var structures = data.structures
	if not resources is Array or resources.size() != 2:
		return false
	if not base_hp is Array or base_hp.size() != 2:
		return false
	for value in resources:
		if not _number_in_range(value, 0.0, BattleModel.MAX_RESOURCE):
			return false
	for value in base_hp:
		if not _number_in_range(value, 0.0, 500.0):
			return false
	var maxima = data.get("base_max_hp", [BattleModel.BASE_MAX_HP, BattleModel.BASE_MAX_HP])
	if not maxima is Array or maxima.size() != 2:
		return false
	for index in 2:
		if not _number_in_range(maxima[index], 1.0, BattleModel.BASE_MAX_HP) or float(base_hp[index]) > float(maxima[index]):
			return false
	if not units is Array or units.size() > MAX_SNAPSHOT_UNITS:
		return false
	if not structures is Array or structures.size() > MAX_SNAPSHOT_STRUCTURES:
		return false
	var unit_ids := {}
	for unit in units:
		if not unit is Dictionary or not _has_required_optional_keys(unit, ["id", "side", "kind", "x", "hp", "max_hp", "damage", "heal", "interval", "cooldown", "speed", "range"], ["support_stacks", "summon_remaining"]):
			return false
		var unit_id = unit.id
		var unit_side = unit.side
		if not unit_id is int or int(unit_id) <= 0 or unit_ids.has(unit_id):
			return false
		unit_ids[unit_id] = true
		if not unit_side is int or not is_valid_match_side(unit_side) or not VALID_UNIT_KINDS.has(String(unit.kind)):
			return false
		if not _number_in_range(unit.x, -256.0, 1536.0) or not _number_in_range(unit.max_hp, 0.01, 10000.0):
			return false
		if not _number_in_range(unit.hp, 0.0, float(unit.max_hp)):
			return false
		for key in ["damage", "heal", "interval", "cooldown", "speed", "range"]:
			if not _number_in_range(unit[key], 0.0, 10000.0):
				return false
		if unit.has("support_stacks") and (not unit.support_stacks is int or int(unit.support_stacks) < 0 or int(unit.support_stacks) > BattleModel.SUPPORT_MAX_STACKS):
			return false
		if unit.has("summon_remaining") and (unit.kind != "necromancer" or not _number_in_range(unit.summon_remaining, 0.0, BattleModel.SUMMON_INTERVAL)):
			return false
	var structure_ids := {}
	for structure in structures:
		if not structure is Dictionary or not _has_required_optional_keys(structure, ["id", "side", "kind", "x", "hp", "max_hp"], ["expires_at"]):
			return false
		var structure_id = structure.id
		var structure_side = structure.side
		if not structure_id is int or int(structure_id) <= 0 or structure_ids.has(structure_id):
			return false
		structure_ids[structure_id] = true
		if not structure_side is int or not is_valid_match_side(structure_side) or not VALID_STRUCTURE_KINDS.has(String(structure.kind)):
			return false
		if not _number_in_range(structure.x, 0.0, BattleModel.WORLD_WIDTH) or not _number_in_range(structure.max_hp, 0.01, 10000.0):
			return false
		if not _number_in_range(structure.hp, 0.0, float(structure.max_hp)):
			return false
		if structure.has("expires_at") and (structure.kind != "swamp" or not _number_in_range(structure.expires_at, 0.0, 1000000000.0)):
			return false
	var winner = data.winner
	var curses = data.get("curses", [])
	if not curses is Array or curses.size() > MAX_SNAPSHOT_UNITS:
		return false
	var sources := {}
	for curse in curses:
		if not curse is Dictionary or not _has_exact_keys(curse, ["source_id", "side", "x", "expires_at"]):
			return false
		if not curse.source_id is int or int(curse.source_id) <= 0 or sources.has(curse.source_id) or not curse.side is int or not is_valid_match_side(int(curse.side)):
			return false
		if not _number_in_range(curse.x, BattleModel.FIELD_LEFT, BattleModel.FIELD_RIGHT) or not _number_in_range(curse.expires_at, 0.0, 1000000000.0):
			return false
		sources[curse.source_id] = true
	if not winner is int or int(winner) < -1 or int(winner) > 2:
		return false
	return _is_finite_number(data.elapsed) and float(data.elapsed) >= 0.0

static func _has_required_optional_keys(value: Dictionary, required: Array, optional: Array) -> bool:
	for key in required:
		if not value.has(key):
			return false
	for key in value:
		if not required.has(key) and not optional.has(key):
			return false
	return true

static func is_valid_room_name(title: String) -> bool:
	var value := title.strip_edges()
	if value.is_empty() or value.length() > ROOM_NAME_LENGTH: return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127: return false
	return true

static func is_valid_room_listing(data: Dictionary) -> bool:
	if not _has_exact_keys(data,["rooms","page","total"]) or not data.rooms is Array: return false
	if not _number_in_range(data.page,0,TRANSPORT_MAX_PEERS) or not _number_in_range(data.total,0,TRANSPORT_MAX_PEERS): return false
	if float(data.page) != floor(float(data.page)) or float(data.total) != floor(float(data.total)) or data.rooms.size() > ROOM_LIST_PAGE_SIZE: return false
	var last_page := maxi(0,(int(data.total)-1)/ROOM_LIST_PAGE_SIZE)
	if int(data.page)>last_page or data.rooms.size()!=mini(ROOM_LIST_PAGE_SIZE,maxi(0,int(data.total)-int(data.page)*ROOM_LIST_PAGE_SIZE)): return false
	var codes: Dictionary = {}
	for item in data.rooms:
		if not item is Dictionary or not _has_required_optional_keys(item,["code","name","players"],["locked","state","spectators"]): return false
		if not item.code is String or not is_valid_room_code(item.code) or codes.has(item.code): return false
		if not item.name is String or not is_valid_room_name(item.name) or not _number_in_range(item.players,1,2) or float(item.players)!=floor(float(item.players)): return false
		if not item.has("state") and int(item.players)!=1: return false
		if item.has("locked") and not item.locked is bool: return false
		if item.has("state") and item.state not in ["waiting","playing","finished"]: return false
		if item.has("spectators") and (not _number_in_range(item.spectators,0,TRANSPORT_MAX_PEERS) or float(item.spectators)!=floor(float(item.spectators))): return false
		codes[item.code] = true
	return true

static func _hex_string(value: String, length: int) -> bool:
	if value.length() != length: return false
	for char_value in value:
		if not char_value in "0123456789abcdef": return false
	return true

static func valid_session_state(data: Dictionary) -> bool:
	if not _has_exact_keys(data,["code","name","owner","phase","locked","members","messages"]): return false
	if not data.code is String or not is_valid_room_code(data.code) or not data.name is String or not is_valid_room_name(data.name): return false
	if not data.locked is bool or data.phase not in ["waiting","playing","finished"] or not data.members is Array or not data.messages is Array: return false
	if data.members.size()<1 or data.members.size()>TRANSPORT_MAX_PEERS or data.messages.size()>SessionStore.CHAT_HISTORY: return false
	var players := 0; var ids: Dictionary = {}
	for member in data.members:
		if not member is Dictionary or not _has_required_optional_keys(member,["id","nickname","role","ready","returned","deck"],["connected","reconnect_remaining"]): return false
		if not _number_in_range(member.id,1,2147483647) or float(member.id)!=floor(float(member.id)) or ids.has(int(member.id)): return false
		if not member.nickname is String or not SessionStore.safe_text(member.nickname,SessionStore.MAX_NICKNAME) or member.role not in ["player","spectator"] or not member.ready is bool or not member.returned is bool: return false
		if not member.deck is Dictionary or not _has_exact_keys(member.deck,["units","structures"]) or not member.deck.units is Array or not member.deck.structures is Array or not validate_deck_payload(member.deck.units,member.deck.structures): return false
		if member.has("connected") and not member.connected is bool: return false
		if member.has("reconnect_remaining") and not _number_in_range(member.reconnect_remaining,0.0,RECONNECT_GRACE): return false
		ids[int(member.id)] = true
		if member.role == "player": players += 1
	if players<1 or players>2 or not _number_in_range(data.owner,1,2147483647) or float(data.owner)!=floor(float(data.owner)) or not ids.has(int(data.owner)): return false
	for message in data.messages:
		if not valid_chat_message(message): return false
	return true

static func valid_chat_message(message: Variant) -> bool:
	return message is Dictionary and _has_exact_keys(message,["id","nickname","role","text"]) and _number_in_range(message.id,1,1e9) and message.nickname is String and SessionStore.safe_text(message.nickname,SessionStore.MAX_NICKNAME) and message.role in ["player","spectator"] and message.text is String and SessionStore.safe_text(message.text,SessionStore.MAX_CHAT)

static func valid_recovery_state(data: Variant) -> bool:
	return data is Dictionary and _has_exact_keys(data,["paused","reconnect_remaining"]) and data.paused is bool and _number_in_range(data.reconnect_remaining,0.0,RECONNECT_GRACE)

static func validate_deck_payload(unit_deck: Array, structure_deck: Array) -> bool:
	return BattleModel._valid_deck(unit_deck, BattleModel.UNIT_STATS) and BattleModel._valid_deck(structure_deck, BattleModel.STRUCTURE_STATS)
