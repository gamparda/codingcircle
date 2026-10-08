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

## Deletes the data and returns {"files": removed save/cache files, "replays": removed replay count}.
static func wipe(main) -> Dictionary:
	var replays := BattleReplay.list_saved().size()
	var removed := 0
	for path in [save_path, save_path + ".tmp", MetaStats.cache_path]:
		if FileAccess.file_exists(path):
			removed += 1 if DirAccess.remove_absolute(path) == OK else 0
	_remove_folder(BattleReplay.save_dir)
	MetaStats.snapshot = {}
	MetaStats.boards = {}
	if main.network.client_connection_state != "idle":
		main.network.disconnect_from_server()
	main.save_data = SaveData.default_data()
	main.network.client_nickname = String(main.save_data.nickname)
	main.battle_preset = {}
	main.campaign_mode = false
	Localization.install(String(main.save_data.settings.language))
	main._apply_settings()
	return {"files": removed, "replays": replays}

static func _remove_folder(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(name))
	for name in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(name))
	DirAccess.remove_absolute(path)

static func _wrapped(text: String, size: int, color: Color) -> Label:
	var label := MultiplayerUI.label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 700
	return label

## The confirmation screen: says what goes, and unlocks "모두 삭제" only after a short countdown.
static func show_confirm(main) -> void:
	var dialog = main._action_panel("데이터 전체 초기화", Rect2(260, 90, 760, 540))
	var replays := BattleReplay.list_saved().size()
	dialog.add_child(_wrapped("이 기기에 저장된 데이터를 모두 지웁니다. 되돌릴 수 없습니다.", 17, UIKit.DANGER.lightened(0.2)))
	var items := [
		"캠페인 진행도·별·최고 기록, 전적, 업적, 일일·주간 도전 기록",
		"덱 프리셋, 닉네임, 설정(소리·화면·단축키), 튜토리얼과 시작 목표 진행",
		"저장된 리플레이 %d개" % replays,
		"전체 통계 캐시와 내 결과 보내기 설정",
	]
	for item in items:
		dialog.add_child(_wrapped("•  " + Localization.text(String(item)), 15, UIKit.TEXT))
	dialog.add_child(_wrapped("서버에 이미 올라간 기록(순위표 점수, 공유한 리플레이 코드, 온라인 통계)은 지워지지 않습니다. 초기화하면 새 익명 ID가 만들어져 이전 순위표 기록과는 이어지지 않습니다.", 13, UIKit.TEXT_MUTED))
	var status := _wrapped("", 13, UIKit.GOLD)
	status.name = "DataResetStatus"
	dialog.add_child(status)
	var confirm: Button = MultiplayerUI.button(main, dialog, "모두 삭제", "ConfirmDataReset", func(): _do_reset(main))
	UIKit.style_button(confirm, UIKit.DANGER, true, 16)
	MultiplayerUI.button(main, dialog, "취소", "CancelDataReset", main._dismiss_action_overlay)
	_count_down(main, confirm, countdown_seconds)

static func _count_down(main, confirm: Button, seconds: int) -> void:
	if not is_instance_valid(confirm):
		return
	confirm.disabled = seconds > 0
	confirm.text = Localization.text("모두 삭제") + (" (%d)" % seconds if seconds > 0 else "")
	if seconds > 0:
		main.get_tree().create_timer(1.0).timeout.connect(func(): _count_down(main, confirm, seconds - 1))

static func _do_reset(main) -> void:
	var result := wipe(main)
	main._dismiss_action_overlay()
	main._build_connect_screen(Localization.text("데이터를 초기화했습니다. 저장 파일과 리플레이 %d개를 지웠습니다.") % int(result.replays))
