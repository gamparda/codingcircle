extends RefCounted
## Replay list and player entry points (menu → 리플레이).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ChallengeReplays = preload("res://scripts/ChallengeReplays.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const ReplayViewer = preload("res://scripts/ui/ReplayViewer.gd")
const MenuScreens = preload("res://scripts/screens/MenuScreens.gd")
const DeckAnalysis = preload("res://scripts/DeckAnalysis.gd")
const GhostOpponent = preload("res://scripts/GhostOpponent.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
const ServerLink = preload("res://scripts/ServerLink.gd")
const ReplayRequest = preload("res://scripts/ui/ReplayRequest.gd")
const NetworkProtocol = preload("res://scripts/NetworkProtocol.gd")
const ServerReplayShelf = preload("res://scripts/ServerReplayShelf.gd")
const MetaStatsUI = preload("res://scripts/screens/MetaStatsUI.gd")
const REPLAY_LIST_SCREEN := preload("res://scenes/ui/ReplayListScreen.tscn")

static func describe(replay: Dictionary) -> Dictionary:
	var meta: Dictionary = replay.get("meta", {})
	var result: Dictionary = replay.get("result", {})
	var mode := String(meta.get("mode", ""))
	var title := "방 대전"
	if mode == "campaign":
		title = "캠페인 %d단계" % int(meta.get("stage", 1))
	elif mode == "practice":
		title = "연습 %d단계" % int(meta.get("stage", 1))
	elif mode == "daily":
		title = ("주간 도전 %s" if String(meta.get("period", "daily")) == "weekly" else "일일 도전 %s") % String(meta.get("date", ""))
	elif mode == "draft":
		title = "드래프트 %d단계" % int(meta.get("stage", 1))
	elif mode == "quick":
		title = "빠른 대전"
	var winner := int(result.get("winner", -1))
	var outcome := "무승부"
	if mode == "campaign" or mode == "practice" or mode == "daily" or mode == "draft":
		outcome = "승리" if winner == 0 else ("패배" if winner == 1 else "무승부")
	else:
		outcome = "블루 승" if winner == 0 else ("레드 승" if winner == 1 else "무승부")
	var clip := BattleReplay.clip_of(replay)
	if not clip.is_empty():
		title = "클립 ▸ %s" % String(clip.get("title", title))
	var seconds := int(float(result.get("elapsed", 0.0)))
	var range_text := ""
	var length_text := ""
	if not clip.is_empty():
		var hz := int(replay.get("hz", BattleReplay.DEFAULT_HZ))
		range_text = "%s–%s" % [_tick_time(int(clip.start), hz), _tick_time(int(clip.end), hz)]
		length_text = _tick_time(int(clip.end) - int(clip.start), hz)
	return {"title": title, "outcome": outcome, "winner": winner, "duration": "%02d:%02d" % [seconds / 60, seconds % 60], "notes": BattleReplay.notes_of(replay).size(), "clip_range": range_text, "clip_length": length_text}

static func _tick_time(tick: int, hz: int) -> String:
	var seconds := float(tick) / float(maxi(1, hz))
	return "%02d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

static func _shelf_entry(path: String, replay: Dictionary) -> Dictionary:
	var entry := {"path": path, "replay": replay, "order": BattleReplay._storage_order(replay), "mode": "unreadable", "winner": -1, "clip": false, "search": (_stamp(path) + " " + path.get_file()).to_lower()}
	if replay.is_empty():
		entry.search += " 읽기 실패 손상"
		return entry
	var meta: Dictionary = replay.get("meta", {})
	var mode := String(meta.get("mode", ""))
	entry.mode = ("weekly" if String(meta.get("period", "daily")) == "weekly" else "daily") if mode == "daily" else (mode if mode in ["campaign", "practice", "draft"] else "online")
	var info := describe(replay)
	entry.winner = int(info.winner) if int(info.winner) in [0, 1] else 2
	entry.clip = not BattleReplay.clip_of(replay).is_empty()
	var whole := replay.duplicate()
	whole.erase("clip")
	var base_info := describe(whole)
	var parts := PackedStringArray([_stamp(path), path.get_file(), String(info.title), String(base_info.title), String(info.outcome), String(info.duration), mode, String(entry.mode)])
	var date := String(meta.get("date", ""))
	if date.length() == 8:
		parts.append("%s-%s-%s" % [date.substr(0, 4), date.substr(4, 2), date.substr(6, 2)])
	if entry.clip:
		parts.append("클립 구간 %s 길이 %s" % [info.clip_range, info.clip_length])
	else:
		parts.append("전체 전투")
	for side in 2:
		for kind in replay.setup.unit_decks[side]:
			parts.append("%s %s" % [kind, BattleModel.UNIT_NAMES.get(kind, kind)])
		for kind in replay.setup.structure_decks[side]:
			var definition: Resource = load("res://data/structures/%s.tres" % kind)
			parts.append("%s %s" % [kind, definition.get("display_name")])
	for note in BattleReplay.notes_of(replay):
		parts.append(String(note.text))
	entry.search = " ".join(parts).to_lower()
	return entry

static func _stamp(path: String) -> String:
	var file := path.get_file()
	if file.length() >= 15 and file.substr(8, 1) == "_":
		return "%s-%s-%s  %s:%s" % [file.substr(0, 4), file.substr(4, 2), file.substr(6, 2), file.substr(9, 2), file.substr(11, 2)]
	return file.get_basename()

static func _build_replay_list(main) -> void:
	var frame = MenuScreens._show_scene(main, REPLAY_LIST_SCREEN, "리플레이", "저장된 전투를 다시 보고 분석합니다 (최근 %d개)" % BattleReplay.MAX_SAVED)
	var column: VBoxContainer = frame.column
	var status: Label = column.get_node("ReplayStatus")
	# Load once per visit, preserving the existing persisted order and path tie-break.
	var entries: Array = []
	var shown := 0
	var unreadable := 0
	for path in BattleReplay.list_saved(false):
		var replay := BattleReplay.load_file(path)
		entries.append(_shelf_entry(String(path), replay))
		if replay.is_empty():
			unreadable += 1
		else:
			shown += 1
	entries.sort_custom(func(a, b): return int(a.order) > int(b.order) or (int(a.order) == int(b.order) and String(a.path) > String(b.path)))
	frame.populate(entries, func(entry): return _unreadable_replay_card(main, String(entry.path)) if entry.replay.is_empty() else _replay_card(main, String(entry.path), entry.replay), main.replay_list_state)
	frame.refresh_requested.connect(main._build_replay_list)
	var notices := PackedStringArray()
	if unreadable > 0:
		notices.append("읽을 수 없는 리플레이 %d개가 있습니다. 자동 정리에서 제외하며, 파일을 보관하거나 목록에서 삭제할 수 있습니다." % unreadable)
	if shown > BattleReplay.MAX_SAVED:
		notices.append("리플레이 %d개를 보관 중입니다. 자동 정리를 완료하지 못했습니다. 파일 권한을 확인하고 정리를 다시 시도하세요." % shown)
		var retry := main._styled_button("오래된 리플레이 정리 재시도", UIKit.GOLD_DEEP, false) as Button
		retry.name = "RetryReplayCleanup"
		column.add_child(retry)
		column.move_child(retry, column.get_node("Footer").get_index())
		retry.pressed.connect(func():
			BattleReplay._prune()
			main._build_replay_list())
	status.text = "\n".join(notices)
	var back: Button = column.get_node("Footer/ReplayBack")
	UIKit.style_button(back, Color("#697386"), false, 16)
	back.text = Localization.text("메인 화면으로")
	back.pressed.connect(main._build_connect_screen)
	var import_button: Button = column.get_node("Footer/ImportReplayButton")
	UIKit.style_button(import_button, UIKit.TEAL, false, 16)
	import_button.text = Localization.text("클립보드에서 가져오기")
	import_button.pressed.connect(func():
		var message := import_text(main, DisplayServer.clipboard_get())
		# import_text may have rebuilt the shelf; the previous frame is queued for deletion.
		var current_status := main.root_background.find_child("ReplayStatus", true, false) as Label
		if current_status != null and not current_status.text.begins_with(message):
			current_status.text = message + ("\n" + current_status.text if not current_status.text.is_empty() else ""))
	var analysis_button := Button.new()
	analysis_button.name = "DeckAnalysisButton"
	analysis_button.text = Localization.text("덱 분석")
	analysis_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.style_button(analysis_button, UIKit.GOLD_DEEP, false, 16)
	column.get_node("Footer").add_child(analysis_button)
	analysis_button.pressed.connect(func(): _show_deck_analysis(main))
	var code_button := Button.new()
	code_button.name = "OpenByCodeButton"
	code_button.text = Localization.text("코드로 열기")
	code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.style_button(code_button, UIKit.TEAL, false, 16)
	column.get_node("Footer").add_child(code_button)
	code_button.pressed.connect(func(): _show_code_dialog(main))
	var recent_button := Button.new()
	recent_button.name = "RecentBattlesButton"
	recent_button.text = Localization.text("최근 온라인 전투")
	recent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.style_button(recent_button, UIKit.ACCENT, false, 16)
	column.get_node("Footer").add_child(recent_button)
	recent_button.pressed.connect(func(): _show_recent_battles(main))

static func _delete_replay(main, path: String) -> void:
	# Keep the existing card (and its retry button) when removal fails.
	if DirAccess.dir_exists_absolute(path) or (FileAccess.file_exists(path) and DirAccess.remove_absolute(path) != OK):
		var status := main.find_child("ReplayStatus", true, false) as Label
		if status != null:
			status.text = "리플레이를 삭제하지 못했습니다. 파일 권한을 확인하고 삭제를 다시 시도하세요."
			status.tooltip_text = ProjectSettings.globalize_path(path)
		return
	main._build_replay_list()

static func _delete_button(main, path: String) -> Button:
	var button: Button = main._styled_button("삭제", UIKit.DANGER, false)
	button.name = "DeleteReplayButton"
	button.custom_minimum_size = Vector2(80, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 46)
	button.pressed.connect(func(): _delete_replay(main, path))
	return button

static func _unreadable_replay_card(main, path: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "UnreadableReplayCard"
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE, UIKit.SURFACE, UIKit.DANGER, 12), 14, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "읽을 수 없는 리플레이\n%s\n파일이 손상되었거나 지원하지 않는 형식입니다." % path.get_file()
	label.tooltip_text = ProjectSettings.globalize_path(path)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	row.add_child(_delete_button(main, path))
	card.add_child(row)
	return card

## Overlay with one row per deck I have played: record, average length, hardest stage and advice.
static func _show_deck_analysis(main) -> void:
	var dialog = main._action_panel("덱 분석", Rect2(150, 50, 980, 620))
	var rows: Array = DeckAnalysis.collect(BattleReplay.list_saved())
	var global_box := VBoxContainer.new()
	global_box.name = "GlobalDeckStats"
	global_box.add_theme_constant_override("separation", 3)
	dialog.add_child(global_box)
	MetaStatsUI.fill_global_card(global_box)
	dialog.add_child(MetaStatsUI.share_toggle(main))
	var decks: Array = rows.map(func(row): return row.deck)
	ServerLink.run(main, func(): main.network.send_stats_request(decks), Callable(), false)
	var scroll := ScrollContainer.new()
	scroll.name = "DeckAnalysisScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dialog.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "DeckAnalysisRows"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	if rows.is_empty():
		var empty := Label.new()
		empty.name = "NoDeckAnalysis"
		empty.text = Localization.text("분석할 전투가 없습니다. 캠페인이나 연습 전투를 치르면 덱별 기록이 쌓입니다.")
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		list.add_child(empty)
	for row in rows:
		list.add_child(_analysis_row(row))
	var refresh := func(_data):
		if not is_instance_valid(global_box):
			return
		MetaStatsUI.fill_global_card(global_box)
		for label in list.find_children("DeckGlobalLine", "Label", true, false):
			label.text = Localization.text(MetaStats.record_text(MetaStats.deck_record(label.get_meta("deck"))))
	main.network.meta_stats_received.connect(refresh)
	global_box.tree_exited.connect(func(): if main.network.meta_stats_received.is_connected(refresh): main.network.meta_stats_received.disconnect(refresh))
	MultiplayerUI.button(main, dialog, "닫기", "CloseDeckAnalysis", main._dismiss_action_overlay)

static func _analysis_row(row: Dictionary) -> Control:
	var tone := UIKit.SUCCESS if float(row.win_rate) >= 0.6 else (UIKit.GOLD if float(row.win_rate) >= 0.35 else UIKit.DANGER)
	var card := PanelContainer.new()
	card.name = "DeckAnalysisRow"
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(tone.r, tone.g, tone.b, 0.45), 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 16, 10))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 16)
	card.add_child(line)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 0)
	line.add_child(icons)
	for kind in row.deck:
		var icon := TextureRect.new()
		icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
		icon.custom_minimum_size = Vector2(44, 58)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icons.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 4)
	line.add_child(text)
	var headline := Label.new()
	headline.name = "DeckAnalysisHeadline"
	headline.text = Localization.text("%d판  %d승 %d패 %d무  ·  평균 %d:%02d") % [int(row.games), int(row.wins), int(row.losses), int(row.draws), int(row.average_seconds) / 60, int(row.average_seconds) % 60]
	headline.add_theme_font_size_override("font_size", 15)
	text.add_child(headline)
	var bar := HpBar.new()
	bar.color = tone
	bar.pulse_below = 0.0
	bar.show_ticks = false
	bar.custom_minimum_size = Vector2(0, 8)
	bar.max_value = 1.0
	bar.value = float(row.win_rate)
	text.add_child(bar)
	var notes := PackedStringArray()
	if not row.hardest_stage.is_empty():
		notes.append(Localization.text("가장 어려운 단계: %d단계 (승률 %d%%)") % [int(row.hardest_stage.stage), roundi(float(row.hardest_stage.rate) * 100.0)])
	if not row.tips.is_empty():
		notes.append(String(row.tips[0]))
	var detail := Label.new()
	detail.text = "  ·  ".join(notes)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	text.add_child(detail)
	var global_line := Label.new()
	global_line.name = "DeckGlobalLine"
	global_line.set_meta("deck", row.deck)
	global_line.text = Localization.text(MetaStats.record_text(MetaStats.deck_record(row.deck)))
	global_line.add_theme_font_size_override("font_size", 12)
	global_line.add_theme_color_override("font_color", UIKit.TEAL)
	text.add_child(global_line)
	var rate := Label.new()
	rate.text = "%d%%" % roundi(float(row.win_rate) * 100.0)
	UIKit.display(rate, 30, tone.lightened(0.3))
	line.add_child(rate)
	return card

