class_name SaveData
extends RefCounted

const Localization = preload("res://scripts/Localization.gd")

const SAVE_VERSION := 1
const SAVE_PATH := "user://catwar_save.json"
const MAX_BACKUP_TRANSFER_BYTES := 2 * 1024 * 1024
const WINDOW_SIZES := ["1280x720", "1600x900", "1920x1080"]
const FPS_LIMITS := [30, 60, 120, 144, 240]
const GRAPHICS_QUALITIES := ["auto", "high", "medium", "low"]
## A failed read must remain protected even if permissions recover before the next
## automatic save: the caller is still working with fallback progress.
static var protected_paths: Dictionary = {}
const CAMPAIGN_TARGETS := [
	{"time": 90.0, "base_hp": 400.0}, {"time": 100.0, "base_hp": 390.0},
	{"time": 110.0, "base_hp": 380.0}, {"time": 120.0, "base_hp": 365.0},
	{"time": 130.0, "base_hp": 350.0}, {"time": 145.0, "base_hp": 335.0},
	{"time": 160.0, "base_hp": 320.0}, {"time": 180.0, "base_hp": 300.0},
]

static func _record() -> Dictionary:
	return {"cleared": false, "best_stars": 0, "fastest_win": 0.0, "best_base_hp": 0.0, "attempts": 0, "wins": 0}

static func _preset(name: String, units: Array, structures: Array) -> Dictionary:
	return {"name": name, "units": units, "structures": structures}

static func default_data() -> Dictionary:
	var campaign_records: Array = []
	for _stage in 8:
		campaign_records.append(_record())
	return {
		"save_version": SAVE_VERSION,
		"nickname": "플레이어",
		"campaign_unlocked": 1,
		"campaign_records": campaign_records,
		"deck_presets": [
			_preset(Localization.text("덱 1"), ["shield", "archer", "healer"], ["wall", "turret", "generator"]),
			_preset(Localization.text("덱 2"), ["swordsman", "archer", "healer"], ["wall", "swamp", "turret"]),
			_preset(Localization.text("덱 3"), ["shield", "swordsman", "archer"], ["swamp", "turret", "generator"]),
		],
		"last_deck": 0,
		"tutorial_completed": false,
		"settings": {
			"master_volume": 0.8, "bgm_volume": 0.7, "sfx_volume": 0.8, "muted": false,
			"window_size": "1920x1080", "fullscreen": true, "vsync": true, "fps_limit": 60,
			"graphics_quality": "high", "damage_numbers": true, "screen_shake": true, "battle_effects": true, "effect_intensity": 1.0,
			"language": "ko", "share_results": false, "battle_keys": preload("res://scripts/BattleBindings.gd").DEFAULTS.duplicate(),
		},
		"stats": {
			"ai_matches": 0, "ai_wins": 0, "ai_losses": 0, "highest_campaign": 0, "total_stars": 0,
			"online_completed": 0, "online_wins": 0, "online_losses": 0, "online_draws": 0, "online_interrupted": 0,
			"win_streak": 0, "best_streak": 0, "daily_completed": 0, "weekly_completed": 0,
		},
		"achievements": {},
		"daily": {},
		"weekly": {},
		"seen_features": [],
		"goals": {},
		"install_id": "",
		"next_report_sequence": 1,
		"pending_reports": [],
		"pending_daily": {},
	}

static func _migrate_removed_structures(structures: Array, fallback: Array) -> Array:
	var migrated := structures.duplicate()
	for index in migrated.size():
		if String(migrated[index]) != "jump_pad":
			continue
		var replacement := ""
		for candidate in fallback:
			var kind := String(candidate)
			if BattleModel.STRUCTURE_STATS.has(kind) and not migrated.has(kind):
				replacement = kind
				break
		if replacement.is_empty():
			for candidate in BattleModel.STRUCTURE_STATS.keys():
				var kind := String(candidate)
				if not migrated.has(kind):
					replacement = kind
					break
		migrated[index] = replacement
	return migrated
