extends RefCounted
## Server-side accounts, kept in one JSON file written atomically. Stores no Google data except a
## salted hash of the account's Google subject, and sessions only as hashes of their tokens. A file that
## cannot be read is set aside and restored from the newest daily backup (ServerBackup), never overwritten.

const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerBackup = preload("res://scripts/ServerBackup.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

const FILE_NAME := "accounts.json"
const SESSION_SECONDS := 30 * 86400
const MAX_SESSIONS := 5
const MAX_ACCOUNTS := 200000
const START_RATING := 1000
## Past seasons kept per account (newest first when shown).
const SEASON_HISTORY := 24

var path := ""
## account id -> {"subject": hash, "nickname": String, "created": int, "last_login": int, "sessions": {token hash: expires},
##   "rating": int, "ranked": {"wins": int, "losses": int, "draws": int},
##   "season": "YYYY-MM", "best": int, "history": {season: {"rating", "best", "wins", "losses", "draws"}}}
## Ranked seasons follow the UTC calendar month. When an account first plays or looks at its profile in a
## new month, the finished season is archived, its rating moves halfway back to START_RATING and the
## win/loss counts start over (so the first PROVISIONAL_GAMES games of a season are placement games).
var accounts: Dictionary = {}
## session token hash -> account id
var by_session: Dictionary = {}
## subject hash -> account id
var by_subject: Dictionary = {}
## lowercase nickname -> account id
var by_nickname: Dictionary = {}
## Per-store salt so a leaked file cannot be matched against Google IDs from elsewhere.
var salt := ""
var dirty := false
## Unix time used instead of the clock (tests).
var now_override := 0

func configure(directory: String) -> void:
	path = "" if directory.is_empty() else directory.path_join(FILE_NAME)
	accounts = {}; by_subject = {}; by_nickname = {}; by_session = {}
	salt = ""
	var stored = ServerBackup.read_store(path).value
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
	var ranked := {"wins": 0, "losses": 0, "draws": 0}
	if record.get("ranked") is Dictionary:
		for key in ranked:
			if _is_number(record.ranked.get(key)) and int(record.ranked[key]) >= 0:
				ranked[key] = int(record.ranked[key])
	var rating := START_RATING
	if _is_number(record.get("rating")) and int(record.rating) > 0 and int(record.rating) < 10000:
		rating = int(record.rating)
	# Accounts from before seasons existed belong to the season in progress.
	var season := String(record.get("season", "")) if valid_season(record.get("season")) else current_season()
	var best := int(record.best) if _is_number(record.get("best")) and int(record.best) >= rating and int(record.best) < 10000 else rating
	var history := {}
	if record.get("history") is Dictionary:
		for key in record.history:
			var entry = record.history[key]
			if valid_season(key) and String(key) < season and entry is Dictionary and ["rating", "best", "wins", "losses", "draws"].all(func(field): return _is_number(entry.get(field)) and int(entry[field]) >= 0 and int(entry[field]) < 1_000_000_000):
				history[String(key)] = {"rating": int(entry.rating), "best": int(entry.best), "wins": int(entry.wins), "losses": int(entry.losses), "draws": int(entry.draws)}
	_trim_history(history)
	accounts[id] = {"subject": String(record.subject), "nickname": nickname, "created": int(record.get("created", 0)), "last_login": int(record.get("last_login", 0)), "sessions": sessions, "rating": rating, "ranked": ranked, "season": season, "best": best, "history": history}
	by_subject[String(record.subject)] = id
	by_nickname[nickname.to_lower()] = id
	for token_hash in sessions:
		by_session[token_hash] = id

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
	accounts[id] = {"subject": subject_hash(subject), "nickname": nickname, "created": now, "last_login": now, "sessions": {}, "rating": START_RATING, "ranked": {"wins": 0, "losses": 0, "draws": 0}, "season": current_season(), "best": START_RATING, "history": {}}
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
			by_session.erase(token_hash)
	while sessions.size() >= MAX_SESSIONS:
		var oldest := ""
		for token_hash in sessions:
			if oldest.is_empty() or int(sessions[token_hash]) < int(sessions[oldest]):
				oldest = token_hash
		sessions.erase(oldest)
		by_session.erase(oldest)
	var token := Crypto.new().generate_random_bytes(32).hex_encode()
	sessions[token.sha256_text()] = now + SESSION_SECONDS
	by_session[token.sha256_text()] = id
	accounts[id].last_login = now
	dirty = true
	return token

## Account id for a live session token, or "".
func resume(token: String, now: int) -> String:
	if not _hex(token, 64):
		return ""
	var token_hash := token.sha256_text()
	var id := String(by_session.get(token_hash, ""))
	if id.is_empty() or not accounts.has(id):
		return ""
	if int(accounts[id].sessions.get(token_hash, 0)) > now:
		accounts[id].last_login = now
		dirty = true
		return id
	accounts[id].sessions.erase(token_hash)
	by_session.erase(token_hash)
	dirty = true
	return ""

func revoke(token: String) -> void:
	if not _hex(token, 64):
		return
	var token_hash := token.sha256_text()
	var id := String(by_session.get(token_hash, ""))
	by_session.erase(token_hash)
	if accounts.has(id) and accounts[id].sessions.erase(token_hash):
		dirty = true

## Removes the account and every session; the Google subject can sign up again as a new account.
func delete(id: String) -> bool:
	if not accounts.has(id):
		return false
	by_subject.erase(accounts[id].subject)
	by_nickname.erase(String(accounts[id].nickname).to_lower())
	for token_hash in accounts[id].sessions:
		by_session.erase(token_hash)
	accounts.erase(id)
	dirty = true
	return true

func profile(id: String) -> Dictionary:
	if not accounts.has(id):
		return {}
	_roll_season(id)
	var account: Dictionary = accounts[id]
	return {"nickname": String(account.nickname), "created": int(account.created), "rating": int(account.rating), "ranked": account.ranked.duplicate(),
		"season": String(account.season), "best": int(account.best), "history": account.history.duplicate(true)}

## Records one ranked result for `id`: the new rating and the win/loss/draw count. `outcome` is "wins", "losses" or "draws".
func record_ranked(id: String, rating: int, outcome: String) -> void:
	if not accounts.has(id) or outcome not in ["wins", "losses", "draws"]:
		return
	_roll_season(id)
	accounts[id].rating = clampi(rating, 1, 9999)
	accounts[id].best = maxi(int(accounts[id].best), int(accounts[id].rating))
	accounts[id].ranked[outcome] = int(accounts[id].ranked[outcome]) + 1
	dirty = true

func now() -> int:
	return now_override if now_override > 0 else int(Time.get_unix_time_from_system())

static func season_id(unix_time: int) -> String:
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d" % [int(date.year), int(date.month)]

func current_season() -> String:
	return season_id(now())

static func valid_season(value: Variant) -> bool:
	if not value is String or value.length() != 7 or value[4] != "-":
		return false
	var year := String(value).substr(0, 4)
	var month := String(value).substr(5, 2)
	return year.is_valid_int() and month.is_valid_int() and int(year) >= 2026 and int(month) >= 1 and int(month) <= 12

## Starts the current season for `id` if its last one has ended.
func _roll_season(id: String) -> void:
	var account: Dictionary = accounts[id]
	var season := current_season()
	if String(account.season) >= season:
		return
	var ranked: Dictionary = account.ranked
	if int(ranked.wins) + int(ranked.losses) + int(ranked.draws) > 0:
		account.history[String(account.season)] = {"rating": int(account.rating), "best": int(account.best), "wins": int(ranked.wins), "losses": int(ranked.losses), "draws": int(ranked.draws)}
		_trim_history(account.history)
	account.rating = START_RATING + roundi(float(int(account.rating) - START_RATING) * 0.5)
	account.best = int(account.rating)
	account.ranked = {"wins": 0, "losses": 0, "draws": 0}
	account.season = season
	dirty = true

static func _trim_history(history: Dictionary) -> void:
	var seasons: Array = history.keys()
	seasons.sort()
	while seasons.size() > SEASON_HISTORY:
		history.erase(seasons.pop_front())

## Highest ratings this season among accounts that played at least one ranked game in it.
func leaderboard(limit: int) -> Array:
	var rows: Array = []
	var season := current_season()
	for id in accounts:
		if String(accounts[id].season) != season:
			continue
		var ranked: Dictionary = accounts[id].ranked
		var games := int(ranked.wins) + int(ranked.losses) + int(ranked.draws)
		if games > 0:
			rows.append({"nickname": String(accounts[id].nickname), "rating": int(accounts[id].rating), "wins": int(ranked.wins), "losses": int(ranked.losses), "draws": int(ranked.draws)})
	rows.sort_custom(func(a, b): return int(a.rating) > int(b.rating) or (int(a.rating) == int(b.rating) and String(a.nickname) < String(b.nickname)))
	return rows.slice(0, limit)

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
