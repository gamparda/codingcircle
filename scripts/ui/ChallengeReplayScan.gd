extends RefCounted
## Read-only, frame-budgeted snapshot. The owning screen decides when to step/cancel.

const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ChallengeReplays = preload("res://scripts/ChallengeReplays.gd")
const BUDGET_USEC := 4000
const SCAN_BATCH_NAMES := 64
const READ_BATCH_FILES := 4

var entries: Array = []
var done := false
var error := ""
var progress := "보관 전투 파일을 찾고 있습니다"
var _directory: DirAccess
var _paths: Array[String] = []
var _index := 0
var _scanning := true
var _with_analysis := false
var _period := ""
var _date := ""
var _ruleset := "0"

func begin(with_analysis: bool = false, period: String = "", date: String = "", ruleset: String = "0") -> void:
	_with_analysis = with_analysis
	_period = period
	_date = date
	_ruleset = ruleset
	_directory = DirAccess.open(BattleReplay.save_dir)
	if _directory == null:
		if DirAccess.dir_exists_absolute(BattleReplay.save_dir) or FileAccess.file_exists(BattleReplay.save_dir):
			error = "보관 폴더를 열지 못했습니다. 파일 권한과 저장 장치 연결을 확인한 뒤 새로고침하세요."
		done = true
	elif _directory.list_dir_begin() != OK:
		error = "보관 폴더의 파일 목록을 읽지 못했습니다. 새로고침으로 다시 시도하세요."
		cancel()

func step() -> void:
	if done: return
	var deadline := Time.get_ticks_usec() + BUDGET_USEC
	if _scanning:
		for _name_index in SCAN_BATCH_NAMES:
			var file := _directory.get_next()
			if file.is_empty():
				_directory.list_dir_end()
				_scanning = false
				break
			if not _directory.current_is_dir() and not _directory.is_link(file) and file.ends_with(".json"):
				_paths.append(BattleReplay.save_dir.path_join(file))
			if Time.get_ticks_usec() >= deadline: break
		if _scanning:
			progress = "보관 전투 파일을 찾고 있습니다 · %d개 발견" % _paths.size()
			return
	for _file_index in READ_BATCH_FILES:
		if _index >= _paths.size() or Time.get_ticks_usec() >= deadline: break
		var path := _paths[_index]
		_index += 1
		# Recheck links/directories: files may be replaced while the screen is open.
		if _directory.is_link(path.get_file()) or DirAccess.dir_exists_absolute(path): continue
		var replay := BattleReplay.load_file(path)
		if replay.is_empty() or String(replay.get("meta", {}).get("mode", "")) != "daily": continue
		if not _period.is_empty() and not ChallengeReplays.belongs_to(replay, _period, _date, _ruleset): continue
		# Count-only queries avoid serializing the entire command log for a fingerprint.
		entries.append(ChallengeReplays.shelf_entry(path, replay, _with_analysis, _with_analysis))
	progress = "보관 전투 읽는 중 · %d / %d개 확인" % [_index, _paths.size()]
	if _index >= _paths.size():
		if _with_analysis: ChallengeReplays.sort_entries(entries)
		done = true
		_directory = null
		_paths.clear()

func cancel() -> void:
	if _directory != null: _directory.list_dir_end()
	_directory = null
	_paths.clear()
	entries.clear()
	done = true
