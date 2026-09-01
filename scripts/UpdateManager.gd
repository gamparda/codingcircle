class_name UpdateManager
extends Node

const Localization = preload("res://scripts/Localization.gd")

signal update_started(version: String)
signal update_status(message: String, progress: float)
signal update_failed(message: String)
signal restart_scheduled

const BUILD_INFO_PATH := "res://build_info.json"
const DEFAULT_UPDATE_URL := "https://gamparda.github.io/codingcircle/update.json"
const OFFICIAL_DOWNLOAD_PREFIX := "https://gamparda.github.io/codingcircle/"
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
	http.max_redirects = 0
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
		update_status.emit(Localization.text("업데이트 설치 파일 다운로드 중..."), progress)
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
	if not is_trusted_manifest_url(update_url, allow_insecure_update):
		_fail_update(Localization.text("신뢰할 수 없는 업데이트 주소입니다."))
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
	elif state == "failed":
		state = "idle"
		check_for_update(true)
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
	accept_manifest(body)

func accept_manifest(body: PackedByteArray) -> bool:
	manifest.clear()
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary or not validate_manifest(parsed, allow_insecure_update):
		_fail_update(Localization.text("신뢰할 수 없는 업데이트 정보입니다."))
		return false
	var candidate: Dictionary = parsed
	var remote_version: String = candidate.version
	if not is_newer_version(remote_version, current_version):
		state = "idle"
		return true
	manifest = candidate
	state = "waiting_safe"
	if safe_to_update:
		_begin_download()
	return true

func _begin_download() -> void:
	var version := String(manifest.get("version", "new"))
	update_started.emit(version)
	update_status.emit(Localization.text("필수 업데이트 준비 중..."), 0.0)
	var update_dir := ProjectSettings.globalize_path("user://updates")
	DirAccess.make_dir_recursive_absolute(update_dir)
	installer_path = update_dir.path_join(random_update_basename("exe"))
	http.download_file = installer_path
	state = "downloading"
	var error := http.request(String(manifest.installer_url), ["Cache-Control: no-cache"])
	if error != OK:
		_fail_update(Localization.text("업데이트 다운로드를 시작하지 못했습니다."))

func _handle_installer_response(result: int, response_code: int) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not FileAccess.file_exists(installer_path):
		_fail_update(Localization.text("업데이트 설치 파일 다운로드에 실패했습니다."))
		return
	update_status.emit(Localization.text("다운로드 파일 무결성 확인 중..."), 1.0)
	var actual_hash := FileAccess.get_sha256(installer_path).to_lower()
	var expected_hash := String(manifest.sha256).to_lower()
	if actual_hash != expected_hash:
		DirAccess.remove_absolute(installer_path)
		_fail_update(Localization.text("업데이트 파일의 SHA-256 검증에 실패했습니다."))
		return
	state = "ready_to_install"
	if safe_to_update:
		_schedule_install_and_restart()
	else:
		update_status.emit(Localization.text("진행 중인 경기가 끝나면 업데이트를 설치합니다."), 1.0)

func _schedule_install_and_restart() -> void:
	state = "installing"
	update_status.emit(Localization.text("게임을 종료하고 업데이트를 설치합니다..."), 1.0)
	var expected_hash := String(manifest.get("sha256", "")).to_lower()
	if FileAccess.get_sha256(installer_path).to_lower() != expected_hash:
		DirAccess.remove_absolute(installer_path)
		_fail_update(Localization.text("설치 직전 SHA-256 재검증에 실패했습니다."))
		return
	var executable := OS.get_executable_path()
	var install_dir := executable.get_base_dir()
	var helper_path := installer_path.get_base_dir().path_join(random_update_basename("cmd"))
	var backup_name := random_update_basename("bak")
	var restart_port := ""
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--server"):
		restart_port = "7777"
		for arg in user_args:
			if arg.begins_with("--port="):
				var candidate_port := validated_port(arg.trim_prefix("--port="))
				restart_port = str(candidate_port) if candidate_port != -1 else "7777"
	var batch := build_update_helper_batch(
		installer_path.get_file(), backup_name, executable, install_dir, expected_hash, restart_port
	)
	if batch.is_empty():
		_fail_update(Localization.text("안전한 업데이트 실행 도우미를 만들지 못했습니다."))
		return
	var helper := FileAccess.open(helper_path, FileAccess.WRITE)
	if helper == null:
		_fail_update(Localization.text("업데이트 실행 도우미를 만들지 못했습니다."))
		return
	helper.store_string(batch)
	helper.close()
	var pid := OS.create_process("cmd.exe", ["/d", "/c", helper_path])
	if pid <= 0:
		DirAccess.remove_absolute(helper_path)
		_fail_update(Localization.text("업데이트 설치 프로그램을 실행하지 못했습니다."))
		return
	restart_scheduled.emit()
	get_tree().quit(0)

func _fail_update(message: String) -> void:
	state = "failed"
	countdown = 10.0
	update_failed.emit(message)

func _valid_installer_url(url: String) -> bool:
	return is_trusted_installer_url(url, allow_insecure_update)

static func is_trusted_manifest_url(url: String, allow_insecure: bool = false) -> bool:
	if url == DEFAULT_UPDATE_URL:
		return true
	return allow_insecure and (url.begins_with("http://127.0.0.1/") or url.begins_with("http://localhost/"))

static func is_trusted_installer_url(url: String, allow_insecure: bool = false) -> bool:
	if url.begins_with(OFFICIAL_DOWNLOAD_PREFIX) and url.ends_with(".exe"):
		return true
	return allow_insecure and (url.begins_with("http://127.0.0.1/") or url.begins_with("http://localhost/"))

