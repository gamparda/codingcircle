extends RefCounted
## Reports the opponent of the last online match (RankedFlow.request_report). Signed-in players only; the
## server keeps one report per match and a daily limit.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

const REASONS := [["nickname", "부적절한 닉네임"], ["manner", "비매너 플레이 (고의 지연·방치 등)"], ["cheat", "부정행위 의심"]]
const ERRORS := {
	"": "신고가 접수되었습니다. 운영자가 확인합니다.",
	"already_reported": "이 경기는 이미 신고했습니다.",
	"limit": "오늘은 더 신고할 수 없습니다.",
	"no_match": "신고할 경기를 찾지 못했습니다.",
	"not_signed_in": "로그인한 계정만 신고할 수 있습니다.",
}

static func show(main) -> void:
	var dialog = main._action_panel("상대 신고", Rect2(340, 150, 600, 420))
	main.action_overlay.name = "ReportOverlay"
	var note := MultiplayerUI.label("이번 경기의 상대를 신고합니다. 이유를 고르세요.", 15, UIKit.TEXT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(note)
	var status := MultiplayerUI.label("", 14, UIKit.GOLD)
	status.name = "ReportStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var buttons: Array = []
	for entry in REASONS:
		var reason := String(entry[0])
		var button: Button = MultiplayerUI.button(main, dialog, String(entry[1]), "Report_" + reason, func():
			if not main.network.send_report(reason):
				status.text = "서버에 연결되어 있지 않아 신고하지 못했습니다."
				return
			for other in buttons: other.disabled = true
			status.text = "보내는 중...")
		buttons.append(button)
	dialog.add_child(status)
	MultiplayerUI.button(main, dialog, "닫기", "CloseReport", main._dismiss_action_overlay)
	var on_result := func(error: String):
		if is_instance_valid(status): status.text = String(ERRORS.get(error, "신고하지 못했습니다. (%s)" % error))
	main.network.report_result_received.connect(on_result, CONNECT_ONE_SHOT)
	status.tree_exited.connect(func():
		if main.network.report_result_received.is_connected(on_result): main.network.report_result_received.disconnect(on_result))
