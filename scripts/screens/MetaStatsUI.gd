extends RefCounted
## Widgets that show the community statistics and daily board, and the opt-in switch for sharing results.

const MetaStats = preload("res://scripts/MetaStats.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")
const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")

static func share_toggle(main) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.name = "ShareResultsToggle"
	toggle.text = Localization.text("내 결과를 익명 통계와 일일 순위표에 보내기 (순위표에는 닉네임이 표시됩니다)")
	toggle.button_pressed = MetaStats.sharing(main.save_data)
	toggle.add_theme_font_size_override("font_size", 13)
	toggle.toggled.connect(func(on):
		main.save_data.settings.share_results = on
		if not on:
			main.save_data.pending_reports = []
			main.save_data.pending_daily = {}
		SaveData.save_data(main.save_data))
	return toggle

static func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

static func unit_name(kind: String) -> String:
	return String(BattleModel.UNIT_NAMES.get(kind, kind))

static func deck_text(deck: Array) -> String:
	return " · ".join(PackedStringArray(deck.map(func(kind): return unit_name(String(kind)))))

## Fills `box` with the best decks of all online players (or a hint when there is nothing yet).
static func fill_global_card(box: VBoxContainer) -> void:
	for child in box.get_children():
		child.queue_free()
	var data := MetaStats.current()
	if data.is_empty():
		box.add_child(_label(Localization.text("서버에 연결하면 전체 플레이어의 덱 통계를 볼 수 있습니다."), 13, UIKit.TEXT_MUTED))
		return
	var online: Dictionary = data.online
	box.add_child(_label(Localization.text("온라인 전체 %d판 기준  ·  표본이 적은 덱은 제외됩니다") % int(online.matches), 13, UIKit.GOLD))
	if online.top.is_empty():
		box.add_child(_label(Localization.text("아직 순위를 낼 만큼 표본이 모이지 않았습니다."), 13, UIKit.TEXT_MUTED))
	var rank := 0
	for row in online.top.slice(0, 3):
		rank += 1
		var rate := roundi(100.0 * float(row.wins) / maxf(1.0, float(row.games)))
		box.add_child(_label("%d. %s   승률 %d%% (%d판)" % [rank, deck_text(row.deck), rate, int(row.games)], 14, UIKit.TEXT))

## Replaces `box` contents with the top of a daily board plus the player's own rank.
static func fill_board(box: VBoxContainer, date: String) -> void:
	for child in box.get_children():
		child.queue_free()
	var board: Dictionary = MetaStats.boards.get(date, {})
	if board.is_empty():
		box.add_child(_label(Localization.text("서버에 연결하면 오늘의 순위표를 볼 수 있습니다."), 13, UIKit.TEXT_MUTED))
		return
	box.add_child(_label(Localization.text("오늘의 순위표  ·  참가 %d명") % int(board.total), 13, UIKit.GOLD))
	var rank := 0
	for entry in board.entries.slice(0, 5):
		rank += 1
		box.add_child(_label("%d. %s   %d점  (%d초)" % [rank, String(entry.nick), int(entry.score), roundi(float(entry.seconds))], 14, UIKit.TEXT))
	if int(board.get("rank", 0)) > 0:
		box.add_child(_label(Localization.text("내 순위 %d위  ·  %d점") % [int(board.rank), int(board.mine)], 14, UIKit.SUCCESS))
	elif board.entries.is_empty():
		box.add_child(_label(Localization.text("아직 기록이 없습니다. 첫 기록을 남겨 보세요."), 13, UIKit.TEXT_MUTED))