# Godot JSON numbers decode as floats; only accept finite integral values.
static func _is_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and abs(float(value)) <= 9007199254740991.0 and float(value) == floor(float(value))

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _challenge_record(entry: Variant) -> Dictionary:
	# Local battles have no time limit. Keep legitimate long battles unchanged,
	# but never convert a missing, negative or non-finite time into a fast result.
	if not entry is Dictionary or not entry.get("won") is bool or not _is_integer(entry.get("score")) or not _is_number(entry.get("seconds")) or float(entry.seconds) < 0.0:
		return {}
	var points := int(entry.score)
	if (entry.won and (points < preload("res://scripts/ServerDailyBoard.gd").MIN_SCORE or points > preload("res://scripts/ServerDailyBoard.gd").MAX_SCORE)) or (not entry.won and points != 0):
		return {}
	return {"won": entry.won, "score": int(entry.score), "seconds": float(entry.seconds),
		"ruleset": String(entry.ruleset) if preload("res://scripts/ServerStats.gd").valid_ruleset(entry.get("ruleset")) else "0"}

static func _challenge_history(raw: Variant, weekly: bool, limit: int) -> Dictionary:
	var result := {"records": {}, "excluded": 0}
	if not raw is Dictionary:
		result.excluded = 1 if raw != null else 0
		return result
	for key in raw:
		# Validate before sorting or pruning: malformed future dates must not evict
		# valid older days, and weekly records must use the actual Monday key.
		if not key is String or not preload("res://scripts/ServerDailyBoard.gd").valid_date(("w" if weekly else "") + key) or (not weekly and key.length() != 8):
			result.excluded += 1
			continue
		var entry = raw[key]
		var record := _challenge_record(entry)
		var versions := {}
		if record.is_empty():
			result.excluded += 1
		if entry is Dictionary and entry.get("previous") is Dictionary:
			for rule in entry.previous:
				var old := _challenge_record(entry.previous[rule])
				if not preload("res://scripts/ServerStats.gd").valid_ruleset(rule) or old.is_empty():
					result.excluded += 1
					continue
				# The history key is authoritative for the originating version.
				old.ruleset = rule
				versions[rule] = old
		elif entry is Dictionary and entry.has("previous") and entry.previous != null:
			result.excluded += 1
		if record.is_empty():
			if versions.is_empty():
				continue
			# Recover a valid version without attributing its score to current rules.
			var rules: Array = versions.keys()
			rules.sort()
			record = versions[rules[0]]
		versions.erase(record.ruleset)
		record.previous = versions
		result.records[key] = record
	var days: Array = result.records.keys()
	days.sort()
	for key in days.slice(0, maxi(0, days.size() - limit)):
		result.records.erase(key)
	return result

static func _string_array(values: Array) -> bool:
	for value in values:
		if not value is String:
			return false
	return true

static func graphics_profile(quality: String, mobile: bool, screen_size: Vector2i) -> Dictionary:
	var resolved := quality
	if resolved == "auto":
		resolved = "medium" if mobile and maxi(screen_size.x, screen_size.y) >= 1920 and mini(screen_size.x, screen_size.y) >= 1080 else "low" if mobile else "high"
	match resolved:
		"low":
			return {"window_size": "1280x720", "fps_limit": 30, "damage_numbers": false, "screen_shake": false, "battle_effects": false, "effect_intensity": 0.2}
		"medium":
			return {"window_size": "1600x900", "fps_limit": 60, "damage_numbers": true, "screen_shake": false, "battle_effects": true, "effect_intensity": 0.6}
		_:
			return {"window_size": "1920x1080", "fps_limit": 60, "damage_numbers": true, "screen_shake": true, "battle_effects": true, "effect_intensity": 1.0}

static func apply_graphics_profile(settings: Dictionary, quality: String, mobile: bool, screen_size: Vector2i) -> void:
	var profile := graphics_profile(quality, mobile, screen_size)
	for key in profile:
		settings[key] = profile[key]
	settings.graphics_quality = quality

const DAILY_HISTORY := 60
const WEEKLY_HISTORY := 16

