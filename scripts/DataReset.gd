extends RefCounted
## "데이터 전체 초기화": deletes everything the game keeps on this device (the save file, the saved replays, the
## community-statistics cache) and starts over with defaults. Downloaded content packs, update installers and engine
## logs are not player data and stay. Nothing on the server is touched.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")

## Where the save file lives; tests point it somewhere harmless.
static var save_path := SaveData.SAVE_PATH
## Seconds the confirm button stays locked, so it cannot be hit by accident.
static var countdown_seconds := 3

## Report actual deletions and remaining paths. If the profile cannot be removed, keep
## its in-memory identity/progress and leave the other files alone so a retry is safe.
static func wipe(main) -> Dictionary:
	var result := {"ok": false, "files": 0, "replays": 0, "failed": [], "profile_reset": false}
	result.files += _remove_file(save_path, result.failed)
	if not result.failed.is_empty():
		return result
	for path in [save_path + ".tmp", MetaStats.cache_path]:
		result.files += _remove_file(path, result.failed)
	_remove_folder(SaveData.recovery_dir(save_path), result, false)
	_remove_folder(BattleReplay.save_dir, result)
	MetaStats.snapshot = {}
	MetaStats.boards = {}
	if main.network.client_connection_state != "idle":
		main.network.disconnect_from_server()
	main.save_data = SaveData.default_data()
	main.pending_battle_replays.clear()
	main.replay_recording_error = ""
	main.last_replay_path = ""
	main.local_recorder = null
	main.profile_load_warning = ""
	main.profile_load_details = ""
	main.network.client_nickname = String(main.save_data.nickname)
	main.account.forget() # this device's sign-in only; the account stays on the server
	main.battle_preset = {}
	main.campaign_mode = false
	Localization.install(String(main.save_data.settings.language))
	main._apply_settings()
	main._profile_saved()
	result.profile_reset = true
	result.ok = result.failed.is_empty()
	return result

static func _remove_file(path: String, failed: Array) -> int:
	# An unexpected directory is a failure, never a reason to recursively delete it.
	if DirAccess.dir_exists_absolute(path):
		failed.append(path)
		return 0
	if not FileAccess.file_exists(path):
		return 0
	if DirAccess.remove_absolute(path) != OK:
		failed.append(path)
		return 0
	return 1

static func _remove_folder(path: String, result: Dictionary, count_replays: bool = true) -> void:
	if FileAccess.file_exists(path):
		result.failed.append(path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	var directory := DirAccess.open(path)
	if directory == null or directory.list_dir_begin() != OK:
		result.failed.append(path)
		return
	var name := directory.get_next()
	while not name.is_empty():
		if name != "." and name != "..":
			var child := path.path_join(name)
			if directory.is_link(name):
				# Never follow a link out of the player-data folder.
				if DirAccess.remove_absolute(child) != OK:
					result.failed.append(child)
			elif directory.current_is_dir():
				_remove_folder(child, result, count_replays)
			else:
				var removed := _remove_file(child, result.failed)
				if count_replays and name.ends_with(".json"):
					result.replays += removed
				elif not count_replays:
					result.files += removed
		name = directory.get_next()
	directory.list_dir_end()
	if DirAccess.remove_absolute(path) != OK and not result.failed.has(path):
		result.failed.append(path)

static func _wrapped(text: String, size: int, color: Color) -> Label:
	var label := MultiplayerUI.label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 700
	return label

## The confirmation screen: says what goes, and unlocks "모두 삭제" only after a short countdown.
static func show_confirm(main) -> void:
	var dialog = main._action_panel("데이터 전체 초기화", Rect2(260, 90, 760, 540))
	main.action_overlay.set_meta("profile_reset", false)
	var replays := BattleReplay.list_saved(false).size()
	dialog.add_child(_wrapped("이 기기에 저장된 데이터를 모두 지웁니다. 되돌릴 수 없습니다.", 17, UIKit.DANGER.lightened(0.2)))
	var items := [
		"캠페인 진행도·별·최고 기록, 전적, 업적, 일일·주간 도전 기록",
		"덱 프리셋, 닉네임, 설정(소리·화면·단축키), 튜토리얼과 시작 목표 진행",
		"저장된 리플레이 %d개" % replays,
		"전체 통계 캐시와 내 결과 보내기 설정",
		"진행도 사본과 손상된 저장 파일의 복구용 원본 보관함",
	]
	for item in items:
		dialog.add_child(_wrapped("•  " + Localization.text(String(item)), 15, UIKit.TEXT))
	dialog.add_child(_wrapped("서버에 이미 올라간 기록(순위표 점수, 공유한 리플레이 코드, 온라인 통계)은 지워지지 않습니다. 초기화하면 새 익명 ID가 만들어져 이전 순위표 기록과는 이어지지 않습니다.", 13, UIKit.TEXT_MUTED))
	var status := _wrapped("", 13, UIKit.GOLD)
	status.name = "DataResetStatus"
	dialog.add_child(status)
	var confirm: Button = MultiplayerUI.button(main, dialog, "모두 삭제", "ConfirmDataReset", func(): _do_reset(main))
	UIKit.style_button(confirm, UIKit.DANGER, true, 16)
	MultiplayerUI.button(main, dialog, "취소", "CancelDataReset", func(): _close_confirm(main))
	_count_down(main, confirm, countdown_seconds)

static func _count_down(main, confirm: Button, seconds: int) -> void:
	if not is_instance_valid(confirm):
		return
	confirm.disabled = seconds > 0
	confirm.text = Localization.text("모두 삭제") + (" (%d)" % seconds if seconds > 0 else "")
	if seconds > 0:
		main.get_tree().create_timer(1.0).timeout.connect(func(): _count_down(main, confirm, seconds - 1))

static func _close_confirm(main) -> void:
	var reset_applied: bool = is_instance_valid(main.action_overlay) and bool(main.action_overlay.get_meta("profile_reset", false))
	main._dismiss_action_overlay()
	if reset_applied:
		# The settings form underneath still holds a pre-reset copy of the whole profile.
		main._build_connect_screen("일부 데이터가 남아 있습니다. 설정에서 데이터 초기화를 다시 시도하세요.")

static func _do_reset(main) -> void:
	var result := wipe(main)
	if not result.ok:
		if result.profile_reset and is_instance_valid(main.action_overlay):
			main.action_overlay.set_meta("profile_reset", true)
			var close := main.find_child("CancelDataReset", true, false) as Button
			if close != null:
				close.text = "닫기"
		var status := main.find_child("DataResetStatus", true, false) as Label
		if status != null:
			status.text = "일부 데이터를 삭제하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요.\n이번 시도에서 파일 %d개, 리플레이 %d개를 삭제했습니다." % [int(result.files), int(result.replays)]
			if not result.profile_reset:
				status.text += "\n저장 파일을 지우지 못해 현재 진행도와 설정을 유지했습니다."
			status.tooltip_text = "삭제하지 못한 경로:\n" + "\n".join(result.failed)
		var confirm := main.find_child("ConfirmDataReset", true, false) as Button
		if confirm != null:
			confirm.text = "남은 데이터 삭제 재시도"
		return
	main._dismiss_action_overlay()
	main._build_connect_screen(Localization.text("데이터를 초기화했습니다. 이번 시도에서 파일 %d개와 리플레이 %d개를 지웠습니다.") % [int(result.files), int(result.replays)])
