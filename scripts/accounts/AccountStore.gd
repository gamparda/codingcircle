extends RefCounted
## Server-side accounts, kept in one JSON file written atomically. Stores no Google data except a
## salted hash of the account's Google subject, and sessions only as hashes of their tokens. A file that
## cannot be read is set aside and restored from the newest daily backup (ServerBackup), never overwritten.

const ServerStats = preload("res://scripts/ServerStats.gd")
const ServerBackup = preload("res://scripts/ServerBackup.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")

const FILE_NAME := "accounts.json"
const SESSION_SECONDS := 30 * 86400
const MAX_SESSIONS := 5
const MAX_ACCOUNTS := 200000
const START_RATING := 1000
## Past seasons kept per account (newest first when shown).
const SEASON_HISTORY := 24
## The hyper account (appoints super accounts): the account that already had the nickname whose SHA-256 is
## HYPER_NICKNAME_SHA256 when titles came out (only the hash is kept here, so the name is not in the game data).
## Binding it once, by account and only to an account created before HYPER_CREATED_BEFORE, means a later
## sign-up under the same name (after a rename) never inherits the role. CATWAR_HYPER_ACCOUNT names an
## account id instead.
static var HYPER_NICKNAME_SHA256 := "c7e498a9907c963726c7e076f59e77001f18d0a86b120e602dfdf1378841655a"
const HYPER_CREATED_BEFORE := 1793433600 # 2026-10-31 08:00 UTC
const HYPER_ENV := "CATWAR_HYPER_ACCOUNT"
## Distinct challenge days remembered per account (enough for the daily title).
const MAX_DAILY_DAYS := 40

var path := ""
## account id -> {"subject": hash, "nickname": String, "created": int, "last_login": int, "sessions": {token hash: expires},
##   "rating": int, "ranked": {"wins": int, "losses": int, "draws": int},
##   "season": "YYYY-MM", "best": int, "history": {season: {"rating", "best", "wins", "losses", "draws"}},
##   "role": "" | "super" | "hyper", "titles": {title id: unix time earned}, "title": worn title id or "",
##   "progress": {"streak", "ranked_games", "summons", "campaign": {"1".."8": best stars}, "daily": [date keys], "endless": best verified wave}}
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
## Ranked seasons whose top-ten titles were already handed out.
var awarded_seasons: Array = []
var dirty := false
## Unix time used instead of the clock (tests).
var now_override := 0

func configure(directory: String) -> void:
	path = "" if directory.is_empty() else directory.path_join(FILE_NAME)
	accounts = {}; by_subject = {}; by_nickname = {}; by_session = {}
	salt = ""
	awarded_seasons = []
	var stored = ServerBackup.read_store(path).value
	if stored is Dictionary:
		if stored.get("salt") is String and String(stored.salt).length() == 64:
			salt = String(stored.salt)
		if stored.get("accounts") is Dictionary:
			for id in stored.accounts:
				_adopt(String(id), stored.accounts[id])
		if stored.get("awarded_seasons") is Array:
			for season in stored.awarded_seasons:
				if valid_season(season) and not awarded_seasons.has(season):
					awarded_seasons.append(String(season))
	if salt.is_empty():
		salt = Crypto.new().generate_random_bytes(32).hex_encode()
		dirty = true
	bind_hyper()
	award_seasons()
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
	var role := String(record.get("role", "")) if String(record.get("role", "")) in Titles.ROLES else ""
	var titles := {}
	if record.get("titles") is Dictionary:
		for title in record.titles:
			if Titles.valid_id(title) and _is_number(record.titles[title]):
				titles[String(title)] = int(record.titles[title])
	var worn := String(record.get("title", "")) if titles.has(String(record.get("title", ""))) else ""
	accounts[id] = {"subject": String(record.subject), "nickname": nickname, "created": int(record.get("created", 0)), "last_login": int(record.get("last_login", 0)), "sessions": sessions, "rating": rating, "ranked": ranked, "season": season, "best": best, "history": history,
		"role": role, "titles": titles, "title": worn, "progress": _clean_progress(record.get("progress"))}
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
	accounts[id] = {"subject": subject_hash(subject), "nickname": nickname, "created": now, "last_login": now, "sessions": {}, "rating": START_RATING, "ranked": {"wins": 0, "losses": 0, "draws": 0}, "season": current_season(), "best": START_RATING, "history": {},
		"role": "", "titles": {}, "title": "", "progress": _clean_progress(null)}
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
		"season": String(account.season), "best": int(account.best), "history": account.history.duplicate(true), "role": String(account.role), "title": String(account.title)}