static func sanitize(raw: Variant, diagnostics: Dictionary = {}) -> Dictionary:
	diagnostics.challenge_excluded = 0
	var clean := default_data()
	if not raw is Dictionary:
		return clean
	if raw.get("nickname") is String and preload("res://scripts/RoomSessions.gd").safe_text(raw.nickname,16): clean.nickname = raw.nickname.strip_edges()
	if _is_integer(raw.get("save_version")):
		clean.save_version = clampi(int(raw.save_version), 1, SAVE_VERSION)
	if _is_integer(raw.get("campaign_unlocked")):
		clean.campaign_unlocked = clampi(int(raw.campaign_unlocked), 1, 8)
	if _is_integer(raw.get("last_deck")) and int(raw.last_deck) >= 0 and int(raw.last_deck) < 3:
		clean.last_deck = int(raw.last_deck)
	if raw.get("tutorial_completed") is bool:
		clean.tutorial_completed = raw.tutorial_completed
	if raw.get("campaign_records") is Array:
		for index in min(8, raw.campaign_records.size()):
			if raw.campaign_records[index] is Dictionary:
				var source: Dictionary = raw.campaign_records[index]
				var record: Dictionary = clean.campaign_records[index]
				if source.get("cleared") is bool: record.cleared = source.cleared
				if _is_integer(source.get("best_stars")): record.best_stars = clampi(source.best_stars, 0, 3)
				if _is_number(source.get("fastest_win")): record.fastest_win = max(0.0, float(source.fastest_win))
				if _is_number(source.get("best_base_hp")): record.best_base_hp = clamp(float(source.best_base_hp), 0.0, 500.0)
				if _is_integer(source.get("attempts")): record.attempts = max(0, int(source.attempts))
				if _is_integer(source.get("wins")): record.wins = clampi(int(source.wins), 0, int(record.attempts))
	if raw.get("deck_presets") is Array and raw.deck_presets.size() == 3:
		for index in 3:
			var preset = raw.deck_presets[index]
			if preset is Dictionary and preset.get("units") is Array and preset.get("structures") is Array and _string_array(preset.units) and _string_array(preset.structures):
				var structures := _migrate_removed_structures(preset.structures, clean.deck_presets[index].structures)
				if BattleModel._valid_deck(preset.units, BattleModel.UNIT_STATS) and BattleModel._valid_deck(structures, BattleModel.STRUCTURE_STATS):
					var name: String = preset.name.left(20) if preset.get("name") is String else clean.deck_presets[index].name
					clean.deck_presets[index] = {"name": name, "units": preset.units.duplicate(), "structures": structures}
	if raw.get("settings") is Dictionary:
		clean.settings.battle_keys = preload("res://scripts/BattleBindings.gd").sanitize(raw.settings.get("battle_keys"))
		# Existing players' hand-tuned visual settings must not be replaced by a new preset.
		clean.settings.graphics_quality = "custom"
		if raw.settings.get("graphics_quality") is String and GRAPHICS_QUALITIES.has(String(raw.settings.graphics_quality)):
			clean.settings.graphics_quality = String(raw.settings.graphics_quality)
		for key in ["master_volume", "bgm_volume", "sfx_volume"]:
			if _is_number(raw.settings.get(key)):
				clean.settings[key] = clamp(float(raw.settings[key]), 0.0, 1.0)
		if _is_number(raw.settings.get("effect_intensity")):
			clean.settings.effect_intensity = clamp(float(raw.settings.effect_intensity), 0.2, 1.0)
		if raw.settings.get("window_size") is String and WINDOW_SIZES.has(String(raw.settings.window_size)):
			clean.settings.window_size = String(raw.settings.window_size)
		if _is_integer(raw.settings.get("fps_limit")) and FPS_LIMITS.has(int(raw.settings.fps_limit)):
			clean.settings.fps_limit = int(raw.settings.fps_limit)
		if raw.settings.get("language") is String:
			clean.settings.language = "ko"
		for key in ["muted", "fullscreen", "vsync", "damage_numbers", "screen_shake", "battle_effects", "share_results"]:
			if raw.settings.get(key) is bool:
				clean.settings[key] = raw.settings[key]
	if raw.get("stats") is Dictionary:
		for key in clean.stats.keys():
			if _is_integer(raw.stats.get(key)):
				clean.stats[key] = max(0, int(raw.stats[key]))
	if raw.get("achievements") is Dictionary:
		for id in preload("res://scripts/Achievements.gd").ids():
			if _is_integer(raw.achievements.get(id)):
				clean.achievements[id] = max(0, int(raw.achievements[id]))
	for store in [["daily", DAILY_HISTORY], ["weekly", WEEKLY_HISTORY]]:
		var history := _challenge_history(raw.get(store[0]), store[0] == "weekly", int(store[1]))
		clean[store[0]] = history.records
		diagnostics.challenge_excluded += int(history.excluded)
	if raw.get("goals") is Dictionary:
		for id in preload("res://scripts/Goals.gd").ids():
			if raw.goals.get(id) is bool and raw.goals[id]:
				clean.goals[id] = true
	if raw.get("seen_features") is Array:
		for id in raw.seen_features.slice(0, 60):
			if id is String and not id.is_empty() and id.length() <= 40 and not clean.seen_features.has(id):
				clean.seen_features.append(id)
	if raw.get("install_id") is String and preload("res://scripts/ServerDailyBoard.gd").valid_id(String(raw.install_id)):
		clean.install_id = String(raw.install_id)
	if _is_integer(raw.get("next_report_sequence")) and int(raw.next_report_sequence) > 0 and int(raw.next_report_sequence) < preload("res://scripts/ServerStats.gd").MAX_COUNT:
		clean.next_report_sequence = int(raw.next_report_sequence)
	var last_sequence := 0
	if raw.get("pending_reports") is Array:
		for report in raw.pending_reports.slice(0, 20):
			if report is Dictionary and report.get("units") is Array and report.get("structures") is Array and _is_integer(report.get("result")) and report.get("mode") is String and preload("res://scripts/MetaStats.gd").REPORT_MODES.has(report.mode) and preload("res://scripts/NetworkProtocol.gd").validate_deck_payload(report.units, report.structures) and int(report.result) >= 0 and int(report.result) <= 2:
				var sequence := int(report.sequence) if _is_integer(report.get("sequence")) and int(report.sequence) > last_sequence and int(report.sequence) < preload("res://scripts/ServerStats.gd").MAX_COUNT - 1 else int(clean.next_report_sequence)
				sequence = maxi(sequence, last_sequence + 1)
				if sequence >= preload("res://scripts/ServerStats.gd").MAX_COUNT - 1:
					break
				clean.next_report_sequence = maxi(int(clean.next_report_sequence), sequence + 1)
				last_sequence = sequence
				# Older builds did not record the originating version. Do not relabel those results as current.
				var ruleset: String = String(report.ruleset) if preload("res://scripts/ServerStats.gd").valid_ruleset(report.get("ruleset")) else "0"
				clean.pending_reports.append({"units": report.units.duplicate(), "structures": report.structures.duplicate(), "result": int(report.result), "mode": String(report.mode), "sequence": sequence, "ruleset": ruleset})
	if not clean.pending_reports.is_empty() and clean.install_id.is_empty():
		preload("res://scripts/MetaStats.gd").install_id(clean)
	var pending = raw.get("pending_daily")
	if pending is Dictionary:
		for date in pending:
			if clean.pending_daily.size() >= 4:
				break
			var queued = pending[date]
			if date is String and preload("res://scripts/ServerDailyBoard.gd").valid_date(date) and queued is Dictionary and preload("res://scripts/ServerDailyBoard.gd").valid_score(queued.get("score"), queued.get("seconds")):
				clean.pending_daily[date] = {"score": int(queued.score), "seconds": float(queued.seconds),
					"ruleset": String(queued.ruleset) if preload("res://scripts/ServerStats.gd").valid_ruleset(queued.get("ruleset")) else "0"}
	clean.stats.highest_campaign = mini(8, int(clean.stats.highest_campaign))
	clean.stats.total_stars = 0
	for record in clean.campaign_records:
		clean.stats.total_stars += int(record.best_stars)
	return clean

