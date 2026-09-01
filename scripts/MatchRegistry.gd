class_name MatchRegistry
extends RefCounted

var next_match_id := 1
var peer_to_match: Dictionary = {}
var peer_to_side: Dictionary = {}
var matches: Dictionary = {}
var rooms: Dictionary = {}
var peer_to_room: Dictionary = {}

func create_room(peer_id: int, code: String) -> bool:
	if peer_id <= 0 or code.is_empty() or rooms.has(code) or peer_to_match.has(peer_id) or peer_to_room.has(peer_id):
		return false
	rooms[code] = peer_id
	peer_to_room[peer_id] = code
	return true

func join_room(peer_id: int, code: String) -> Dictionary:
	if peer_id <= 0 or not rooms.has(code) or peer_to_match.has(peer_id) or peer_to_room.has(peer_id):
		return {}
	var first := int(rooms[code])
	if first == peer_id:
		return {}
	rooms.erase(code)
	peer_to_room.erase(first)
	var match_id := next_match_id
	next_match_id += 1
	matches[match_id] = [first, peer_id]
	peer_to_match[first] = match_id
	peer_to_match[peer_id] = match_id
	peer_to_side[first] = 0
	peer_to_side[peer_id] = 1
	return {first: 0, peer_id: 1}

func has_match(peer_id: int) -> bool:
	return peer_to_match.has(peer_id)

func get_match_id(peer_id: int) -> int:
	return int(peer_to_match.get(peer_id, 0))

func get_side(peer_id: int) -> int:
	return int(peer_to_side.get(peer_id, -1))

func get_players_for_peer(peer_id: int) -> Array:
	var match_id := get_match_id(peer_id)
	return matches.get(match_id, []).duplicate()

func remove_player(peer_id: int) -> Array:
	if peer_to_room.has(peer_id):
		rooms.erase(String(peer_to_room[peer_id]))
		peer_to_room.erase(peer_id)
		return [peer_id]
	if not peer_to_match.has(peer_id):
		return []
	var match_id := get_match_id(peer_id)
	var players: Array = matches.get(match_id, []).duplicate()
	for player in players:
		peer_to_match.erase(player)
		peer_to_side.erase(player)
	matches.erase(match_id)
	return players
