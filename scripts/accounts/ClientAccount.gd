extends Node
## The player's account on this device. Without one the player is a guest; with one the game resumes
## the account with a session token whenever it reaches the official server. Google sign-in runs through
## the Android plugin (android/plugins/keepfall_signin) and only over a verified connection
## (NetworkController.account_ready). Only the session token and the nickname are kept, in SAVE_PATH.

signal changed

const GoogleIdToken = preload("res://scripts/accounts/GoogleIdToken.gd")
const AccountStore = preload("res://scripts/accounts/AccountStore.gd")

const PLUGIN := "KeepfallSignIn"
const PRIVACY_URL := "https://gampa.xyz/privacy_policy.html"
## Long enough for the Google account picker; a stuck request goes back to the guest state.
const REQUEST_SECONDS := 120.0
## After the server last confirmed the account, Android plays offline this long without reaching it.
const OFFLINE_GRACE_SECONDS := 7 * 86400

## Tests point it somewhere harmless.
static var save_path := "user://account.json"
## -1 follows the platform (sign-in required on Android); tests set 0 or 1.
static var required_override := -1

var network
var plugin: Object = null
## "guest" | "busy" | "needs_nickname" | "signed_in"
var state := "guest"
var session := ""
var nickname := ""
## True once the server accepted the session on this connection.
var online := false
## True once the server accepted the account during this run of the game; opens the game on Android.
var verified := false
## Unix time the server last confirmed the account (saved), for offline play.
var verified_at := 0
## Cloud save bookkeeping for this account (CloudSync): the revision and content hash last in sync.
var cloud_revision := 0
var cloud_hash := ""
var message := ""
var busy_elapsed := 0.0
var _busy_return := "guest"
var _was_ready := false

func setup(network_node, sign_in_plugin: Object = null) -> void:
	network = network_node
	plugin = sign_in_plugin
	if plugin == null and Engine.has_singleton(PLUGIN):
		plugin = Engine.get_singleton(PLUGIN)
	if plugin != null:
		plugin.connect("sign_in_succeeded", _on_google_token)
		plugin.connect("sign_in_failed", _on_google_failed)
	network.account_nonce_received.connect(_on_nonce)
	network.account_result_received.connect(_on_result)
	network.server_ready.connect(resume)
	_load()

func _process(delta: float) -> void:
	# Explicit disconnects emit no status, so follow the connection here.
	var ready: bool = network.account_ready()
	if ready != _was_ready:
		_was_ready = ready
		if not ready:
			_connection_lost()
		else:
			changed.emit()
	if state != "busy":
		return
	busy_elapsed += delta
	if busy_elapsed >= REQUEST_SECONDS:
		_finish(_busy_return, "응답이 없습니다. 다시 시도하세요.")

## Android requires a Google account to play; the PC version (no sign-in there) does not.
static func required() -> bool:
	return OS.has_feature("android") if required_override < 0 else required_override == 1

func unlocked() -> bool:
	return verified or not required() or offline_grace(int(Time.get_unix_time_from_system()))

## A saved account the server confirmed within OFFLINE_GRACE_SECONDS opens the game without a connection.
func offline_grace(now: int) -> bool:
	return not session.is_empty() and verified_at > 0 and now >= verified_at and now - verified_at <= OFFLINE_GRACE_SECONDS

func can_sign_in() -> bool:
	return plugin != null

func is_signed_in() -> bool:
	return state == "signed_in" or (state == "busy" and _busy_return == "signed_in")

## Why account actions are unavailable right now, or "" when they are available.
func blocker() -> String:
	if network == null or not network.client_is_online():
		return "서버에 연결되면 계정을 쓸 수 있습니다."
	if not network.client_transport_verified:
		return "공식 서버와의 보안 연결에서만 계정을 쓸 수 있습니다."
	return ""

# ---------- actions ----------