static func recovery_dir(path: String = SAVE_PATH) -> String:
	return path + ".recovery"

## A recovery candidate must be a profile, not an unrelated JSON dictionary.
static func _recoverable(raw: Dictionary) -> bool:
	if not _is_integer(raw.get("save_version")) or int(raw.save_version) < 1 or int(raw.save_version) > SAVE_VERSION:
		return false
	if not raw.get("campaign_records") is Array or raw.campaign_records.size() != 8 or not raw.get("deck_presets") is Array or raw.deck_presets.size() != 3 or not raw.get("settings") is Dictionary or not raw.get("stats") is Dictionary:
		return false
	for record in raw.campaign_records:
		if not record is Dictionary:
			return false
	for preset in raw.deck_presets:
		if not preset is Dictionary:
			return false
	return true

static func _fingerprint(bytes: PackedByteArray) -> String:
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	return digest.finish().hex_encode()

## All snapshots share the existing recovery directory and reset policy. No pruning:
## overwriting or removing a player's last usable recovery point is never automatic.
static func create_backup(data: Dictionary, path: String = SAVE_PATH) -> String:
	return _preserve_original(JSON.stringify(sanitize(data), "\t").to_utf8_buffer(), path)

## Portable progress uses the existing profile format, without an installation's
## identity or queued submissions. Importing must never resend another device's results.
static func to_backup_text(data: Dictionary) -> String:
	var portable := data.duplicate(true)
	portable.install_id = ""
	portable.next_report_sequence = 1
	portable.pending_reports = []
	portable.pending_daily = {}
	return JSON.stringify(sanitize(portable), "\t")