## Records one ranked result for `id`: the new rating and the win/loss/draw count. `outcome` is "wins", "losses" or "draws".
func record_ranked(id: String, rating: int, outcome: String) -> void:
	if not accounts.has(id) or outcome not in ["wins", "losses", "draws"]:
		return
	_roll_season(id)
	accounts[id].rating = clampi(rating, 1, 9999)
	accounts[id].best = maxi(int(accounts[id].best), int(accounts[id].rating))
	accounts[id].ranked[outcome] = int(accounts[id].ranked[outcome]) + 1
	var progress: Dictionary = accounts[id].progress
	progress.ranked_games = int(progress.ranked_games) + 1
	progress.streak = int(progress.streak) + 1 if outcome == "wins" else 0
	for tier in Titles.RANKED_TIERS:
		if int(accounts[id].best) >= int(tier[0]):
			grant(id, String(tier[1]))
	if int(progress.streak) >= Titles.STREAK:
		grant(id, "ranked_streak")
	if int(progress.ranked_games) >= Titles.VETERAN_GAMES:
		grant(id, "ranked_veteran")
	dirty = true

## Skeletons `id`'s necromancers raised in one ranked game.
func record_summons(id: String, count: int) -> void:
	if not accounts.has(id) or count <= 0:
		return
	var progress: Dictionary = accounts[id].progress
	progress.summons = mini(int(progress.summons) + count, 1_000_000_000)
	if int(progress.summons) >= Titles.NECRO_SUMMONS:
		grant(id, "necro_lord")
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
			rows.append({"nickname": String(accounts[id].nickname), "rating": int(accounts[id].rating), "wins": int(ranked.wins), "losses": int(ranked.losses), "draws": int(ranked.draws), "title": String(accounts[id].title)})
	rows.sort_custom(func(a, b): return int(a.rating) > int(b.rating) or (int(a.rating) == int(b.rating) and String(a.nickname) < String(b.nickname)))
	return rows.slice(0, limit)

# ---------- roles and titles ----------

static func _clean_progress(raw: Variant) -> Dictionary:
	var clean := {"streak": 0, "ranked_games": 0, "summons": 0, "campaign": {}, "daily": [], "endless": 0}
	if not raw is Dictionary:
		return clean
	for key in ["streak", "ranked_games", "summons", "endless"]:
		if _is_number(raw.get(key)) and int(raw[key]) >= 0 and int(raw[key]) < 1_000_000_000:
			clean[key] = int(raw[key])
	if raw.get("campaign") is Dictionary:
		for stage in raw.campaign:
			if String(stage) in ["1", "2", "3", "4", "5", "6", "7", "8"] and _is_number(raw.campaign[stage]):
				clean.campaign[String(stage)] = clampi(int(raw.campaign[stage]), 1, 3)
	if raw.get("daily") is Array:
		for key in raw.daily:
			if key is String and key.length() <= 9 and not clean.daily.has(key) and clean.daily.size() < MAX_DAILY_DAYS:
				clean.daily.append(key)
	return clean

## Gives `title` to `id`; true when it is new.
func grant(id: String, title: String) -> bool:
	if not accounts.has(id) or not Titles.valid_id(title) or accounts[id].titles.has(title):
		return false
	accounts[id].titles[title] = now()
	dirty = true
	return true

func titles_of(id: String) -> Dictionary:
	return accounts[id].titles.duplicate() if accounts.has(id) else {}

## Wears `title` (one the account owns, or "" for none). Returns an error code or "".
func wear(id: String, title: String) -> String:
	if not accounts.has(id):
		return "not_signed_in"
	if not title.is_empty() and not accounts[id].titles.has(title):
		return "not_owned"
	accounts[id].title = title
	dirty = true
	return ""

## The title `id` wears, or "".
func worn_title(id: String) -> String:
	return String(accounts[id].title) if accounts.has(id) else ""

func role_of(id: String) -> String:
	return String(accounts[id].role) if accounts.has(id) else ""

func find_by_nickname(nickname: String) -> String:
	return String(by_nickname.get(nickname.strip_edges().to_lower(), ""))

## Sets a role and its title; losing a role takes its title away (and off the account's name).
func set_role(id: String, role: String) -> void:
	if not accounts.has(id) or not role in Titles.ROLES:
		return
	for title in Titles.role_titles(String(accounts[id].role)):
		accounts[id].titles.erase(title)
		if String(accounts[id].title) == title:
			accounts[id].title = ""
	accounts[id].role = role
	for title in Titles.role_titles(role):
		grant(id, title)
	dirty = true

## The hyper account appoints (`enabled`) or dismisses a super account by nickname. Returns an error code or "".
func appoint(by: String, nickname: String, enabled: bool) -> String:
	if role_of(by) != "hyper":
		return "forbidden"
	var target := find_by_nickname(nickname)
	if target.is_empty():
		return "no_account"
	if role_of(target) == "hyper":
		return "forbidden"
	set_role(target, "super" if enabled else "")
	return ""