static func _replay_card(main, path: String, replay: Dictionary) -> Control:
	var info := describe(replay)
	var tone := UIKit.SUCCESS if info.outcome in ["승리", "블루 승"] else (UIKit.DANGER if info.outcome in ["패배", "레드 승"] else UIKit.TEXT_MUTED)
	var card := PanelContainer.new()
	card.name = "ReplayCard"
	card.custom_minimum_size.y = 84
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(tone.r, tone.g, tone.b, 0.45), 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 16, 10))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	content.add_child(row)
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(86, 0)
	chip.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(Color(tone.r, tone.g, tone.b, 0.22), Color(tone.r, tone.g, tone.b, 0.08), Color(tone.r, tone.g, tone.b, 0.8), 10, 1.0, 0.0, Color(0, 0, 0, 0), 0.0), 8, 6))
	row.add_child(chip)
	var outcome := Label.new()
	outcome.text = String(info.outcome)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.display(outcome, 18, tone.lightened(0.4))
	chip.add_child(outcome)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := Label.new()
	title.text = String(info.title)
	if String(info.clip_range).is_empty():
		title.text += "  ·  %s" % info.duration
	if int(info.notes) > 0:
		title.text += Localization.text("  ·  메모 %d개") % int(info.notes)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 18)
	text.add_child(title)
	if not String(info.clip_range).is_empty():
		var range_label := Label.new()
		range_label.name = "ReplayClipRange"
		range_label.text = "구간 %s · 길이 %s" % [info.clip_range, info.clip_length]
		range_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		range_label.add_theme_font_size_override("font_size", 14)
		range_label.add_theme_color_override("font_color", UIKit.GOLD)
		range_label.tooltip_text = "전체 전투 %s 중의 공유 구간입니다. 클립의 승패·덱·메모는 전체 전투 기준이며 끝에서 재생을 누르면 이어서 볼 수 있습니다." % info.duration
		text.add_child(range_label)
	var stamp := Label.new()
	stamp.text = _stamp(path)
	stamp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stamp.tooltip_text = ProjectSettings.globalize_path(path)
	stamp.add_theme_font_size_override("font_size", 12)
	stamp.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	text.add_child(stamp)
	for side in 2:
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 2)
		deck_row.tooltip_text = "블루 덱" if side == 0 else "레드 덱"
		row.add_child(deck_row)
		for kind in replay.setup.unit_decks[side]:
			var icon := TextureRect.new()
			icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
			icon.custom_minimum_size = Vector2(34, 46)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			deck_row.add_child(icon)
		if side == 0:
			var versus := Label.new()
			versus.text = "VS"
			versus.add_theme_color_override("font_color", UIKit.TEXT_DIM)
			row.add_child(versus)
	# Keep all actions reachable within the shelf width, including on touch devices.
	var actions := HBoxContainer.new()
	actions.name = "ReplayCardActions"
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var action_height := UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 46.0
	var play = main._styled_button("재생", UIKit.ACCENT, true)
	play.name = "PlayReplayButton"
	play.custom_minimum_size = Vector2(100, action_height)
	play.pressed.connect(main._play_replay.bind(path))
	actions.add_child(play)
	if GhostOpponent.playable(replay):
		var ghost = main._styled_button("고스트 도전", UIKit.ACCENT, false)
		ghost.name = "GhostReplayButton"
		ghost.custom_minimum_size = Vector2(120, action_height)
		ghost.tooltip_text = Localization.text("이 리플레이의 상대 플레이어를 고스트로 두고 직접 싸워 봅니다")
		ghost.pressed.connect(main._start_ghost_battle.bind(replay))
		actions.add_child(ghost)
	var code_share = main._styled_button("코드", UIKit.ACCENT, false)
	code_share.name = "ShareCodeButton"
	code_share.custom_minimum_size = Vector2(80, action_height)
	code_share.tooltip_text = Localization.text("서버에 올리고 6자리 코드로 공유합니다 (필요하면 자동으로 접속합니다)")
	code_share.pressed.connect(func(): _share_by_code(main, replay, code_share))
	actions.add_child(code_share)
	var share = main._styled_button("복사", UIKit.TEAL, false)
	share.name = "ShareReplayButton"
	share.custom_minimum_size = Vector2(80, action_height)
	share.tooltip_text = Localization.text("공유용 텍스트를 클립보드에 복사합니다")
	share.pressed.connect(func():
		DisplayServer.clipboard_set(BattleReplay.to_share_text(replay))
		share.text = "복사됨 ✓")
	actions.add_child(share)
	actions.add_child(_delete_button(main, path))
	return card