## The progress a cloud save carries: the portable profile without this device's settings. Compact and
## key-sorted, so the same progress always gives the same text (CloudSync compares hashes).
static func cloud_text(data: Dictionary) -> String:
	var portable: Dictionary = JSON.parse_string(to_backup_text(data))
	portable.settings = default_data().settings
	return JSON.stringify(portable, "", true)

## No progress worth keeping yet (a new install): a cloud save replaces it without asking.
static func is_fresh(data: Dictionary) -> bool:
	var stats: Dictionary = data.get("stats", {})
	return int(stats.get("ai_matches", 0)) == 0 and int(stats.get("online_completed", 0)) == 0 and int(data.get("campaign_unlocked", 1)) <= 1 \
		and data.get("achievements", {}).is_empty() and data.get("daily", {}).is_empty() and data.get("weekly", {}).is_empty()

## Replaces the progress with a cloud save, keeping this device's settings, identity and unsent results, and
## keeping a recovery copy of the current progress first. Returns {"ok", "data", "error"}.
static func apply_cloud(current: Dictionary, text: String, path: String = SAVE_PATH) -> Dictionary:
	var result := {"ok": false, "data": {}, "error": ""}
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary or not _recoverable(parsed):
		result.error = "서버의 진행도를 읽을 수 없습니다."
		return result
	var live := sanitize(current)
	if create_backup(live, path).is_empty():
		result.error = "현재 진행도를 보관하지 못해 불러오기를 중단했습니다. 저장 공간을 확인하세요."
		return result
	var restored := sanitize(parsed)
	for key in ["settings", "install_id", "pending_reports", "pending_daily", "next_report_sequence"]:
		restored[key] = live[key]
	if not save_data(restored, path):
		result.error = "불러온 진행도를 저장하지 못했습니다. 현재 진행도는 유지됩니다."
		return result
	result.ok = true
	result.data = restored
	return result

static func backup_export(candidate: String, fingerprint: String, path: String = SAVE_PATH) -> Dictionary:
	var result := {"ok": false, "text": "", "error": ""}
	if candidate.get_base_dir() != recovery_dir(path):
		result.error = "이 저장 파일의 복구 폴더에 있는 사본만 내보낼 수 있습니다."
		return result
	var source := _read_profile(candidate)
	if source.status != "ok" or not _recoverable(source.raw):
		result.error = "선택한 사본을 읽을 수 없습니다. 목록을 새로고침하세요."
		return result
	if _fingerprint(source.bytes) != fingerprint:
		result.error = "선택한 사본의 내용이 바뀌었습니다. 목록을 새로고침해 다시 확인하세요."
		return result
	result.text = to_backup_text(source.raw)
	result.ok = true
	return result

## Preview is read-only. Keep the exact input for the later explicit import,
## rather than silently discarding damaged records from the recovery original.
static func preview_backup_text(text: String) -> Dictionary:
	var result := {"ok": false, "data": {}, "bytes": PackedByteArray(), "excluded": 0, "error": ""}
	if text.length() > MAX_BACKUP_TRANSFER_BYTES:
		result.error = "사본이 너무 큽니다. 진행도 JSON 사본만 복사하세요."
		return result
	if text.strip_edges().is_empty():
		result.error = "클립보드가 비어 있습니다. 내보낸 진행도 JSON 전체를 복사하세요."
		return result
	var bytes := text.to_utf8_buffer()
	if bytes.size() > MAX_BACKUP_TRANSFER_BYTES:
		result.error = "사본이 너무 큽니다. 진행도 JSON 사본만 복사하세요."
		return result
	var json := JSON.new()
	if json.parse(text.trim_prefix("\ufeff")) != OK or not json.data is Dictionary:
		result.error = "진행도 JSON을 읽을 수 없습니다. 중간에 빠진 내용 없이 전체를 복사하세요."
		return result
	if _is_integer(json.data.get("save_version")) and int(json.data.save_version) > SAVE_VERSION:
		result.error = "더 새로운 저장 형식의 사본입니다. 게임을 업데이트한 뒤 가져오세요."
		return result
	if not _recoverable(json.data):
		result.error = "진행도 사본이 아닙니다. 리플레이나 일부 내용 대신 진행도 JSON 전체를 복사하세요."
		return result
	var diagnostics := {}
	result.data = sanitize(json.data, diagnostics)
	result.excluded = int(diagnostics.challenge_excluded)
	result.bytes = bytes
	result.ok = true
	return result

