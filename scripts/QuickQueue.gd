extends RefCounted
## FIFO matchmaking queue for the one-button "quick match". Pure bookkeeping (no
## networking) so pairing rules are unit-testable; NetworkController turns a returned
## pair into a ready-to-start room.

const MAX_WAIT_MSEC := 120000
const MAX_QUEUED := 512

var entries: Array = [] # {"peer": int, "nickname": String, "since": int}

func has(peer_id: int) -> bool:
	for entry in entries:
		if int(entry.peer) == peer_id:
			return true
	return false

func size() -> int:
	return entries.size()

func enqueue(peer_id: int, nickname: String, now_msec: int) -> bool:
	if has(peer_id) or entries.size() >= MAX_QUEUED:
		return false
	entries.append({"peer": peer_id, "nickname": nickname, "since": now_msec})
	return true

func cancel(peer_id: int) -> bool:
	for index in entries.size():
		if int(entries[index].peer) == peer_id:
			entries.remove_at(index)
			return true
	return false

## Longest-waiting two eligible players, or [] when fewer than two are eligible.
## Entries failing `is_eligible` (disconnected, already in a room) are dropped.
func take_pair(is_eligible: Callable) -> Array:
	entries = entries.filter(func(entry): return bool(is_eligible.call(int(entry.peer))))
	if entries.size() < 2:
		return []
	return [entries.pop_front(), entries.pop_front()]

## Removes and returns the peer ids that waited longer than MAX_WAIT_MSEC.
func expire(now_msec: int) -> Array:
	var expired: Array = []
	var keep: Array = []
	for entry in entries:
		if now_msec - int(entry.since) >= MAX_WAIT_MSEC:
			expired.append(int(entry.peer))
		else:
			keep.append(entry)
	entries = keep
	return expired
