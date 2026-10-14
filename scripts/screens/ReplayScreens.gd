extends RefCounted
## Replay list and player entry points (menu → 리플레이).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ChallengeReplays = preload("res://scripts/ChallengeReplays.gd")
const ChallengeReplayScan = preload("res://scripts/ui/ChallengeReplayScan.gd")
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
const ReplayListScreen = preload("res://scripts/ui/ReplayListScreen.gd")
const ChallengeSearchTerms = preload("res://scripts/ui/ChallengeSearchTerms.gd")

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
	var entry := {"path": path, "replay": replay, "order": BattleReplay._storage_order(replay), "protected": BattleReplay.is_protected(replay), "mode": "unreadable", "winner": -1, "clip": false, "search": (_stamp(path) + " " + path.get_file()).to_lower()}
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
	entry["deck_search"] = PackedStringArray([_challenge_deck_search_text(replay, 0), _challenge_deck_search_text(replay, 1)])
	for deck in entry.deck_search:
		parts.append(deck)
	for note in BattleReplay.notes_of(replay):
		parts.append(String(note.text))
	entry.search = " ".join(parts).to_lower()
	return entry

static func _stamp(path: String) -> String:
	var file := path.get_file()
	if file.length() >= 15 and file.substr(8, 1) == "_":
		return "%s-%s-%s  %s:%s" % [file.substr(0, 4), file.substr(4, 2), file.substr(6, 2), file.substr(9, 2), file.substr(11, 2)]
	return file.get_basename()

## Read file length only, including malformed/oversized JSON. Never read a link.
static func _shelf_file_bytes(path: String, directory: DirAccess) -> int:
	if directory == null or directory.is_link(path.get_file()) or DirAccess.dir_exists_absolute(path): return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return -1
	var bytes := file.get_length()
	file.close()
	return bytes

static func _read_shelf_entry(path: String, directory: DirAccess) -> Dictionary:
	# Recheck links/folders at read time; the scan and this read can span frames.
	var replay := {} if directory.is_link(path.get_file()) or DirAccess.dir_exists_absolute(path) else BattleReplay.load_file(path)
	var entry := _shelf_entry(path, replay)
	entry["file_bytes"] = _shelf_file_bytes(path, directory)
	return entry

static func _build_replay_list(main) -> void:
	var frame = MenuScreens._show_scene(main, REPLAY_LIST_SCREEN, "리플레이", "최근 %d개와 정리 제외한 전투를 다시 보고 분석합니다" % BattleReplay.MAX_SAVED)
	var column: VBoxContainer = frame.column
	frame.deck_filters_changed.connect(_refresh_shelf_deck_buttons.bind(frame))
	frame.refresh_requested.connect(main._build_replay_list)
	frame.loading_completed.connect(func(entries: Array, error: String): _complete_replay_list(main, frame, entries, error))
	# Footer actions are usable while the frame scans/reads its snapshot.
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
	analysis_button.disabled = true
	analysis_button.tooltip_text = "보관함 읽기를 마치면 전체 기록을 분석할 수 있습니다."
	UIKit.style_button(analysis_button, UIKit.GOLD_DEEP, false, 16)
	column.get_node("Footer").add_child(analysis_button)
	analysis_button.pressed.connect(func(): _show_deck_analysis(main, frame))
	var code_button := Button.new()
	code_button.name = "OpenByCodeButton"
	code_button.text = Localization.text("코드로 열기")
	code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.style_button(code_button, UIKit.TEAL, false, 16)
	column.get_node("Footer").add_child(code_button)
	code_button.pressed.connect(func():
		code_button.grab_focus()
		_show_code_dialog(main))
	var recent_button := Button.new()
	recent_button.name = "RecentBattlesButton"
	recent_button.text = Localization.text("최근 온라인 전투")
	recent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UIKit.style_button(recent_button, UIKit.ACCENT, false, 16)
	column.get_node("Footer").add_child(recent_button)
	recent_button.pressed.connect(func(): _show_recent_battles(main))
	frame.begin_loading(BattleReplay.save_dir, _read_shelf_entry, func(entry): return _unreadable_replay_card(main, String(entry.path), int(entry.file_bytes)) if entry.replay.is_empty() else _replay_card(main, String(entry.path), entry.replay, int(entry.file_bytes), frame), main.replay_list_state)