## Asks for a six-letter code and plays the replay it names.
static func _show_code_dialog(main) -> void:
	var dialog = main._action_panel("코드로 열기", Rect2(340, 150, 600, 420))
	dialog.add_child(MultiplayerUI.label("공유받은 6자리 코드를 입력하세요. 필요하면 자동으로 서버에 접속합니다.", 14, MultiplayerUI.MUTED))
	var input := LineEdit.new()
	input.name = "ReplayCodeInput"
	input.max_length = 6
	input.placeholder_text = "ABC234"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 28)
	input.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	input.text_changed.connect(func(text): input.text = text.to_upper(); input.caret_column = input.text.length())
	dialog.add_child(input)
	var status := MultiplayerUI.label("", 14, MultiplayerUI.GOLD)
	status.name = "ReplayCodeStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(status)
	var open_button: Button = main._styled_button("열기", UIKit.ACCENT, true)
	open_button.name = "OpenReplayCode"
	open_button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	dialog.add_child(open_button)
	var pending := {"active": false}
	var open_code := func():
		if bool(pending.active):
			return
		var code := input.text.strip_edges().to_upper()
		if not main.network.is_valid_room_code(code):
			status.text = "영문 대문자와 숫자로 된 6자리 코드를 확인하세요."
			input.grab_focus()
			return
		pending.active = true
		open_button.disabled = true
		input.editable = false
		var fail := func(text: String):
			pending.active = false
			open_button.disabled = false
			input.editable = true
			status.text = Localization.text(text)
		var result := func(text: String):
			var replay := BattleReplay.from_share_text(text)
			if replay.is_empty():
				fail.call(Localization.text("%s 코드의 리플레이를 찾을 수 없습니다.") % code)
				return
			main._dismiss_action_overlay()
			_play_replay_data(main, replay)
		ReplayRequest.start(main, dialog, "fetch", code, result, fail, func(text): status.text = Localization.text(text))
	open_button.pressed.connect(open_code)
	input.text_submitted.connect(func(_text): open_code.call())
	var close := MultiplayerUI.button(main, dialog, "닫기", "CloseReplayCode", main._dismiss_action_overlay)
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	input.grab_focus()

