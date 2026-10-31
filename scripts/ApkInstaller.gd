extends Node
## In-app APK update (GitHub build only): downloads the published APK with resume, checks its SHA-256 against
## the update manifest, and hands it to the KeepfallUpdater Android plugin, which opens the system install
## dialog. The first time, Android asks the player to let this app install updates; the install continues
## when they come back from that setting. Without the plugin (ONE store build, older APKs) `available()` is
## false and callers open the download page instead.

signal status(text: String, progress: float) ## progress 0..1, or -1 when there is none to show
signal finished(ok: bool)

const Localization = preload("res://scripts/Localization.gd")
const ResumableDownload = preload("res://scripts/ResumableDownload.gd")
const PLUGIN := "KeepfallUpdater"
const APK_PATH := "user://apk/update.apk"
const UPDATE_URL := "https://gamparda.github.io/codingcircle/update.json"
const APK_URL := "https://gamparda.github.io/codingcircle/CatWar.apk"

var plugin: Object = null
var download: ResumableDownload
var expected_sha := ""
## "idle" | "checking" | "downloading" | "permission" (waiting for the install setting) | "installing"
var state := "idle"

static func available() -> bool:
	return Engine.has_singleton(PLUGIN) and not OS.has_feature("onestore")

func _ready() -> void:
	if Engine.has_singleton(PLUGIN):
		plugin = Engine.get_singleton(PLUGIN)
		plugin.connect("install_status", _on_install_status)

## Installs the APK the update manifest names (fetching the manifest first).
func start_latest() -> void:
	if plugin == null or state in ["checking", "downloading", "installing"]:
		return
	state = "checking"
	status.emit(Localization.text("업데이트 정보를 확인하는 중..."), -1.0)
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray):
		http.queue_free()
		state = "idle"
		var manifest = JSON.parse_string(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else null
		var sha := String(manifest.get("android_sha256", "")) if manifest is Dictionary else ""
		if not manifest is Dictionary or String(manifest.get("android_apk_url", "")) != APK_URL or RegEx.create_from_string("^[0-9a-fA-F]{64}$").search(sha) == null:
			_fail(Localization.text("업데이트 정보를 받지 못했습니다. 다시 시도해 주세요."))
			return
		start(APK_URL, sha))
	if http.request(UPDATE_URL, PackedStringArray(["Cache-Control: no-cache"])) != OK:
		http.queue_free()
		_fail(Localization.text("업데이트 정보를 받지 못했습니다. 다시 시도해 주세요."))

func start(url: String, sha256: String) -> void:
	if plugin == null or state in ["downloading", "installing"] or url != APK_URL:
		return
	expected_sha = sha256.to_lower()
	var path := ProjectSettings.globalize_path(APK_PATH)
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path).to_lower() == expected_sha:
		_install()
		return
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if not is_instance_valid(download):
		download = ResumableDownload.new()
		download.progressed.connect(func(done: int, total: int):
			if state == "downloading" and total > 0:
				status.emit(Localization.text("업데이트 받는 중 · %.1f / %.1f MB") % [done / 1048576.0, total / 1048576.0], float(done) / float(total)))
		download.retrying.connect(func(attempt: int, attempts: int):
			status.emit(Localization.text("연결이 불안정해 이어서 받는 중... (%d/%d)") % [attempt, attempts], -1.0))
		download.finished.connect(_on_downloaded)
		add_child(download)
	state = "downloading"
	status.emit(Localization.text("업데이트 받는 중..."), 0.0)
	download.start(url, path, expected_sha, PackedStringArray(["Cache-Control: no-cache"]))

func _on_downloaded(ok: bool) -> void:
	var path := ProjectSettings.globalize_path(APK_PATH)
	if not ok or not FileAccess.file_exists(path):
		_fail(Localization.text("업데이트를 받지 못했습니다. 다시 누르면 받은 부분부터 이어서 받습니다."))
		return
	if FileAccess.get_sha256(path).to_lower() != expected_sha:
		download.discard()
		_fail(Localization.text("받은 업데이트의 SHA-256 검증에 실패했습니다. 다시 시도해 주세요."))
		return
	_install()

func _install() -> void:
	if not bool(plugin.call("canInstall")):
		state = "permission"
		status.emit(Localization.text("처음 한 번만: 'Keepfall에서 앱 설치 허용'을 켠 뒤 돌아오면 설치가 이어집니다."), -1.0)
		plugin.call("openInstallSettings")
		return
	state = "installing"
	status.emit(Localization.text("설치 창을 여는 중..."), 1.0)
	plugin.call("installApk", ProjectSettings.globalize_path(APK_PATH))

func _notification(what: int) -> void:
	# Back from the install setting: carry on if the player allowed it.
	if what == NOTIFICATION_APPLICATION_RESUMED and state == "permission" and plugin != null and bool(plugin.call("canInstall")):
		_install()

func _on_install_status(result: String, detail: String) -> void:
	match result:
		"confirm":
			status.emit(Localization.text("설치 창에서 '업데이트'를 누르세요. 설치가 끝나면 게임이 닫히니 다시 실행해 주세요."), 1.0)
		"installed":
			state = "idle"
			status.emit(Localization.text("업데이트를 설치했습니다. 게임을 다시 실행해 주세요."), 1.0)
			finished.emit(true)
		"cancelled":
			_fail(Localization.text("설치를 취소했습니다. 다시 누르면 설치 창이 열립니다."))
		_:
			push_warning("APK install failed: %s" % detail)
			_fail(Localization.text("설치하지 못했습니다. 다시 시도하거나 웹에서 APK를 받아 설치해 주세요."))

func _fail(message: String) -> void:
	state = "idle"
	status.emit(message, -1.0)
	finished.emit(false)
