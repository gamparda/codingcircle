extends RefCounted

const MAX_NICKNAME := 16
const MAX_CHAT := 160
const CHAT_HISTORY := 40
var rooms: Dictionary = {}
var peer_to_room: Dictionary = {}

static func safe_text(value: String, maximum: int) -> bool:
	if value.strip_edges().is_empty() or value.length() > maximum: return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127: return false
	return true

static func verifier(password: String, salt: String) -> String:
	return "" if password.is_empty() else (salt + "|" + password).sha256_text()

static func proof(secret: String, nonce: String, peer_id: int, code: String) -> String:
	var context := HMACContext.new()
	if context.start(HashingContext.HASH_SHA256,secret.to_utf8_buffer()) != OK: return ""
	context.update((nonce + ":" + str(peer_id) + ":" + code).to_utf8_buffer())
	return context.finish().hex_encode()

static func equal_secret(a: String, b: String) -> bool:
	if a.length() != b.length(): return false
	var difference := 0
	for index in a.length(): difference |= a.unicode_at(index) ^ b.unicode_at(index)
	return difference == 0

func create(peer_id: int, code: String, title: String, nickname: String, salt: String, secret: String, deck: Dictionary) -> bool:
	if peer_to_room.has(peer_id) or rooms.has(code): return false
	rooms[code] = {"code":code,"name":title,"owner":peer_id,"salt":salt,"secret":secret,"phase":"waiting","match_id":0,"members":{},"messages":[],"next_message":1}
	rooms[code].members[peer_id] = _member(nickname,"player",deck,true)
	peer_to_room[peer_id] = code
	return true

func _member(nickname: String, role: String, deck: Dictionary, ready: bool = false) -> Dictionary:
	return {"nickname":nickname,"role":role,"ready":ready,"returned":true,"deck":deck.duplicate(true),"connected":true,"reconnect_deadline":0,"reconnect_hash":""}

func players(room: Dictionary) -> Array:
	var result: Array = []
	for id in room.members:
		if room.members[id].role == "player": result.append(int(id))
	return result

func join(peer_id: int, code: String, nickname: String, role: String, deck: Dictionary) -> String:
	if peer_to_room.has(peer_id): return "이미 방에 참가 중입니다."
	if not rooms.has(code): return "종료된 방입니다."
	var room: Dictionary = rooms[code]
	if role == "player" and (room.phase != "waiting" or players(room).size() >= 2): return "참가할 자리가 없습니다. 관전으로 입장하세요."
	if role not in ["player","spectator"]: return "잘못된 참가 요청입니다."
	room.members[peer_id] = _member(nickname,role,deck)
	peer_to_room[peer_id] = code
	return ""

func room_for(peer_id: int) -> Dictionary:
	return rooms.get(peer_to_room.get(peer_id,""),{})

func listing() -> Array:
	var result: Array = []
	for room in rooms.values():
		result.append({"code":room.code,"name":room.name,"players":players(room).size(),"locked":not room.secret.is_empty(),"state":room.phase,"spectators":room.members.size()-players(room).size()})
	return result

func public_state(code: String) -> Dictionary:
	if not rooms.has(code): return {}
	var room: Dictionary = rooms[code]
	var members: Array = []
	for id in room.members:
		var member: Dictionary = room.members[id]
		members.append({"id":int(id),"nickname":member.nickname,"role":member.role,"ready":member.ready,"returned":member.returned,"deck":member.deck.duplicate(true),"connected":member.connected,"reconnect_remaining":maxf(0.0,(int(member.reconnect_deadline)-Time.get_ticks_msec())/1000.0)})
	return {"code":code,"name":room.name,"owner":room.owner,"phase":room.phase,"locked":not room.secret.is_empty(),"members":members,"messages":room.messages.duplicate(true)}

func set_ready(peer_id: int, ready: bool) -> bool:
	var room := room_for(peer_id)
	if room.is_empty() or room.phase != "waiting" or room.members[peer_id].role != "player": return false
	room.members[peer_id].ready = ready
	return true

func set_deck(peer_id: int, deck: Dictionary) -> bool:
	var room := room_for(peer_id)
	if room.is_empty() or room.phase != "waiting" or room.members[peer_id].role != "player": return false
	room.members[peer_id].deck = deck.duplicate(true)
	room.members[peer_id].ready = false
	return true