## Nicknames of the super accounts.
func super_nicknames() -> Array:
	var names: Array = []
	for id in accounts:
		if String(accounts[id].role) == "super":
			names.append(String(accounts[id].nickname))
	names.sort()
	return names

## A campaign stage won (verified): best stars per stage and the campaign titles. Returns the new titles.
func record_campaign(id: String, stage: int, stars: int, untouched: bool) -> Array:
	if not accounts.has(id) or stage < 1 or stage > 8:
		return []
	var campaign: Dictionary = accounts[id].progress.campaign
	campaign[str(stage)] = maxi(int(campaign.get(str(stage), 0)), clampi(stars, 1, 3))
	dirty = true
	var earned: Array = []
	if campaign.size() >= 8 and grant(id, "campaign_clear"): earned.append("campaign_clear")
	if campaign.size() >= 8 and campaign.values().all(func(value): return int(value) >= 3) and grant(id, "campaign_stars"): earned.append("campaign_stars")
	if stage == 8 and untouched and grant(id, "campaign_flawless"): earned.append("campaign_flawless")
	return earned

## A daily or weekly challenge won (verified) on `day`.
func record_daily(id: String, day: String) -> Array:
	if not accounts.has(id):
		return []
	var days: Array = accounts[id].progress.daily
	if not days.has(day) and days.size() < MAX_DAILY_DAYS:
		days.append(day)
		dirty = true
	return ["daily_30"] if days.size() >= Titles.DAILY_DAYS and grant(id, "daily_30") else []

## An endless run (verified): `waves` survived, whether the castle stayed above half and whether the deck had no ranged units.
func record_endless(id: String, waves: int, flawless: bool, melee: bool) -> Array:
	if not accounts.has(id):
		return []
	var progress: Dictionary = accounts[id].progress
	progress.endless = maxi(int(progress.endless), waves)
	dirty = true
	var earned: Array = []
	for tier in Titles.ENDLESS_TIERS:
		if waves >= int(tier[0]) and grant(id, String(tier[1])): earned.append(String(tier[1]))
	if waves >= Titles.ENDLESS_FEAT_WAVES and flawless and grant(id, "endless_flawless"): earned.append("endless_flawless")
	if waves >= Titles.ENDLESS_FEAT_WAVES and melee and grant(id, "endless_melee"): earned.append("endless_melee")
	return earned

## Every title a cheat may hand out (not the role titles).
func grant_all(id: String) -> Array:
	var earned: Array = []
	for title in Titles.CATALOG:
		if not String(title) in ["founder", "warden"] and grant(id, String(title)):
			earned.append(String(title))
	return earned

## Binds the hyper role once (see HYPER_NICKNAME).
func bind_hyper() -> void:
	for id in accounts:
		if String(accounts[id].role) == "hyper":
			return
	var chosen := OS.get_environment(HYPER_ENV).strip_edges()
	if not accounts.has(chosen):
		chosen = ""
		for id in accounts:
			if String(accounts[id].nickname).sha256_text() == HYPER_NICKNAME_SHA256:
				chosen = id
		if chosen.is_empty() or int(accounts[chosen].created) <= 0 or int(accounts[chosen].created) >= HYPER_CREATED_BEFORE:
			return
	set_role(chosen, "hyper")
	print("ACCOUNT_HYPER_BOUND")

## Hands out the top-ten title of every finished season not yet awarded. Accounts that have not played since
## a season ended still hold its final numbers live; the others keep them in their history.
func award_seasons() -> void:
	var current := current_season()
	var seasons := {}
	for id in accounts:
		var account: Dictionary = accounts[id]
		if String(account.season) < current and int(account.ranked.wins) + int(account.ranked.losses) + int(account.ranked.draws) > 0:
			seasons[String(account.season)] = true
		for past in account.history:
			seasons[String(past)] = true
	for season in seasons:
		if awarded_seasons.has(season) or String(season) >= current:
			continue
		var rows: Array = []
		for id in accounts:
			var account: Dictionary = accounts[id]
			if String(account.season) == season and int(account.ranked.wins) + int(account.ranked.losses) + int(account.ranked.draws) > 0:
				rows.append([int(account.rating), String(account.nickname), id])
			elif account.history.has(season):
				rows.append([int(account.history[season].rating), String(account.nickname), id])
		rows.sort_custom(func(a, b): return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
		for row in rows.slice(0, Titles.SEASON_TOP):
			grant(String(row[2]), "ranked_season_top")
		awarded_seasons.append(season)
		dirty = true

## Writes when changed. Returns false while the write keeps failing (the caller retries).
func flush() -> bool:
	if path.is_empty() or not dirty:
		return true
	if ServerStats.write_json(path, {"salt": salt, "accounts": accounts, "awarded_seasons": awarded_seasons}):
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