static func _complete_replay_list(main, frame, entries: Array, error: String) -> void:
	if not _dialog_alive(frame) or not main.root_background.is_ancestor_of(frame): return
	var column: VBoxContainer = frame.column
	var status: Label = column.get_node("ReplayStatus")
	var analysis_button: Button = column.get_node("Footer/DeckAnalysisButton")
	analysis_button.disabled = not error.is_empty()
	analysis_button.tooltip_text = "보관 폴더를 읽지 못했습니다. 새로고침 후 다시 시도하세요." if not error.is_empty() else "읽어 둔 전체 보관함의 내 덱 전적을 분석합니다. 검색·정렬·페이지 조건과 관계없이 집계합니다. 게임 밖에서 파일을 바꿨다면 먼저 새로고침하세요."
	var shown := 0
	var unreadable := 0
	var preserved := 0
	for entry in entries:
		if entry.replay.is_empty():
			unreadable += 1
		else:
			shown += 1
			if bool(entry.protected): preserved += 1
	var storage_help := UIKit.style_button(Button.new(), UIKit.TEAL)
	storage_help.name = "ReplayStorageHelp"
	storage_help.text = "보관 안내"
	storage_help.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	storage_help.tooltip_text = "서버 코드 보관 정책과 이 기기의 저장 경로·백업 방법을 확인합니다."
	frame.column.get_node("ReplaySearchTools").add_child(storage_help)
	storage_help.pressed.connect(func():
		storage_help.grab_focus()
		var background: Control = main.root_background
		var focus_ref: WeakRef = weakref(storage_help)
		var return_to := func():
			if not _dialog_alive(background) or main.root_background != background: return
			main._dismiss_action_overlay()
			background.get_tree().process_frame.connect(_restore_code_entry_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
		_show_replay_storage_help(main, return_to))
	var notices := PackedStringArray()
	if not error.is_empty(): notices.append(error)
	if preserved > 0:
		notices.append("정리 제외 %d개 · 일반 리플레이 %d개. 정리 제외한 전투는 최근 %d개와 별도로 보존합니다. 직접 삭제·데이터 초기화는 적용됩니다." % [preserved, shown - preserved, BattleReplay.MAX_SAVED])
	if unreadable > 0:
		notices.append("읽을 수 없는 리플레이 %d개가 있습니다. 자동 정리에서 제외하며, 파일을 보관하거나 목록에서 삭제할 수 있습니다." % unreadable)
	if shown - preserved > BattleReplay.MAX_SAVED:
		notices.append("일반 리플레이 %d개를 보관 중입니다. 자동 정리를 완료하지 못했습니다. 파일 권한을 확인하고 정리를 다시 시도하세요." % (shown - preserved))
		var retry := main._styled_button("오래된 리플레이 정리 재시도", UIKit.GOLD_DEEP, false) as Button
		retry.name = "RetryReplayCleanup"
		retry.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		retry.tooltip_text = "전체 보관함에서 삭제할 오래된 전투·클립·메모를 먼저 확인합니다."
		column.add_child(retry)
		column.move_child(retry, column.get_node("Footer").get_index())
		retry.pressed.connect(func(): _confirm_replay_cleanup(main, retry))
	# Imports and failed playback may have posted a message before loading finished.
	var summary := "\n".join(notices)
	if not summary.is_empty(): status.text += ("\n" if not status.text.is_empty() else "") + summary

static func _confirm_replay_cleanup(main, entry_button: Button) -> void:
	var background: Control = main.root_background
	if not _dialog_alive(background) or not _dialog_alive(entry_button): return
	entry_button.grab_focus()
	var focus_ref: WeakRef = weakref(entry_button)
	var snapshot := BattleReplay.cleanup_snapshot()
	var target_count := maxi(0, snapshot.plan.readable.size() - BattleReplay.MAX_SAVED)
	var dialog: VBoxContainer = main._action_panel("오래된 리플레이 정리 확인", Rect2(200, 50, 880, 620))
	dialog.name = "ReplayCleanupDialog"
	var headline := MultiplayerUI.label("삭제 대상 %d개 · 정상 리플레이 %d개 보존 · 읽기 실패 %d개 보존" % [target_count, int(snapshot.kept), int(snapshot.unreadable)], 18, UIKit.TEXT)
	headline.name = "ReplayCleanupSummary"
	if int(snapshot.protected) > 0:
		headline.text += "\n정리 제외 %d개는 최근 %d개와 별도로 보존합니다." % [int(snapshot.protected), BattleReplay.MAX_SAVED]
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(headline)
	var scroll := ScrollContainer.new()
	scroll.name = "ReplayCleanupScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	var warning := MultiplayerUI.label("검색·종류·결과·클립 조건과 관계없이 전체 보관함을 정리합니다. 아래 파일과 메모를 영구 삭제하며 되돌릴 수 없습니다.\n정리 제외한 전투를 모두 보존하고, 일반 리플레이는 보관 순서로 최근 %d개를 남깁니다. 가장 최근 저장한 파일과 읽기 실패 파일도 보존합니다. 일반 전투의 메모와 클립도 정리 대상에 포함됩니다.\n남길 전투는 아래 이 전투 정리 제외를 누르세요. 목록을 다시 계산하며 해당 전투는 삭제하지 않습니다. 전적·도전 점수·서버 기록은 유지됩니다. 게임 밖의 백업은 텍스트나 JSON 사본으로 별도 보관하세요." % BattleReplay.MAX_SAVED, 15, UIKit.DANGER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(warning)
	var status := MultiplayerUI.label(String(snapshot.error), 15, UIKit.DANGER)
	status.name = "ReplayCleanupStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(status)
	var controls: Array[Control] = [scroll]
	var notes := 0
	var clips := 0
	for entry in snapshot.entries:
		var replay: Dictionary = entry.replay
		var info := describe(replay)
		notes += int(info.notes)
		if not String(info.clip_range).is_empty(): clips += 1
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE, UIKit.SURFACE, UIKit.DANGER, 12), 14, 10))
		details.add_child(card)
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(column)
		var text := "%s · %s · 전체 전투 %s · 메모 %d개\n보관 파일명 기준 시각: %s\n%s" % [info.title, info.outcome, info.duration, int(info.notes), _stamp(String(entry.path)), String(entry.path).get_file()]
		if not String(info.clip_range).is_empty():
			text += "\n클립 구간 %s · 길이 %s" % [info.clip_range, info.clip_length]
		var label := MultiplayerUI.label(text, 15, UIKit.TEXT)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = ProjectSettings.globalize_path(String(entry.path))
		column.add_child(label)
		var copy := MultiplayerUI.button(main, column, "먼저 이 전투 텍스트 복사", "CopyReplayBeforeCleanup", func():
			if not _dialog_alive(dialog) or main.root_background != background: return
			var shared := BattleReplay.to_share_text(replay)
			if shared.length() > BattleReplay.MAX_SHARE_CHARS:
				status.text = "공유 텍스트가 가져오기 한도를 넘습니다. 취소하고 이 전투의 JSON 파일을 게임 밖에 복사하세요."
				status.add_theme_color_override("font_color", UIKit.DANGER)
			else:
				DisplayServer.clipboard_set(shared)
				status.text = "%s의 전투와 메모를 복사했습니다. 다른 전투를 복사하거나 정리하기 전에 게임 밖에 붙여넣어 보관하세요." % String(entry.path).get_file()
				status.add_theme_color_override("font_color", UIKit.TEAL))
		copy.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		copy.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
		copy.tooltip_text = "이 확인창에 표시한 전투·클립·메모를 복사합니다. 다음 복사는 클립보드 내용을 덮어쓰므로 매번 게임 밖에 붙여넣으세요."
		controls.append(copy)
		var protect := MultiplayerUI.button(main, column, "이 전투 정리 제외", "ProtectReplayBeforeCleanup", func():
			if not _dialog_alive(dialog) or main.root_background != background: return
			var result := BattleReplay.set_protected(String(entry.path), String(entry.fingerprint), true)
			if not result.ok:
				status.text = String(result.error)
				status.add_theme_color_override("font_color", UIKit.DANGER)
				return
			# Rebuild the shelf as well: cancelling the new preview must show the
			# newly protected badge, counts and retention-filter membership.
			main._build_replay_list()
			var current_background: Control = main.root_background
			var shelf_status := current_background.find_child("ReplayStatus", true, false) as Label
			if shelf_status != null: shelf_status.text = "이 전투를 정리 대상에서 보존했습니다. 보관함을 다시 읽고 있습니다."
			_after_replay_list_loaded(current_background, func():
				if not _dialog_alive(current_background) or main.root_background != current_background or is_instance_valid(main.action_overlay): return
				var retry := current_background.find_child("RetryReplayCleanup", true, false) as Button
				if retry != null:
					_confirm_replay_cleanup(main, retry)
					var current_status := main.action_overlay.find_child("ReplayCleanupStatus", true, false) as Label
					if current_status != null and current_status.text.is_empty():
						current_status.text = "이 전투를 정리 대상에서 보존했습니다. 남은 삭제 대상을 다시 확인하세요."
						current_status.add_theme_color_override("font_color", UIKit.TEAL)
				else:
					_restore_protection_focus(main, current_background, String(entry.path))))
		protect.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		protect.tooltip_text = "이 파일과 메모를 정리 대상에서 보존합니다. 새 사본을 저장하거나 보관 순서를 바꾸지 않습니다."
		controls.append(protect)
	if String(snapshot.error).is_empty():
		headline.text += "\n함께 삭제되는 메모 %d개 · 클립 파일 %d개" % [notes, clips]
		if target_count == 0: status.text = "현재 정리할 오래된 리플레이가 없습니다. 취소하고 보관함을 새로고침하세요."
	var path_input := LineEdit.new()
	path_input.name = "ReplayCleanupDirectory"
	path_input.text = ProjectSettings.globalize_path(BattleReplay.save_dir)
	path_input.editable = false
	path_input.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	path_input.tooltip_text = "위 삭제 대상이 들어 있는 실제 보관 폴더입니다. 경로 선택만으로 파일이 백업되지는 않습니다."
	dialog.add_child(path_input)
	controls.append(path_input)
	var close := func():
		if not _dialog_alive(dialog) or main.root_background != background: return
		main._dismiss_action_overlay()
		background.get_tree().process_frame.connect(_restore_code_entry_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	dialog.add_child(actions)
	var refresh := MultiplayerUI.button(main, actions, "삭제 대상 다시 확인", "RefreshReplayCleanup", func():
		if _dialog_alive(dialog) and main.root_background == background:
			_confirm_replay_cleanup(main, entry_button))
	var confirm := UIKit.style_button(Button.new(), UIKit.DANGER)
	confirm.name = "ConfirmReplayCleanup"
	confirm.text = "위 %d개 영구 삭제" % target_count
	confirm.disabled = target_count == 0 or not String(snapshot.error).is_empty()
	actions.add_child(confirm)
	var cancel := MultiplayerUI.button(main, actions, "취소", "CancelReplayCleanup", close)
	for button in [refresh, confirm, cancel]:
		button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.append(button)
	_bind_challenge_navigation(controls)
	confirm.pressed.connect(func():
		if not _dialog_alive(dialog) or main.root_background != background or confirm.disabled: return
		var result := BattleReplay.cleanup_saved(snapshot)
		if int(result.removed) == 0 and not String(result.error).is_empty():
			status.text = String(result.error)
			status.add_theme_color_override("font_color", UIKit.DANGER)
			confirm.disabled = not bool(result.retryable)
			_bind_challenge_navigation(controls)
			cancel.grab_focus()
			return
		main._build_replay_list()
		var current_background: Control = main.root_background
		var shelf_status := current_background.find_child("ReplayStatus", true, false) as Label
		if shelf_status != null:
			var notice := "오래된 리플레이 %d개를 삭제했습니다." % int(result.removed)
			var remaining := target_count - int(result.removed)
			if remaining > 0:
				notice += " 정리 대상 %d개가 남았습니다.\n%s\n남은 파일은 보존했습니다. 정리 재시도로 삭제 대상을 다시 확인하세요." % [remaining, result.error]
			shelf_status.text = notice + ("\n" + shelf_status.text if not shelf_status.text.is_empty() else "")
		_after_replay_list_loaded(current_background, _restore_cleanup_focus.bind(main, current_background)))
	for control in controls:
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
	cancel.grab_focus()

static func _restore_cleanup_focus(main, background: Control) -> void:
	if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
	var target := background.find_child("RetryReplayCleanup", true, false) as Control
	if target == null: target = background.find_child("ReplaySearch", true, false) as Control
	if target != null: _restore_shelf_focus(background, target)

static func _restore_shelf_focus(background: Control, target: Control) -> void:
	var frame = background.find_child("ReplayListScreen", true, false)
	if frame != null:
		frame.restore_focus(target)

static func _after_replay_list_loaded(background: Control, action: Callable) -> void:
	if not _dialog_alive(background): return
	var frame := background.find_child("ReplayListScreen", true, false) as ReplayListScreen
	if frame != null: frame.after_loading(action)

static func _confirm_replay_delete(main, path: String, entry_button: Button) -> void:
	var background: Control = main.root_background
	if not _dialog_alive(background) or not _dialog_alive(entry_button): return
	entry_button.grab_focus()
	var focus_ref: WeakRef = weakref(entry_button)
	var rows := background.find_child("ReplayRows", true, false) as VBoxContainer
	var selected_index := 0
	if rows != null:
		for card in rows.get_children():
			if not card.visible: continue
			if card.is_ancestor_of(entry_button): break
			selected_index += 1
	var snapshot := BattleReplay.deletion_snapshot(path)
	var dialog: VBoxContainer = main._action_panel("리플레이 삭제 확인", Rect2(230, 70, 820, 580))
	dialog.name = "ReplayDeleteDialog"
	var scroll := ScrollContainer.new()
	scroll.name = "ReplayDeleteScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	var replay: Dictionary = snapshot.replay
	var summary := "읽을 수 없는 리플레이\n복구할 수 있는 내용이 남아 있을 수 있습니다. 필요하면 먼저 JSON 파일을 다른 곳에 보관하세요."
	if not replay.is_empty():
		var info := describe(replay)
		summary = "%s · %s · 전체 전투 %s\n보관 파일명 기준 시각: %s\n함께 삭제되는 메모: %d개" % [info.title, info.outcome, info.duration, _stamp(path), int(info.notes)]
		if not String(info.clip_range).is_empty():
			summary += "\n클립 구간 %s · 길이 %s" % [info.clip_range, info.clip_length]
		if BattleReplay.is_protected(replay):
			summary += "\n정리 제외한 전투입니다. 직접 삭제하면 보존 상태와 관계없이 이 파일·메모가 사라집니다."
	var headline := MultiplayerUI.label(summary, 18, UIKit.TEXT)
	headline.name = "ReplayDeleteSummary"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(headline)
	var warning := MultiplayerUI.label("선택한 로컬 파일 하나와 그 안의 메모를 영구 삭제합니다. 되돌릴 수 없습니다.\n필요한 전투는 먼저 공유 텍스트나 JSON 파일을 게임 밖에 보관하세요. 서버 코드만으로는 계속 보관되지 않습니다.\n전적·도전 점수·다른 리플레이·서버에 보관된 전투는 유지됩니다.", 15, UIKit.DANGER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(warning)
	var path_label := MultiplayerUI.label("삭제할 파일의 실제 경로", 14, UIKit.TEXT_MUTED)
	dialog.add_child(path_label)
	var path_input := LineEdit.new()
	path_input.name = "ReplayDeletePath"
	path_input.text = ProjectSettings.globalize_path(path)
	path_input.editable = false
	path_input.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	path_input.tooltip_text = path_input.text
	dialog.add_child(path_input)
	var status := MultiplayerUI.label(String(snapshot.error), 15, UIKit.DANGER)
	status.name = "ReplayDeleteStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(status)
	var close := func():
		if not _dialog_alive(dialog) or main.root_background != background: return
		main._dismiss_action_overlay()
		background.get_tree().process_frame.connect(_restore_code_entry_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	dialog.add_child(actions)
	var copy := MultiplayerUI.button(main, actions, "먼저 텍스트 복사", "CopyReplayBeforeDelete", func():
		if not _dialog_alive(dialog) or main.root_background != background: return
		var text := BattleReplay.to_share_text(replay)
		if text.length() > BattleReplay.MAX_SHARE_CHARS:
			status.text = "공유 텍스트가 가져오기 한도를 넘습니다. 취소하고 표시된 JSON 파일을 게임 밖에 복사해 보관하세요."
			status.add_theme_color_override("font_color", UIKit.DANGER)
			scroll.ensure_control_visible.call_deferred(status)
			return
		DisplayServer.clipboard_set(text)
		status.text = "리플레이 텍스트를 복사했습니다. 삭제하기 전에 메모장 등 게임 밖에 붙여넣어 보관하세요."
		status.add_theme_color_override("font_color", UIKit.TEAL)
		scroll.ensure_control_visible.call_deferred(status))
	copy.disabled = replay.is_empty() or not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	copy.tooltip_text = "이 확인창에 표시한 전투와 메모를 복사합니다. 복사만으로 백업이 완료되지는 않습니다."
	var confirm := UIKit.style_button(Button.new(), UIKit.DANGER)
	confirm.name = "ConfirmReplayDelete"
	confirm.text = "이 파일만 영구 삭제"
	confirm.disabled = not String(snapshot.error).is_empty()
	actions.add_child(confirm)
	var cancel := MultiplayerUI.button(main, actions, "취소", "CancelReplayDelete", close)
	for button in [copy, confirm, cancel]:
		button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var controls: Array[Control] = [scroll, path_input, copy, confirm, cancel]
	_bind_challenge_navigation(controls)
	confirm.pressed.connect(func():
		if not _dialog_alive(dialog) or main.root_background != background or confirm.disabled: return
		var result := BattleReplay.delete_saved(path, String(snapshot.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			status.add_theme_color_override("font_color", UIKit.DANGER)
			confirm.disabled = not bool(result.retryable)
			_bind_challenge_navigation(controls)
			scroll.ensure_control_visible.call_deferred(status)
			cancel.grab_focus()
			return
		main._build_replay_list()
		var current_background: Control = main.root_background
		var shelf_status := current_background.find_child("ReplayStatus", true, false) as Label
		if shelf_status != null:
			var notice := "리플레이 1개를 삭제했습니다: %s" % path.get_file()
			shelf_status.text = notice + ("\n" + shelf_status.text if not shelf_status.text.is_empty() else "")
		_after_replay_list_loaded(current_background, _restore_deleted_replay_focus.bind(main, current_background, selected_index)))
	for control in controls:
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
	# Opening with Enter must never make permanent deletion the default action.
	cancel.grab_focus()

static func _restore_deleted_replay_focus(main, background: Control, selected_index: int) -> void:
	if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
	var rows := background.find_child("ReplayRows", true, false) as VBoxContainer
	var visible_cards: Array[Control] = []
	if rows != null:
		for card in rows.get_children():
			if card.visible and card.find_child("DeleteReplayButton", true, false) != null: visible_cards.append(card)
	if not visible_cards.is_empty():
		var card := visible_cards[clampi(selected_index, 0, visible_cards.size() - 1)]
		var target := card.find_child("PlayReplayButton", true, false) as Button
		if target == null: target = card.find_child("DeleteReplayButton", true, false) as Button
		if target != null:
			_restore_shelf_focus(background, target)
			return
	var search := background.find_child("ReplaySearch", true, false) as LineEdit
	if search != null: _restore_shelf_focus(background, search)

static func _delete_button(main, path: String) -> Button:
	var button: Button = main._styled_button("삭제", UIKit.DANGER, false)
	button.name = "DeleteReplayButton"
	button.custom_minimum_size = Vector2(80, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 46)
	button.tooltip_text = "전투·메모·파일 경로를 확인한 뒤 선택한 로컬 파일 하나만 삭제합니다."
	button.pressed.connect(func(): _confirm_replay_delete(main, path, button))
	return button

static func _unreadable_replay_card(main, path: String, file_bytes: int = -1) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "UnreadableReplayCard"
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE, UIKit.SURFACE, UIKit.DANGER, 12), 14, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "읽을 수 없는 리플레이 · %s\n%s\n파일이 손상되었거나 지원하지 않는 형식입니다." % [ReplayListScreen.storage_size_text(file_bytes), path.get_file()]
	label.tooltip_text = ProjectSettings.globalize_path(path)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	row.add_child(label)
	row.add_child(_delete_button(main, path))
	card.add_child(row)
	return card

## Overlay with one row per deck I have played: record, average length, hardest stage and advice.
static func _show_deck_analysis(main, shelf: ReplayListScreen = null) -> void:
	if shelf != null and not _dialog_alive(shelf): return
	var dialog = main._action_panel("덱 분석", Rect2(150, 50, 980, 620))
	var rows: Array = DeckAnalysis.collect_replays(shelf.snapshot_replays()) if shelf != null else DeckAnalysis.collect(BattleReplay.list_saved())
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

static func _confirm_replay_protection(main, path: String, entry_button: Button) -> void:
	var background: Control = main.root_background
	if not _dialog_alive(background) or not _dialog_alive(entry_button): return
	entry_button.grab_focus()
	var focus_ref: WeakRef = weakref(entry_button)
	var snapshot := BattleReplay.deletion_snapshot(path)
	var replay: Dictionary = snapshot.replay
	var enabled := not BattleReplay.is_protected(replay)
	var dialog: VBoxContainer = main._action_panel("리플레이 정리 제외" if enabled else "리플레이 보존 해제", Rect2(230, 80, 820, 560))
	dialog.name = "ReplayProtectionDialog"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	scroll.add_child(details)
	var summary := path.get_file()
	if not replay.is_empty():
		var info := describe(replay)
		summary = "%s · %s · 전체 전투 %s · 메모 %d개\n%s" % [info.title, info.outcome, info.duration, int(info.notes), path.get_file()]
		if not String(info.clip_range).is_empty():
			summary += "\n클립 구간 %s · 길이 %s" % [info.clip_range, info.clip_length]
	var headline := MultiplayerUI.label(summary, 18, UIKit.TEXT)
	headline.name = "ReplayProtectionSummary"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	headline.tooltip_text = ProjectSettings.globalize_path(path)
	details.add_child(headline)
	var explanation := "이 전투·클립과 메모를 자동 정리와 정리 재시도에서 보존합니다. 일반 리플레이 최근 %d개와 별도로 남으며, 새 사본을 만들거나 보관 순서를 바꾸지 않습니다.\n보존 상태는 이 파일에만 저장합니다. 공유·가져오기·새 클립에는 넘기지 않습니다. 직접 삭제·데이터 전체 초기화는 적용되므로 필요한 전투는 게임 밖에도 백업하세요." % BattleReplay.MAX_SAVED
	if not enabled:
		explanation = "보존을 해제하면 이 파일은 일반 리플레이가 되어 다음 저장 또는 정리 재시도 때 오래된 순서에 따라 삭제될 수 있습니다.\n해제만으로 지금 삭제하거나 보관 순서를 갱신하지 않습니다. 필요한 전투·메모는 해제 전에 복사 버튼으로 게임 밖에 백업하세요."
	var warning := MultiplayerUI.label(explanation, 16, UIKit.TEAL if enabled else UIKit.DANGER)
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(warning)
	var status := MultiplayerUI.label(String(snapshot.error), 15, UIKit.DANGER)
	status.name = "ReplayProtectionStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if replay.is_empty() and status.text.is_empty():
		status.text = "읽을 수 없는 파일은 이미 정리 대상에서 제외됩니다. 목록을 새로고침하세요."
	details.add_child(status)
	var close := func():
		if not _dialog_alive(dialog) or main.root_background != background: return
		main._dismiss_action_overlay()
		background.get_tree().process_frame.connect(_restore_code_entry_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	dialog.add_child(actions)
	var confirm := UIKit.style_button(Button.new(), UIKit.TEAL if enabled else UIKit.GOLD_DEEP)
	confirm.name = "ConfirmReplayProtection"
	confirm.text = "이 전투 정리 제외" if enabled else "보존 해제"
	confirm.disabled = replay.is_empty() or not String(snapshot.error).is_empty()
	actions.add_child(confirm)
	var cancel := MultiplayerUI.button(main, actions, "취소", "CancelReplayProtection", close)
	for button in [confirm, cancel]:
		button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var controls: Array[Control] = [scroll, confirm, cancel]
	_bind_challenge_navigation(controls)
	confirm.pressed.connect(func():
		if not _dialog_alive(dialog) or main.root_background != background or confirm.disabled: return
		var result := BattleReplay.set_protected(path, String(snapshot.fingerprint), enabled)
		if not result.ok:
			status.text = String(result.error)
			confirm.disabled = true
			_bind_challenge_navigation(controls)
			scroll.ensure_control_visible.call_deferred(status)
			cancel.grab_focus()
			return
		main._build_replay_list()
		var current_background: Control = main.root_background
		var shelf_status := current_background.find_child("ReplayStatus", true, false) as Label
		if shelf_status != null:
			var notice := "정리 제외했습니다. 이 파일과 메모를 보존합니다." if enabled else "보존을 해제했습니다. 지금 삭제하지 않으며 다음 정리 때 대상이 될 수 있습니다."
			shelf_status.text = notice + ("\n" + shelf_status.text if not shelf_status.text.is_empty() else "")
		_after_replay_list_loaded(current_background, _restore_protection_focus.bind(main, current_background, path)))
	for control in controls:
		control.gui_input.connect(func(event: InputEvent):
			if not event is InputEventKey or not event.pressed or event.alt_pressed or event.ctrl_pressed or event.meta_pressed: return
			if event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call()
			elif control == scroll:
				match event.keycode:
					KEY_UP: scroll.scroll_vertical -= 48
					KEY_DOWN: scroll.scroll_vertical += 48
					KEY_PAGEUP: scroll.scroll_vertical -= maxi(48, int(scroll.size.y))
					KEY_PAGEDOWN: scroll.scroll_vertical += maxi(48, int(scroll.size.y))
					KEY_HOME: scroll.scroll_vertical = 0
					KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
					_: return
				control.accept_event())
	cancel.grab_focus()

static func _restore_protection_focus(main, background: Control, path: String) -> void:
	if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
	var rows := background.find_child("ReplayRows", true, false) as VBoxContainer
	if rows != null:
		for card in rows.get_children():
			if card.visible and String(card.get_meta("replay_path", "")) == path:
				var button := card.find_child("ProtectReplayButton", true, false) as Button
				if button != null:
					_restore_shelf_focus(background, button)
					return
	var search := background.find_child("ReplaySearch", true, false) as Control
	if search != null: _restore_shelf_focus(background, search)

static func _replay_card(main, path: String, replay: Dictionary, file_bytes: int = -1, shelf: ReplayListScreen = null) -> Control:
	var info := describe(replay)
	var tone := UIKit.SUCCESS if info.outcome in ["승리", "블루 승"] else (UIKit.DANGER if info.outcome in ["패배", "레드 승"] else UIKit.TEXT_MUTED)
	var card := PanelContainer.new()
	card.name = "ReplayCard"
	card.set_meta("replay_path", path)
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
	stamp.name = "ReplayFileSize"
	stamp.text = "%s · %s" % [_stamp(path), ReplayListScreen.storage_size_text(file_bytes)]
	stamp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stamp.tooltip_text = "%s\n%s\n클립도 전체 전투 기록과 메모를 담은 파일입니다." % [ProjectSettings.globalize_path(path), ("파일 크기 %d B" % file_bytes if file_bytes >= 0 else "파일 크기를 확인하지 못했습니다. 새로고침해 다시 확인하세요.")]
	stamp.add_theme_font_size_override("font_size", 12)
	stamp.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	text.add_child(stamp)
	if BattleReplay.is_protected(replay):
		var badge := MultiplayerUI.label("✓ 정리 제외 · 전투와 메모 보존", 14, UIKit.TEAL)
		badge.name = "ReplayProtectedBadge"
		badge.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		badge.tooltip_text = "최근 50개와 별도로 남습니다. 직접 삭제·데이터 초기화는 적용됩니다."
		text.add_child(badge)
	for side in 2:
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 2)
		deck_row.tooltip_text = "블루 덱" if side == 0 else "레드 덱"
		row.add_child(deck_row)
		for kind in replay.setup.unit_decks[side]:
			var icon := TextureRect.new()
			icon.tooltip_text = "%s (%s)" % [BattleModel.UNIT_NAMES.get(kind, kind), kind]
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
	_shelf_deck_preview(content, replay, shelf)
	# Keep all actions reachable within the shelf width, including on touch devices.
	var actions := HFlowContainer.new()
	actions.name = "ReplayCardActions"
	actions.alignment = FlowContainer.ALIGNMENT_END
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	content.add_child(actions)
	var action_height := UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 46.0
	var play = main._styled_button("재생", UIKit.ACCENT, true)
	play.name = "PlayReplayButton"
	play.custom_minimum_size = Vector2(100, action_height)
	play.pressed.connect(func():
		# Mouse/touch and keyboard launches all bookmark this exact file/action.
		play.grab_focus()
		main._play_replay(path))
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
	var protect := main._styled_button("보존 해제" if BattleReplay.is_protected(replay) else "정리 제외", UIKit.TEAL, false) as Button
	protect.name = "ProtectReplayButton"
	protect.custom_minimum_size = Vector2(110, UIKit.TOUCH_MIN_HEIGHT)
	protect.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	protect.tooltip_text = "이 파일의 전투·클립·메모를 정리 대상에서 보존하거나 해제합니다."
	protect.pressed.connect(func(): _confirm_replay_protection(main, path, protect))
	actions.add_child(protect)
	actions.add_child(_delete_button(main, path))
	return card

## A compact, readable composition preview; online files do not identify the local side.
static func _shelf_deck_preview(parent: VBoxContainer, replay: Dictionary, shelf: ReplayListScreen = null) -> void:
	var mode := String(replay.get("meta", {}).get("mode", ""))
	var local_battle := mode in ["campaign", "practice", "daily", "draft"]
	var preview := VBoxContainer.new()
	preview.name = "ReplayDeckPreview"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_constant_override("separation", 4)
	parent.add_child(preview)
	var buttons: Array[Button] = []
	var queries := PackedStringArray([_challenge_full_deck_query(replay, 0), _challenge_full_deck_query(replay, 1)])
	for side in 2:
		var units := PackedStringArray()
		var structures := PackedStringArray()
		for kind in replay.setup.unit_decks[side]:
			units.append(String(BattleModel.UNIT_NAMES.get(kind, kind)))
		for kind in replay.setup.structure_decks[side]:
			var definition: Resource = load("res://data/structures/%s.tres" % kind)
			structures.append(String(definition.get("display_name")))
		var side_name := ("내 덱 (블루)" if side == 0 else "상대 덱 (레드)") if local_battle else ("블루 덱" if side == 0 else "레드 덱")
		var label := MultiplayerUI.label("%s · 병력: %s · 구조물: %s" % [side_name, " · ".join(units), " · ".join(structures)], 14, UIKit.TEAM_BLUE.lightened(0.3) if side == 0 else UIKit.TEAM_RED.lightened(0.3))
		label.name = "ReplayBlueDeckPreview" if side == 0 else "ReplayRedDeckPreview"
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.tooltip_text = "저장된 전체 전투의 출전 구성입니다. 실제 생산·설치 수가 아닙니다. 아래 항목을 눌러 해당 진영의 검색 조건을 추가·해제하거나 위 검색칸에서 직접 입력할 수 있습니다.\n" + queries[side]
		preview.add_child(label)
		if shelf == null: continue
		var items := HFlowContainer.new()
		items.name = "ReplayDeckSearchItems%d" % side
		items.mouse_filter = Control.MOUSE_FILTER_IGNORE
		items.add_theme_constant_override("h_separation", 8)
		items.add_theme_constant_override("v_separation", 4)
		preview.add_child(items)
		var choose := _choose_shelf_deck_filter.bind(shelf)
		for kind in replay.setup.unit_decks[side]:
			var button := _challenge_deck_button(String(kind), String(BattleModel.UNIT_NAMES.get(kind, kind)), side, choose)
			button.name = "ReplayUnitFilter%d_%s" % [side, kind]
			button.set_meta("deck_side_name", side_name)
			items.add_child(button)
			buttons.append(button)
		for index in replay.setup.structure_decks[side].size():
			var kind := String(replay.setup.structure_decks[side][index])
			var button := _challenge_deck_button(kind, structures[index], side, choose)
			button.name = "ReplayStructureFilter%d_%s" % [side, kind]
			button.set_meta("deck_side_name", side_name)
			items.add_child(button)
			buttons.append(button)
		var whole := _challenge_full_deck_button(queries, side, choose)
		whole.name = "ReplayFullDeckFilter%d" % side
		whole.set_meta("full_deck_title", side_name)
		items.add_child(whole)
		buttons.append(whole)
	if shelf != null:
		var pair := _challenge_full_deck_button(queries, -1, _choose_shelf_deck_filter.bind(shelf))
		pair.name = "ReplayBothDeckFilter"
		var actions := HFlowContainer.new()
		actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(actions)
		actions.add_child(pair)
		buttons.append(pair)
	preview.set_meta("deck_filter_buttons", buttons)

static func _choose_shelf_deck_filter(button: Button, shelf: ReplayListScreen) -> void:
	if not _dialog_alive(shelf) or not _dialog_alive(button) or not button.is_visible_in_tree(): return
	var queries: PackedStringArray = shelf.deck_queries()
	var side := int(button.get_meta("deck_side"))
	var message: String
	if button.has_meta("full_deck_queries"):
		var removing := _challenge_full_deck_selected(button, queries)
		var expected: PackedStringArray = button.get_meta("full_deck_queries")
		for target in 2:
			if side < 0 or side == target: queries[target] = "" if removing else expected[target]
		message = "%s 검색 %s · 전체 검색·필터·정렬%s 조건은 유지합니다." % [String(button.get_meta("full_deck_title", "양쪽 덱")), "해제" if removing else "조건을 이 카드의 전체 구성으로 교체했습니다", "·다른 덱" if side >= 0 else ""]
	else:
		var kind := String(button.get_meta("deck_kind"))
		var title := String(button.get_meta("deck_title"))
		var removing := _challenge_deck_term_selected(queries[side], kind, title)
		queries[side] = _challenge_toggle_deck_term(queries[side], kind, title)
		message = "%s 검색: %s %s · 다른 검색·필터·정렬 조건은 유지합니다." % [String(button.get_meta("deck_side_name")), title, "해제" if removing else "추가"]
	shelf.apply_deck_queries(queries, button, message)

## Refresh only the current page, including reused cards after typing or paging.
static func _refresh_shelf_deck_buttons(queries: PackedStringArray, shelf: ReplayListScreen) -> void:
	if not _dialog_alive(shelf): return
	for preview in shelf.find_children("ReplayDeckPreview", "VBoxContainer", true, false):
		for button in preview.get_meta("deck_filter_buttons", []):
			if button.has_meta("full_deck_queries"):
				_refresh_challenge_full_deck_button(button, queries)
			else:
				_refresh_challenge_deck_button(button, queries[int(button.get_meta("deck_side"))])

## An empty reply identifies no reason: do not assert that a code expired or was deleted.
static func _replay_fetch_error(code: String, text: String) -> String:
	if text.strip_edges().is_empty():
		return "%s 코드의 리플레이를 현재 서버에서 찾을 수 없습니다. 코드·서버 주소를 확인하세요. 이미 저장했다면 리플레이 보관함에서 찾을 수 있습니다." % code
	return "%s 코드의 응답을 리플레이로 읽을 수 없습니다. 지원하지 않는 형식이거나 내용이 손상되었을 수 있습니다. 보낸 사람에게 리플레이 텍스트를 요청하세요." % code

## Read-only guidance. Opening it never fetches, saves, prunes or creates a directory.
static func _show_replay_storage_help(main, return_to: Callable) -> void:
	var dialog: VBoxContainer = main._action_panel("리플레이 보관·복구 도움말", Rect2(230, 50, 820, 620))
	var scroll := ScrollContainer.new()
	scroll.name = "ReplayStorageHelpScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_ALL
	scroll.follow_focus = true
	dialog.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var paragraphs := [
		["코드를 찾을 수 없을 때", "코드와 멀티플레이 설정의 서버 주소를 확인하세요. 코드는 발급한 서버에서 열어야 합니다. 서버에서 전투를 찾지 못해도 정리된 코드라고 확정할 수는 없습니다. 오타·다른 서버 접속·서버의 파일 읽기 실패로도 열리지 않을 수 있습니다."],
		["서버 보관은 영구적이지 않습니다", "서버는 공유 코드와 공개 전투를 합쳐 최근 %d개를 보관합니다. 새 전투·공유 업로드로 오래된 코드가 정리될 수 있으며 고정 만료 시간은 없습니다. 최근 공개 목록은 최대 %d개라 목록에 없어도 코드로 열릴 수 있습니다. 코드 복사·재조회는 전투를 백업하거나 보관 순서를 갱신하지 않습니다." % [ServerReplayShelf.MAX_STORED, ServerReplayShelf.RECENT_LIMIT]],
		["이미 저장한 전투 찾기", "코드·최근 온라인 전투로 본 리플레이는 로컬 보관을 눌렀거나 메모 저장에 성공했을 때 이 기기에 남습니다. 아래 보관함에서 찾기는 검색·필터를 해제해 전체 목록을 보여 줍니다. 날짜·병력·메모로 찾으세요. 이 기기에 저장하지 않은 전투는 목록에 나타나지 않습니다."],
		["중요한 전투는 정리 제외", "보관함 카드의 정리 제외로 전투·클립·메모를 일반 리플레이 최근 %d개와 별도로 남길 수 있습니다. 새 사본을 만들거나 보관 순서를 바꾸지 않으며, 보존 해제만으로 지금 삭제하지 않습니다. 직접 삭제·데이터 초기화에는 적용되지 않고 다른 기기로 공유한 사본은 별도로 정리 제외해야 합니다." % BattleReplay.MAX_SAVED],
		["다른 사람에게 다시 받거나 백업하기", "저장한 사본이 없다면 보낸 사람에게 보관한 전투의 복사 버튼으로 리플레이 텍스트를 요청하세요. 리플레이 → 클립보드에서 가져오기로 저장할 수 있습니다. 정리 제외도 게임 밖의 백업은 아니므로 카드의 복사 버튼으로 텍스트를 따로 보관하거나 아래 폴더의 JSON 파일을 다른 곳에 복사하세요. 모바일의 앱 전용 폴더는 파일 앱에서 접근하지 못할 수 있으니 텍스트 복사를 이용하세요. 경로 복사만으로 파일이 백업되지는 않습니다."]
	]
	for paragraph in paragraphs:
		var heading := MultiplayerUI.label(String(paragraph[0]), 18, UIKit.GOLD)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(heading)
		var explanation := MultiplayerUI.label(String(paragraph[1]), 15, UIKit.TEXT)
		explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(explanation)
	var path := ProjectSettings.globalize_path(BattleReplay.save_dir)
	var path_label := MultiplayerUI.label("이 기기의 실제 보관 경로 (저장 전에는 폴더가 없을 수 있습니다)", 14, UIKit.TEXT_MUTED)
	path_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(path_label)
	var path_row := HBoxContainer.new()
	path_row.add_theme_constant_override("separation", 10)
	dialog.add_child(path_row)
	var path_input := LineEdit.new()
	path_input.name = "ReplayStoragePath"
	path_input.text = path
	path_input.editable = false
	path_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_input.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	path_input.tooltip_text = "이 기기의 실제 저장 경로입니다. 모바일에서는 앱 전용 폴더라 파일 앱에서 접근하지 못할 수 있습니다. 전투 카드의 복사로 텍스트를 백업할 수 있습니다."
	path_row.add_child(path_input)
	var copy_path := UIKit.style_button(Button.new(), UIKit.TEAL)
	copy_path.name = "CopyReplayStoragePath"
	copy_path.text = "경로 복사"
	copy_path.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	copy_path.disabled = not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD)
	copy_path.tooltip_text = "경로만 복사하며 리플레이 파일을 복사하거나 백업하지 않습니다." if not copy_path.disabled else "이 환경에서는 클립보드를 사용할 수 없습니다. 표시된 경로를 직접 확인하세요."
	copy_path.pressed.connect(func():
		if not _dialog_alive(dialog): return
		DisplayServer.clipboard_set(path)
		copy_path.text = "경로 복사됨")
	path_row.add_child(copy_path)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	dialog.add_child(footer)
	var find_local := UIKit.style_button(Button.new(), UIKit.ACCENT)
	find_local.name = "FindLocalReplays"
	find_local.text = "보관함에서 찾기"
	find_local.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	find_local.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	find_local.tooltip_text = "보관함의 검색·종류·결과·클립·보존 조건을 해제하고 이 기기의 전체 목록으로 이동합니다. 서버 요청은 하지 않습니다."
	find_local.pressed.connect(func():
		if not _dialog_alive(dialog): return
		main.replay_list_state.clear()
		main._build_replay_list()
		var background: Control = main.root_background
		var focus_search := func():
			if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
			var search := background.find_child("ReplaySearch", true, false) as Control
			if search != null: search.grab_focus()
		_after_replay_list_loaded(background, focus_search))
	footer.add_child(find_local)
	var close_dialog := func():
		if _dialog_alive(dialog): return_to.call()
	var close := MultiplayerUI.button(main, footer, "돌아가기", "CloseReplayStorageHelp", close_dialog)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	var controls: Array[Control] = [scroll, path_input, copy_path, find_local, close]
	_bind_challenge_navigation(controls)
	for control in controls:
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close_dialog.call())
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
	scroll.grab_focus()

## Validate the entire clipboard/input. Never extract a prefix from a longer message.
static func _replay_code_from_text(text: String) -> String:
	var code := text.strip_edges().to_upper()
	return code if NetworkProtocol.is_valid_room_code(code) else ""

## Asks for a six-character code and plays the replay it names.
static func _show_code_dialog(main, return_code: String = "", return_notice: String = "") -> void:
	var background: Control = main.root_background
	var return_focus: Control = main.get_viewport().gui_get_focus_owner()
	var focus_ref: WeakRef = weakref(return_focus) if return_focus != null else null
	var dialog = main._action_panel("코드로 열기", Rect2(320, 100, 640, 520))
	var hint := MultiplayerUI.label("공유받은 6자리 코드를 입력하거나 붙여넣으세요. 열기를 누르면 필요에 따라 서버에 접속합니다.", 14, MultiplayerUI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(hint)
	var input_row := HBoxContainer.new()
	input_row.name = "ReplayCodeInputRow"
	input_row.add_theme_constant_override("separation", 12)
	dialog.add_child(input_row)
	var input := LineEdit.new()
	input.name = "ReplayCodeInput"
	# A length limit would silently turn a pasted longer value into a valid prefix.
	# Keep the full value so both typing and the native paste action are validated.
	input.placeholder_text = "ABC234"
	input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	input.add_theme_font_size_override("font_size", 28)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	input.text = return_code
	input.text_changed.connect(func(text):
		var caret := input.caret_column
		input.text = text.to_upper()
		input.caret_column = caret)
	input_row.add_child(input)
	var paste: Button = main._styled_button("붙여넣기", UIKit.TEAL, false)
	paste.name = "PasteReplayCode"
	paste.custom_minimum_size = Vector2(150, UIKit.TOUCH_MIN_HEIGHT)
	paste.tooltip_text = "클립보드의 6자리 공유 코드를 확인한 뒤 입력합니다. 앞뒤 공백과 소문자는 자동으로 정리하며, 열기를 눌러야 불러옵니다."
	input_row.add_child(paste)
	var status := MultiplayerUI.label("", 14, MultiplayerUI.GOLD)
	status.name = "ReplayCodeStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not return_notice.is_empty():
		status.text = return_notice
	elif not return_code.is_empty():
		status.text = "%s 코드의 재생에서 돌아왔습니다. 열기로 다시 보거나 다른 코드를 입력하세요." % return_code
	dialog.add_child(status)
	var actions := HBoxContainer.new()
	actions.name = "ReplayCodeActions"
	actions.add_theme_constant_override("separation", 12)
	dialog.add_child(actions)
	var open_button: Button = main._styled_button("열기", UIKit.ACCENT, true)
	open_button.name = "OpenReplayCode"
	open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open_button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	actions.add_child(open_button)
	var cancel: Button = main._styled_button("불러오기 취소", UIKit.TEAL, false)
	cancel.name = "CancelReplayCodeFetch"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	cancel.tooltip_text = "이 전투의 불러오기를 취소합니다. 창과 입력한 코드는 유지하며 다른 코드를 바로 열 수 있습니다."
	cancel.visible = false
	cancel.disabled = true
	actions.add_child(cancel)
	var close_dialog := func():
		if not _dialog_alive(dialog): return
		# Dispose immediately so a response in the closing frame cannot open a viewer.
		ReplayRequest.cancel_fetch(main, dialog)
		main._dismiss_action_overlay()
		background.get_tree().process_frame.connect(_restore_code_entry_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	dialog.add_child(footer)
	var help := UIKit.style_button(Button.new(), UIKit.TEAL)
	help.name = "ReplayCodeStorageHelp"
	help.text = "보관·복구 도움말"
	help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	help.pressed.connect(func():
		if not _dialog_alive(dialog) or open_button.disabled: return
		var code := input.text
		var notice := status.text if not status.text.is_empty() else "보관·복구 도움말에서 돌아왔습니다. 코드를 입력하고 열기를 눌러 불러오세요."
		# Retain strings and the original entry's weak reference, never this dialog's controls.
		var resume := func():
			if not _dialog_alive(background) or main.root_background != background: return
			main._dismiss_action_overlay()
			_restore_code_entry_focus(main, background, focus_ref)
			_show_code_dialog(main, code, notice)
		_show_replay_storage_help(main, resume))
	footer.add_child(help)
	var close := MultiplayerUI.button(main, footer, "닫기", "CloseReplayCode", close_dialog)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	var update_navigation := func(): _bind_code_navigation([input, paste, open_button, cancel, help, close], close_dialog)
	var pending := {"active": false}
	paste.pressed.connect(func():
		if not _dialog_alive(dialog) or bool(pending.active): return
		var text := DisplayServer.clipboard_get()
		var code := _replay_code_from_text(text)
		if code.is_empty():
			status.text = "클립보드가 비어 있습니다. 공유받은 6자리 코드를 복사한 뒤 다시 붙여넣으세요." if text.strip_edges().is_empty() else "클립보드에 유효한 공유 코드가 없습니다. 6자리 코드만 복사하세요. I·O·0·1은 사용할 수 없습니다."
			input.grab_focus()
			return
		input.text = code
		input.caret_column = code.length()
		input.grab_focus()
		input.select_all()
		status.text = "%s 코드를 붙여넣었습니다. 열기를 눌러 불러오세요." % code)
	cancel.pressed.connect(func():
		if not _dialog_alive(dialog) or not bool(pending.active): return
		ReplayRequest.cancel_fetch(main, dialog)
		pending.active = false
		cancel.visible = false
		cancel.disabled = true
		open_button.disabled = false
		paste.disabled = false
		help.disabled = false
		input.editable = true
		status.text = "불러오기를 취소했습니다. 코드를 수정하거나 열기를 눌러 다시 시도하세요."
		update_navigation.call()
		input.grab_focus())
	var open_code := func():
		if not _dialog_alive(dialog) or bool(pending.active):
			return
		var code := _replay_code_from_text(input.text)
		if code.is_empty():
			status.text = "영문·숫자 6자리 코드를 입력하세요. I·O·0·1과 코드 중간의 공백은 사용할 수 없습니다."
			input.grab_focus()
			return
		input.text = code
		pending.active = true
		open_button.disabled = true
		paste.disabled = true
		help.disabled = true
		input.editable = false
		cancel.visible = true
		cancel.disabled = false
		update_navigation.call()
		var fail := func(text: String):
			if not _dialog_alive(dialog): return
			var restore_focus := cancel.has_focus()
			pending.active = false
			cancel.visible = false
			cancel.disabled = true
			open_button.disabled = false
			paste.disabled = false
			help.disabled = false
			input.editable = true
			status.text = Localization.text(text)
			update_navigation.call()
			if restore_focus: input.grab_focus()
		var result := func(text: String):
			if not _dialog_alive(dialog): return
			var replay := BattleReplay.from_share_text(text)
			if replay.is_empty():
				fail.call(_replay_fetch_error(code, text) + "\n보관·복구 도움말에서 보관 정책과 복구 방법을 확인하세요.")
				return
			# Retain only the code; the viewer must not keep this dialog's controls alive.
			_open_viewer(main, replay, "", _return_to_code_dialog.bind(main, code), "코드 입력 창으로 돌아갑니다. 입력한 코드를 유지하며 다시 보거나 다른 코드를 입력할 수 있습니다.")
		ReplayRequest.start(main, dialog, "fetch", code, result, fail, func(text): status.text = Localization.text(text))
		if _dialog_alive(dialog) and bool(pending.active): cancel.grab_focus()
	open_button.pressed.connect(open_code)
	input.text_submitted.connect(func(_text): open_code.call())
	update_navigation.call()
	input.grab_focus()
	if not return_code.is_empty(): input.select_all()

## The code dialog only needs its footer button, which exists during shelf loading.
## Restore immediately without reconnecting, downloading or waiting for local files.
static func _return_to_code_dialog(main, code: String) -> void:
	main._build_replay_list()
	var entry := main.root_background.find_child("OpenByCodeButton", true, false) as Button
	if entry != null: entry.grab_focus()
	_show_code_dialog(main, code)

static func _restore_code_entry_focus(main, background: Control, focus_ref: WeakRef) -> void:
	if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
	var target: Control = focus_ref.get_ref() if focus_ref != null else null
	if not is_instance_valid(target) or not target.is_visible_in_tree() or not background.is_ancestor_of(target):
		target = background.find_child("OpenByCodeButton", true, false) as Control
	if target == null or (target is BaseButton and target.disabled): return
	target.grab_focus()

## Keep Tab inside this dialog while the input/open action is locked for a download.
static func _bind_code_navigation(candidates: Array[Control], close_dialog: Callable) -> void:
	var controls: Array[Control] = []
	for control in candidates:
		if not control.is_visible_in_tree(): continue
		if control is BaseButton and control.disabled: continue
		if control is LineEdit and not control.editable: continue
		controls.append(control)
	for index in controls.size():
		var control := controls[index]
		control.focus_previous = control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		if control.has_meta("ReplayCodeNavigationBound"): continue
		control.set_meta("ReplayCodeNavigationBound", true)
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close_dialog.call())

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
	# The fetch belongs to the dialog, so replacing/filtering cards cannot abandon it.
	var watch_state := {"active": false, "code": "", "message": "", "failed": false, "cancelled": false}
	var watch_status := MultiplayerUI.label("", 14, UIKit.TEXT_MUTED)
	watch_status.name = "RecentBattleRequestStatus"
	watch_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	watch_status.visible = false
	dialog.add_child(watch_status)
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
	refresh.tooltip_text = "서버에서 최신 공개 목록을 다시 조회합니다. 검색 조건·스크롤 위치와 진행 중인 전투 보기 요청은 유지합니다."
	footer.add_child(refresh)
	var cancel: Button = main._styled_button("불러오기 취소", UIKit.TEAL, false)
	cancel.name = "CancelRecentBattleFetch"
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	cancel.tooltip_text = "선택한 전투의 불러오기를 취소합니다. 검색·스크롤·목록 새로고침은 유지하며 다른 전투를 바로 선택할 수 있습니다."
	cancel.visible = false
	cancel.disabled = true
	footer.add_child(cancel)
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
		_update_recent_watch(rows, watch_state, watch_status, cancel)
		_bind_recent_navigation(scroll, rows, refresh, close, close_dialog, filter_controls, cancel)
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
	var update_watch := func():
		if not _dialog_alive(dialog): return
		var restore_focus := cancel.has_focus() and not bool(watch_state.active)
		_update_recent_watch(rows, watch_state, watch_status, cancel)
		_bind_recent_navigation(scroll, rows, refresh, close, close_dialog, filter_controls, cancel)
		if restore_focus:
			scroll.grab_focus()
			for item in pending.entries:
				if String(item.entry.code) == String(watch_state.code) and item.card.is_visible_in_tree():
					var watch := item.card.find_child("WatchRecentBattle", true, false) as Button
					if watch != null and not watch.disabled: watch.grab_focus()
					break
	cancel.pressed.connect(func():
		if not _dialog_alive(dialog) or not bool(watch_state.active): return
		ReplayRequest.cancel_fetch(main, dialog)
		watch_state.active = false
		watch_state.failed = false
		watch_state.cancelled = true
		watch_state.message = "불러오기를 취소했습니다. 해당 카드의 보기 또는 다른 전투를 선택하세요."
		update_watch.call())
	var watch_request := func(code: String):
		if not _dialog_alive(dialog) or bool(watch_state.active): return
		watch_state.active = true
		watch_state.code = code
		watch_state.failed = false
		watch_state.cancelled = false
		watch_state.message = "요청 준비 중..."
		update_watch.call()
		var fail := func(message: String):
			if not _dialog_alive(dialog): return
			watch_state.active = false
			watch_state.failed = true
			watch_state.message = Localization.text(message)
			update_watch.call()
		var result := func(replay_text: String):
			if not _dialog_alive(dialog): return
			var replay := BattleReplay.from_share_text(replay_text)
			if replay.is_empty():
				fail.call(_replay_fetch_error(code, replay_text) + " 목록을 새로고침하거나 다른 전투를 선택하세요.")
				return
			watch_state.active = false
			play.call(replay, code)
		var progress := func(message: String):
			if not _dialog_alive(dialog): return
			watch_state.message = Localization.text(message)
			update_watch.call()
		ReplayRequest.start(main, dialog, "fetch", code, result, fail, progress)
		if _dialog_alive(dialog) and bool(watch_state.active): cancel.grab_focus()
	var show_list := func(list: Array, from_cache: bool = false):
		if not _dialog_alive(dialog): return
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
			var row := _recent_row(main, entry, now, play, watch_request)
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
			if is_instance_valid(next_focus) and next_focus.is_visible_in_tree() and not (next_focus is BaseButton and next_focus.disabled): next_focus.grab_focus()
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
			update_watch.call()
		ReplayRequest.start(main, dialog, "recent", "", show_list, fail, func(text): status.text = Localization.text(text))
		update_watch.call()
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

## Keep progress visible even when the requested code is filtered out or leaves the latest list.
static func _update_recent_watch(rows: VBoxContainer, state: Dictionary, status: Label, cancel: Button = null) -> void:
	var active := bool(state.active)
	var failed := bool(state.failed)
	var cancelled := bool(state.get("cancelled", false))
	if cancel != null:
		cancel.visible = active
		cancel.disabled = not active
	var selected_code := String(state.code)
	var selected_visible := false
	for row in rows.get_children():
		var watch := row.find_child("WatchRecentBattle", true, false) as Button
		if watch == null: continue
		var selected := String(watch.get_meta("ReplayCode", "")) == selected_code
		if selected and row.visible: selected_visible = true
		watch.disabled = active
		watch.text = "불러오는 중" if active and selected else ("재시도" if failed and selected else "보기")
		watch.tooltip_text = String(state.message) if selected else ("불러오기 취소 후 다른 전투를 선택할 수 있습니다. 코드 복사·검색·새로고침·닫기도 사용할 수 있습니다." if active else "전투를 불러와 재생합니다.")
		var detail := row.find_child("RecentBattleWatchStatus", true, false) as Label
		if detail != null:
			detail.visible = selected and (active or failed or cancelled)
			detail.text = String(state.message)
			detail.add_theme_color_override("font_color", UIKit.DANGER if failed else UIKit.TEXT_MUTED)
	status.visible = active or failed or cancelled
	status.add_theme_color_override("font_color", UIKit.DANGER if failed else UIKit.TEXT_MUTED)
	status.text = "%s · %s" % [selected_code, String(state.message)]
	if active:
		status.text += "\n검색·새로고침 중에도 이 전투를 계속 불러옵니다. 불러오기 취소 또는 창 닫기로 재생을 중단할 수 있습니다."
	elif failed:
		status.text += "\n해당 카드의 재시도를 누르거나 다른 전투를 선택하세요."
	if not selected_visible and (active or failed or cancelled):
		status.text += "\n선택한 코드는 현재 표시 목록에 없습니다." + (" 검색 조건을 초기화하거나 목록을 새로고침해 확인하세요." if failed or cancelled else "")

static func _recent_row(main, entry: Dictionary, now: int = -1, on_watch: Callable = Callable(), on_request: Callable = Callable()) -> Control:
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
		if on_request.is_valid():
			on_request.call(String(entry.code))
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
				fail.call(_replay_fetch_error(String(entry.code), replay_text) + " 목록을 새로고침하거나 다른 전투를 선택하세요.")
				return
			if on_watch.is_valid():
				on_watch.call(replay, String(entry.code))
			else:
				main._dismiss_action_overlay()
				_play_replay_data(main, replay)
		ReplayRequest.start(main, watch, "fetch", String(entry.code), result, fail, func(_text): watch.text = "불러오는 중"))
	line.add_child(watch)
	var detail := MultiplayerUI.label("", 14, UIKit.TEXT_MUTED)
	detail.name = "RecentBattleWatchStatus"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.visible = false
	content.add_child(detail)
	return card

static func _bind_recent_navigation(scroll: ScrollContainer, rows: VBoxContainer, refresh: Button, close: Button, close_dialog: Callable, filter_controls: Array[Control] = [], cancel: Button = null) -> void:
	var controls: Array[Control] = []
	for control in filter_controls:
		if control is BaseButton and (control as BaseButton).disabled: continue
		controls.append(control)
	controls.append(scroll)
	for row in rows.get_children():
		if not row.visible: continue
		for button_name in ["CopyRecentBattleCode", "WatchRecentBattle"]:
			var button := row.find_child(button_name, true, false) as Control
			if button != null and not (button is BaseButton and button.disabled): controls.append(button)
	if not refresh.disabled: controls.append(refresh)
	if cancel != null and cancel.visible and not cancel.disabled: controls.append(cancel)
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
		var status := main.root_background.find_child("ReplayStatus", true, false) as Label
		if status != null:
			var notice := "선택한 전투를 재생할 수 없습니다. 파일이 없어졌거나 읽을 수 없는 상태입니다. 보관함에서 다른 전투를 선택하세요."
			status.text = notice + ("\n" + status.text if not status.text.is_empty() else "")
		return
	_open_viewer(main, replay, path, main._build_replay_list, "리플레이 보관함의 검색 조건·카드 위치·재생 버튼 초점으로 돌아갑니다.")

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

## Rebuild records first, then reopen the selection after its navigation has settled.
## The viewer's return callback keeps summaries and strings, never the old dialog's nodes.
static func _return_to_challenge_replays(main, period: String, date: String, ruleset: String, record: Dictionary, view_state: Dictionary) -> void:
	main.records_state["focus"] = String(view_state.get("records_focus", ""))
	main._build_records_screen()
	var background: Control = main.root_background
	var reopen := func():
		if not _dialog_alive(background) or main.root_background != background or is_instance_valid(main.action_overlay): return
		var target: Control = main.get_viewport().gui_get_focus_owner()
		if target == null or not background.is_ancestor_of(target):
			target = background.find_child("RecordsScroll", true, false) as Control
		_show_challenge_replays(main, period, date, ruleset, record, target, view_state)
	background.get_tree().process_frame.connect(reopen, CONNECT_ONE_SHOT)

## Read the decks recorded for this battle, including clips and older versions.
## Do not regenerate a challenge from the date or substitute the player's current deck.
static func _challenge_deck_preview(parent: VBoxContainer, replay: Dictionary, choose: Callable, choose_full_deck: Callable = Callable()) -> Array[Button]:
	var buttons: Array[Button] = []
	var setup: Dictionary = replay.get("setup", {})
	if not setup.has_all(["unit_decks", "structure_decks"]):
		return buttons
	var preview := VBoxContainer.new()
	preview.name = "ChallengeReplayDecks"
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_constant_override("separation", 6)
	parent.add_child(preview)
	var deck_queries := PackedStringArray([_challenge_full_deck_query(replay, 0), _challenge_full_deck_query(replay, 1)])
	for side in 2:
		var tone := UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
		var heading_row := HFlowContainer.new()
		heading_row.add_theme_constant_override("h_separation", 12)
		heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(heading_row)
		var heading := MultiplayerUI.label("내 덱 (블루)" if side == 0 else "상대 덱 (레드)", 14, tone.lightened(0.3))
		heading.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if choose_full_deck.is_valid() else 0.0
		heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		heading_row.add_child(heading)
		if choose_full_deck.is_valid():
			var whole := _challenge_full_deck_button(deck_queries, side, choose_full_deck)
			heading_row.add_child(whole)
			buttons.append(whole)
		var units := HFlowContainer.new()
		units.name = "ChallengeUnitDeck%d" % side
		units.mouse_filter = Control.MOUSE_FILTER_IGNORE
		units.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		units.add_theme_constant_override("h_separation", 12)
		units.add_theme_constant_override("v_separation", 4)
		preview.add_child(units)
		for kind in setup.unit_decks[side]:
			var item := _challenge_deck_button(String(kind), String(BattleModel.UNIT_NAMES.get(kind, kind)), side, choose)
			item.name = "ChallengeUnitFilter%d_%s" % [side, kind]
			item.icon = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
			item.expand_icon = true
			item.add_theme_constant_override("icon_max_width", 28)
			item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			units.add_child(item)
			buttons.append(item)
		var structures := HFlowContainer.new()
		structures.name = "ChallengeStructureDeck%d" % side
		structures.mouse_filter = Control.MOUSE_FILTER_IGNORE
		structures.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		structures.add_theme_constant_override("h_separation", 12)
		structures.add_theme_constant_override("v_separation", 4)
		preview.add_child(structures)
		var structure_label := MultiplayerUI.label("구조물:", 14, UIKit.TEXT_MUTED)
		structure_label.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		structure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		structure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		structures.add_child(structure_label)
		for kind in setup.structure_decks[side]:
			var definition: Resource = load("res://data/structures/%s.tres" % kind)
			var item := _challenge_deck_button(String(kind), String(definition.get("display_name")), side, choose)
			item.name = "ChallengeStructureFilter%d_%s" % [side, kind]
			structures.add_child(item)
			buttons.append(item)
	if choose_full_deck.is_valid():
		var actions := HFlowContainer.new()
		actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
		preview.add_child(actions)
		var pair := _challenge_full_deck_button(deck_queries, -1, choose_full_deck)
		actions.add_child(pair)
		buttons.append(pair)
	return buttons

## IDs describe composition, not button order or the units actually produced.
static func _challenge_full_deck_query(replay: Dictionary, side: int) -> String:
	var setup: Dictionary = replay.get("setup", {})
	if not setup.has_all(["unit_decks", "structure_decks"]): return ""
	var terms := PackedStringArray()
	for deck in [setup.unit_decks[side], setup.structure_decks[side]]:
		for kind in deck:
			if not terms.has(String(kind)): terms.append(String(kind))
	return " ".join(terms)

static func _challenge_full_deck_button(queries: PackedStringArray, side: int, choose: Callable) -> Button:
	var tone := UIKit.TEAL if side < 0 else (UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED)
	var button := UIKit.style_button(Button.new(), tone, false, 14)
	button.name = "ChallengeBothDeckFilter" if side < 0 else "ChallengeFullDeckFilter%d" % side
	button.custom_minimum_size = Vector2(180, UIKit.TOUCH_MIN_HEIGHT)
	button.toggle_mode = true
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.set_meta("full_deck_queries", queries)
	button.set_meta("deck_side", side)
	var chosen_styles := UIKit.button_styles(tone, true)
	button.add_theme_stylebox_override("pressed", chosen_styles.normal)
	button.add_theme_stylebox_override("hover_pressed", chosen_styles.hover)
	button.pressed.connect(choose.bind(button))
	return button

## A whole-deck toggle is selected only when it owns all terms in the target field.
## Extra manual conditions must not be silently erased by treating a superset as selected.
static func _challenge_full_deck_selected(button: Button, queries: PackedStringArray) -> bool:
	var expected: PackedStringArray = button.get_meta("full_deck_queries")
	var side := int(button.get_meta("deck_side"))
	for target in 2:
		if side >= 0 and target != side: continue
		var wanted := _challenge_deck_terms(expected[target].to_lower())
		var actual := _challenge_deck_terms(queries[target].to_lower())
		if wanted.is_empty() or actual.size() != wanted.size(): return false
		for term in wanted:
			if not actual.has(term): return false
	return true

static func _refresh_challenge_full_deck_button(button: Button, queries: PackedStringArray) -> void:
	var selected := _challenge_full_deck_selected(button, queries)
	var side := int(button.get_meta("deck_side"))
	var title := String(button.get_meta("full_deck_title", "양쪽 덱" if side < 0 else ("내 덱" if side == 0 else "상대 덱")))
	button.set_pressed_no_signal(selected)
	button.text = ("✓ %s 검색 해제" if selected else "%s 전체 검색") % title
	button.tooltip_text = ("%s 검색칸만 비웁니다. 다른 검색·필터·정렬 조건은 유지합니다." if selected else "%s 검색칸을 이 카드의 병력·구조물 전체 영문 ID로 교체합니다. 해당 칸의 기존 검색어는 대체하고 다른 조건은 유지합니다. 출전 순서는 구분하지 않으며 클립도 전체 전투의 덱을 사용합니다.") % title

static func _challenge_deck_button(kind: String, title: String, side: int, choose: Callable) -> Button:
	var tone := UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
	var button := UIKit.style_button(Button.new(), tone, false, 14)
	button.custom_minimum_size = Vector2(96, UIKit.TOUCH_MIN_HEIGHT)
	button.toggle_mode = true
	# ScrollContainer can cancel a touch press when it becomes a drag.
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.set_meta("deck_side", side)
	button.set_meta("deck_kind", kind)
	button.set_meta("deck_title", title)
	button.text = title
	var chosen_styles := UIKit.button_styles(tone, true)
	button.add_theme_stylebox_override("pressed", chosen_styles.normal)
	button.add_theme_stylebox_override("hover_pressed", chosen_styles.hover)
	button.pressed.connect(choose.bind(button))
	return button

static func _challenge_deck_terms(query: String) -> PackedStringArray:
	return query.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)

static func _challenge_deck_term_selected(query: String, kind: String, title: String) -> bool:
	var terms := _challenge_deck_terms(query.to_lower())
	return terms.has(kind.to_lower()) or terms.has(title.to_lower())

## Preserve all other terms. Only exact names/IDs are toggled; partial searches stay intact.
static func _challenge_toggle_deck_term(query: String, kind: String, title: String) -> String:
	var terms := _challenge_deck_terms(query)
	if _challenge_deck_term_selected(query, kind, title):
		var kept := PackedStringArray()
		for term in terms:
			if term.to_lower() != kind.to_lower() and term.to_lower() != title.to_lower(): kept.append(term)
		return " ".join(kept)
	# IDs distinguish names such as 마법사 and 흑마법사 that overlap in text search.
	terms.append(kind)
	return " ".join(terms)

static func _refresh_challenge_deck_button(button: Button, query: String) -> void:
	var kind := String(button.get_meta("deck_kind"))
	var title := String(button.get_meta("deck_title"))
	var selected := _challenge_deck_term_selected(query, kind, title)
	button.set_pressed_no_signal(selected)
	button.text = ("✓ " if selected else "") + title
	var side_name := String(button.get_meta("deck_side_name", "내 덱 (블루)" if int(button.get_meta("deck_side")) == 0 else "상대 덱 (레드)"))
	button.tooltip_text = "%s 검색에서 %s (%s) %s · 종류를 구분하는 영문 ID로 추가합니다. 다른 검색·필터·정렬 조건은 유지합니다. 부분 검색어는 직접 수정하세요." % [side_name, title, kind, "해제" if selected else "추가"]

## Build once from the saved decks; filtering never reloads files or simulates battles.
static func _challenge_deck_search_text(replay: Dictionary, side: int) -> String:
	var setup: Dictionary = replay.get("setup", {})
	if not setup.has_all(["unit_decks", "structure_decks"]): return ""
	var parts := PackedStringArray()
	for kind in setup.unit_decks[side]:
		parts.append("%s %s" % [kind, BattleModel.UNIT_NAMES.get(kind, kind)])
	for kind in setup.structure_decks[side]:
		var definition: Resource = load("res://data/structures/%s.tres" % kind)
		parts.append("%s %s" % [kind, definition.get("display_name")])
	return " ".join(parts).to_lower()

static func _challenge_search_text(entry: Dictionary) -> String:
	var replay: Dictionary = entry.replay
	var info := describe(replay)
	var parts := PackedStringArray([_stamp(String(entry.path)), String(entry.path).get_file(), String(info.title), String(info.outcome), String(info.duration), String(info.clip_range), String(info.clip_length)])
	parts.append("클립" if not replay.clip.is_empty() else "전체 전투")
	var rule := ChallengeReplays.ruleset_of(replay)
	parts.append("버전 미상" if rule == "0" else "버전 " + rule)
	var deck_search: PackedStringArray = entry.get("deck_search", PackedStringArray())
	for side in 2:
		parts.append(deck_search[side] if deck_search.size() == 2 else _challenge_deck_search_text(replay, side))
	return " ".join(parts).to_lower()

static func _challenge_query_matches(text: String, query: String) -> bool:
	for term in _challenge_deck_terms(query.to_lower()):
		if not text.contains(term): return false
	return true

static func _challenge_matches(entry: Dictionary, query: String, outcome: int, scope: int, my_query: String = "", opponent_query: String = "") -> bool:
	if outcome > 0 and int(entry.replay.result.winner) != outcome - 1: return false
	if scope > 0 and (not entry.replay.clip.is_empty()) != (scope == 2): return false
	if not _challenge_query_matches(String(entry.search), query): return false
	var deck_search: PackedStringArray = entry.get("deck_search", PackedStringArray())
	var mine := deck_search[0] if deck_search.size() == 2 else ""
	var opponent := deck_search[1] if deck_search.size() == 2 else ""
	return _challenge_query_matches(mine, my_query) and _challenge_query_matches(opponent, opponent_query)

## Filtering changes the reachable cards without adding another input handler.
static func _bind_challenge_navigation(controls: Array[Control]) -> void:
	var reachable: Array[Control] = []
	for control in controls:
		if not control.is_visible_in_tree() or (control is BaseButton and control.disabled): continue
		reachable.append(control)
	for index in reachable.size():
		var control := reachable[index]
		control.focus_previous = control.get_path_to(reachable[(index + reachable.size() - 1) % reachable.size()])
		control.focus_next = control.get_path_to(reachable[(index + 1) % reachable.size()])
		control.focus_neighbor_left = control.focus_previous
		control.focus_neighbor_top = control.focus_previous
		control.focus_neighbor_right = control.focus_next
		control.focus_neighbor_bottom = control.focus_next

## Find candidates without treating matching dates, rounded times or legacy versions as a battle ID.
static func _show_challenge_replays(main, period: String, date: String, ruleset: String, record: Dictionary, return_focus: Control = null, view_state: Dictionary = {}) -> void:
	if view_state.is_empty(): view_state = {"completed": {}}
	if return_focus == null: return_focus = main.get_viewport().gui_get_focus_owner()
	var focus_target := return_focus
	if not view_state.has("records_focus"):
		view_state["records_focus"] = String(focus_target.name) if is_instance_valid(focus_target) else String(main.records_state.get("focus", ""))
	var dialog: VBoxContainer = main._action_panel("도전의 보관 전투", Rect2(140, 30, 1000, 660))
	var progress := MultiplayerUI.label("보관 전투 파일을 찾고 있습니다", 20, UIKit.GOLD)
	progress.name = "ChallengeReplayLoadProgress"
	progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(progress)
	var hint := MultiplayerUI.label("보관 파일을 나누어 읽습니다. 읽기를 마치면 검색·점수 분석·재생을 사용할 수 있습니다. 도전 기록으로 돌아가거나 읽기를 다시 시작하면 남은 작업을 중단합니다.", 16, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dialog.add_child(hint)
	var scan := ChallengeReplayScan.new()
	scan.begin(true, period, date, ruleset)
	# Closing/replacing the overlay releases the directory even before the next frame.
	dialog.tree_exiting.connect(scan.cancel, CONNECT_ONE_SHOT)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	dialog.add_child(footer)
	var retry := UIKit.style_button(Button.new(), UIKit.TEAL)
	retry.name = "RestartChallengeReplayRead"
	retry.text = "읽기 다시 시작"
	retry.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(retry)
	retry.pressed.connect(func():
		if _dialog_alive(dialog): _show_challenge_replays(main, period, date, ruleset, record, focus_target, view_state))
	var back := UIKit.style_button(Button.new(), UIKit.ACCENT)
	back.name = "CloseChallengeReplays"
	back.text = "도전 기록으로"
	back.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(back)
	var close := _close_challenge_replays.bind(main, dialog, focus_target, String(view_state.get("records_focus", "")))
	back.pressed.connect(close)
	var controls: Array[Control] = [retry, back]
	var interaction := {"used": false}
	_bind_challenge_navigation(controls)
	for control in controls:
		control.gui_input.connect(func(event: InputEvent):
			if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed):
				interaction.used = true
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	back.grab_focus()
	# Render the cancel/restart controls before performing any file reads.
	await dialog.get_tree().process_frame
	while _dialog_alive(dialog) and not scan.done:
		scan.step()
		progress.text = scan.progress
		if not scan.done: await dialog.get_tree().process_frame
	if not _dialog_alive(dialog):
		scan.cancel()
		return
	if not scan.error.is_empty():
		progress.text = scan.error
		return
	var entries := scan.entries
	var loading_focus := ""
	if bool(interaction.used):
		var focused: Control = main.get_viewport().gui_get_focus_owner()
		if focused == retry: loading_focus = "RefreshChallengeReplays"
		elif focused == back: loading_focus = "CloseChallengeReplays"
	# The old dialog's exit callback clears the scanner; transfer its snapshot first.
	scan.entries = []
	_populate_challenge_replays(main, period, date, ruleset, record, entries, focus_target, view_state, loading_focus)

static func _close_challenge_replays(main, dialog: Control, focus_target: Control, records_focus: String = "") -> void:
	if not _dialog_alive(dialog): return
	main._dismiss_action_overlay()
	main.records_state.erase("focus")
	# Counts may have finished after the picker opened. Find the now-enabled row.
	if not records_focus.is_empty():
		var record_button := main.root_background.find_child(records_focus, true, false) as Button
		if record_button != null and record_button.is_visible_in_tree() and not record_button.disabled:
			focus_target = record_button
	if _dialog_alive(focus_target) and focus_target.is_visible_in_tree() and not (focus_target is Button and focus_target.disabled):
		focus_target.grab_focus.call_deferred()
	else:
		var records_scroll := main.root_background.find_child("RecordsScroll", true, false) as Control
		if _dialog_alive(records_scroll): records_scroll.grab_focus.call_deferred()

static func _populate_challenge_replays(main, period: String, date: String, ruleset: String, record: Dictionary, entries: Array, return_focus: Control, view_state: Dictionary, loading_focus: String = "") -> void:
	if view_state.is_empty():
		view_state = {"completed": {}}
	if return_focus == null:
		return_focus = main.get_viewport().gui_get_focus_owner()
	var focus_target := return_focus
	if not view_state.has("records_focus"):
		view_state["records_focus"] = String(focus_target.name) if is_instance_valid(focus_target) else String(main.records_state.get("focus", ""))
	# Retain only small, completed summaries through selection and replay navigation.
	# A changed or removed file must never inherit a previous analysis.
	var completed: Dictionary = view_state.get("completed", {})
	view_state["completed"] = completed
	var fingerprints := {}
	for entry in entries:
		fingerprints[String(entry.analysis_fingerprint)] = true
	var discarded := 0
	for key in completed.keys():
		if not fingerprints.has(key):
			completed.erase(key)
			discarded += 1
	var dialog: VBoxContainer = main._action_panel("도전의 보관 전투", Rect2(140, 30, 1000, 660))
	var title := "주간 도전" if period == "weekly" else "일일 도전"
	var date_text := "%s-%s-%s" % [date.substr(0, 4), date.substr(4, 2), date.substr(6, 2)]
	var rule_text := "버전 미상" if ruleset == "0" else "버전 " + ruleset
	var heading := MultiplayerUI.label("%s %s (UTC) · %s\n보관 기록: %s · %d점 · %.1f초" % [title, date_text, rule_text, "성공" if bool(record.get("won", false)) else "실패", int(record.get("score", 0)), float(record.get("seconds", 0.0))], 16, UIKit.TEXT)
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(heading)
	var hint := MultiplayerUI.label("카드의 병력·구조물을 누르면 해당 진영의 검색 조건에 추가합니다. 검색칸에는 종류를 구분하는 영문 ID가 들어갑니다. ✓ 항목은 다시 눌러 해제합니다. 카드가 숨겨져도 검색칸 아래의 ‘검색어 ×’로 조건을 하나씩 해제할 수 있습니다. 내 덱·상대 덱의 전체 검색은 해당 검색칸을 카드의 전체 구성으로 교체하며, 양쪽 덱 전체 검색은 두 칸을 함께 교체합니다. ✓ 덱 검색 해제는 해당 칸만 비웁니다. 전체 검색·결과·클립 조건은 유지합니다. 내 덱·상대 덱 검색은 각 진영의 출전 구성만 찾으며, 빈 검색칸은 제한하지 않습니다. 덱은 저장된 전투의 출전 구성이며 순서나 실제 생산·설치 수는 구분하지 않습니다. 점수 분석으로 기지 체력·시간의 점수 근거를 확인합니다. 클립도 전체 전투 기준입니다. 이전·미상 버전은 현재 규칙의 참고 점수이며, 결과·시간·점수가 같아도 같은 전투인지는 확정할 수 없습니다.", 14, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var status := MultiplayerUI.label("보관 전투 %d개 · 버전 확인된 전투 우선" % entries.size(), 14, UIKit.GOLD)
	status.name = "ChallengeReplayStatus"
	if discarded > 0:
		status.text += "\n전투 내용이 바뀌거나 삭제되어 이전 분석 %d개를 해제했습니다. 남아 있는 전투는 다시 분석할 수 있습니다." % discarded
	status.tooltip_text = "버전이 확인된 전투를 먼저 표시하며, 각 그룹 안에서는 최신 보관순입니다."
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(status)
	var search_tools := HBoxContainer.new()
	search_tools.add_theme_constant_override("separation", 8)
	dialog.add_child(search_tools)
	var search := LineEdit.new()
	search.name = "ChallengeReplaySearch"
	search.placeholder_text = "전체 검색: 병력·구조물·파일·클립 구간"
	search.tooltip_text = "이 도전의 보관 전투 안에서 양쪽 덱과 파일·클립 정보를 함께 검색합니다. 공백으로 나눈 검색어를 모두 포함해야 합니다. 예: 탱커 포탑 / archer wall / 버전 미상. 아래 내 덱·상대 덱 검색으로 진영별 조건을 함께 지정할 수 있습니다."
	search.max_length = 160
	search.clear_button_enabled = true
	search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.text = String(view_state.get("query", ""))
	search_tools.add_child(search)
	var reset := UIKit.style_button(Button.new(), UIKit.TEAL, false, 16)
	reset.name = "ResetChallengeReplayFilters"
	reset.text = "초기화"
	reset.tooltip_text = "전체 검색·내 덱·상대 덱·결과·클립 조건을 모두 해제합니다."
	reset.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	search_tools.add_child(reset)
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	dialog.add_child(filters)
	var deck_tools := HBoxContainer.new()
	deck_tools.add_theme_constant_override("separation", 12)
	deck_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(deck_tools)
	var deck_queries: Array[LineEdit] = []
	for side in 2:
		var field := HBoxContainer.new()
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_constant_override("separation", 8)
		deck_tools.add_child(field)
		var side_name := "내 덱 (블루)" if side == 0 else "상대 덱 (레드)"
		var tone := UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
		var label := MultiplayerUI.label(side_name, 14, tone.lightened(0.3))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		field.add_child(label)
		var deck_query := LineEdit.new()
		deck_query.name = "ChallengeReplayMyDeckSearch" if side == 0 else "ChallengeReplayOpponentDeckSearch"
		deck_query.placeholder_text = "예: 탱커 포탑" if side == 0 else "예: 궁수 방벽"
		deck_query.tooltip_text = "%s에 저장된 병력·구조물의 한글 이름과 영문 ID만 검색합니다. 공백으로 나눈 검색어를 모두 포함해야 하며, 빈칸은 제한하지 않습니다. 두 덱 조건과 위 검색·결과·클립 조건을 함께 적용합니다." % side_name
		deck_query.max_length = 160
		deck_query.clear_button_enabled = true
		deck_query.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
		deck_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		deck_query.text = String(view_state.get("my_query" if side == 0 else "opponent_query", ""))
		field.add_child(deck_query)
		deck_queries.append(deck_query)
	var outcome := OptionButton.new()
	outcome.name = "ChallengeReplayOutcomeFilter"
	outcome.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	for label in ["결과 전체", "승리", "패배", "무승부"]: outcome.add_item(label)
	outcome.select(clampi(int(view_state.get("outcome", 0)), 0, 3))
	outcome.tooltip_text = "내 덱 (블루)의 전체 전투 결과입니다. 클립도 전체 전투 기준으로 구분합니다."
	filters.add_child(outcome)
	var scope := OptionButton.new()
	scope.name = "ChallengeReplayScopeFilter"
	scope.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	for label in ["전투·클립 전체", "전체 전투만", "클립만"]: scope.add_item(label)
	scope.select(clampi(int(view_state.get("scope", 0)), 0, 2))
	filters.add_child(scope)
	var count := MultiplayerUI.label("", 14, UIKit.TEXT_MUTED)
	count.name = "ChallengeReplayMatchCount"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	filters.add_child(count)
	var search_terms := ChallengeSearchTerms.new()
	dialog.add_child(search_terms)
	var scroll := ScrollContainer.new()
	scroll.name = "ChallengeReplayScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	scroll.focus_mode = Control.FOCUS_ALL
	dialog.add_child(scroll)
	var layout := {"restoring": true, "revision": 0, "deck_filtering": false, "loading": true}
	var rows := VBoxContainer.new()
	rows.name = "ChallengeReplayRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 10)
	scroll.add_child(rows)
	# Let the longer explanation scroll so touch-sized filters leave room for cards.
	rows.add_child(hint)
	var controls: Array[Control] = [search, reset, deck_queries[0], deck_queries[1], outcome, scope, scroll]
	# Validate both fields before assigning either. Emit once after the entire update
	# so a two-deck search never exposes an intermediate filter or cancels its analysis.
	var apply_deck_queries := func(button: Button, next_queries: PackedStringArray, message: String):
		if not _dialog_alive(dialog) or not button.is_visible_in_tree(): return
		for side in 2:
			if next_queries[side].length() > deck_queries[side].max_length:
				if button.has_meta("full_deck_queries"):
					_refresh_challenge_full_deck_button(button, PackedStringArray([deck_queries[0].text, deck_queries[1].text]))
				else:
					_refresh_challenge_deck_button(button, deck_queries[int(button.get_meta("deck_side"))].text)
				status.text = "검색어가 길어 조건을 적용하지 못했습니다. 해당 덱 검색칸의 조건을 줄인 뒤 다시 누르세요. 기존 검색 조건은 유지했습니다."
				deck_queries[side].grab_focus()
				return
		# Keep the clicked card reachable for composing more conditions without opening a keyboard.
		layout.revision = int(layout.revision) + 1
		layout.restoring = true
		layout.deck_filtering = true
		# Programmatic text assignment does not emit LineEdit.text_changed.
		for side in 2:
			if deck_queries[side].text != next_queries[side]: deck_queries[side].text = next_queries[side]
		deck_queries[0].text_changed.emit(deck_queries[0].text)
		layout.deck_filtering = false
		status.text = message
		button.grab_focus()
		view_state["focus_name"] = String(button.name)
		view_state["focus_path"] = String(button.get_meta("ChallengeReplayPath", ""))
		var revision := int(layout.revision)
		var keep_card_visible := func():
			if not _dialog_alive(dialog) or int(layout.revision) != revision: return
			if button.is_visible_in_tree(): scroll.ensure_control_visible(button)
			view_state["scroll"] = scroll.scroll_vertical
			layout.restoring = false
		dialog.get_tree().process_frame.connect(keep_card_visible, CONNECT_ONE_SHOT)
	var choose_deck_term := func(button: Button):
		if not _dialog_alive(dialog) or not button.is_visible_in_tree(): return
		var side := int(button.get_meta("deck_side"))
		var title_text := String(button.get_meta("deck_title"))
		var kind := String(button.get_meta("deck_kind"))
		var removing := _challenge_deck_term_selected(deck_queries[side].text, kind, title_text)
		var next_queries := PackedStringArray([deck_queries[0].text, deck_queries[1].text])
		next_queries[side] = _challenge_toggle_deck_term(next_queries[side], kind, title_text)
		apply_deck_queries.call(button, next_queries, "%s 검색: %s %s · 다른 조건은 유지합니다." % ["내 덱 (블루)" if side == 0 else "상대 덱 (레드)", title_text, "해제" if removing else "추가"])
	var choose_full_deck := func(button: Button):
		if not _dialog_alive(dialog) or not button.is_visible_in_tree(): return
		var side := int(button.get_meta("deck_side"))
		var next_queries := PackedStringArray([deck_queries[0].text, deck_queries[1].text])
		var removing := _challenge_full_deck_selected(button, next_queries)
		var expected: PackedStringArray = button.get_meta("full_deck_queries")
		for target in 2:
			if side < 0 or side == target: next_queries[target] = "" if removing else expected[target]
		var title_text := "양쪽 덱" if side < 0 else ("내 덱 (블루)" if side == 0 else "상대 덱 (레드)")
		apply_deck_queries.call(button, next_queries, "%s 검색 %s · 전체 검색·결과·클립%s 조건은 유지합니다." % [title_text, "해제" if removing else "조건을 이 카드의 전체 구성으로 교체했습니다", "·다른 덱" if side >= 0 else ""])
	var groups: Array = []
	# A new analysis cancels the previous one. State belongs only to this dialog.
	var analysis_job := {"serial": 0}
	# Build hidden cards in short batches after the footer can handle cancel/restart.
	var build_cards := func():
		var deadline := Time.get_ticks_usec() + 4000
		var built_count := 0
		# Confirmed versions come first; unknown versions remain visible in a separate group.
		for unknown in [false, true]:
			var group: Array = entries.filter(func(entry): return (ChallengeReplays.ruleset_of(entry.replay) == "0") == unknown)
			if group.is_empty(): continue
			var group_title := MultiplayerUI.label(("버전 미상 · 날짜만 일치" if unknown else "기록의 버전 확인됨") + " · %d개" % group.size(), 16, UIKit.GOLD)
			group_title.visible = false
			rows.add_child(group_title)
			groups.append({"heading": group_title, "entries": group, "unknown": unknown})
			for entry in group:
				if not _dialog_alive(dialog): return false
				var card := PanelContainer.new()
				card.visible = false
				card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.EDGE_SOFT, 12), 14, 10))
				rows.add_child(card)
				entry["card"] = card
				entry["deck_search"] = PackedStringArray([_challenge_deck_search_text(entry.replay, 0), _challenge_deck_search_text(entry.replay, 1)])
				entry["search"] = _challenge_search_text(entry)
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
				entry["deck_buttons"] = _challenge_deck_preview(content, replay, choose_deck_term, choose_full_deck)
				for button in entry.deck_buttons:
					button.set_meta("ChallengeReplayPath", String(entry.path))
					controls.append(button)
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
				var analysis_fingerprint := String(entry.analysis_fingerprint)
				if completed.has(analysis_fingerprint):
					_show_challenge_score(score_detail, completed[analysis_fingerprint], replay, record)
				var stamp := MultiplayerUI.label(_stamp(path) + " · " + path.get_file(), 13, UIKit.TEXT_MUTED)
				stamp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				stamp.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				stamp.tooltip_text = ProjectSettings.globalize_path(path)
				actions.add_child(stamp)
				var analyze := UIKit.style_button(Button.new(), UIKit.TEAL, false, 16)
				analyze.name = "AnalyzeChallengeScore"
				analyze.set_meta("ChallengeReplayPath", path)
				analyze.text = "다시 분석" if completed.has(analysis_fingerprint) else "점수 분석"
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
				watch.tooltip_text = "나가기로 이 보관 전투 목록에 돌아옵니다. 공통 검색·내 덱·상대 덱·결과·클립 조건, 내용이 같은 전투의 완료된 분석과 스크롤·선택 카드 초점을 유지합니다."
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
						_bind_challenge_navigation(controls)
						return
					if not bool(layout.restoring): view_state["scroll"] = scroll.scroll_vertical
					view_state["focus_name"] = String(watch.name)
					view_state["focus_path"] = path
					analysis_job.serial = int(analysis_job.serial) + 1
					watch.disabled = true
					_open_viewer(main, current, path, _return_to_challenge_replays.bind(main, period, date, ruleset, record.duplicate(true), view_state), "도전의 보관 전투 목록으로 돌아갑니다. 공통 검색·내 덱·상대 덱·결과·클립 조건과 완료된 점수 분석·스크롤·선택 카드 초점을 유지합니다. 도전 기록으로는 목록을 닫아 돌아갑니다."))
				built_count += 1
				if built_count % 2 == 0 or Time.get_ticks_usec() >= deadline:
					status.text = "보관 전투 카드 준비 중 · %d / %d개 · 도전 기록으로 돌아가면 중단합니다" % [built_count, entries.size()]
					await dialog.get_tree().process_frame
					if not _dialog_alive(dialog): return false
					deadline = Time.get_ticks_usec() + 4000
		return true
	if entries.is_empty():
		var empty := MultiplayerUI.label("읽을 수 있는 보관 전투가 없습니다. 저장 실패·자동 정리·삭제로 점수 기록만 남을 수 있습니다. 다른 버전으로 확인된 전투는 포함하지 않습니다.", 16, UIKit.TEXT_MUTED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(empty)
	var no_matches := MultiplayerUI.label("검색 조건에 맞는 보관 전투가 없습니다. 위의 ‘검색어 ×’로 조건을 하나씩 해제할 수 있습니다. 내 덱은 블루, 상대 덱은 레드의 출전 구성에서 찾습니다. 결과·클립 조건을 바꾸거나 초기화로 모두 해제할 수도 있습니다.", 16, UIKit.TEXT_MUTED)
	no_matches.name = "NoChallengeReplayMatches"
	no_matches.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	no_matches.visible = false
	rows.add_child(no_matches)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	dialog.add_child(footer)
	var refresh := UIKit.style_button(Button.new(), UIKit.TEAL)
	refresh.name = "RefreshChallengeReplays"
	refresh.text = "새로고침"
	refresh.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	refresh.tooltip_text = "파일을 다시 조회합니다. 공통 검색·내 덱·상대 덱·결과·클립 조건, 내용이 같은 전투의 분석과 스크롤 위치를 유지하며 진행 중인 분석은 중단합니다."
	refresh.pressed.connect(func():
		if _dialog_alive(dialog):
			if not bool(layout.restoring): view_state["scroll"] = scroll.scroll_vertical
			var focused: Control = main.get_viewport().gui_get_focus_owner()
			if not bool(layout.loading):
				view_state["focus_name"] = String(focused.name) if focused in controls else String(scroll.name)
				view_state["focus_path"] = String(focused.get_meta("ChallengeReplayPath", "")) if focused in controls else ""
			_show_challenge_replays(main, period, date, ruleset, record, focus_target, view_state))
	footer.add_child(refresh)
	var close := _close_challenge_replays.bind(main, dialog, focus_target, String(view_state.get("records_focus", "")))
	var back := UIKit.style_button(Button.new(), UIKit.ACCENT)
	back.name = "CloseChallengeReplays"
	back.text = "도전 기록으로"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	back.pressed.connect(close)
	footer.add_child(back)
	controls.append(refresh)
	controls.append(back)
	var initial_controls := controls.duplicate()
	for control in controls:
		control.gui_input.connect(func(event: InputEvent):
			if bool(layout.loading) and ((event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed)):
				layout.revision = int(layout.revision) + 1
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	search_terms.close_requested.connect(close)
	var apply_filters := func(reset_scroll: bool):
		if not _dialog_alive(dialog) or bool(layout.loading): return
		view_state["query"] = search.text
		view_state["my_query"] = deck_queries[0].text
		view_state["opponent_query"] = deck_queries[1].text
		view_state["outcome"] = outcome.selected
		view_state["scope"] = scope.selected
		reset.disabled = search.text.is_empty() and deck_queries[0].text.is_empty() and deck_queries[1].text.is_empty() and outcome.selected == 0 and scope.selected == 0
		var focused: Control = main.get_viewport().gui_get_focus_owner()
		var shown := 0
		var current_deck_queries := PackedStringArray([deck_queries[0].text, deck_queries[1].text])
		for group in groups:
			var group_shown := 0
			for entry in group.entries:
				entry.card.visible = _challenge_matches(entry, search.text, outcome.selected, scope.selected, deck_queries[0].text, deck_queries[1].text)
				for button in entry.deck_buttons:
					if button.has_meta("full_deck_queries"):
						_refresh_challenge_full_deck_button(button, current_deck_queries)
					else:
						_refresh_challenge_deck_button(button, deck_queries[int(button.get_meta("deck_side"))].text)
				if entry.card.visible:
					group_shown += 1
				else:
					# A hidden card cannot offer its cancel button; stop only its running job.
					var analyzing := entry.card.find_child("AnalyzeChallengeScore", true, false) as Button
					if bool(analyzing.get_meta("analyzing", false)) and int(analyzing.get_meta("analysis_serial", -1)) == int(analysis_job.serial):
						analysis_job.serial = int(analysis_job.serial) + 1
			group.heading.visible = group_shown > 0
			group.heading.text = ("버전 미상 · 날짜만 일치" if bool(group.unknown) else "기록의 버전 확인됨") + " · %d / %d개" % [group_shown, group.entries.size()]
			shown += group_shown
		count.text = "%d / %d개 표시" % [shown, entries.size()]
		no_matches.visible = shown == 0 and not entries.is_empty()
		for button in search_terms.buttons(): controls.erase(button)
		search_terms.sync_queries(PackedStringArray([search.text, deck_queries[0].text, deck_queries[1].text]), scroll)
		var term_index := controls.find(scroll)
		for button in search_terms.buttons():
			controls.insert(term_index, button)
			term_index += 1
		if focused in controls and (not focused.is_visible_in_tree() or (focused is BaseButton and focused.disabled)):
			search.grab_focus()
		_bind_challenge_navigation(controls)
		if not reset_scroll: return
		view_state["scroll"] = 0
		view_state["focus_name"] = ""
		view_state["focus_path"] = ""
		layout.revision = int(layout.revision) + 1
		layout.restoring = true
		var revision := int(layout.revision)
		var reset_position := func():
			if not _dialog_alive(dialog) or int(layout.revision) != revision: return
			scroll.scroll_vertical = 0
			layout.restoring = false
		dialog.get_tree().process_frame.connect(reset_position, CONNECT_ONE_SHOT)
	search_terms.term_removed.connect(func(field: int, term: String):
		if not _dialog_alive(dialog): return
		var query: LineEdit = search if field == 0 else deck_queries[field - 1]
		var remaining := PackedStringArray()
		for other in _challenge_deck_terms(query.text):
			if other.to_lower() != term: remaining.append(other)
		# Cancel delayed restoration before replacing a condition; refresh exactly once.
		var position := scroll.scroll_vertical
		layout.revision = int(layout.revision) + 1
		layout.restoring = true
		query.text = " ".join(remaining)
		apply_filters.call(false)
		var removed_title := term.left(32) + ("…" if term.length() > 32 else "")
		status.text = "%s 검색: ‘%s’ 해제 · 다른 검색·결과·클립 조건은 유지합니다." % [ChallengeSearchTerms.FIELD_NAMES[field], removed_title]
		var focused: Control = main.get_viewport().gui_get_focus_owner()
		view_state["focus_name"] = String(focused.name) if focused in controls else String(scroll.name)
		view_state["focus_path"] = ""
		view_state["scroll"] = position
		var revision := int(layout.revision)
		var restore_position := func():
			if not _dialog_alive(dialog) or int(layout.revision) != revision: return
			scroll.scroll_vertical = position
			view_state["scroll"] = scroll.scroll_vertical
			layout.restoring = false
		dialog.get_tree().process_frame.connect(restore_position, CONNECT_ONE_SHOT))
	search.text_changed.connect(func(_text): apply_filters.call(true))
	for deck_query in deck_queries:
		deck_query.text_changed.connect(func(_text): apply_filters.call(not bool(layout.deck_filtering)))
	outcome.item_selected.connect(func(_index): apply_filters.call(true))
	scope.item_selected.connect(func(_index): apply_filters.call(true))
	reset.pressed.connect(func():
		search.text = ""
		for deck_query in deck_queries: deck_query.text = ""
		outcome.select(0)
		scope.select(0)
		apply_filters.call(true)
		search.grab_focus())
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
		if bool(layout.loading): layout.revision = int(layout.revision) + 1
		scroll.accept_event())
	var initial_revision := int(layout.revision)
	search.editable = false
	for deck_query in deck_queries: deck_query.editable = false
	reset.disabled = true
	outcome.disabled = true
	scope.disabled = true
	status.text = "보관 전투 카드 준비 중 · %d개" % entries.size()
	_bind_challenge_navigation(controls)
	back.grab_focus()
	if not loading_focus.is_empty():
		layout.revision = int(layout.revision) + 1
		if loading_focus == String(refresh.name): refresh.grab_focus()
	await dialog.get_tree().process_frame
	if not _dialog_alive(dialog): return
	var built: bool = await build_cards.call()
	if not built or not _dialog_alive(dialog): return
	layout.loading = false
	search.editable = true
	for deck_query in deck_queries: deck_query.editable = true
	outcome.disabled = false
	scope.disabled = false
	# New card controls join the existing Escape handling and navigation order.
	for control in controls:
		if control in initial_controls: continue
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	controls.erase(refresh)
	controls.erase(back)
	controls.append(refresh)
	controls.append(back)
	status.text = "보관 전투 %d개 · 버전 확인된 전투 우선" % entries.size()
	if discarded > 0:
		status.text += "\n전투 내용이 바뀌거나 삭제되어 이전 분석 %d개를 해제했습니다. 남아 있는 전투는 다시 분석할 수 있습니다." % discarded
	apply_filters.call(false)
	if int(layout.revision) != initial_revision:
		layout.restoring = false
		return
	var restore := func():
		if not _dialog_alive(dialog) or int(layout.revision) != initial_revision: return
		var target: Control = scroll
		var selected_path := String(view_state.get("focus_path", ""))
		for control in controls:
			if String(control.name) == String(view_state.get("focus_name", "")) and String(control.get_meta("ChallengeReplayPath", "")) == String(view_state.get("focus_path", "")):
				if control.is_visible_in_tree() and not (control is BaseButton and control.disabled): target = control
				break
		if not selected_path.is_empty() and target == scroll:
			status.text += "\n선택했던 전투가 삭제되었거나 날짜·버전·검색 조건에서 제외되어 목록으로 초점을 옮겼습니다."
		target.grab_focus()
		scroll.scroll_vertical = int(view_state.get("scroll", 0))
		view_state["scroll"] = scroll.scroll_vertical
		layout.restoring = false
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
	completed[ChallengeReplays.analysis_fingerprint(replay)] = analysis
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