## Lists the most recent online matches the server has shelved; each can be watched directly.
static func _show_recent_battles(main, return_code: String = "") -> void:
	var return_focus: Control = main.get_viewport().gui_get_focus_owner()
	var dialog = main._action_panel("최근 온라인 전투", Rect2(190, 60, 900, 600))
	var policy := MultiplayerUI.label("공개 전투는 최근 %d개를 표시합니다. 서버는 공유 코드·공개 전투를 합쳐 최근 %d개를 보관하며, 새 전투나 공유 업로드로 오래된 코드가 정리될 수 있습니다. 고정 만료 시간은 없습니다. 계속 보려면 보기 → 로컬 보관을 이용하세요. 시각은 UTC 기준이며 전투 시작 시각이 아닌 서버 보관 시각입니다." % [ServerReplayShelf.RECENT_LIMIT, ServerReplayShelf.MAX_STORED], 14, UIKit.TEXT_MUTED)
	policy.name = "RecentBattlesPolicy"
	policy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(policy)
	var status := MultiplayerUI.label("", 14, MultiplayerUI.GOLD)
	status.name = "RecentBattlesStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(status)
	var state: Dictionary = main.recent_battles_state
	var search_tools := HBoxContainer.new()
	search_tools.add_theme_constant_override("separation", 8)
	dialog.add_child(search_tools)
	var search := LineEdit.new()
	search.name = "RecentBattleSearch"
	search.placeholder_text = "보관 날짜·코드·병력 검색"
	search.tooltip_text = "조회된 최근 공개 전투 안에서 검색합니다. 공백으로 나눈 검색어를 모두 포함해야 합니다. 예: 2026-10-13 방패병 / ABC234 / archer"
	search.max_length = 160
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	search.text = String(state.get("query", ""))
	search_tools.add_child(search)
	var reset: Button = main._styled_button("초기화", UIKit.TEAL, false)
	reset.name = "ResetRecentBattleFilters"
	reset.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	search_tools.add_child(reset)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	dialog.add_child(filters)
	var mode := OptionButton.new()
	mode.name = "RecentBattleModeFilter"
	for label in ["종류 전체", "빠른 대전", "방 대전"]:
		mode.add_item(label)
	mode.select(clampi(int(state.get("mode", 0)), 0, 2))
	mode.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	filters.add_child(mode)
	var outcome := OptionButton.new()
	outcome.name = "RecentBattleOutcomeFilter"
	for label in ["결과 전체", "블루 승", "레드 승", "무승부"]:
		outcome.add_item(label)
	outcome.select(clampi(int(state.get("outcome", 0)), 0, 3))
	outcome.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	outcome.tooltip_text = "모든 전투의 블루·레드 진영 기준 결과입니다. 내 전적의 승리·패배가 아닙니다."
	filters.add_child(outcome)
	var count := MultiplayerUI.label("목록 수신 대기", 14, UIKit.TEXT_MUTED)
	count.name = "RecentBattleMatchCount"
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.tooltip_text = "서버에서 조회한 최근 공개 전투 안의 검색 결과입니다. 전체 보관 전투를 검색하지 않습니다. 날짜는 UTC 보관 시각 기준이며 추정 시각도 포함합니다."
	filters.add_child(count)
	var scroll := ScrollContainer.new()
	scroll.name = "RecentBattlesScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "RecentBattleRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	dialog.add_child(footer)
	var refresh: Button = main._styled_button("새로고침", UIKit.ACCENT, false)
	refresh.name = "RefreshRecentBattles"
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	refresh.tooltip_text = "서버에서 최신 공개 목록을 다시 조회합니다. 검색 조건과 스크롤 위치는 유지합니다."
	footer.add_child(refresh)
	var close_dialog := func():
		if not _dialog_alive(dialog): return
		main._dismiss_action_overlay()
		if is_instance_valid(return_focus) and return_focus.is_inside_tree():
			return_focus.grab_focus.call_deferred()
	var close := MultiplayerUI.button(main, footer, "닫기", "CloseRecentBattles", close_dialog)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	var filter_controls: Array[Control] = [search, reset, mode, outcome]
	var pending := {"active": false, "revision": 0, "loaded": false, "restoring": false, "entries": []}
	var empty := MultiplayerUI.label("", 16, UIKit.TEXT_MUTED)
	empty.name = "NoRecentBattleMatches"
	empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	empty.visible = false
	rows.add_child(empty)
	var apply_filters := func(reset_scroll: bool):
		if not _dialog_alive(dialog): return
		pending.revision = int(pending.revision) + 1
		var revision := int(pending.revision)
		state["query"] = search.text
		state["mode"] = mode.selected
		state["outcome"] = outcome.selected
		reset.disabled = search.text.is_empty() and mode.selected == 0 and outcome.selected == 0
		var focus: Control = main.get_viewport().gui_get_focus_owner()
		var hidden_focus := false
		var shown := 0
		for item in pending.entries:
			var row: Control = item.card
			row.visible = _recent_matches(item.entry, String(item.search), search.text, mode.selected, outcome.selected)
			if row.visible: shown += 1
			elif focus != null and row.is_ancestor_of(focus): hidden_focus = true
		count.text = "%d / %d개 표시" % [shown, pending.entries.size()] if bool(pending.loaded) else "목록 수신 대기"
		empty.visible = bool(pending.loaded) and shown == 0
		empty.text = "현재 공개 목록에 보관된 전투가 없습니다. 미저장·정리된 전투는 표시되지 않습니다." if pending.entries.is_empty() else "검색 조건에 맞는 전투가 없습니다. 검색어·종류·결과를 바꾸거나 초기화하세요. 검색은 조회된 최근 공개 전투 안에서만 수행합니다."
		_bind_recent_navigation(scroll, rows, refresh, close, close_dialog, filter_controls)
		if hidden_focus: search.grab_focus()
		if reset_scroll: state["scroll"] = 0
		# An empty waiting list must not clamp a saved viewport before its first response.
		if not bool(pending.loaded): return
		var position := int(state.get("scroll", 0))
		pending.restoring = true
		var restore := func():
			if not _dialog_alive(dialog) or revision != int(pending.revision): return
			scroll.scroll_vertical = position
			state["scroll"] = scroll.scroll_vertical
			pending.restoring = false
		dialog.get_tree().process_frame.connect(restore, CONNECT_ONE_SHOT)
	search.text_changed.connect(func(_text): apply_filters.call(true))
	mode.item_selected.connect(func(_index): apply_filters.call(true))
	outcome.item_selected.connect(func(_index): apply_filters.call(true))
	reset.pressed.connect(func():
		search.text = ""
		mode.select(0)
		outcome.select(0)
		apply_filters.call(true)
		search.grab_focus())
	scroll.get_v_scroll_bar().value_changed.connect(func(value):
		if bool(pending.loaded) and not bool(pending.restoring): state["scroll"] = int(value))
	var play := func(replay: Dictionary, code: String):
		if not _dialog_alive(dialog): return
		# Keep navigation data only; never retain the overlay or a downloaded replay.
		if not bool(pending.restoring): state["scroll"] = scroll.scroll_vertical
		pending.revision = int(pending.revision) + 1
		_open_viewer(main, replay, "", _return_to_recent_battles.bind(main, code), "최근 온라인 전투 목록으로 돌아갑니다. 검색·종류·결과·스크롤과 선택 카드 초점을 유지합니다.")
	var show_list := func(list: Array, from_cache: bool = false):
		pending.active = false
		refresh.disabled = false
		var focus: Control = main.get_viewport().gui_get_focus_owner()
		var focused_code := return_code if from_cache else ""
		var focused_action := "WatchRecentBattle" if from_cache else ""
		if focus != null and rows.is_ancestor_of(focus):
			focused_code = String(focus.get_meta("ReplayCode", ""))
			focused_action = String(focus.name)
		# Keep the saved position on the first response, and the current viewport on refresh.
		if bool(pending.loaded) and not bool(pending.restoring): state["scroll"] = scroll.scroll_vertical
		pending.restoring = true
		pending.loaded = true
		pending.entries = []
		for child in rows.get_children():
			rows.remove_child(child)
			if child != empty: child.queue_free()
		var now := int(state.get("queried_at", 0)) if from_cache else int(Time.get_unix_time_from_system())
		if not from_cache:
			# Cache only a successful response, including an explicitly empty list.
			state["snapshot"] = list.duplicate(true)
			state["queried_at"] = now
		status.text = ("재생 전 조회 목록 · 최신 목록은 새로고침\n" if from_cache else "") + "공개 전투 %d개 · 최신 보관순 · 조회 %s UTC" % [list.size(), Time.get_datetime_string_from_unix_time(now).replace("T", " ")]
		var next_focus: Control = null
		for entry in list:
			var row := _recent_row(main, entry, now, play)
			rows.add_child(row)
			pending.entries.append({"entry": entry, "search": _recent_search_text(entry), "card": row})
			if String(entry.code) == focused_code:
				next_focus = row.find_child(focused_action, true, false) as Control
		rows.add_child(empty)
		apply_filters.call(false)
		var revision := int(pending.revision)
		# Refresh keeps the viewport and surviving focused code, rather than jumping to the top.
		var restore := func():
			if not _dialog_alive(dialog) or revision != int(pending.revision): return
			var position := int(state.get("scroll", 0))
			pending.restoring = true
			if is_instance_valid(next_focus) and next_focus.is_visible_in_tree(): next_focus.grab_focus()
			elif not focused_code.is_empty(): scroll.grab_focus()
			scroll.scroll_vertical = position
			state["scroll"] = scroll.scroll_vertical
			pending.restoring = false
		dialog.get_tree().process_frame.connect(restore, CONNECT_ONE_SHOT)
	var request := func():
		if bool(pending.active):
			return
		pending.active = true
		refresh.disabled = true
		var fail := func(text: String):
			pending.active = false
			refresh.disabled = false
			status.text = ("목록 갱신 실패 · 이전 조회 목록과 검색 조건을 유지합니다.\n" if bool(pending.loaded) else "") + Localization.text(text)
		ReplayRequest.start(main, dialog, "recent", "", show_list, fail, func(text): status.text = Localization.text(text))
	refresh.pressed.connect(request)
	apply_filters.call(false)
	if not return_code.is_empty() and state.has("snapshot"):
		# Returning must work offline and keep the same cards until an explicit refresh.
		# Do not queue an initial scroll focus that could run after card focus restoration.
		scroll.grab_focus()
		show_list.call(state.snapshot, true)
	else:
		scroll.grab_focus.call_deferred()
		request.call()

