extends RefCounted
## Titles, roles and verified offline feats over the game connection. A signed-in client asks for its titles,
## wears one, and sends the command log of a campaign win, challenge win or finished endless run; the server
## re-simulates it (TitleVerifier, a slice per frame) and hands out what its own result earns. The hyper account
## also appoints super accounts here, and accounts with a role may take every title (a cheat for testing).

const Titles = preload("res://scripts/accounts/Titles.gd")
const TitleVerifier = preload("res://scripts/accounts/TitleVerifier.gd")
const SessionStore = preload("res://scripts/RoomSessions.gd")

const STATE_KEYS := ["role", "owned", "worn", "supers", "error", "granted", "verified"]
const ERRORS := ["", "not_signed_in", "not_owned", "forbidden", "no_account", "busy", "invalid", "mismatch", "expired"]
## Re-simulation time per server frame and the most jobs waiting at once.
const BUDGET_USEC := 4000
const MAX_JOBS := 32

static func _account(main, peer: int) -> String:
	return String(main.peer_accounts.get(peer, ""))

# ---------- server ----------

## Sends `peer` its titles (and, to the hyper account, the super accounts).
static func send_state(main, peer: int, error: String = "", granted: Array = [], verified: String = "") -> void:
	if not main._peer_is_connected(peer):
		return
	var id := _account(main, peer)
	var owned: Array = main.accounts.titles_of(id).keys() if not id.is_empty() else []
	owned.sort()
	var role: String = main.accounts.role_of(id) if not id.is_empty() else ""
	main.receive_title_state.rpc_id(peer, {"role": role, "owned": owned, "worn": main.accounts.worn_title(id) if not id.is_empty() else "",
		"supers": main.accounts.super_nicknames() if role == "hyper" else [], "error": error, "granted": granted, "verified": verified})

static func request_state(main) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	send_state(main, sender, "" if not _account(main, sender).is_empty() else "not_signed_in")

static func request_wear(main, title: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	var error: String = "not_signed_in" if id.is_empty() else main.accounts.wear(id, title if title.is_empty() or Titles.valid_id(title) else "?")
	if error.is_empty(): main.accounts.flush()
	send_state(main, sender, error)

static func request_appoint(main, nickname: String, enabled: bool) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	var error: String = "not_signed_in" if id.is_empty() else main.accounts.appoint(id, nickname, enabled)
	if error.is_empty():
		main.accounts.flush()
		print("ACCOUNT_ROLE_CHANGED")
		# A connected appointee sees its new role at once.
		var target: String = main.accounts.find_by_nickname(nickname)
		for peer in main.peer_accounts:
			if String(main.peer_accounts[peer]) == target:
				send_state(main, int(peer))
	send_state(main, sender, error)

static func request_cheat_titles(main) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	if id.is_empty() or not Titles.can_cheat(main.accounts.role_of(id)):
		send_state(main, sender, "forbidden"); return
	var granted: Array = main.accounts.grant_all(id)
	main.accounts.flush()
	send_state(main, sender, "", granted)

static func request_verify(main, kind: String, text: String) -> void:
	var sender: int = main.multiplayer.get_remote_sender_id()
	if not main.server_mode or not main.can_process_request(sender): return
	var id := _account(main, sender)
	if id.is_empty():
		send_state(main, sender, "not_signed_in"); return
	if not kind in TitleVerifier.KINDS or text.length() > TitleVerifier.MAX_TEXT:
		send_state(main, sender, "invalid"); return
	if main.title_jobs.size() >= MAX_JOBS or main.title_jobs.any(func(job): return job.account == id):
		send_state(main, sender, "busy"); return
	var job = TitleVerifier.create(kind, text, id, sender)
	main.title_jobs.append(job)

## Runs the waiting verifications for a while each frame, oldest first, and settles finished ones.
static func advance(main) -> void:
	if main.title_jobs.is_empty():
		return
	var job = main.title_jobs[0]
	if not job.step(BUDGET_USEC):
		return
	main.title_jobs.pop_front()
	var outcome: Dictionary = job.result
	if not bool(outcome.ok):
		print("TITLE_VERIFY_FAILED kind=%s error=%s" % [job.kind, String(outcome.error)])
		send_state(main, job.peer, String(outcome.error), [], job.kind)
		return
	var granted: Array = []
	match job.kind:
		"campaign":
			if bool(outcome.won): granted = main.accounts.record_campaign(job.account, int(outcome.stage), int(outcome.stars), bool(outcome.untouched))
		"daily":
			if bool(outcome.won): granted = main.accounts.record_daily(job.account, String(outcome.day))
		"endless":
			granted = main.accounts.record_endless(job.account, int(outcome.waves), bool(outcome.flawless), bool(outcome.melee))
	main.accounts.flush()
	print("TITLE_VERIFIED kind=%s granted=%d" % [job.kind, granted.size()])
	# The run may have finished after its player reconnected under a new peer id.
	var targets: Array = []
	for peer in main.peer_accounts:
		if String(main.peer_accounts[peer]) == String(job.account):
			targets.append(int(peer))
	for peer in targets:
		send_state(main, peer, "", granted, job.kind)

# ---------- client ----------

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.size() != STATE_KEYS.size() or not data.has_all(STATE_KEYS):
		return false
	if not String(data.get("role")) in Titles.ROLES or not data.role is String or not data.error is String or not String(data.error) in ERRORS:
		return false
	if not data.verified is String or not (String(data.verified).is_empty() or String(data.verified) in TitleVerifier.KINDS):
		return false
	if not data.worn is String or not (String(data.worn).is_empty() or Titles.valid_id(data.worn)):
		return false
	for key in ["owned", "granted"]:
		if not data[key] is Array or data[key].size() > Titles.CATALOG.size() or not data[key].all(func(id): return Titles.valid_id(id)):
			return false
	if not data.supers is Array or data.supers.size() > 200 or not data.supers.all(func(name): return name is String and SessionStore.safe_text(name, SessionStore.MAX_NICKNAME)):
		return false
	return true