func can_start(peer_id: int) -> bool:
	var room := room_for(peer_id)
	if room.is_empty() or room.owner != peer_id or room.phase != "waiting": return false
	var ids := players(room)
	if ids.size() != 2: return false
	for id in ids:
		if not room.members[id].ready or not room.members[id].connected: return false
	return true

func start(peer_id: int, match_id: int) -> Array:
	if not can_start(peer_id): return []
	var room := room_for(peer_id)
	room.phase = "playing"; room.match_id = match_id
	for member in room.members.values(): member.returned = false
	return players(room)

func finish(code: String) -> void:
	if not rooms.has(code): return
	rooms[code].phase = "finished"
	for member in rooms[code].members.values(): member.ready = false

func return_from_battle(peer_id: int) -> bool:
	var room := room_for(peer_id)
	if room.is_empty() or room.phase != "finished": return false
	room.members[peer_id].returned = true
	for id in players(room):
		if not room.members[id].returned: return true
	room.phase = "waiting"
	for member in room.members.values(): member.returned = true
	return true

func append_chat(peer_id: int, text: String) -> Dictionary:
	var room := room_for(peer_id)
	if room.is_empty() or not safe_text(text,MAX_CHAT): return {}
	var message: Dictionary = {"id":room.next_message,"nickname":room.members[peer_id].nickname,"role":room.members[peer_id].role,"text":text.strip_edges()}
	room.next_message += 1
	room.messages.append(message)
	if room.messages.size() > CHAT_HISTORY: room.messages.pop_front()
	return message

# Credentials are private; public_state deliberately never copies them.
func issue_reconnect_token(peer_id: int) -> String:
	var room := room_for(peer_id)
	if room.is_empty(): return ""
	var bytes := Crypto.new().generate_random_bytes(32)
	if bytes.size() != 32: return ""
	var token := bytes.hex_encode()
	room.members[peer_id].reconnect_hash = token.sha256_text()
	return token

func suspend(peer_id: int, deadline: int) -> bool:
	var room := room_for(peer_id)
	if room.is_empty() or room.members[peer_id].reconnect_hash.is_empty(): return false
	room.members[peer_id].connected = false
	room.members[peer_id].reconnect_deadline = deadline
	return true

func resume(code: String, token: String, new_peer: int, now: int) -> int:
	if not rooms.has(code) or peer_to_room.has(new_peer): return 0
	var room: Dictionary = rooms[code]
	for old_peer in room.members.keys():
		var member: Dictionary = room.members[old_peer]
		if member.connected or int(member.reconnect_deadline) <= now: continue
		if member.reconnect_hash.is_empty() or not equal_secret(member.reconnect_hash,token.sha256_text()): continue
		member.reconnect_hash = "" # Consume before rekeying membership.
		member.connected = true; member.reconnect_deadline = 0
		var rebound := {}
		for id in room.members: rebound[new_peer if id==old_peer else id] = room.members[id]
		room.members = rebound
		peer_to_room.erase(old_peer); peer_to_room[new_peer] = code
		if int(room.owner) == int(old_peer): room.owner = new_peer
		return int(old_peer)
	return 0

func paused(code: String) -> bool:
	var room: Dictionary = rooms.get(code,{})
	if room.is_empty() or room.phase != "playing": return false
	for id in players(room):
		if not room.members[id].connected: return true
	return false

func leave(peer_id: int, preserve_result: bool = false) -> Dictionary:
	var room := room_for(peer_id)
	if room.is_empty(): return {}
	var code: String = room.code
	var before: Array = room.members.keys()
	var match_id: int = room.match_id
	var was_player: bool = room.members[peer_id].role == "player"
	room.members.erase(peer_id); peer_to_room.erase(peer_id)
	var remaining := players(room)
	if remaining.is_empty():
		for id in room.members: peer_to_room.erase(id)
		rooms.erase(code)
		return {"code":code,"affected":before,"closed":true,"match_id":match_id,"interrupted":was_player and not preserve_result}
	if room.owner == peer_id: room.owner = remaining[0]
	if was_player and not preserve_result:
		room.phase = "waiting"; room.match_id = 0
		for member in room.members.values(): member.ready = false; member.returned = true
	return {"code":code,"affected":before,"closed":false,"match_id":match_id,"interrupted":was_player and not preserve_result}