## This only adds a recovery point. Replacing live progress still goes through
## restore_backup's preview, original preservation and device-local queue policy.
static func import_backup_text(text: String, path: String = SAVE_PATH) -> Dictionary:
	var result := {"ok": false, "path": "", "error": ""}
	var preview := preview_backup_text(text)
	if not preview.ok:
		result.error = preview.error
		return result
	result.path = _preserve_original(preview.bytes, path)
	if String(result.path).is_empty():
		result.error = "사본을 보관하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요. 현재 진행도는 유지됩니다."
		return result
	result.ok = true
	return result

static func recovery_candidates(path: String = SAVE_PATH) -> Dictionary:
	var result := {"entries": [], "excluded": 0, "error": ""}
	var folder := recovery_dir(path)
	if not DirAccess.dir_exists_absolute(folder) and not FileAccess.file_exists(folder):
		return result
	var directory := DirAccess.open(folder)
	if directory == null or directory.list_dir_begin() != OK:
		result.error = "복구 폴더를 읽지 못했습니다. 파일 권한을 확인하고 다시 시도하세요."
		return result
	var name := directory.get_next()
	while not name.is_empty():
		if not directory.current_is_dir() and not directory.is_link(name) and name.ends_with(".json"):
			var candidate := folder.path_join(name)
			var source := _read_profile(candidate)
			if source.status == "ok" and _recoverable(source.raw):
				var diagnostics := {}
				var data := sanitize(source.raw, diagnostics)
				result.entries.append({"path": candidate, "data": data, "fingerprint": _fingerprint(source.bytes), "modified": FileAccess.get_modified_time(candidate), "excluded": int(diagnostics.challenge_excluded)})
			else:
				result.excluded += 1
		name = directory.get_next()
	directory.list_dir_end()
	result.entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return int(a.modified) > int(b.modified) if int(a.modified) != int(b.modified) else String(a.path) < String(b.path))
	return result

## Explicit cleanup only: recheck the preview and retain a usable recovery point.
static func delete_backup(candidate: String, fingerprint: String, path: String = SAVE_PATH) -> Dictionary:
	var result := {"ok": false, "error": ""}
	var folder := recovery_dir(path)
	if candidate.get_base_dir() != folder or not candidate.ends_with(".json") or candidate.simplify_path() != candidate:
		result.error = "이 저장 파일의 복구 폴더에 있는 사본만 삭제할 수 있습니다."
		return result
	var directory := DirAccess.open(folder)
	if directory == null or directory.is_link(candidate.get_file()):
		result.error = "선택한 사본에 접근할 수 없습니다. 목록을 새로고침하세요."
		return result
	var candidates := recovery_candidates(path)
	var matched := false
	for entry in candidates.entries:
		if String(entry.path) == candidate and String(entry.fingerprint) == fingerprint:
			matched = true
	if not String(candidates.error).is_empty() or not matched:
		result.error = "선택한 사본을 읽을 수 없거나 내용이 바뀌었습니다. 목록을 새로고침해 다시 확인하세요."
		return result
	if candidates.entries.size() < 2:
		result.error = "마지막으로 읽을 수 있는 사본은 삭제할 수 없습니다. 현재 진행도를 다른 사본으로 보관한 뒤 다시 시도하세요."
		return result
	# The directory scan may take time; verify the selected bytes again just before removal.
	var source := _read_profile(candidate)
	if source.status != "ok" or not _recoverable(source.raw) or _fingerprint(source.bytes) != fingerprint or directory.is_link(candidate.get_file()):
		result.error = "확인 중 사본의 내용이 바뀌었습니다. 목록을 새로고침해 다시 확인하세요."
		return result
	if directory.remove(candidate.get_file()) != OK:
		result.error = "사본을 삭제하지 못했습니다. 파일 권한을 확인하고 다시 시도하세요."
		return result
	result.ok = true
	return result