func sign_in() -> bool:
	if not can_sign_in():
		return _refuse("Google 로그인은 Android 앱에서만 할 수 있습니다.")
	if state != "guest" or not network.account_request_nonce():
		return _refuse(blocker())
	_begin("guest")
	return true

func create(name_text: String, age_confirmed: bool) -> bool:
	if state != "needs_nickname":
		return false
	if not age_confirmed:
		return _refuse("계정은 만 14세 이상만 만들 수 있습니다.")
	if not AccountStore.valid_nickname(name_text.strip_edges()):
		return _refuse(nickname_rule())
	if not network.account_create(name_text.strip_edges()):
		return _refuse(blocker())
	_begin("needs_nickname")
	return true

func cancel_sign_up() -> void:
	if state == "needs_nickname":
		_finish("guest", "")

func rename(name_text: String) -> bool:
	if state != "signed_in":
		return false
	if not AccountStore.valid_nickname(name_text.strip_edges()):
		return _refuse(nickname_rule())
	if not online or not network.account_rename(name_text.strip_edges()):
		return _refuse(blocker() if not blocker().is_empty() else "계정 확인이 끝난 뒤 다시 시도하세요.")
	_begin("signed_in")
	return true

func delete_account() -> bool:
	if state != "signed_in":
		return false
	if not online or not network.account_delete():
		return _refuse(blocker() if not blocker().is_empty() else "계정 확인이 끝난 뒤 다시 시도하세요.")
	_begin("signed_in")
	return true

## Signing out always works on this device; the server forgets the session when it can be told.
func sign_out() -> void:
	if state != "signed_in":
		return
	if not session.is_empty():
		network.account_sign_out(session)
	forget()
	if plugin != null:
		plugin.call("signOut")
	_finish("guest", "로그아웃했습니다.")

## Drops the local session (sign-out, data reset). The account itself stays on the server.
func forget() -> void:
	session = ""
	nickname = ""
	online = false
	verified = false
	verified_at = 0
	cloud_revision = 0
	cloud_hash = ""
	state = "guest"
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
	changed.emit()

## Called when a server connection is ready: come back as the saved account.
func resume() -> void:
	online = false
	if session.is_empty() or state == "busy":
		changed.emit()
		return
	if network.account_resume(session):
		_begin("signed_in")
	else:
		changed.emit()

static func nickname_rule() -> String:
	return "닉네임은 1~%d자로, 줄바꿈이나 특수 제어 문자 없이 정하세요." % AccountStore.SessionStore.MAX_NICKNAME

# ---------- replies ----------

func _on_nonce(nonce: String) -> void:
	if state != "busy" or _busy_return != "guest":
		return
	busy_elapsed = 0.0
	plugin.call("signIn", String(GoogleIdToken.DEFAULT_CLIENT_IDS[0]), nonce)

func _on_google_token(token: String) -> void:
	if state != "busy" or _busy_return != "guest":
		return
	busy_elapsed = 0.0
	if not network.account_sign_in(token):
		_finish("guest", blocker())

func _on_google_failed(code: String, _detail: String) -> void:
	if state != "busy" or _busy_return != "guest":
		return
	_finish("guest", {
		"cancelled": "로그인을 취소했습니다.",
		"no_account": "이 기기에 Google 계정이 없습니다. 기기 설정에서 계정을 추가하세요.",
	}.get(code, "Google 로그인에 실패했습니다. (%s)" % code))

