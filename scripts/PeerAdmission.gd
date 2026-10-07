extends RefCounted
## Per-peer request throttling and per-address connection accounting for the dedicated server.

const MAX_REQUESTS_PER_SECOND := 24

var request_windows: Dictionary = {}
var peer_addresses: Dictionary = {}
var address_connection_counts: Dictionary = {}

func can_process_request(peer_id: int, now_msec: int = -1) -> bool:
	if peer_id <= 0:
		return false
	var now := Time.get_ticks_msec() if now_msec < 0 else now_msec
	var window: Dictionary = request_windows.get(peer_id, {"started": now, "count": 0})
	if now - int(window.started) >= 1000:
		window = {"started": now, "count": 0}
	if int(window.count) >= MAX_REQUESTS_PER_SECOND:
		request_windows[peer_id] = window
		return false
	window.count = int(window.count) + 1
	request_windows[peer_id] = window
	return true

func register_peer_address(peer_id: int, address: String) -> bool:
	if peer_id <= 0 or address.is_empty() or peer_addresses.has(peer_id):
		return false
	var count := int(address_connection_counts.get(address, 0))
	peer_addresses[peer_id] = address
	address_connection_counts[address] = count + 1
	return true

func release_peer_address(peer_id: int) -> void:
	if not peer_addresses.has(peer_id):
		return
	var address := String(peer_addresses[peer_id])
	peer_addresses.erase(peer_id)
	var count := int(address_connection_counts.get(address, 0)) - 1
	if count <= 0:
		address_connection_counts.erase(address)
	else:
		address_connection_counts[address] = count

func forget_requests(peer_id: int) -> void:
	request_windows.erase(peer_id)
