extends Control

const MAIN_SCENE := "res://scenes/Main.tscn"
const BUILD_INFO_PATH := "res://build_info.json"
const UPDATE_URL := "https://gamparda.github.io/codingcircle/update.json"
const OFFICIAL_CONTENT_PREFIX := "https://gamparda.github.io/codingcircle/"
const CONTENT_DIR := "user://content"
const ACTIVE_PACK := CONTENT_DIR + "/active.pck"
const PREVIOUS_PACK := CONTENT_DIR + "/previous.pck"
const PENDING_PACK := CONTENT_DIR + "/pending.pck"
const ACTIVE_METADATA := CONTENT_DIR + "/active.json"
const PREVIOUS_METADATA := CONTENT_DIR + "/previous.json"
const PACK_BOOT_STABILITY_SECONDS := 5.0

var bundled_version := "0.0.0"
var bundled_commit := "unknown"
var active_version := "0.0.0"
var active_commit := "unknown"
var active_pack_loaded := false
var state := "idle"
var manifest: Dictionary = {}
var http: HTTPRequest
var status_label: Label
var progress_bar: ProgressBar
var retry_button: Button
var offline_button: Button
var apk_button: Button

func _ready() -> void:
	_build_interface()
	var build_info := _read_json(BUILD_INFO_PATH)
	bundled_version = String(build_info.get("version", bundled_version))
	bundled_commit = String(build_info.get("commit", bundled_commit))
	active_version = bundled_version
	active_commit = bundled_commit
	var args := OS.get_cmdline_user_args()
	if OS.get_name() != "Android" or args.has("--server") or args.has("--disable-content-updates"):
		_launch_game()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_DIR))
	_recover_interrupted_update()
	_load_installed_pack()
	_check_for_update()

func _process(_delta: float) -> void:
	if state != "downloading" or not is_instance_valid(http):
		return
	var total := http.get_body_size()
	var downloaded := http.get_downloaded_bytes()
	progress_bar.value = 0.0 if total <= 0 else clamp(float(downloaded) / float(total) * 100.0, 0.0, 100.0)
	if total > 0:
		status_label.text = "게임 데이터 업데이트 다운로드 중 · %d%%" % int(progress_bar.value)

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("#090d18")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := VBoxContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-280, -125)
	panel.size = Vector2(560, 250)
	panel.add_theme_constant_override("separation", 18)
	background.add_child(panel)
	var title := Label.new()
	title.text = "CAT WAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#7ee8ff"))
	panel.add_child(title)
	status_label = Label.new()
	status_label.text = "게임을 준비하는 중..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(560, 54)
	panel.add_child(status_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(560, 22)
	progress_bar.show_percentage = false
	panel.add_child(progress_bar)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	panel.add_child(buttons)
	retry_button = Button.new()
	retry_button.text = "다시 시도"
	retry_button.visible = false
	retry_button.pressed.connect(_check_for_update)
	buttons.add_child(retry_button)
	offline_button = Button.new()
	offline_button.text = "현재 버전으로 시작"
	offline_button.visible = false
	offline_button.pressed.connect(_launch_game)
	buttons.add_child(offline_button)
	apk_button = Button.new()
	apk_button.text = "APK 다운로드"
	apk_button.visible = false
	apk_button.pressed.connect(func(): OS.shell_open(String(manifest.get("android_apk_url", ""))))
	buttons.add_child(apk_button)

func _check_for_update() -> void:
	if state == "checking" or state == "downloading" or state == "launching":
		return
	retry_button.visible = false
	offline_button.visible = false
	apk_button.visible = false
	progress_bar.value = 0.0
	status_label.text = "최신 게임 데이터를 확인하는 중..."
	if is_instance_valid(http):
		http.queue_free()
	http = HTTPRequest.new()
	http.timeout = 20.0
	http.max_redirects = 0
	http.use_threads = true
	http.request_completed.connect(_on_request_completed)
	add_child(http)
	state = "checking"
	var error := http.request(UPDATE_URL, ["Cache-Control: no-cache"])
	if error != OK:
		_show_recoverable_error("업데이트 확인을 시작하지 못했습니다.")

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state == "checking":
		_handle_manifest(result, response_code, body)
	elif state == "downloading":
		_handle_pack_download(result, response_code)

func _handle_manifest(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_show_recoverable_error("업데이트 서버에 연결하지 못했습니다.")
		return
	var candidate = JSON.parse_string(body.get_string_from_utf8())
	if not candidate is Dictionary or not validate_content_manifest(candidate):
		_show_recoverable_error("업데이트 정보가 올바르지 않습니다.")
		return
	manifest = candidate
	if requires_apk_update(String(manifest.get("version", "")), bundled_version, String(manifest.get("android_apk_url", ""))):
		_show_apk_update_required()
		return
	var remote_version := String(manifest.content_pack_version)
	var remote_commit := String(manifest.content_pack_commit)
	if not should_install_content(remote_version, active_version, remote_commit, active_commit):
		status_label.text = "최신 버전입니다."
		_launch_game()
		return
	_begin_pack_download()

func _begin_pack_download() -> void:
	status_label.text = "게임 데이터 업데이트 다운로드 중..."
	progress_bar.value = 0.0
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PENDING_PACK))
	http.download_file = ProjectSettings.globalize_path(PENDING_PACK)
	state = "downloading"
	var error := http.request(String(manifest.content_pack_url), ["Cache-Control: no-cache"])
	if error != OK:
		_show_recoverable_error("게임 데이터 다운로드를 시작하지 못했습니다.")