func _on_result(result: Dictionary) -> void:
	var error := String(result.error)
	match String(result.action):
		"login", "create":
			if state != "busy":
				return
			if error == "needs_nickname":
				_finish("needs_nickname", "처음 로그인했습니다. 닉네임을 정해 계정을 만드세요.")
			elif error.is_empty():
				_save_session(String(result.session), String(result.nickname))
				_finish("signed_in", "%s 님으로 로그인했습니다." % nickname)
			else:
				_finish("needs_nickname" if String(result.action) == "create" and error in ["nickname_taken", "invalid_nickname"] else "guest", _error_text(error))
		"resume":
			if session.is_empty():
				return
			if error.is_empty():
				online = true
				verified = true
				_save_session(session, String(result.nickname) if not String(result.nickname).is_empty() else nickname)
				_finish("signed_in", "")
			else:
				forget()
				_finish("guest", "로그인이 만료되었습니다. 다시 로그인하세요.")
		"rename":
			if error.is_empty():
				_save_session(session, String(result.nickname))
				_finish("signed_in", "닉네임을 바꿨습니다.")
			else:
				_finish("signed_in", _error_text(error))
		"delete":
			if error.is_empty():
				forget()
				if plugin != null:
					plugin.call("signOut")
				_finish("guest", "계정을 삭제했습니다.")
			else:
				_finish("signed_in", _error_text(error))

static func _error_text(error: String) -> String:
	return {
		"no_nonce": "로그인 요청이 만료되었습니다. 다시 시도하세요.",
		"invalid_token": "Google 로그인을 확인하지 못했습니다. 다시 시도하세요.",
		"not_signed_in": "로그인 확인이 만료되었습니다. 다시 로그인하세요.",
		"nickname_taken": "이미 쓰이는 닉네임입니다.",
		"invalid_nickname": nickname_rule(),
		"no_account": "계정을 찾지 못했습니다. 다시 로그인하세요.",
		"full": "지금은 새 계정을 만들 수 없습니다. 나중에 다시 시도하세요.",
		"exists": "이 Google 계정에는 이미 계정이 있습니다. 다시 로그인하세요.",
		"expired": "로그인이 만료되었습니다. 다시 로그인하세요.",
	}.get(error, "요청을 처리하지 못했습니다. (%s)" % error)

func _connection_lost() -> void:
	online = false
	if state == "busy":
		_finish(_busy_return if _busy_return != "needs_nickname" else "guest", "서버 연결이 끊겼습니다.")
	elif state == "needs_nickname":
		_finish("guest", "서버 연결이 끊겨 계정 만들기를 취소했습니다.")
	else:
		changed.emit()

# ---------- state ----------

func _begin(return_state: String) -> void:
	_busy_return = return_state
	busy_elapsed = 0.0
	state = "busy"
	message = ""
	changed.emit()

func _finish(next_state: String, text: String) -> void:
	state = "signed_in" if next_state == "signed_in" and not session.is_empty() else ("guest" if next_state == "signed_in" else next_state)
	message = text
	busy_elapsed = 0.0
	changed.emit()

func _refuse(text: String) -> bool:
	message = text
	changed.emit()
	return false

func _save_session(token: String, name_text: String) -> void:
	if token != session:
		cloud_revision = 0
		cloud_hash = ""
	session = token
	nickname = name_text
	online = true
	verified = true
	verified_at = int(Time.get_unix_time_from_system())
	if not save():
		message = "로그인 정보를 저장하지 못했습니다. 다음 실행 때 다시 로그인해야 합니다."

func save() -> bool:
	if session.is_empty():
		return false
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"session": session, "nickname": nickname, "verified_at": verified_at, "cloud_revision": cloud_revision, "cloud_hash": cloud_hash}))
	return true

func _load() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if not data is Dictionary or not data.get("session") is String or not data.get("nickname") is String:
		return
	if String(data.session).length() != 64 or String(data.nickname).length() > AccountStore.SessionStore.MAX_NICKNAME:
		return
	session = String(data.session)
	nickname = String(data.nickname)
	state = "signed_in"
	if data.get("verified_at") is float or data.get("verified_at") is int:
		verified_at = int(data.verified_at)
	if (data.get("cloud_revision") is float or data.get("cloud_revision") is int) and data.get("cloud_hash") is String:
		cloud_revision = maxi(0, int(data.cloud_revision))
		cloud_hash = String(data.cloud_hash)
