extends RefCounted
## Accounts over the game connection. Google sign-in opens (or, with a nickname, creates) an account;
## afterwards the client comes back with a session token. Clients only send these credentials over a
## verified connection (NetworkController.client_transport_verified). The server cannot see that, so
## it trusts nothing but Google's token signatures and its own session hashes.

const NONCE_SECONDS := 300
const SIGN_UP_SECONDS := 300
const JWKS_REFRESH_SECONDS := 3600.0
const JWKS_RETRY_SECONDS := 60.0
const MAX_PENDING_LOGINS := 64
const RESULT_KEYS := ["action", "error", "session", "nickname"]
const ACTIONS := ["login", "create", "resume", "rename", "delete", "logout"]

static func now() -> int:
	return int(Time.get_unix_time_from_system())

# ---------- server ----------

static func configure(main, directory: String, fetch_keys: bool = true) -> void:
	main.accounts.configure(directory)
	if fetch_keys and not is_instance_valid(main.jwks_http):
		main.jwks_http = HTTPRequest.new()
		main.jwks_http.timeout = 20.0
		main.add_child(main.jwks_http)
		main.jwks_http.request_completed.connect(func(result, code, _headers, body): _on_keys(main, result, code, body))
		refresh_keys(main, true)

static func advance(main, delta: float) -> void:
	main.jwks_elapsed += delta
	if main.jwks_elapsed >= JWKS_REFRESH_SECONDS:
		refresh_keys(main, true)
	var current := now()
	for peer in main.account_nonces.keys():
		if int(main.account_nonces[peer].expires) < current: main.account_nonces.erase(peer)
	for peer in main.verified_subjects.keys():
		if int(main.verified_subjects[peer].expires) < current: main.verified_subjects.erase(peer)

## `force` asks again even if the keys are fresh (an unknown key ID), but never more than once a minute.
static func refresh_keys(main, force: bool) -> void:
	if not is_instance_valid(main.jwks_http) or main.jwks_http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if main.jwks_elapsed < (JWKS_RETRY_SECONDS if force else JWKS_REFRESH_SECONDS) and not main.google.keys.is_empty():
		return
	main.jwks_elapsed = 0.0
	if main.jwks_http.request(main.google.JWKS_URL) != OK:
		printerr("ACCOUNT_KEYS_FETCH_FAILED")

static func _on_keys(main, result: int, code: int, body: PackedByteArray) -> void:
	var loaded := 0
	if result == HTTPRequest.RESULT_SUCCESS and code == 200:
		loaded = main.google.load_jwks(JSON.parse_string(body.get_string_from_utf8()))
	if loaded == 0:
		printerr("ACCOUNT_KEYS_FETCH_FAILED result=%d code=%d" % [result, code])
	var waiting: Array = main.pending_logins
	main.pending_logins = []
	for login in waiting:
		if main._peer_is_connected(int(login.peer)):
			_finish_login(main, int(login.peer), main.google.verify(String(login.token), String(login.nonce)))

static func forget_peer(main, peer: int) -> void:
	main.account_nonces.erase(peer)
	main.verified_subjects.erase(peer)
	main.peer_accounts.erase(peer)
	main.pending_logins = main.pending_logins.filter(func(login): return int(login.peer) != peer)

static func request_nonce(main) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var nonce := Crypto.new().generate_random_bytes(16).hex_encode()
	main.account_nonces[sender] = {"nonce": nonce, "expires": now() + NONCE_SECONDS}
	main.receive_account_nonce.rpc_id(sender, nonce)

static func request_login(main, token: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var issued = main.account_nonces.get(sender)
	main.account_nonces.erase(sender) # one use, even when the token fails
	if issued == null or int(issued.expires) < now():
		_answer(main, sender, "login", "no_nonce"); return
	var check: Dictionary = main.google.verify(token, String(issued.nonce))
	if not check.ok and check.error == "unknown_key" and main.pending_logins.size() < MAX_PENDING_LOGINS and is_instance_valid(main.jwks_http):
		# Google rotated its keys: finish this login once the new keys arrive.
		main.pending_logins.append({"peer": sender, "token": token, "nonce": String(issued.nonce)})
		refresh_keys(main, true)
		return
	_finish_login(main, sender, check)

static func _finish_login(main, peer: int, check: Dictionary) -> void:
	if not check.ok:
		_answer(main, peer, "login", "invalid_token"); return
	var id: String = main.accounts.find_by_subject(String(check.subject))
	if id.is_empty():
		main.verified_subjects[peer] = {"subject": String(check.subject), "expires": now() + SIGN_UP_SECONDS}
		_answer(main, peer, "login", "needs_nickname"); return
	_open(main, peer, id, "login")

static func request_create(main, nickname: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var pending = main.verified_subjects.get(sender)
	if pending == null or int(pending.expires) < now():
		_answer(main, sender, "create", "not_signed_in"); return
	var created: Dictionary = main.accounts.create(String(pending.subject), nickname.strip_edges(), now())
	if created.has("error"):
		if created.error == "exists": main.verified_subjects.erase(sender)
		_answer(main, sender, "create", String(created.error)); return
	main.verified_subjects.erase(sender)
	print("ACCOUNT_CREATED")
	_open(main, sender, String(created.id), "create")

static func request_resume(main, session: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id: String = main.accounts.resume(session, now())
	if id.is_empty():
		_answer(main, sender, "resume", "expired"); return
	main.peer_accounts[sender] = id
	main.accounts.flush()
	_answer(main, sender, "resume", "", "", String(main.accounts.profile(id).nickname))

static func request_rename(main, nickname: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id: String = String(main.peer_accounts.get(sender, ""))
	var error: String = "not_signed_in" if id.is_empty() else main.accounts.rename(id, nickname.strip_edges())
	if error.is_empty(): main.accounts.flush()
	_answer(main, sender, "rename", error, "", "" if not error.is_empty() else nickname.strip_edges())

static func request_delete(main) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id: String = String(main.peer_accounts.get(sender, ""))
	if id.is_empty() or not main.accounts.delete(id):
		_answer(main, sender, "delete", "not_signed_in"); return
	main.peer_accounts.erase(sender)
	for peer in main.peer_accounts.keys():
		if main.peer_accounts[peer] == id: main.peer_accounts.erase(peer)
	main.accounts.flush()
	print("ACCOUNT_DELETED")
	_answer(main, sender, "delete", "")

static func request_logout(main, session: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	main.accounts.revoke(session)
	main.peer_accounts.erase(sender)
	main.accounts.flush()
	_answer(main, sender, "logout", "")

static func _open(main, peer: int, id: String, action: String) -> void:
	var session: String = main.accounts.issue_session(id, now())
	main.peer_accounts[peer] = id
	main.accounts.flush()
	_answer(main, peer, action, "", session, String(main.accounts.profile(id).nickname))

static func _answer(main, peer: int, action: String, error: String, session: String = "", nickname: String = "") -> void:
	if main._peer_is_connected(peer):
		main.receive_account_result.rpc_id(peer, {"action": action, "error": error, "session": session, "nickname": nickname})

# ---------- client ----------

static func valid_result(result: Variant) -> bool:
	if not result is Dictionary or result.size() != RESULT_KEYS.size() or not result.has_all(RESULT_KEYS):
		return false
	for key in RESULT_KEYS:
		if not result[key] is String or String(result[key]).length() > 64:
			return false
	return String(result.action) in ACTIONS