func _handle_pack_download(result: int, response_code: int) -> void:
	var pending_path := ProjectSettings.globalize_path(PENDING_PACK)
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not FileAccess.file_exists(pending_path):
		DirAccess.remove_absolute(pending_path)
		_show_recoverable_error("게임 데이터 다운로드에 실패했습니다.")
		return
	status_label.text = "다운로드한 게임 데이터를 검증하는 중..."
	progress_bar.value = 100.0
	var expected_hash := String(manifest.content_pack_sha256).to_lower()
	if FileAccess.get_sha256(pending_path).to_lower() != expected_hash:
		DirAccess.remove_absolute(pending_path)
		_show_recoverable_error("게임 데이터의 SHA-256 검증에 실패했습니다.")
		return
	if not _activate_pending_pack(expected_hash):
		_show_recoverable_error("게임 데이터 교체에 실패했습니다.")
		return
	active_version = String(manifest.content_pack_version)
	active_commit = String(manifest.content_pack_commit)
	active_pack_loaded = ProjectSettings.load_resource_pack(ACTIVE_PACK, true)
	if not active_pack_loaded:
		_rollback_pack()
		_show_recoverable_error("새 게임 데이터를 불러오지 못해 이전 버전으로 복구했습니다.")
		return
	status_label.text = "업데이트 완료 · 게임을 시작합니다."
	_launch_game(true)

func _activate_pending_pack(expected_hash: String) -> bool:
	var active_path := ProjectSettings.globalize_path(ACTIVE_PACK)
	var previous_path := ProjectSettings.globalize_path(PREVIOUS_PACK)
	var pending_path := ProjectSettings.globalize_path(PENDING_PACK)
	var metadata_path := ProjectSettings.globalize_path(ACTIVE_METADATA)
	var previous_metadata_path := ProjectSettings.globalize_path(PREVIOUS_METADATA)
	DirAccess.remove_absolute(previous_path)
	DirAccess.remove_absolute(previous_metadata_path)
	if FileAccess.file_exists(active_path):
		if DirAccess.rename_absolute(active_path, previous_path) != OK:
			return false
	if FileAccess.file_exists(metadata_path):
		DirAccess.rename_absolute(metadata_path, previous_metadata_path)
	if DirAccess.rename_absolute(pending_path, active_path) != OK:
		if FileAccess.file_exists(previous_path):
			DirAccess.rename_absolute(previous_path, active_path)
		if FileAccess.file_exists(previous_metadata_path):
			DirAccess.rename_absolute(previous_metadata_path, metadata_path)
		return false
	var metadata := {
		"version": String(manifest.content_pack_version),
		"commit": String(manifest.content_pack_commit),
		"sha256": expected_hash,
		"pending_boot": true,
	}
	if not _write_json_atomic(ACTIVE_METADATA, metadata):
		_rollback_pack()
		return false
	return true

func _recover_interrupted_update() -> void:
	var metadata := _read_json(ACTIVE_METADATA)
	if metadata.get("pending_boot", false) == true:
		_rollback_pack()

func _rollback_pack() -> void:
	var active_path := ProjectSettings.globalize_path(ACTIVE_PACK)
	var previous_path := ProjectSettings.globalize_path(PREVIOUS_PACK)
	var metadata_path := ProjectSettings.globalize_path(ACTIVE_METADATA)
	var previous_metadata_path := ProjectSettings.globalize_path(PREVIOUS_METADATA)
	DirAccess.remove_absolute(active_path)
	DirAccess.remove_absolute(metadata_path)
	if FileAccess.file_exists(previous_path):
		DirAccess.rename_absolute(previous_path, active_path)
	if FileAccess.file_exists(previous_metadata_path):
		DirAccess.rename_absolute(previous_metadata_path, metadata_path)