## Preserve both the current in-memory progress and exact on-disk original before
## replacing anything. Return the new profile only after the atomic write succeeds.
static func restore_backup(current: Dictionary, candidate: String, fingerprint: String, path: String = SAVE_PATH) -> Dictionary:
	var result := {"ok": false, "data": {}, "backup": "", "error": ""}
	if candidate.get_base_dir() != recovery_dir(path):
		result.error = "이 저장 파일의 복구 폴더에 있는 사본만 선택할 수 있습니다."
		return result
	var source := _read_profile(candidate)
	if source.status != "ok" or not _recoverable(source.raw):
		result.error = "선택한 사본을 읽거나 복구할 수 없습니다. 목록을 새로고침하세요."
		return result
	if _fingerprint(source.bytes) != fingerprint:
		result.error = "확인 중 사본의 내용이 바뀌었습니다. 목록을 새로고침해 다시 확인하세요."
		return result
	var active := _read_profile(path)
	if active.status in ["unreadable", "newer"]:
		result.error = "현재 저장 파일을 안전하게 보관할 수 없습니다. 파일 권한이나 게임 버전을 확인하세요."
		return result
	var live := sanitize(current)
	result.backup = create_backup(live, path)
	if result.backup.is_empty() or (active.status in ["ok", "invalid"] and _preserve_original(active.bytes, path).is_empty()):
		result.error = "현재 진행도나 원본을 보관하지 못해 복구를 중단했습니다. 저장 공간과 파일 권한을 확인하세요."
		return result
	var restored := sanitize(source.raw)
	# Never resurrect acknowledged results or roll an installation's sequence back.
	# Keep device settings (including sharing consent) and current unsent results.
	var sequence := int(live.next_report_sequence)
	if not String(live.install_id).is_empty() and live.install_id == restored.install_id:
		sequence = maxi(sequence, int(restored.next_report_sequence))
	if active.status == "ok" and not String(live.install_id).is_empty():
		var disk := sanitize(active.raw)
		if live.install_id == disk.install_id:
			sequence = maxi(sequence, int(disk.next_report_sequence))
	for key in ["settings", "install_id", "pending_reports", "pending_daily"]:
		restored[key] = live[key]
	restored.next_report_sequence = sequence
	if not save_data(restored, path):
		result.error = "복구할 진행도를 저장하지 못했습니다. 현재 진행도는 유지됩니다. 파일 권한을 확인하고 다시 시도하세요."
		return result
	result.ok = true
	result.data = restored
	return result

## Keep missing, unreadable, malformed and newer-version saves distinct. Retain the
## exact bytes of malformed files; decoding and re-encoding could lose evidence.
static func _read_profile(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(path):
		return {"status": "unreadable"}
	if not FileAccess.file_exists(path):
		return {"status": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"status": "unreadable"}
	var length := file.get_length()
	var bytes := file.get_buffer(length)
	var error := file.get_error()
	file.close()
	if bytes.size() != length or error not in [OK, ERR_FILE_EOF]:
		return {"status": "unreadable"}
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8().trim_prefix("\ufeff")) != OK or not json.data is Dictionary:
		return {"status": "invalid", "bytes": bytes}
	if _is_integer(json.data.get("save_version")) and int(json.data.save_version) > SAVE_VERSION:
		return {"status": "newer"}
	return {"status": "ok", "raw": json.data, "bytes": bytes}

static func _preserve_original(bytes: PackedByteArray, path: String) -> String:
	var directory := recovery_dir(path)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(bytes)
	var backup := directory.path_join(digest.finish().hex_encode() + ".json")
	if FileAccess.file_exists(backup):
		var existing := FileAccess.open(backup, FileAccess.READ)
		if existing == null:
			return ""
		var same := existing.get_buffer(existing.get_length()) == bytes
		existing.close()
		return backup if same else ""
	return backup if _write_atomic(bytes, backup) else ""

