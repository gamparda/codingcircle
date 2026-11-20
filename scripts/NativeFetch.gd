extends Node
## Gets the battle engine this game data needs. The battle rules live only in the native engine (native/src);
## the library a device can run comes either with the app (res://native/bin) or, after a rule change, from
## the update channel: update.json names the engine's rules hash and, per platform, a library URL and its
## SHA-256. A match is stored as user://native/<hash>/<library> (read-only, as Android wants for loaded code)
## and loaded with BattleModel.native_available(). No app reinstall is needed for new rules.

signal finished(ok: bool)

const ContentUpdater = preload("res://scripts/ContentUpdater.gd")
const RulesHash = preload("res://scripts/BattleRulesHash.gd")

var status := ""
var _http: HTTPRequest
var _target := ""
var _expected_sha := ""
var _destination := ""

## The manifest fields for `target` (e.g. "android.arm64"): {"url", "sha256"}, or {} when the manifest has no
## engine for this game data's rules or the entry is not from the official channel.
static func manifest_entry(manifest: Dictionary, target: String) -> Dictionary:
	if String(manifest.get("native_rules_hash", "")) != RulesHash.HASH:
		return {}
	var key := target.replace(".", "_")
	var url := String(manifest.get("native_%s_url" % key, ""))
	var sha := String(manifest.get("native_%s_sha256" % key, "")).to_lower()
	var library := url.trim_prefix(ContentUpdater.OFFICIAL_CONTENT_PREFIX)
	# Only this platform's library from the official channel (no paths, no other files).
	if not url.begins_with(ContentUpdater.OFFICIAL_CONTENT_PREFIX) or library != BattleModel.native_library_file(target) or not RegEx.create_from_string("^[0-9a-f]{64}$").search(sha):
		return {}
	return {"url": url, "sha256": sha}

func start() -> void:
	if BattleModel.native_available():
		_finish(true)
		return
	_target = BattleModel.native_target()
	if _target.is_empty():
		_finish(false)
		return
	_destination = BattleModel.downloaded_native_path(_target)
	status = "전투 엔진을 확인하는 중..."
	_http = HTTPRequest.new()
	_http.timeout = 20.0
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	if _http.request(ContentUpdater.UPDATE_URL, PackedStringArray(["Cache-Control: no-cache"])) != OK:
		_finish(false)

func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.request_completed.disconnect(_on_manifest)
	var manifest = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
	var entry := manifest_entry(manifest, _target) if manifest is Dictionary else {}
	if entry.is_empty():
		_finish(false)
		return
	_expected_sha = String(entry.sha256)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_destination.get_base_dir()))
	_http.download_file = ProjectSettings.globalize_path(_destination + ".part")
	_http.timeout = 120.0
	_http.request_completed.connect(_on_library)
	status = "새 전투 엔진을 받는 중..."
	if _http.request(String(entry.url)) != OK:
		_finish(false)

func _on_library(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var part := ProjectSettings.globalize_path(_destination + ".part")
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or FileAccess.get_sha256(part).to_lower() != _expected_sha:
		DirAccess.remove_absolute(part)
		_finish(false)
		return
	var final_path := ProjectSettings.globalize_path(_destination)
	DirAccess.remove_absolute(final_path)
	if DirAccess.rename_absolute(part, final_path) != OK:
		_finish(false)
		return
	# Android 14 refuses to load writable code files.
	FileAccess.set_unix_permissions(final_path, FileAccess.UNIX_READ_OWNER)
	_finish(BattleModel.native_available())

func _finish(ok: bool) -> void:
	status = "" if ok else "전투 엔진을 받지 못했습니다. 인터넷 연결을 확인한 뒤 다시 시도해 주세요."
	finished.emit(ok)