static func verify_manifest_signature(body: PackedByteArray, signature_base64: String, public_key_pem: String) -> bool:
	if body.is_empty() or signature_base64.strip_edges().is_empty() or public_key_pem.strip_edges().is_empty():
		return false
	var public_key := CryptoKey.new()
	if public_key.load_from_string(public_key_pem, true) != OK:
		return false
	var signature := Marshalls.base64_to_raw(signature_base64.strip_edges())
	if signature.is_empty():
		return false
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK:
		return false
	if hashing.update(body) != OK:
		return false
	var digest := hashing.finish()
	return Crypto.new().verify(HashingContext.HASH_SHA256, digest, signature, public_key)

static func validated_port(value: String) -> int:
	if RegEx.create_from_string("^[0-9]{1,5}$").search(value) == null:
		return -1
	var port := int(value)
	return port if port >= 1 and port <= 65535 else -1

static func random_update_basename(extension: String) -> String:
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	return "catwar-update-%s.%s" % [token, extension]

static func validate_manifest(candidate: Dictionary, allow_insecure: bool = false) -> bool:
	for field in ["version", "commit", "installer_url", "sha256", "mandatory", "published_at"]:
		if not candidate.has(field):
			return false
	if not candidate.version is String or not candidate.commit is String:
		return false
	if not candidate.installer_url is String or not candidate.sha256 is String:
		return false
	if not candidate.mandatory is bool or candidate.mandatory != true or not candidate.published_at is String:
		return false
	var version_pattern := RegEx.create_from_string("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	var commit_pattern := RegEx.create_from_string("^[0-9a-fA-F]{40}$")
	var hash_pattern := RegEx.create_from_string("^[0-9a-fA-F]{64}$")
	return version_pattern.search(candidate.version) != null \
		and commit_pattern.search(candidate.commit) != null \
		and hash_pattern.search(candidate.sha256) != null \
		and not candidate.published_at.is_empty() \
		and is_trusted_installer_url(candidate.installer_url, allow_insecure)

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

static func build_update_helper_batch(
	installer_name: String,
	backup_name: String,
	executable: String,
	install_dir: String,
	expected_hash: String,
	requested_port: String
) -> String:
	var safe_name := RegEx.create_from_string("^catwar-update-[0-9a-f]{32}\\.exe$")
	var safe_backup := RegEx.create_from_string("^catwar-update-[0-9a-f]{32}\\.bak$")
	var safe_hash := RegEx.create_from_string("^[0-9a-f]{64}$")
	if safe_name.search(installer_name) == null or safe_backup.search(backup_name) == null:
		return ""
	if safe_hash.search(expected_hash) == null:
		return ""
	var restart_arguments := ""
	if not requested_port.is_empty():
		var port := validated_port(requested_port)
		if port == -1:
			port = 7777
		restart_arguments = " --headless -- --server --port=%d" % port
	var batch := "@echo off\r\nsetlocal EnableExtensions DisableDelayedExpansion\r\n"
	batch += "set \"INSTALLER=%~dp0" + installer_name + "\"\r\n"
	batch += "set \"BACKUP=%~dp0" + backup_name + "\"\r\n"
	batch += "timeout /t 2 /nobreak >nul\r\n"
	batch += "robocopy.exe " + _batch_quote(install_dir) + " \"%BACKUP%\" /MIR /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul\r\n"
	batch += "if errorlevel 8 goto backup_failed\r\n"
	batch += "certutil.exe -hashfile \"%INSTALLER%\" SHA256 | findstr.exe /i /x \"" + expected_hash + "\" >nul\r\n"
	batch += "if errorlevel 1 goto rollback\r\n"
	batch += "\"%INSTALLER%\" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /DIR=" + _batch_quote(install_dir) + "\r\n"
	batch += "if errorlevel 1 goto rollback\r\n"
	batch += "if not exist " + _batch_quote(executable) + " goto rollback\r\n"
	batch += "start \"\" " + _batch_quote(executable) + restart_arguments + "\r\n"
	batch += "rmdir /s /q \"%BACKUP%\"\r\n"
	batch += "del /q \"%INSTALLER%\"\r\n"
	batch += "del /q \"%~f0\"\r\nexit /b 0\r\n"
	batch += ":rollback\r\n"
	batch += "robocopy.exe \"%BACKUP%\" " + _batch_quote(install_dir) + " /MIR /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP >nul\r\n"
	batch += "if errorlevel 8 goto restore_failed\r\n"
	batch += "if not exist " + _batch_quote(executable) + " goto restore_failed\r\n"
	batch += "start \"\" " + _batch_quote(executable) + restart_arguments + "\r\n"
	batch += "rmdir /s /q \"%BACKUP%\"\r\n"
	batch += "del /q \"%INSTALLER%\"\r\n"
	batch += "del /q \"%~f0\"\r\nexit /b 1\r\n"
	batch += ":backup_failed\r\nstart \"\" " + _batch_quote(executable) + restart_arguments + "\r\n"
	batch += "rmdir /s /q \"%BACKUP%\" 2>nul\r\ndel /q \"%INSTALLER%\"\r\ndel /q \"%~f0\"\r\nexit /b 2\r\n"
	batch += ":restore_failed\r\nexit /b 3\r\n"
	return batch

static func _batch_quote(value: String) -> String:
	return "\"" + value.replace("%", "%%") + "\""

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
