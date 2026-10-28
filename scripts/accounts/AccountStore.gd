extends RefCounted
## Server-side accounts, kept in one JSON file written atomically. Stores no Google data except a
## salted hash of the account's Google subject, and sessions only as hashes of their tokens.

const ServerStats = preload("res://scripts/ServerStats.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

const FILE_NAME := "accounts.json"
const SESSION_SECONDS := 30 * 86400
const MAX_SESSIONS := 5
const MAX_ACCOUNTS := 200000

var path := ""
## account id -> {"subject": hash, "nickname": String, "created": int, "last_login": int, "sessions": {token hash: expires}}
var accounts: Dictionary = {}
## subject hash -> account id
var by_subject: Dictionary = {}
## lowercase nickname -> account id
var by_nickname: Dictionary = {}
## Per-store salt so a leaked file cannot be matched against Google IDs from elsewhere.
var salt := ""
var dirty := false

func configure(directory: String) -> void:
	path = "" if directory.is_empty() else directory.path_join(FILE_NAME)
	accounts = {}; by_subject = {}; by_nickname = {}
	salt = ""
	var stored = ServerStats.read_json(path)
	if stored is Dictionary:
		if stored.get("salt") is String and String(stored.salt).length() == 64:
			salt = String(stored.salt)
		if stored.get("accounts") is Dictionary:
			for id in stored.accounts:
				_adopt(String(id), stored.accounts[id])
	if salt.is_empty():
		salt = Crypto.new().generate_random_bytes(32).hex_encode()
		dirty = true
	flush()

func _adopt(id: String, record: Variant) -> void:
	if not record is Dictionary or not _hex(id, 32) or not _hex(String(record.get("subject", "")), 64) or not valid_nickname(String(record.get("nickname", ""))):
		return
	var sessions := {}
	if record.get("sessions") is Dictionary:
		for token_hash in record.sessions:
			if _hex(String(token_hash), 64) and _is_number(record.sessions[token_hash]):
				sessions[String(token_hash)] = int(record.sessions[token_hash])
	var nickname := String(record.nickname)
	if by_subject.has(record.subject) or by_nickname.has(nickname.to_lower()):
		return
	accounts[id] = {"subject": String(record.subject), "nickname": nickname, "created": int(record.get("created", 0)), "last_login": int(record.get("last_login", 0)), "sessions": sessions}
	by_subject[String(record.subject)] = id
	by_nickname[nickname.to_lower()] = id

static func valid_nickname(nickname: String) -> bool:
	return nickname == nickname.strip_edges() and SessionStore.safe_text(nickname, SessionStore.MAX_NICKNAME)

func subject_hash(subject: String) -> String:
	return (salt + ":" + subject).sha256_text()

func find_by_subject(subject: String) -> String:
	return String(by_subject.get(subject_hash(subject), ""))

func nickname_taken(nickname: String, except_id: String = "") -> bool:
	var owner := String(by_nickname.get(nickname.strip_edges().to_lower(), ""))
	return not owner.is_empty() and owner != except_id

## Returns {"id"} or {"error": "invalid_nickname" | "nickname_taken" | "exists" | "full"}.
func create(subject: String, nickname: String, now: int) -> Dictionary:
	if not valid_nickname(nickname):
		return {"error": "invalid_nickname"}
	if nickname_taken(nickname):
		return {"error": "nickname_taken"}
	if not find_by_subject(subject).is_empty():
		return {"error": "exists"}
	if accounts.size() >= MAX_ACCOUNTS:
		return {"error": "full"}
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	accounts[id] = {"subject": subject_hash(subject), "nickname": nickname, "created": now, "last_login": now, "sessions": {}}
	by_subject[accounts[id].subject] = id
	by_nickname[nickname.to_lower()] = id
	dirty = true
	return {"id": id}

func rename(id: String, nickname: String) -> String:
	if not accounts.has(id):
		return "no_account"
	if not valid_nickname(nickname):
		return "invalid_nickname"
	if nickname_taken(nickname, id):
		return "nickname_taken"
	by_nickname.erase(String(accounts[id].nickname).to_lower())
	accounts[id].nickname = nickname
	by_nickname[nickname.to_lower()] = id
	dirty = true
	return ""

## Issues a new session token (returned once, stored only as a hash). Oldest sessions beyond
## MAX_SESSIONS and expired ones are dropped.
func issue_session(id: String, now: int) -> String:
	if not accounts.has(id):
		return ""
	var sessions: Dictionary = accounts[id].sessions
	for token_hash in sessions.keys():
		if int(sessions[token_hash]) <= now:
			sessions.erase(token_hash)
	while sessions.size() >= MAX_SESSIONS:
		var oldest := ""
		for token_hash in sessions:
			if oldest.is_empty() or int(sessions[token_hash]) < int(sessions[oldest]):
				oldest = token_hash
		sessions.erase(oldest)
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	sessions[token.sha256_text()] = now + SESSION_SECONDS
	accounts[id].last_login = now
	dirty = true
	return token

## Account id for a live session token, or "".
func resume(token: String, now: int) -> String:
	if not _hex(token, 64):
		return ""
	var token_hash := token.sha256_text()
	for id in accounts:
		var expires = accounts[id].sessions.get(token_hash)
		if expires != null:
			if int(expires) > now:
				accounts[id].last_login = now
				dirty = true
				return String(id)
			accounts[id].sessions.erase(token_hash)
			dirty = true
			return ""
	return ""

func revoke(token: String) -> void:
	if not _hex(token, 64):
		return
	var token_hash := token.sha256_text()
	for id in accounts:
		if accounts[id].sessions.erase(token_hash):
			dirty = true
			return

## Removes the account and every session; the Google subject can sign up again as a new account.
func delete(id: String) -> bool:
	if not accounts.has(id):
		return false
	by_subject.erase(accounts[id].subject)
	by_nickname.erase(String(accounts[id].nickname).to_lower())
	accounts.erase(id)
	dirty = true
	return true

func profile(id: String) -> Dictionary:
	if not accounts.has(id):
		return {}
	return {"nickname": String(accounts[id].nickname), "created": int(accounts[id].created)}

## Writes when changed. Returns false while the write keeps failing (the caller retries).
func flush() -> bool:
	if path.is_empty() or not dirty:
		return true
	if ServerStats.write_json(path, {"salt": salt, "accounts": accounts}):
		dirty = false
	return not dirty

static func _hex(value: String, length: int) -> bool:
	if value.length() != length:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
