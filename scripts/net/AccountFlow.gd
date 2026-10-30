extends RefCounted
## Accounts over the game connection. Google sign-in opens (or, with a nickname, creates) an account;
## afterwards the client comes back with a session token. Clients only send these credentials over a
## verified connection (NetworkController.client_transport_verified). The server cannot see that, so
## it trusts nothing but Google's token signatures and its own session hashes.

const GoogleIdToken = preload("res://scripts/accounts/GoogleIdToken.gd")

const NONCE_SECONDS := 300
const SIGN_UP_SECONDS := 300
const JWKS_REFRESH_SECONDS := 3600.0
const JWKS_RETRY_SECONDS := 60.0
const MAX_PENDING_LOGINS := 64
const RESULT_KEYS := ["action", "error", "session", "nickname"]
const ACTIONS := ["login", "create", "resume", "rename", "delete", "logout"]
## PC sign-in: the game opens Google's page in the browser and receives an authorization code on a
## loopback address; the server trades the code for an ID token with the desktop client's secret, which
## only the server has (environment, never in the game or the repository).
const DESKTOP_SECRET_ENV := "CATWAR_GOOGLE_DESKTOP_CLIENT_SECRET"
const TOKEN_URL := "https://oauth2.googleapis.com/token"
const MAX_EXCHANGES := 16
const LOOPBACK_PREFIX := "http://127.0.0.1:"

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
	# Same reliable channel, so the client knows whether PC sign-in is offered before the nonce arrives.
	main.receive_account_desktop_client.rpc_id(sender, desktop_client_id() if desktop_configured() else "")
	main.receive_account_nonce.rpc_id(sender, nonce)

static func desktop_client_id() -> String:
	return OS.get_environment(GoogleIdToken.DESKTOP_CLIENT_ID_ENV).strip_edges()

static func desktop_configured() -> bool:
	return not desktop_client_id().is_empty() and not OS.get_environment(DESKTOP_SECRET_ENV).strip_edges().is_empty()

## The shape of a PC sign-in request: an authorization code, a PKCE verifier and a loopback redirect.
static func valid_desktop_request(code: String, verifier: String, redirect_uri: String) -> bool:
	if code.is_empty() or code.length() > 512:
		return false
	for character in code:
		if character.unicode_at(0) <= 32 or character.unicode_at(0) >= 127 or character in ["&", "=", "?", "#"]:
			return false
	if verifier.length() < 43 or verifier.length() > 128:
		return false
	for character in verifier:
		if not (character in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"):
			return false
	if not redirect_uri.begins_with(LOOPBACK_PREFIX):
		return false
	var port := redirect_uri.substr(LOOPBACK_PREFIX.length())
	return port.is_valid_int() and port.length() <= 5 and int(port) >= 1 and int(port) <= 65535 and str(int(port)) == port

static func request_desktop_login(main, code: String, verifier: String, redirect_uri: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var issued = main.account_nonces.get(sender)
	main.account_nonces.erase(sender) # one use, even when the code fails
	if issued == null or int(issued.expires) < now():
		_answer(main, sender, "login", "no_nonce"); return
	if not valid_desktop_request(code, verifier, redirect_uri):
		_answer(main, sender, "login", "invalid_token"); return
	if not desktop_configured():
		_answer(main, sender, "login", "desktop_unavailable"); return
	var nonce := String(issued.nonce)
	if main.desktop_exchange_override.is_valid(): # tests stand in for Google's token endpoint
		_check_token(main, sender, String(main.desktop_exchange_override.call(code, verifier, redirect_uri)), nonce)
		return
	if main.desktop_exchanges >= MAX_EXCHANGES:
		_answer(main, sender, "login", "busy"); return
	var http := HTTPRequest.new()
	http.timeout = 20.0
	main.add_child(http)
	main.desktop_exchanges += 1
	var form := "code=%s&client_id=%s&client_secret=%s&redirect_uri=%s&grant_type=authorization_code&code_verifier=%s" % [
		code.uri_encode(), desktop_client_id().uri_encode(), OS.get_environment(DESKTOP_SECRET_ENV).strip_edges().uri_encode(), redirect_uri.uri_encode(), verifier.uri_encode()]
	http.request_completed.connect(func(result: int, status: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		main.desktop_exchanges -= 1
		var token := ""
		if result == HTTPRequest.RESULT_SUCCESS and status == 200:
			var reply = JSON.parse_string(body.get_string_from_utf8())
			if reply is Dictionary and reply.get("id_token") is String:
				token = String(reply.id_token)
		if token.is_empty():
			printerr("ACCOUNT_DESKTOP_EXCHANGE_FAILED result=%d code=%d" % [result, status])
		if main._peer_is_connected(sender):
			_check_token(main, sender, token, nonce))
	if http.request(TOKEN_URL, PackedStringArray(["Content-Type: application/x-www-form-urlencoded"]), HTTPClient.METHOD_POST, form) != OK:
		http.queue_free()
		main.desktop_exchanges -= 1
		_answer(main, sender, "login", "invalid_token")

static func request_login(main, token: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var issued = main.account_nonces.get(sender)
	main.account_nonces.erase(sender) # one use, even when the token fails
	if issued == null or int(issued.expires) < now():
		_answer(main, sender, "login", "no_nonce"); return
	_check_token(main, sender, token, String(issued.nonce))

static func _check_token(main, peer: int, token: String, nonce: String) -> void:
	var check: Dictionary = main.google.verify(token, nonce)
	if not check.ok and check.error == "unknown_key" and main.pending_logins.size() < MAX_PENDING_LOGINS and is_instance_valid(main.jwks_http):
		# Google rotated its keys: finish this login once the new keys arrive.
		main.pending_logins.append({"peer": peer, "token": token, "nonce": nonce})
		refresh_keys(main, true)
		return
	_finish_login(main, peer, check)

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
	main.cloud.delete(id)
	main.last_opponents.erase(id)
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