static func _return_to_recent_battles(main, code: String) -> void:
	main._build_replay_list()
	var entry_button := main.root_background.find_child("RecentBattlesButton", true, false) as Button
	if entry_button != null: entry_button.grab_focus()
	_show_recent_battles(main, code)

## Search the received snapshot only; no replay downloads or inferred dates per keystroke.
static func _recent_search_text(entry: Dictionary) -> String:
	var winner := int(entry.get("winner", -1))
	var seconds := int(entry.get("ticks", 0)) / BattleReplay.DEFAULT_HZ
	var parts := PackedStringArray([String(entry.code), String(entry.get("mode", "")),
		"빠른 대전" if entry.get("mode", "") == "quick" else "방 대전",
		"블루 승" if winner == 0 else ("레드 승" if winner == 1 else "무승부"),
		"%02d:%02d" % [seconds / 60, seconds % 60]])
	var stored_at = entry.get("stored_at")
	if NetworkProtocol._number_in_range(stored_at, 1, 9e9) and float(stored_at) == floorf(float(stored_at)):
		var stamp := Time.get_datetime_string_from_unix_time(int(stored_at)).replace("T", " ")
		parts.append(stamp)
		parts.append(stamp.substr(0, 10).replace("-", ""))
		var estimated = entry.get("stored_at_estimated", true)
		parts.append("보관 시각 추정" if not estimated is bool or bool(estimated) else "서버 보관")
	else:
		parts.append("보관 시각 미상")
	for side in 2:
		for kind in entry.units[side]:
			parts.append("%s %s" % [kind, BattleModel.UNIT_NAMES.get(kind, kind)])
	return " ".join(parts).to_lower()

static func _recent_matches(entry: Dictionary, text: String, query: String, mode: int, outcome: int) -> bool:
	if mode > 0 and (entry.get("mode", "") == "quick") != (mode == 1): return false
	var winner := int(entry.get("winner", -1))
	if outcome > 0 and (winner if winner in [0, 1] else 2) != outcome - 1: return false
	for term in query.to_lower().replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false):
		if not text.contains(term): return false
	return true

## Age is frozen at the explicitly displayed lookup time; a future clock is never "just now".
static func _recent_time_info(entry: Dictionary, now: int) -> Dictionary:
	var stored_at = entry.get("stored_at")
	if not NetworkProtocol._number_in_range(stored_at, 1, 9e9) or float(stored_at) != floorf(float(stored_at)):
		return {"text": "보관 시각 미상", "tooltip": "이 서버는 유효한 보관 시각을 제공하지 않았습니다. 전투 시간이나 코드로 날짜를 추정하지 않습니다."}
	var stamp := Time.get_datetime_string_from_unix_time(int(stored_at)).replace("T", " ") + " UTC"
	var estimated = entry.get("stored_at_estimated", true)
	var prefix := "보관 시각 추정" if not estimated is bool or bool(estimated) else "서버 보관"
	var difference := now - int(stored_at)
	var age := ""
	if difference < 0:
		age = "기기 시계보다 미래 · 시계 확인 필요"
	elif difference < 60:
		age = "조회 시 1분 미만 경과"
	elif difference < 3600:
		age = "조회 시 %d분 경과" % (difference / 60)
	elif difference < 86400:
		age = "조회 시 %d시간 %d분 경과" % [difference / 3600, (difference % 3600) / 60]
	else:
		age = "조회 시 %d일 %d시간 경과" % [difference / 86400, (difference % 86400) / 3600]
	var explanation := "확인된 보관 시각이 아닙니다. 이전 서버 파일의 수정 시각 등을 사용한 추정값이며 원래 보관 시각과 다를 수 있습니다." if prefix == "보관 시각 추정" else "서버에서 코드가 처음 보관된 시각입니다. 전투 시작·종료 시각과 다를 수 있습니다."
	return {"text": "%s %s · %s" % [prefix, stamp, age], "tooltip": explanation + " 경과 시간은 목록 조회 당시 기기 시계로 계산하며 만료 시간은 아닙니다. 새로고침하면 다시 계산합니다."}

static func _recent_row(main, entry: Dictionary, now: int = -1, on_watch: Callable = Callable()) -> Control:
	var card := PanelContainer.new()
	card.name = "RecentBattleRow"
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE_SOFT, 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 14, 8))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	card.add_child(content)
	var winner := int(entry.get("winner", -1))
	var seconds := int(entry.get("ticks", 0)) / BattleReplay.DEFAULT_HZ
	var title := MultiplayerUI.label("%s · %s · 전투 %02d:%02d" % ["빠른 대전" if entry.get("mode", "") == "quick" else "방 대전", "블루 승" if winner == 0 else ("레드 승" if winner == 1 else "무승부"), seconds / 60, seconds % 60], 16, UIKit.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(title)
	var time_info := _recent_time_info(entry, int(Time.get_unix_time_from_system()) if now < 0 else now)
	var stamp := MultiplayerUI.label(String(time_info.text), 14, UIKit.GOLD)
	stamp.name = "RecentBattleStoredAt"
	stamp.tooltip_text = String(time_info.tooltip)
	stamp.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(stamp)
	for side in 2:
		var deck_names := " · ".join(PackedStringArray(entry.units[side].map(func(kind): return String(BattleModel.UNIT_NAMES.get(kind, kind)))))
		var deck := MultiplayerUI.label("%s: %s" % ["블루" if side == 0 else "레드", deck_names], 14, UIKit.TEXT_MUTED)
		deck.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(deck)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	content.add_child(line)
	var code: Button = main._styled_button("%s · 코드 복사" % String(entry.code), UIKit.GOLD_DEEP, false)
	code.name = "CopyRecentBattleCode"
	code.set_meta("ReplayCode", String(entry.code))
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	code.tooltip_text = "코드만 복사합니다. 서버에서 정리된 코드는 열 수 없으므로 계속 보려면 보기 → 로컬 보관을 이용하세요."
	code.pressed.connect(func():
		if not _dialog_alive(card): return
		if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			code.tooltip_text = "이 환경에서는 클립보드를 사용할 수 없습니다. 표시된 코드를 직접 입력하세요."
			code.text = "%s · 복사 불가" % String(entry.code)
			return
		DisplayServer.clipboard_set(String(entry.code))
		code.text = "%s · 복사됨" % String(entry.code))
	line.add_child(code)
	var watch = main._styled_button("보기", UIKit.ACCENT, true)
	watch.name = "WatchRecentBattle"
	watch.set_meta("ReplayCode", String(entry.code))
	watch.custom_minimum_size = Vector2(110, UIKit.TOUCH_MIN_HEIGHT)
	watch.pressed.connect(func():
		if not _dialog_alive(card) or watch.disabled:
			return
		watch.disabled = true
		var fail := func(message: String):
			watch.disabled = false
			watch.text = "재시도"
			watch.tooltip_text = Localization.text(message)
			var status = main.root_background.find_child("RecentBattlesStatus", true, false)
			if status is Label:
				status.text = Localization.text(message)
		var result := func(replay_text: String):
			var replay := BattleReplay.from_share_text(replay_text)
			if replay.is_empty():
				fail.call("리플레이를 찾을 수 없습니다. 서버에서 정리되었거나 읽을 수 없는 전투입니다. 목록을 새로고침하거나 다른 전투를 선택하세요.")
				return
			if on_watch.is_valid():
				on_watch.call(replay, String(entry.code))
			else:
				main._dismiss_action_overlay()
				_play_replay_data(main, replay)
		ReplayRequest.start(main, watch, "fetch", String(entry.code), result, fail, func(_text): watch.text = "불러오는 중"))
	line.add_child(watch)
	return card

static func _bind_recent_navigation(scroll: ScrollContainer, rows: VBoxContainer, refresh: Button, close: Button, close_dialog: Callable, filter_controls: Array[Control] = []) -> void:
	var controls: Array[Control] = []
	for control in filter_controls:
		if control is BaseButton and (control as BaseButton).disabled: continue
		controls.append(control)
	controls.append(scroll)
	for row in rows.get_children():
		if not row.visible: continue
		for button_name in ["CopyRecentBattleCode", "WatchRecentBattle"]:
			var button := row.find_child(button_name, true, false) as Control
			if button != null: controls.append(button)
	controls.append(refresh)
	controls.append(close)
	for index in controls.size():
		var control := controls[index]
		control.focus_previous = control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		# Persistent footer/scroll controls are rebound after refresh without accumulating handlers.
		if control.has_meta("RecentNavigationBound"): continue
		control.set_meta("RecentNavigationBound", true)
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close_dialog.call())
	if scroll.has_meta("RecentScrollBound"): return
	scroll.set_meta("RecentScrollBound", true)
	scroll.gui_input.connect(func(event: InputEvent):
		if not event is InputEventKey or not event.pressed or event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return
		var bar := scroll.get_v_scroll_bar()
		var target := scroll.scroll_vertical
		match event.keycode:
			KEY_UP: target -= 48
			KEY_DOWN: target += 48
			KEY_PAGEUP: target -= maxi(48, int(bar.page))
			KEY_PAGEDOWN: target += maxi(48, int(bar.page))
			KEY_HOME: target = 0
			KEY_END: target = int(bar.max_value - bar.page)
			_: return
		scroll.scroll_vertical = clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
		scroll.accept_event())

