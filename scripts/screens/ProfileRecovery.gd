extends RefCounted
## Device-local recovery points, with an explicit preview before replacing progress.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

static func _label(text: String, color: Color = UIKit.TEXT_MUTED) -> Label:
	var label := MultiplayerUI.label(text, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func _summary(data: Dictionary) -> String:
	return "%s · 캠페인 %d단계 개방 · 별 %d개\nAI %d판 · 온라인 %d판 · 업적 %d개 · 일일 기록 %d일 · 주간 기록 %d주" % [String(data.nickname), int(data.campaign_unlocked), int(data.stats.total_stars), int(data.stats.ai_matches), int(data.stats.online_completed), data.achievements.size(), data.daily.size(), data.weekly.size()]

static func _stamp(seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(seconds).replace("T", " ") + " UTC"

static func _button(main, parent: Node, text: String, name: String, callback: Callable, primary: bool = false) -> Button:
	var button := MultiplayerUI.button(main, parent, text, name, callback, primary)
	button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	return button

static func _copy_text(status: Label, scroll: ScrollContainer, text: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	elif text.to_utf8_buffer().size() > SaveData.MAX_BACKUP_TRANSFER_BYTES:
		status.text = "사본이 너무 커서 클립보드로 옮길 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	else:
		DisplayServer.clipboard_set(text)
		if DisplayServer.clipboard_get().replace("\r\n", "\n") == text.replace("\r\n", "\n"):
			status.text = "진행도 JSON을 복사했습니다. 메모장 등에 붙여넣어 .json 파일로 저장하세요. 게임 삭제·전체 초기화 전에 게임 밖에 보관해야 합니다."
		else:
			status.text = "클립보드 복사를 확인하지 못했습니다. 다시 시도하거나 보관 폴더에서 사본을 복사하세요."
	scroll.ensure_control_visible.call_deferred(status)

static func _dialog_navigation(scroll: ScrollContainer, confirm: Button, cancel: Button, close: Callable) -> void:
	scroll.focus_mode = Control.FOCUS_ALL
	var controls: Array[Control] = [scroll, confirm, cancel]
	for index in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_top = previous
		control.focus_neighbor_left = previous
		control.focus_neighbor_bottom = next
		control.focus_neighbor_right = next
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	scroll.gui_input.connect(func(event: InputEvent):
		if not event is InputEventKey or not event.pressed:
			return
		match event.keycode:
			KEY_UP: scroll.scroll_vertical -= 40
			KEY_DOWN: scroll.scroll_vertical += 40
			KEY_PAGEUP: scroll.scroll_vertical -= maxi(80, roundi(scroll.size.y * 0.85))
			KEY_PAGEDOWN: scroll.scroll_vertical += maxi(80, roundi(scroll.size.y * 0.85))
			KEY_HOME: scroll.scroll_vertical = 0
			KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			_: return
		scroll.accept_event())
	scroll.grab_focus.call_deferred()

static func _filtered_entries(source: Array, query: String, order: int) -> Array:
	var entries: Array = []
	var terms := query.to_lower().replace("\t", " ").replace("\n", " ").split(" ", false)
	for entry in source:
		var searchable := (_stamp(int(entry.modified)) + " " + String(entry.path).get_file() + " " + _summary(entry.data)).to_lower()
		var matches := true
		for term in terms:
			if not searchable.contains(term):
				matches = false
				break
		if matches:
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if order == 1 and int(a.modified) != int(b.modified):
			return int(a.modified) < int(b.modified)
		if order == 2 and int(a.data.stats.total_stars) != int(b.data.stats.total_stars):
			return int(a.data.stats.total_stars) > int(b.data.stats.total_stars)
		if order == 3 and int(a.data.campaign_unlocked) != int(b.data.campaign_unlocked):
			return int(a.data.campaign_unlocked) > int(b.data.campaign_unlocked)
		return int(a.modified) > int(b.modified) if int(a.modified) != int(b.modified) else String(a.path) < String(b.path))
	return entries

static func show(main, message: String = "", selected_path: String = "", browser_state: Dictionary = {}) -> void:
	# Screen-local state survives refresh/import/cleanup, without changing the save.
	var state := {"query": String(browser_state.get("query", "")), "order": clampi(int(browser_state.get("order", 0)), 0, 3), "selected_path": selected_path if not selected_path.is_empty() else String(browser_state.get("selected_path", ""))}
	var outer: VBoxContainer = main._submenu("진행도 보관·복구", "현재 진행도를 보관하거나, 읽을 수 있는 사본을 골라 복구합니다.")
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRecoveryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	column.add_child(_label("현재 진행도", UIKit.GOLD))
	column.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	column.add_child(_label("현재 진행도 사본은 전적·덱·저장된 설정을 보관합니다. 설정 화면에서 저장하지 않은 편집은 포함되지 않습니다."))
	var backup: Button = _button(main, column, "현재 진행도 사본 보관", "CreateProfileBackup", func():
		var path := SaveData.create_backup(main.save_data)
		if not path.is_empty(): state.query = ""
		show(main, "현재 진행도 사본을 보관했습니다." if not path.is_empty() else "사본을 보관하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요.", path, state))
	backup.tooltip_text = ProjectSettings.globalize_path(SaveData.recovery_dir())
	column.add_child(HSeparator.new())
	var candidates := SaveData.recovery_candidates()
	var entries: Array = []
	column.add_child(_label("복구할 사본 · 검색·정렬", UIKit.GOLD))
	var filters := HBoxContainer.new()
	filters.name = "ProfileRecoveryFilters"
	filters.add_theme_constant_override("separation", 10)
	column.add_child(filters)
	var search := LineEdit.new()
	search.name = "ProfileRecoverySearch"
	search.placeholder_text = "닉네임 · 보관 날짜 · 파일명 검색"
	search.tooltip_text = "UTC 보관 날짜(예: 2026-10)·닉네임·파일명·진행도 요약을 검색합니다. 공백으로 나눈 검색어를 모두 포함한 사본을 표시합니다."
	search.max_length = 120
	search.text = String(state.query)
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(search)
	var order := OptionButton.new()
	order.name = "ProfileRecoveryOrder"
	order.custom_minimum_size = Vector2(180, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44)
	for title in ["최근 보관순", "오래된 보관순", "별 많은 순", "캠페인 진행순"]:
		order.add_item(title)
	order.select(int(state.order))
	filters.add_child(order)
	var reset: Button = main._styled_button("초기화", UIKit.ACCENT, false)
	reset.name = "ResetProfileRecoveryFilters"
	reset.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(reset)
	var count := _label("")
	count.name = "ProfileRecoveryCount"
	column.add_child(count)
	var choice := OptionButton.new()
	choice.name = "ProfileRecoveryChoice"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	choice.fit_to_longest_item = false
	column.add_child(choice)
	var preview := _label("", UIKit.TEXT)
	preview.name = "ProfileRecoveryPreview"
	column.add_child(preview)
	column.add_child(_label("복구는 전적·진행도·덱·닉네임을 사본으로 되돌립니다. 현재 진행도와 디스크 원본을 먼저 별도 보관합니다.\n현재 설정, 익명 ID, 전송 대기 기록은 유지하며 과거 결과를 다시 보내지 않습니다. 리플레이와 서버 기록은 그대로 남습니다."))
	if int(candidates.excluded) > 0:
		column.add_child(_label("손상되었거나 지원하지 않는 사본 %d개는 목록에서 제외했습니다. 원본 파일은 복구 폴더에 남아 있습니다." % int(candidates.excluded)))
	var status := _label(message, UIKit.GOLD)
	status.name = "ProfileRecoveryStatus"
	if not String(candidates.error).is_empty():
		status.text = (message + "\n" if not message.is_empty() else "") + String(candidates.error)
	column.add_child(status)
	column.add_child(HSeparator.new())
	column.add_child(_label("게임 밖에 사본 보관·다른 기기에서 가져오기", UIKit.GOLD))
	column.add_child(_label("내보내기는 진행도를 JSON으로 복사합니다. 익명 ID와 전송 대기 기록은 제외합니다.\n가져오기는 내용을 확인해 사본만 보관합니다. 현재 진행도를 바꾸려면 아래의 복구 확인을 별도로 눌러야 합니다."))
	var transfer := HFlowContainer.new()
	transfer.name = "ProfileBackupTransfer"
	transfer.add_theme_constant_override("h_separation", 10)
	transfer.add_theme_constant_override("v_separation", 10)
	column.add_child(transfer)
	_button(main, transfer, "현재 진행도 내보내기", "ExportCurrentProfile", func():
		_copy_text(status, scroll, SaveData.to_backup_text(main.save_data)))
	var export_selected := _button(main, transfer, "선택한 사본 내보내기", "ExportSelectedProfile", func():
		if choice.selected < 0 or choice.selected >= entries.size():
			return
		var entry: Dictionary = entries[choice.selected]
		var result := SaveData.backup_export(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		_copy_text(status, scroll, String(result.text)))
	_button(main, transfer, "클립보드 사본 가져오기", "ImportProfileBackup", func():
		if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. JSON 사본을 보관 폴더에 복사한 뒤 새로고침하세요."
			scroll.ensure_control_visible.call_deferred(status)
			return
		_preview_import(main, DisplayServer.clipboard_get(), status, scroll, state))
	var delete_selected := _button(main, transfer, "선택한 사본 삭제 확인", "PreviewProfileBackupDelete", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm_delete(main, entries[choice.selected], state))
	delete_selected.tooltip_text = "내용과 파일명을 확인한 뒤 선택한 사본 하나만 삭제합니다. 마지막으로 읽을 수 있는 사본은 남깁니다."
	var folder := _label("보관 위치: " + ProjectSettings.globalize_path(SaveData.recovery_dir()))
	folder.add_theme_font_size_override("font_size", 13)
	column.add_child(folder)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_button(main, column, "보관 폴더 열기", "OpenProfileRecoveryFolder", func():
			var directory := SaveData.recovery_dir()
			if DirAccess.make_dir_recursive_absolute(directory) != OK or OS.shell_open(ProjectSettings.globalize_path(directory)) != OK:
				status.text = "보관 폴더를 열지 못했습니다. 표시된 보관 위치와 파일 권한을 확인하세요."
				scroll.ensure_control_visible.call_deferred(status))
	var footer := HBoxContainer.new()
	footer.name = "ProfileRecoveryFooter"
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	var restore: Button = _button(main, footer, "선택한 사본 복구 확인", "PreviewProfileRestore", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm(main, entries[choice.selected], state), true)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(main, footer, "새로고침", "RefreshProfileRecovery", func():
		show(main, "", "", state))
	_button(main, footer, "설정으로", "ProfileRecoveryBack", main._build_settings_screen)
	var update_preview := func(index: int):
		var valid := index >= 0 and index < entries.size()
		restore.disabled = not valid
		export_selected.disabled = not valid
		delete_selected.disabled = not valid or candidates.entries.size() < 2
		preview.tooltip_text = ""
		if not valid:
			preview.text = "검색 조건에 맞는 사본이 없습니다. 검색어를 바꾸거나 초기화하세요." if not candidates.entries.is_empty() else "현재 진행도를 사본으로 보관하거나, 아래에서 외부 사본을 가져오세요. 손상된 원본은 수정하지 않고 보관합니다."
			if not entries.is_empty():
				preview.text = "선택했던 사본이 검색 결과에 없거나 더 이상 존재하지 않습니다. 복구·내보내기·삭제할 사본을 목록에서 직접 선택하세요."
			return
		state.selected_path = String(entries[index].path)
		preview.text = _stamp(int(entries[index].modified)) + "\n" + _summary(entries[index].data) + "\n파일: " + String(entries[index].path).get_file()
		if int(entries[index].get("excluded", 0)) > 0:
			preview.text += "\n잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entries[index].excluded)
		preview.tooltip_text = ProjectSettings.globalize_path(String(entries[index].path))
	var rebuild := func():
		entries.clear()
		entries.append_array(_filtered_entries(candidates.entries, String(state.query), int(state.order)))
		choice.clear()
		var selected := -1
		for index in entries.size():
			var entry: Dictionary = entries[index]
			choice.add_item("%s · %s · 별 %d개 · 캠페인 %d단계" % [_stamp(int(entry.modified)), String(entry.data.nickname), int(entry.data.stats.total_stars), int(entry.data.campaign_unlocked)])
			choice.set_item_tooltip(index, ProjectSettings.globalize_path(String(entry.path)))
			if String(entry.path) == String(state.selected_path): selected = index
		if selected < 0 and String(state.selected_path).is_empty() and not entries.is_empty(): selected = 0
		choice.select(selected)
		choice.disabled = entries.is_empty()
		if selected < 0:
			choice.text = "복구할 사본을 선택하세요" if not entries.is_empty() else "검색 결과가 없습니다" if not candidates.entries.is_empty() else "복구할 수 있는 사본이 없습니다"
		count.text = "표시 %d개 / 읽을 수 있는 사본 %d개 · 마지막 사본은 삭제하지 않습니다." % [entries.size(), candidates.entries.size()]
		reset.disabled = String(state.query).is_empty() and int(state.order) == 0
		update_preview.call(selected)
	choice.item_selected.connect(update_preview)
	search.text_changed.connect(func(value: String): state.query = value; rebuild.call())
	order.item_selected.connect(func(index: int): state.order = index; rebuild.call())
	reset.pressed.connect(func():
		state.query = ""; state.order = 0
		search.set_text(""); order.select(0)
		rebuild.call(); search.grab_focus())
	rebuild.call()
	if not message.is_empty():
		scroll.ensure_control_visible.call_deferred(status)

static func _preview_import(main, text: String, screen_status: Label, screen_scroll: ScrollContainer, browser_state: Dictionary = {}) -> void:
	var preview := SaveData.preview_backup_text(text)
	if not preview.ok:
		screen_status.text = String(preview.error)
		screen_scroll.ensure_control_visible.call_deferred(screen_status)
		return
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 가져오기 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileImportConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("가져올 사본", UIKit.GOLD))
	details.add_child(_label(_summary(preview.data), UIKit.TEXT))
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	details.add_child(_label("이 단계에서는 사본만 보관합니다. 보관 후 선택한 사본 복구 확인을 눌러야 진행도를 되돌립니다.\n복구할 때도 현재 설정·익명 ID·전송 대기 기록을 유지합니다. 가져온 사본의 결과는 다시 보내지 않습니다."))
	if int(preview.excluded) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 가져온 JSON 원본은 그대로 보관합니다." % int(preview.excluded), UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileImportStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "사본만 보관", "ConfirmProfileImport", func():
		# Use the text that was previewed, even if the clipboard changed meanwhile.
		var result := SaveData.import_backup_text(text)
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		browser_state.query = ""
		show(main, "가져온 사본을 보관하고 선택했습니다. 현재 진행도는 그대로입니다. 되돌리려면 선택한 사본 복구 확인을 누르세요.", String(result.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileImport", close)
	_dialog_navigation(scroll, confirm, cancel, close)

static func _confirm_delete(main, entry: Dictionary, browser_state: Dictionary) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 삭제 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileBackupDeleteScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	details.add_child(_label("삭제할 파일: " + ProjectSettings.globalize_path(String(entry.path))))
	details.add_child(_label("선택한 사본 파일 하나를 영구 삭제합니다. 이 파일로는 더 이상 복구할 수 없습니다. 필요하면 취소하고 먼저 내보내세요.\n현재 진행도·다른 사본·리플레이·서버 기록은 유지합니다. 마지막으로 읽을 수 있는 사본은 삭제할 수 없습니다.", UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileBackupDeleteStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "이 사본만 영구 삭제", "ConfirmProfileBackupDelete", func():
		var result := SaveData.delete_backup(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		# Keep the missing path so another file is never silently selected after deletion.
		show(main, "선택한 사본 하나를 삭제했습니다. 현재 진행도는 그대로입니다. 다른 사본을 사용하려면 목록에서 직접 선택하세요.", "", browser_state))
	var cancel := _button(main, dialog, "취소", "CancelProfileBackupDelete", close)
	_dialog_navigation(scroll, confirm, cancel, close)
	# Destructive confirmation starts on cancel, including keyboard users.
	cancel.grab_focus.call_deferred()

static func _confirm(main, entry: Dictionary, browser_state: Dictionary = {}) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 복구 확인", Rect2(230, 120, 820, 470))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRestoreConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	details.add_child(_label("이 사본으로 진행도를 되돌립니다.", UIKit.GOLD))
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	if int(entry.get("excluded", 0)) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entry.excluded), UIKit.DANGER))
	details.add_child(_label("현재 진행도와 원본을 보관한 뒤 복구합니다. 보관이나 저장에 실패하면 현재 진행도를 유지합니다.\n현재 설정과 전송 대기 기록을 유지하며, 이미 전송한 과거 결과는 다시 보내지 않습니다."))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileRestoreStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "보관 후 복구", "ConfirmProfileRestore", func():
		var result := SaveData.restore_backup(main.save_data, String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		main.save_data = result.data
		main.profile_load_warning = ""
		main.profile_load_details = ""
		main.battle_preset = {}
		main.network.client_nickname = String(main.save_data.nickname)
		main._profile_saved()
		show(main, "진행도를 복구했습니다. 복구 전 진행도도 사본 목록에 보관했습니다.", String(entry.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileRestore", close)
	_dialog_navigation(scroll, confirm, cancel, close)
