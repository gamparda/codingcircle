class_name UpdateManager
extends Node

signal update_started(version: String)
signal update_status(message: String, progress: float)
signal update_failed(message: String)
signal restart_scheduled

const BUILD_INFO_PATH := "res://build_info.json"
const DEFAULT_UPDATE_URL := "https://gamparda.github.io/codingcircle/update.json"
const CHECK_INTERVAL := 60.0

var current_version := "0.0.0"
var current_commit := "unknown"
var update_url := DEFAULT_UPDATE_URL
var safe_to_update := false
var enabled := false
var allow_insecure_update := false
var state := "idle"
var countdown := 0.5
var manifest: Dictionary = {}
var installer_path := ""
var http: HTTPRequest

func _ready() -> void:
	_load_build_info()
	var args := OS.get_cmdline_user_args()
	enabled = OS.get_name() == "Windows" and (OS.has_feature("release") or args.has("--force-update-check"))
	if args.has("--disable-updates"):
		enabled = false
	allow_insecure_update = args.has("--allow-insecure-update")
	for arg in args:
		if arg.begins_with("--update-url="):
			update_url = arg.trim_prefix("--update-url=")
	http = HTTPRequest.new()
	http.timeout = 25.0
	http.request_completed.connect(_on_request_completed)
	add_child(http)
	set_process(enabled)

func _process(delta: float) -> void:
	if not enabled:
		return
	if state == "downloading":
		var total: int = http.get_body_size()
		var downloaded: int = http.get_downloaded_bytes()
		var progress: float = -1.0 if total <= 0 else clamp(float(downloaded) / float(total), 0.0, 1.0)
		update_status.emit("업데이트 설치 파일 다운로드 중...", progress)
		return
	if state == "failed":
		countdown -= delta
		if countdown <= 0.0:
			retry_update()
		return
	if state != "idle":
		return
	countdown -= delta
	if countdown <= 0.0:
		check_for_update()

func set_safe_to_update(value: bool) -> void:
	safe_to_update = value
	if safe_to_update and state == "waiting_safe":
		_begin_download()
	elif safe_to_update and state == "ready_to_install":
		_schedule_install_and_restart()

func check_for_update(force: bool = false) -> void:
	if (not enabled and not force) or state != "idle":
		return
	state = "checking"
	countdown = CHECK_INTERVAL
	http.download_file = ""
	var error := http.request(update_url, ["Cache-Control: no-cache"])
	if error != OK:
		state = "idle"

func retry_update() -> void:
	if state == "failed" and not manifest.is_empty():
		state = "waiting_safe"
		if safe_to_update:
			_begin_download()
	elif state == "idle":
		check_for_update(true)

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if state == "checking":
		_handle_manifest_response(result, response_code, body)
	elif state == "downloading":
		_handle_installer_response(result, response_code)

func _handle_manifest_response(result: int, response_code: int, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		state = "idle"
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		state = "idle"
		return
	var candidate: Dictionary = parsed
	var remote_version := String(candidate.get("version", "0.0.0"))
	if not is_newer_version(remote_version, current_version):
		state = "idle"
		return
	var url := String(candidate.get("installer_url", ""))
	var sha256 := String(candidate.get("sha256", "")).to_lower()
	if not _valid_installer_url(url) or sha256.length() != 64 or not sha256.is_valid_hex_number(false):
		state = "idle"
		return
	manifest = candidate
	state = "waiting_safe"
	if safe_to_update:
		_begin_download()

func _begin_download() -> void:
	var version := String(manifest.get("version", "new"))
	update_started.emit(version)
	update_status.emit("필수 업데이트 준비 중...", 0.0)
	var update_dir := ProjectSettings.globalize_path("user://updates")
	DirAccess.make_dir_recursive_absolute(update_dir)
	installer_path = update_dir.path_join("CatWarSetup.exe")
	if FileAccess.file_exists(installer_path):
		DirAccess.remove_absolute(installer_path)
	http.download_file = installer_path
	state = "downloading"
	var error := http.request(String(manifest.installer_url), ["Cache-Control: no-cache"])
	if error != OK:
		_fail_update("업데이트 다운로드를 시작하지 못했습니다.")

func _handle_installer_response(result: int, response_code: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not FileAccess.file_exists(installer_path):
		_fail_update("업데이트 설치 파일 다운로드에 실패했습니다.")
		return
	update_status.emit("다운로드 파일 무결성 확인 중...", 1.0)
	var actual_hash := FileAccess.get_sha256(installer_path).to_lower()
	var expected_hash := String(manifest.sha256).to_lower()
	if actual_hash != expected_hash:
		DirAccess.remove_absolute(installer_path)
		_fail_update("업데이트 파일의 SHA-256 검증에 실패했습니다.")
		return
	state = "ready_to_install"
	if safe_to_update:
		_schedule_install_and_restart()
	else:
		update_status.emit("진행 중인 경기가 끝나면 업데이트를 설치합니다.", 1.0)

func _schedule_install_and_restart() -> void:
	state = "installing"
	update_status.emit("게임을 종료하고 업데이트를 설치합니다...", 1.0)
	var executable := OS.get_executable_path()
	var install_dir := executable.get_base_dir()
	var helper_path := installer_path.get_base_dir().path_join("apply_update.cmd")
	var restart_arguments := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--server"):
		var port := "7777"
		for arg in user_args:
			if arg.begins_with("--port="):
				port = arg.trim_prefix("--port=")
		restart_arguments = " --headless -- --server --port=" + port
	var batch := "@echo off\r\n"
	batch += "timeout /t 2 /nobreak >nul\r\n"
	batch += _batch_quote(installer_path) + " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /DIR=" + _batch_quote(install_dir) + "\r\n"
	batch += "if errorlevel 1 exit /b %errorlevel%\r\n"
	batch += "start \"\" " + _batch_quote(executable) + restart_arguments + "\r\n"
	batch += "del /q " + _batch_quote(installer_path) + "\r\n"
	batch += "del /q \"%~f0\"\r\n"
	var helper := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null:
		_fail_update("업데이트 실행 도우미를 만들지 못했습니다.")
		return
	helper.store_string(batch)
	helper.close()
	var pid := OS.create_process("cmd.exe", ["/c", helper_path])
	if pid <= 0:
		_fail_update("업데이트 설치 프로그램을 실행하지 못했습니다.")
		return
	restart_scheduled.emit()
	get_tree().quit(0)

func _fail_update(message: String) -> void:
	state = "failed"
	countdown = 10.0
	update_failed.emit(message)

func _valid_installer_url(url: String) -> bool:
	return url.begins_with("https://") or (allow_insecure_update and url.begins_with("http://"))

func _load_build_info() -> void:
	if not FileAccess.file_exists(BUILD_INFO_PATH):
		return
	var file := FileAccess.open(BUILD_INFO_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		current_version = String(parsed.get("version", current_version))
		current_commit = String(parsed.get("commit", current_commit))
		update_url = String(parsed.get("update_url", update_url))

func _batch_quote(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""

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