static func load_result(path: String = SAVE_PATH) -> Dictionary:
	var source := _read_profile(path)
	var result := {"data": default_data(), "status": source.status, "backup": "", "warning": ""}
	if source.status in ["missing", "ok"]:
		protected_paths.erase(path)
	else:
		protected_paths[path] = true
	match source.status:
		"ok":
			var diagnostics := {}
			result.data = sanitize(source.raw, diagnostics)
			if int(diagnostics.challenge_excluded) > 0:
				# Preserve the exact original before any automatic save can remove
				# rejected records. Failed preservation keeps replacement protected.
				protected_paths[path] = true
				result.backup = _preserve_original(source.bytes, path)
				result.warning = "날짜·점수·완료 시간이 잘못된 도전 기록 %d개를 제외했습니다. 정상 진행도와 유효한 버전별 기록은 유지했습니다.\n" % int(diagnostics.challenge_excluded) + ("원본은 복구 폴더에 보관했습니다." if not result.backup.is_empty() else "원본 보관에 실패했습니다. 원본을 보관할 수 있을 때까지 새 진행도를 저장하지 않습니다.")
		"invalid":
			result.backup = _preserve_original(source.bytes, path)
			result.warning = "저장 파일이 손상되어 기본 진행도로 시작했습니다.\n" + ("원본은 별도 복구 폴더에 보관했습니다." if not result.backup.is_empty() else "새 진행도는 원본을 복구 폴더에 보관할 수 있을 때만 저장합니다.")
		"unreadable":
			result.warning = "저장 파일을 읽지 못해 기본 진행도로 시작했습니다.\n파일 권한을 확인하세요. 새 진행도는 원본을 별도 보관한 뒤 저장합니다."
		"newer":
			result.warning = "더 새로운 버전의 저장 파일입니다. 기본 진행도로 시작했습니다.\n원본을 보호하기 위해 저장하지 않습니다. 게임을 업데이트하세요."
	return result

static func load_data(path: String = SAVE_PATH) -> Dictionary:
	return load_result(path).data

static func save_data(data: Dictionary, path: String = SAVE_PATH) -> bool:
	var source := _read_profile(path)
	if source.status in ["unreadable", "newer"]:
		return false
	if (source.status == "invalid" or (source.status == "ok" and protected_paths.has(path))) and _preserve_original(source.bytes, path).is_empty():
		return false
	var saved := _write_atomic(JSON.stringify(sanitize(data), "\t").to_utf8_buffer(), path)
	if saved:
		protected_paths.erase(path)
	return saved

static func _write_atomic(bytes: PackedByteArray, path: String) -> bool:
	# Never truncate the active save before the replacement is fully written.
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(bytes)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return false
	if DirAccess.rename_absolute(temporary, path) != OK:
		DirAccess.remove_absolute(temporary)
		return false
	return true

static func campaign_stars(stage: int, won: bool, elapsed: float, remaining_base_hp: float) -> int:
	if not won:
		return 0
	var target: Dictionary = CAMPAIGN_TARGETS[clampi(stage, 1, 8) - 1]
	var stars := 1
	if remaining_base_hp >= float(target.base_hp):
		stars = 2
	if stars == 2 and elapsed <= float(target.time):
		stars = 3
	return stars

static func campaign_growth_level(data: Dictionary) -> int:
	var levels := 0
	for record in data.get("campaign_records", []):
		if record is Dictionary and bool(record.get("cleared", false)):
			levels += 1
	return clampi(levels, 0, 8)

static func record_campaign(data: Dictionary, stage: int, won: bool, elapsed: float, remaining_base_hp: float, drawn: bool = false) -> int:
	var index := clampi(stage, 1, 8) - 1
	var record: Dictionary = data.campaign_records[index]
	record.attempts += 1
	if won:
		record.wins += 1
		record.cleared = true
		var stars := campaign_stars(stage, true, elapsed, remaining_base_hp)
		record.best_stars = max(int(record.best_stars), stars)
		record.fastest_win = elapsed if float(record.fastest_win) <= 0.0 else min(float(record.fastest_win), elapsed)
		record.best_base_hp = max(float(record.best_base_hp), remaining_base_hp)
		data.campaign_unlocked = max(int(data.campaign_unlocked), min(8, stage + 1))
		data.stats.highest_campaign = max(int(data.stats.highest_campaign), stage)
	data.stats.ai_matches += 1
	data.stats.ai_wins += 1 if won else 0
	data.stats.ai_losses += 1 if not won and not drawn else 0
	var total := 0
	for stage_record in data.campaign_records:
		total += int(stage_record.best_stars)
	data.stats.total_stars = total
	return int(record.best_stars)