## Uploads a replay for a share code, connecting to the server first when needed.
static func _share_by_code(main, replay: Dictionary, button: Button) -> void:
	if button.disabled:
		return
	var text := BattleReplay.to_share_text(replay)
	if text.is_empty():
		button.tooltip_text = "공유할 수 없는 리플레이입니다."
		return
	var digest := text.sha256_text()
	if String(button.get_meta("ReplayShareDigest", "")) == digest:
		DisplayServer.clipboard_set(String(button.get_meta("ReplayShareCode", "")))
		button.tooltip_text = Localization.text("공유 코드를 복사했습니다.")
		return
	button.disabled = true
	var fail := func(message: String):
		button.disabled = false
		button.text = "접속 실패" if message.contains("접속") else "재시도"
		button.tooltip_text = Localization.text(message)
		var status = main.root_background.find_child("ReplayStatus", true, false)
		if status is Label:
			status.text = Localization.text(message)
	var on_code := func(code: String):
		if code.is_empty():
			fail.call("서버가 리플레이를 보관하지 못했습니다. 다시 누르거나 복사 버튼으로 공유하세요.")
			return
		button.disabled = false
		button.text = code
		button.set_meta("ReplayShareDigest", digest)
		button.set_meta("ReplayShareCode", code)
		button.tooltip_text = Localization.text("공유 코드를 복사했습니다.")
		DisplayServer.clipboard_set(code)
	ReplayRequest.start(main, button, "upload", text, on_code, fail, func(message):
		button.text = "접속 중" if message.contains("접속") else "발급 중"
		button.tooltip_text = Localization.text(message))

## Saves a pasted share text as a replay. Returns the message to show the player.
static func import_text(main, text: String) -> String:
	var replay := BattleReplay.from_share_text(text)
	if replay.is_empty():
		return Localization.text("가져올 수 없습니다. 복사한 리플레이 텍스트가 맞는지 확인하세요.")
	var meta: Dictionary = replay.get("meta", {})
	meta["imported"] = true
	replay["meta"] = meta
	var path := BattleReplay.save(replay, "imported")
	if path == "":
		return Localization.text("저장하지 못했습니다.")
	# A successful import should reveal the new record even if a filter hid its kind.
	main.replay_list_state.clear()
	main._build_replay_list()
	var status = main.root_background.find_child("ReplayStatus", true, false)
	var verdict := BattleReplay.verify(replay)
	var message := Localization.text("리플레이를 가져왔습니다.") if bool(verdict.ok) else Localization.text("가져왔지만 현재 규칙에서는 기록과 결과가 달라질 수 있습니다.")
	if status is Label:
		status.text = message + ("\n" + status.text if not status.text.is_empty() else "")
	return message

## Shared replays are kept locally on request or when the first note is made.
static func _play_replay_data(main, replay: Dictionary) -> void:
	_open_viewer(main, replay, "")

static func _play_replay(main, path: String) -> void:
	var replay := BattleReplay.load_file(path)
	if replay.is_empty():
		main._build_replay_list()
		return
	_open_viewer(main, replay, path)

static func _open_viewer(main, replay: Dictionary, path: String, return_to: Callable = Callable(), return_hint: String = "") -> void:
	if not main.save_data.is_empty():
		preload("res://scripts/Goals.gd").mark(main.save_data, "watch_replay")
		main._save_profile()
	main.battle_active = false
	main._clear_screen()
	main.root_background = main._make_background()
	var info := describe(replay)
	var viewer := ReplayViewer.new()
	viewer.open(replay, "%s  ·  %s" % [Localization.text(String(info.title)), info.duration])
	viewer.closed.connect(return_to if return_to.is_valid() else main._build_replay_list)
	if return_to.is_valid():
		var close := viewer.find_child("ReplayClose", true, false) as Button
		if close != null:
			close.tooltip_text = return_hint if not return_hint.is_empty() else "이전 화면으로 돌아갑니다."
	viewer.branch_requested.connect(func(tick): main._start_branch_battle(viewer.replay, tick))
	viewer.set_storage_state(path, false)
	var store := func():
		var stored_path: String = viewer.storage_path
		var saved := false
		if stored_path.is_empty():
			stored_path = BattleReplay.save(viewer.replay, "shared")
			saved = not stored_path.is_empty()
		else:
			saved = BattleReplay.write_file(stored_path, viewer.replay)
		viewer.set_storage_state(stored_path, not saved)
		main.updater.set_safe_to_update(main._client_can_update())
		if not saved:
			viewer.moment_toast.text = Localization.text("메모를 저장하지 못했습니다. 저장 공간과 파일 권한을 확인하세요.")
	viewer.storage_requested.connect(store)
	viewer.notes_changed.connect(func(_updated): store.call())
	main.root_background.add_child(viewer)
	main.replay_viewer = viewer