func _load_installed_pack() -> void:
	var metadata := _read_json(ACTIVE_METADATA)
	if not validate_active_metadata(metadata):
		return
	var active_path := ProjectSettings.globalize_path(ACTIVE_PACK)
	if not FileAccess.file_exists(active_path) or FileAccess.get_sha256(active_path).to_lower() != String(metadata.sha256).to_lower():
		_rollback_pack()
		return
	if ProjectSettings.load_resource_pack(ACTIVE_PACK, true):
		active_pack_loaded = true
		active_version = String(metadata.version)
		active_commit = String(metadata.commit)
	else:
		_rollback_pack()

func _launch_game(confirm_new_pack: bool = false) -> void:
	if state == "launching":
		return
	state = "launching"
	retry_button.visible = false
	offline_button.visible = false
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		if active_pack_loaded:
			_rollback_pack()
		status_label.text = "게임 장면을 불러오지 못했습니다. 앱을 다시 실행해 주세요."
		state = "failed"
		return
	var game := packed_scene.instantiate()
	if game == null:
		status_label.text = "게임을 시작하지 못했습니다."
		state = "failed"
		return
	for child in get_children():
		if child is CanvasItem:
			child.visible = false
	add_child(game)
	if confirm_new_pack:
		await get_tree().create_timer(PACK_BOOT_STABILITY_SECONDS).timeout
		if is_instance_valid(game) and game.is_inside_tree() and game.is_node_ready():
			_confirm_pack_boot()

func _confirm_pack_boot() -> void:
	var metadata := _read_json(ACTIVE_METADATA)
	if metadata.is_empty() or metadata.get("pending_boot", false) != true:
		return
	metadata.pending_boot = false
	if _write_json_atomic(ACTIVE_METADATA, metadata):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS_PACK))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS_METADATA))

func _show_recoverable_error(message: String) -> void:
	state = "failed"
	status_label.text = message
	progress_bar.value = 0.0
	retry_button.visible = true
	offline_button.visible = true
	apk_button.visible = false

func _show_apk_update_required() -> void:
	state = "apk_required"
	status_label.text = "APK 업데이트가 필요합니다.\n새 APK를 설치한 뒤 다시 실행해 주세요."
	progress_bar.value = 0.0
	retry_button.visible = false
	offline_button.visible = false
	apk_button.visible = true

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data) + "\n")
	file.close()
	DirAccess.remove_absolute(absolute_path)
	return DirAccess.rename_absolute(temporary_path, absolute_path) == OK

static func is_trusted_content_url(url: String) -> bool:
	return url.begins_with(OFFICIAL_CONTENT_PREFIX) and url.ends_with(".pck")

static func requires_apk_update(remote_version: String, installed_version: String, apk_url: String) -> bool:
	return is_newer_version(remote_version, installed_version) and apk_url == OFFICIAL_CONTENT_PREFIX + "CatWar.apk"

static func validate_content_manifest(candidate: Dictionary) -> bool:
	for field in ["content_pack_version", "content_pack_commit", "content_pack_url", "content_pack_sha256"]:
		if not candidate.has(field) or not candidate[field] is String:
			return false
	var version_pattern := RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	var commit_pattern := RegEx.create_from_string("^[0-9a-fA-F]{40}$")
	var hash_pattern := RegEx.create_from_string("^[0-9a-fA-F]{64}$")
	return version_pattern.search(candidate.content_pack_version) != null \
		and commit_pattern.search(candidate.content_pack_commit) != null \
		and hash_pattern.search(candidate.content_pack_sha256) != null \
		and is_trusted_content_url(candidate.content_pack_url)

static func validate_active_metadata(candidate: Dictionary) -> bool:
	if not validate_content_manifest({
		"content_pack_version": candidate.get("version", ""),
		"content_pack_commit": candidate.get("commit", ""),
		"content_pack_url": OFFICIAL_CONTENT_PREFIX + "CatWarContent.pck",
		"content_pack_sha256": candidate.get("sha256", ""),
	}):
		return false
	return candidate.get("pending_boot", false) is bool

static func should_install_content(remote_version: String, current_version: String, remote_commit: String, current_commit: String) -> bool:
	if is_newer_version(remote_version, current_version):
		return true
	return remote_version == current_version and remote_commit != current_commit

static func is_newer_version(remote: String, current: String) -> bool:
	var remote_parts := remote.trim_prefix("v").split(".")
	var current_parts := current.trim_prefix("v").split(".")
	var count: int = max(remote_parts.size(), current_parts.size())
	for index in count:
		var remote_value := int(remote_parts[index]) if index < remote_parts.size() else 0
		var current_value := int(current_parts[index]) if index < current_parts.size() else 0
		if remote_value > current_value:
			return true
		if remote_value < current_value:
			return false
	return false
