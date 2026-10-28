extends RefCounted
## Asked when this device and the server both changed the account's progress since they were last in sync
## (CloudSync): shows both and keeps the one the player picks. The other is kept as a recovery copy on this
## device (Settings → 데이터 → 진행도 보관·복구) when the server copy wins.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const ProfileRecovery = preload("res://scripts/screens/ProfileRecovery.gd")

static func show(main, server_text: String) -> void:
	var server = JSON.parse_string(server_text)
	if not server is Dictionary:
		return
	var server_data := SaveData.sanitize(server)
	var dialog = main._action_panel("진행도 선택", Rect2(240, 110, 800, 500))
	main.action_overlay.name = "CloudConflictOverlay"
	dialog.add_child(_wrapped("이 기기와 서버의 진행도가 서로 다릅니다. 이어서 할 진행도를 고르세요.", 16, UIKit.TEXT))
	dialog.add_child(_wrapped("서버에 저장된 진행도", 15, UIKit.GOLD))
	dialog.add_child(_wrapped(ProfileRecovery._summary(server_data), 14, UIKit.TEXT_MUTED))
	dialog.add_child(_wrapped("이 기기의 진행도", 15, UIKit.GOLD))
	dialog.add_child(_wrapped(ProfileRecovery._summary(SaveData.sanitize(main.save_data)), 14, UIKit.TEXT_MUTED))
	dialog.add_child(_wrapped("서버 진행도를 고르면 이 기기의 진행도는 복구용 사본으로 보관됩니다. 이 기기 진행도를 고르면 서버의 진행도를 덮어씁니다.", 13, UIKit.TEXT_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	dialog.add_child(row)
	MultiplayerUI.button(main, row, "서버 진행도 사용", "CloudUseServer", func():
		main._dismiss_action_overlay()
		main.cloud_sync.apply_server(main.cloud_sync.server_revision, server_text), true)
	MultiplayerUI.button(main, row, "이 기기 진행도 사용", "CloudKeepLocal", func():
		main._dismiss_action_overlay()
		main.cloud_sync.keep_local())

static func _wrapped(text: String, size: int, color: Color) -> Label:
	var label := MultiplayerUI.label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