## Find candidates without treating matching dates, rounded times or legacy versions as a battle ID.
static func _show_challenge_replays(main, period: String, date: String, ruleset: String, record: Dictionary, return_focus: Control = null, view_state: Dictionary = {}) -> void:
	if view_state.is_empty():
		view_state = {"completed": {}}
	if return_focus == null:
		return_focus = main.get_viewport().gui_get_focus_owner()
	var focus_target := return_focus
	var entries := ChallengeReplays.matching(ChallengeReplays.load_saved(), period, date, ruleset)
	# Retain only small, completed summaries while this selection dialog is open.
	# A changed or removed file must never inherit a previous analysis.
	var completed: Dictionary = view_state.get("completed", {})
	view_state["completed"] = completed
	var fingerprints := {}
	for entry in entries:
		fingerprints[String(entry.fingerprint)] = true
	for key in completed.keys():
		if not fingerprints.has(key): completed.erase(key)
	var dialog: VBoxContainer = main._action_panel("도전의 보관 전투", Rect2(190, 60, 900, 600))
	var title := "주간 도전" if period == "weekly" else "일일 도전"
	var date_text := "%s-%s-%s" % [date.substr(0, 4), date.substr(4, 2), date.substr(6, 2)]
	var rule_text := "버전 미상" if ruleset == "0" else "버전 " + ruleset
	var heading := MultiplayerUI.label("%s %s (UTC) · %s\n보관 기록: %s · %d점 · %.1f초" % [title, date_text, rule_text, "성공" if bool(record.get("won", false)) else "실패", int(record.get("score", 0)), float(record.get("seconds", 0.0))], 16, UIKit.TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(heading)
	var hint := MultiplayerUI.label("점수 분석으로 기지 체력·시간의 점수 근거를 확인합니다. 클립도 전체 전투 기준입니다. 이전·미상 버전은 현재 규칙의 참고 점수이며, 결과·시간·점수가 같아도 같은 전투인지는 확정할 수 없습니다.", 14, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(hint)
	var status := MultiplayerUI.label("보관 전투 %d개 · 버전 확인된 전투 우선" % entries.size(), 14, UIKit.GOLD)
	status.name = "ChallengeReplayStatus"
	status.tooltip_text = "버전이 확인된 전투를 먼저 표시하며, 각 그룹 안에서는 최신 보관순입니다."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.name = "ChallengeReplayScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	scroll.focus_mode = Control.FOCUS_ALL
	dialog.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "ChallengeReplayRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	var controls: Array[Control] = [scroll]
	# A new analysis cancels the previous one. State belongs only to this dialog.
	var analysis_job := {"serial": 0}
	# Confirmed versions come first; unknown versions remain visible in a separate group.
	for unknown in [false, true]:
		var group: Array = entries.filter(func(entry): return (ChallengeReplays.ruleset_of(entry.replay) == "0") == unknown)
		if group.is_empty(): continue
		var group_title := MultiplayerUI.label(("버전 미상 · 날짜만 일치" if unknown else "기록의 버전 확인됨") + " · %d개" % group.size(), 16, UIKit.GOLD)
		rows.add_child(group_title)
		for entry in group:
			var card := PanelContainer.new()
			card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE_SOFT, 12), 14, 10))
			rows.add_child(card)
			var content := VBoxContainer.new()
			card.add_child(content)
			var replay: Dictionary = entry.replay
			var info := describe(replay)
			var caption := "%s · %.1f초 · %s" % [info.outcome, float(replay.result.elapsed), "클립" if not replay.clip.is_empty() else "전체 전투"]
			if not replay.clip.is_empty():
				caption += " · 구간 %s · 길이 %s" % [info.clip_range, info.clip_length]
			var details := MultiplayerUI.label(caption, 16, UIKit.TEXT)
			details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(details)
			if ChallengeReplays.same_time_and_outcome(replay, record):
				var match_hint := MultiplayerUI.label("기록과 결과·완료 시간 일치 · 점수 분석으로 비교할 수 있습니다.", 14, UIKit.TEAL)
				match_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				content.add_child(match_hint)
			var score_detail := MultiplayerUI.label("점수 분석 전 · 종료 상태를 재현해 확인합니다.", 14, UIKit.TEXT_MUTED)
			score_detail.name = "ChallengeReplayScore"
			score_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.add_child(score_detail)
			var actions := HBoxContainer.new()
			actions.add_theme_constant_override("separation", 10)
			content.add_child(actions)
			var path := String(entry.path)
			var fingerprint := String(entry.fingerprint)
			if completed.has(fingerprint):
				_show_challenge_score(score_detail, completed[fingerprint], replay, record)
			var stamp := MultiplayerUI.label(_stamp(path) + " · " + path.get_file(), 13, UIKit.TEXT_MUTED)
			stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			stamp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			stamp.tooltip_text = ProjectSettings.globalize_path(path)
			actions.add_child(stamp)
			var analyze := UIKit.style_button(Button.new(), UIKit.TEAL, false, 16)
			analyze.name = "AnalyzeChallengeScore"
			analyze.set_meta("ChallengeReplayPath", path)
			analyze.text = "다시 분석" if completed.has(fingerprint) else "점수 분석"
			analyze.custom_minimum_size = Vector2(130, UIKit.TOUCH_MIN_HEIGHT)
			analyze.tooltip_text = "선택한 전투만 분석합니다. 다시 누르면 취소하며, 다른 전투를 분석하면 이전 분석은 중단됩니다."
			actions.add_child(analyze)
			controls.append(analyze)
			analyze.pressed.connect(func():
				if not _dialog_alive(dialog): return
				if bool(analyze.get_meta("analyzing", false)):
					if int(analyze.get_meta("analysis_serial", -1)) == int(analysis_job.serial):
						analysis_job.serial = int(analysis_job.serial) + 1
					analyze.set_meta("analyzing", false)
					analyze.text = "점수 분석"
					score_detail.text = "점수 분석을 취소했습니다. 다시 분석할 수 있습니다."
					return
				analysis_job.serial = int(analysis_job.serial) + 1
				_analyze_challenge_score(dialog, analyze, score_detail, analysis_job, int(analysis_job.serial), path, fingerprint, period, date, ruleset, record, completed))
			var watch := UIKit.style_button(Button.new(), UIKit.ACCENT, true, 16)
			watch.name = "WatchChallengeReplay"
			watch.set_meta("ChallengeReplayPath", path)
			watch.text = "재생"
			watch.custom_minimum_size = Vector2(110, UIKit.TOUCH_MIN_HEIGHT)
			actions.add_child(watch)
			controls.append(watch)
			watch.pressed.connect(func():
				if not _dialog_alive(dialog) or watch.disabled:
					return
				# Read again before leaving the records screen: the file may have been removed or replaced.
				var current := BattleReplay.load_file(path)
				if current.is_empty() or not ChallengeReplays.belongs_to(current, period, date, ruleset) or ChallengeReplays.fingerprint(current) != fingerprint:
					status.text = "선택한 전투를 읽을 수 없거나 파일 내용이 바뀌었습니다. 새로고침 후 다시 선택하세요."
					watch.disabled = true
					return
				main._dismiss_action_overlay()
				watch.disabled = true
				_open_viewer(main, current, path, main._build_records_screen, "도전 기록으로 돌아갑니다. 날짜·버전·결과 조건과 페이지·스크롤을 유지합니다."))
	if entries.is_empty():
		var empty := MultiplayerUI.label("읽을 수 있는 보관 전투가 없습니다. 저장 실패·자동 정리·삭제로 점수 기록만 남을 수 있습니다. 다른 버전으로 확인된 전투는 포함하지 않습니다.", 16, UIKit.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(empty)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	dialog.add_child(footer)
	var refresh := UIKit.style_button(Button.new(), UIKit.TEAL)
	refresh.name = "RefreshChallengeReplays"
	refresh.text = "새로고침"
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	refresh.tooltip_text = "파일을 다시 조회합니다. 내용이 같은 전투의 분석 결과와 스크롤 위치를 유지하며, 진행 중인 분석은 중단합니다."
	refresh.pressed.connect(func():
		if _dialog_alive(dialog):
			view_state["scroll"] = scroll.scroll_vertical
			var focused: Control = main.get_viewport().gui_get_focus_owner()
			view_state["focus_name"] = String(focused.name) if focused in controls else String(scroll.name)
			view_state["focus_path"] = String(focused.get_meta("ChallengeReplayPath", "")) if focused in controls else ""
			_show_challenge_replays(main, period, date, ruleset, record, focus_target, view_state))
	footer.add_child(refresh)
	var close := func():
		if not _dialog_alive(dialog): return
		main._dismiss_action_overlay()
		main.records_state.erase("focus")
		if is_instance_valid(focus_target) and focus_target.is_inside_tree():
			focus_target.grab_focus.call_deferred()
	var back := UIKit.style_button(Button.new(), UIKit.ACCENT)
	back.name = "CloseChallengeReplays"
	back.text = "도전 기록으로"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	back.pressed.connect(close)
	footer.add_child(back)
	controls.append(refresh)
	controls.append(back)
	for index in controls.size():
		var control := controls[index]
		control.focus_previous = control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_neighbor_left = control.focus_previous
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_right = control.focus_next
		control.focus_neighbor_bottom = control.focus_next
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	scroll.gui_input.connect(func(event: InputEvent):
		if not event is InputEventKey or not event.pressed or event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return
		match event.keycode:
			KEY_UP: scroll.scroll_vertical -= 48
			KEY_DOWN: scroll.scroll_vertical += 48
			KEY_PAGEUP: scroll.scroll_vertical -= maxi(48, int(scroll.size.y))
			KEY_PAGEDOWN: scroll.scroll_vertical += maxi(48, int(scroll.size.y))
			KEY_HOME: scroll.scroll_vertical = 0
			KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			_: return
		scroll.accept_event())
	var restore := func():
		if not _dialog_alive(dialog): return
		var target: Control = scroll
		for control in controls:
			if String(control.name) == String(view_state.get("focus_name", "")) and String(control.get_meta("ChallengeReplayPath", "")) == String(view_state.get("focus_path", "")):
				if not (control is Button and control.disabled): target = control
				break
		target.grab_focus()
		scroll.scroll_vertical = int(view_state.get("scroll", 0))
	dialog.get_tree().process_frame.connect(restore, CONNECT_ONE_SHOT)

## Yield between short batches so long battles leave the dialog responsive.
## Never write the replay, profile, leaderboard or a score calculated here.
static func _analyze_challenge_score(dialog: Control, button: Button, detail: Label, job: Dictionary, serial: int, path: String, fingerprint: String, period: String, date: String, ruleset: String, record: Dictionary, completed: Dictionary) -> void:
	button.set_meta("analyzing", true)
	button.set_meta("analysis_serial", serial)
	button.text = "분석 취소"
	detail.tooltip_text = ""
	detail.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	var replay := BattleReplay.load_file(path)
	if replay.is_empty() or not ChallengeReplays.belongs_to(replay, period, date, ruleset) or ChallengeReplays.fingerprint(replay) != fingerprint:
		detail.text = "전투를 읽을 수 없거나 파일 내용이 바뀌었습니다. 새로고침 후 다시 분석하세요."
		button.text = "점수 분석"
		button.set_meta("analyzing", false)
		return
	var player := BattleReplay.Player.new(replay)
	var total := int(replay.result.ticks)
	var tree := dialog.get_tree()
	var running := true
	while running and not player.is_finished() and player.ticks <= total:
		detail.text = "점수 분석 중 · %d%% · 다른 전투 분석 또는 분석 취소로 중단" % mini(100, int(float(player.ticks) * 100.0 / float(maxi(1, total))))
		await tree.process_frame
		if not _dialog_alive(dialog): return
		if int(job.serial) != serial:
			# Cancel/restart can happen before this suspended job resumes.
			# An older job must not reset the same button's new analysis.
			if int(button.get_meta("analysis_serial", -1)) == serial:
				button.set_meta("analyzing", false)
				button.text = "점수 분석"
				detail.text = "점수 분석을 취소했습니다. 다시 분석할 수 있습니다."
			return
		var started := Time.get_ticks_usec()
		for _step in 120:
			# Forced endings may need one final step at the recorded tick, but
			# an incomplete file must never trigger simulation past that point.
			if player.ticks == total and replay.get("forced_end", {}).is_empty():
				running = false
				break
			running = player.step()
			# This silent analysis consumes no animations or sounds. Discard transient
			# events each tick instead of accumulating a long battle's entire history.
			player.model.combat_events.clear()
			if not running or player.ticks >= total or Time.get_ticks_usec() - started >= 5000:
				break
	var analysis := ChallengeReplays.score_analysis(replay, player, record, ruleset)
	completed[fingerprint] = analysis
	button.set_meta("analyzing", false)
	button.text = "다시 분석"
	_show_challenge_score(detail, analysis, replay, record)

## Reuse completed summaries after refresh without re-simulating every battle.
static func _show_challenge_score(detail: Label, analysis: Dictionary, replay: Dictionary, record: Dictionary) -> void:
	if not bool(analysis.ok):
		detail.text = "저장된 종료 상태와 재현 결과가 달라 점수를 확인할 수 없습니다. 규칙 변경·파일 손상 가능성이 있으며 보관 기록은 유지됩니다."
		detail.add_theme_color_override("font_color", UIKit.DANGER)
		return
	var points: Dictionary = analysis.breakdown
	var lines := PackedStringArray()
	lines.append(("재현 점수 %d점" if bool(analysis.known_current) else "현재 규칙의 참고 점수 %d점") % int(points.score))
	lines.append("종료 기지 체력 %.2f · 전체 전투 %.2f초" % [float(analysis.health), float(analysis.seconds)])
	if bool(analysis.won):
		lines.append("기본 %d + 체력 가점 %.2f − 시간 감점 %.2f = %.2f → 반올림 %d점" % [int(DailyChallenge.SCORE_BASE), float(points.health_bonus), float(points.time_penalty), float(points.raw), int(points.rounded)])
		if int(points.adjustment) != 0:
			lines.append("승리 점수의 최솟값 %d·최댓값 %d 적용 → %d점" % [DailyChallenge.SCORE_MIN, DailyChallenge.SCORE_MAX, int(points.score)])
	else:
		lines.append("패배·무승부는 체력과 시간에 관계없이 0점입니다.")
	if bool(analysis.comparable):
		var difference := int(analysis.difference)
		lines.append("보관 최고 기록보다 %d점 높음" % difference if difference > 0 else ("보관 최고 기록보다 %d점 낮음" % -difference if difference < 0 else "보관 기록과 점수 같음"))
		if bool(analysis.won) and bool(record.get("won", false)):
			var time_difference := float(analysis.seconds) - float(record.get("seconds", 0.0))
			if absf(time_difference) >= 0.001:
				lines.append(("보관 기록보다 %.2f초 빠름" if time_difference < 0.0 else "보관 기록보다 %.2f초 느림") % absf(time_difference))
		if bool(analysis.record_matches):
			lines.append("기록과 결과·완료 시간·점수 일치 · 같은 전투인지는 확정할 수 없습니다.")
		elif difference == 0:
			lines.append("결과 또는 완료 시간이 기록과 다릅니다. 동점이면 더 빠른 성공 기록을 보관합니다.")
	else:
		lines.append("이전·미상 버전의 원래 점수는 확정할 수 없어 최고 기록과 비교하지 않습니다.")
	if not BattleReplay.clip_of(replay).is_empty():
		lines.append("클립 구간의 점수가 아닌 전체 전투의 종료 점수입니다.")
	detail.text = "\n".join(lines)
	detail.tooltip_text = "기지 체력에 %.1f를 곱해 가점, 전투 시간(초)에 %.1f를 곱해 감점합니다. 표시 소수는 반올림하며, 점수는 원래 값으로 합산 후 한 번 반올림합니다. 분석은 기록을 변경하거나 서버로 전송하지 않습니다." % [DailyChallenge.SCORE_HEALTH_FACTOR, DailyChallenge.SCORE_TIME_FACTOR]
	detail.add_theme_color_override("font_color", UIKit.TEAL if bool(analysis.comparable) else UIKit.TEXT_MUTED)

static func _dialog_alive(dialog: Control) -> bool:
	if not is_instance_valid(dialog) or not dialog.is_inside_tree(): return false
	var node: Node = dialog
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true
