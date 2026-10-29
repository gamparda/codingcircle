extends RefCounted
## The ranking dialog: this season's leaderboard, ranked card statistics (pick, ban and win rates) and the
## player's past seasons. Rendered from the last ranked profile; a fresh one is requested on open.

const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")

## Below this many picks a card's win rate is shown as a small sample.
const MIN_CARD_PICKS := 20
const TABS := [["board", "순위"], ["cards", "카드 통계"], ["seasons", "지난 시즌"]]

static func season_name(season: String) -> String:
	if season.length() != 7:
		return season
	return "%s년 %d월" % [season.substr(0, 4), int(season.substr(5, 2))]

static func show(main, tab: String = "board") -> void:
	var dialog = main._action_panel("랭킹", Rect2(240, 60, 800, 600))
	main.action_overlay.name = "RankedBoardOverlay"
	main.action_overlay.set_meta("tab", tab)
	var profile: Dictionary = main.ranked_profile
	var header := MultiplayerUI.label(_header(profile), 15, MultiplayerUI.MUTED)
	header.name = "RankedSeasonHeader"
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(header)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	dialog.add_child(tabs)
	for entry in TABS:
		var id := String(entry[0])
		var button: Button = main._styled_button(String(entry[1]), Color("#6375d2") if id == tab else Color("#3d647d"), id == tab)
		button.name = "RankedTab_" + id
		button.custom_minimum_size = Vector2(150, 44)
		button.pressed.connect(func(): show(main, id))
		tabs.add_child(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "RankedBoardRows"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	if profile.is_empty():
		list.add_child(MultiplayerUI.label("서버에서 랭킹을 받지 못했습니다. 연결을 확인하세요.", 15, MultiplayerUI.MUTED))
	else:
		match tab:
			"cards": _cards(list, profile)
			"seasons": _seasons(list, profile)
			_: _board(list, profile)
	MultiplayerUI.button(main, dialog, "닫기", "CloseRankedBoard", main._dismiss_action_overlay)

## Re-renders an open dialog when a newer profile arrives.
static func refresh(main) -> void:
	if is_instance_valid(main.action_overlay) and main.action_overlay.name == "RankedBoardOverlay":
		show(main, String(main.action_overlay.get_meta("tab", "board")))

static func _header(profile: Dictionary) -> String:
	if profile.is_empty():
		return "랭킹을 불러오는 중..."
	var text := "%s 시즌 · 매달 1일(UTC)에 새 시즌이 시작되고 점수가 1000점 쪽으로 절반 돌아갑니다." % season_name(String(profile.season))
	if int(profile.best) > 0:
		text += "\n내 점수 %d · 시즌 최고 %d · %d승 %d패 %d무" % [int(profile.rating), int(profile.best), int(profile.wins), int(profile.losses), int(profile.draws)]
	return text

static func _board(list: VBoxContainer, profile: Dictionary) -> void:
	var rows: Array = profile.leaderboard
	if rows.is_empty():
		list.add_child(MultiplayerUI.label("이번 시즌 랭크 대전 기록이 아직 없습니다.", 15, MultiplayerUI.MUTED))
	for index in rows.size():
		var row: Dictionary = rows[index]
		list.add_child(MultiplayerUI.label("%d. %s  ·  %d점  ·  %d승 %d패 %d무" % [index + 1, String(row.nickname), int(row.rating), int(row.wins), int(row.losses), int(row.draws)], 15, MultiplayerUI.GOLD if index < 3 else Color.WHITE))

static func _cards(list: VBoxContainer, profile: Dictionary) -> void:
	var matches := int(profile.card_matches)
	if matches == 0 or profile.cards.is_empty():
		list.add_child(MultiplayerUI.label("이번 시즌 랭크 대전 기록이 쌓이면 카드별 사용률·금지율·승률이 표시됩니다.", 15, MultiplayerUI.MUTED))
		return
	list.add_child(MultiplayerUI.label("이번 시즌 랭크 %d경기 · 사용률은 덱에 넣은 비율, 금지율은 상대에게 금지당한 비율입니다." % matches, 13, MultiplayerUI.MUTED))
	var grid := GridContainer.new()
	grid.name = "RankedCardStats"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	list.add_child(grid)
	for title in ["카드", "사용률", "금지율", "승률"]:
		grid.add_child(MultiplayerUI.label(title, 14, MultiplayerUI.GOLD))
	var decks := float(matches * 2)
	for row in profile.cards:
		var picks := int(row.picks)
		var decided := picks - int(row.draws)
		var name := String(BattleModel.UNIT_NAMES.get(row.kind, BattleModel.STRUCTURE_NAMES.get(row.kind, row.kind)))
		grid.add_child(MultiplayerUI.label(name, 14))
		grid.add_child(MultiplayerUI.label("%.0f%%" % (100.0 * float(picks) / decks), 14))
		grid.add_child(MultiplayerUI.label("%.0f%%" % (100.0 * float(row.bans) / decks), 14))
		var win := "—" if decided <= 0 else "%.0f%%" % (100.0 * float(row.wins) / float(decided))
		if picks < MIN_CARD_PICKS and decided > 0:
			win += " (표본 적음)"
		grid.add_child(MultiplayerUI.label(win, 14, MultiplayerUI.MUTED if picks < MIN_CARD_PICKS else Color.WHITE))

static func _seasons(list: VBoxContainer, profile: Dictionary) -> void:
	if profile.history.is_empty():
		list.add_child(MultiplayerUI.label("지난 시즌 기록이 없습니다. 시즌이 끝나면 최종 점수와 전적이 여기에 남습니다.", 15, MultiplayerUI.MUTED))
	for row in profile.history:
		list.add_child(MultiplayerUI.label("%s  ·  최종 %d점 (최고 %d)  ·  %d승 %d패 %d무" % [season_name(String(row.season)), int(row.rating), int(row.best), int(row.wins), int(row.losses), int(row.draws)], 15))
