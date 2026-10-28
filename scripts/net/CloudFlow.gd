extends RefCounted
## Cloud saves over the game connection, for the account bound to the connection (AccountFlow). The client
## loads the stored progress and its revision, and stores with the revision it last saw (CloudSaves).

const STORE_INTERVAL_MSEC := 5000
const MAX_CHARS := 512 * 1024

static func request_load(main) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var id := String(main.peer_accounts.get(sender, ""))
	if id.is_empty():
		main.receive_cloud_save.rpc_id(sender, -1, ""); return
	var stored: Dictionary = main.cloud.read(id)
	main.receive_cloud_save.rpc_id(sender, int(stored.revision), String(stored.data))

static func request_store(main, expected: int, text: String) -> void:
	if not main.server_mode: return
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.can_process_request(sender): return
	var id := String(main.peer_accounts.get(sender, ""))
	if id.is_empty():
		main.receive_cloud_stored.rpc_id(sender, false, 0, "not_signed_in"); return
	var last := int(main.cloud_store_times.get(sender, -STORE_INTERVAL_MSEC))
	if Time.get_ticks_msec() - last < STORE_INTERVAL_MSEC:
		main.receive_cloud_stored.rpc_id(sender, false, expected, "busy"); return
	main.cloud_store_times[sender] = Time.get_ticks_msec()
	var result: Dictionary = main.cloud.write(id, expected, text, int(Time.get_unix_time_from_system()))
	main.receive_cloud_stored.rpc_id(sender, bool(result.ok), int(result.revision), String(result.error))

static func valid_load(revision: Variant, text: Variant) -> bool:
	return revision is int and int(revision) >= -1 and text is String and String(text).length() <= MAX_CHARS

static func valid_stored(ok: Variant, revision: Variant, error: Variant) -> bool:
	return ok is bool and revision is int and int(revision) >= 0 and error is String and String(error).length() <= 32
