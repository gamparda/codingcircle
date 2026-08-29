class_name MatchRegistry
extends RefCounted

var waiting_peer := 0
var next_match_id := 1
var peer_to_match: Dictionary = {}
var peer_to_side: Dictionary = {}
var matches: Dictionary = {}

func add_player(peer_id: int) -> Dictionary:
	if peer_id <= 0 or peer_to_match.has(peer_id) or waiting_peer == peer_id:
		return {}
	if waiting_peer == 0:
		waiting_peer = peer_id
		return {}
	var first := waiting_peer
	waiting_peer = 0
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
	if waiting_peer == peer_id:
		waiting_peer = 0
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
