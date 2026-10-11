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

static func show(main, message: String = "") -> void:
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
	var backup: Button = MultiplayerUI.button(main, column, "현재 진행도 사본 보관", "CreateProfileBackup", func():
		var path := SaveData.create_backup(main.save_data)
		show(main, "현재 진행도 사본을 보관했습니다." if not path.is_empty() else "사본을 보관하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요."))
	backup.tooltip_text = ProjectSettings.globalize_path(SaveData.recovery_dir())
	column.add_child(HSeparator.new())
	var candidates := SaveData.recovery_candidates()
	var entries: Array = candidates.entries
	column.add_child(_label("복구할 사본 · 파일 보관 시간순", UIKit.GOLD))
	var choice := OptionButton.new()
	choice.name = "ProfileRecoveryChoice"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	choice.fit_to_longest_item = false
	column.add_child(choice)
	for entry in entries:
		var data: Dictionary = entry.data
		choice.add_item("%s · %s · 별 %d개" % [_stamp(int(entry.modified)), String(data.nickname), int(data.stats.total_stars)])
		choice.set_item_tooltip(choice.item_count - 1, ProjectSettings.globalize_path(String(entry.path)))
	var preview := _label("", UIKit.TEXT)
	preview.name = "ProfileRecoveryPreview"
	column.add_child(preview)
	column.add_child(_label("복구는 전적·진행도·덱·닉네임을 사본으로 되돌립니다. 현재 진행도와 디스크 원본을 먼저 별도 보관합니다.\n현재 설정, 익명 ID, 전송 대기 기록은 유지하며 과거 결과를 다시 보내지 않습니다. 리플레이와 서버 기록은 그대로 남습니다."))
	if int(candidates.excluded) > 0:
		column.add_child(_label("손상되었거나 지원하지 않는 사본 %d개는 목록에서 제외했습니다. 원본 파일은 복구 폴더에 남아 있습니다." % int(candidates.excluded)))
	var status := _label(message, UIKit.GOLD)
	status.name = "ProfileRecoveryStatus"
	if not String(candidates.error).is_empty():
		status.text = String(candidates.error)
	column.add_child(status)
	var folder := _label("보관 위치: " + ProjectSettings.globalize_path(SaveData.recovery_dir()))
	folder.add_theme_font_size_override("font_size", 13)
	column.add_child(folder)
	var footer := HBoxContainer.new()
	footer.name = "ProfileRecoveryFooter"
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	var restore: Button = MultiplayerUI.button(main, footer, "선택한 사본 복구 확인", "PreviewProfileRestore", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm(main, entries[choice.selected]), true)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	MultiplayerUI.button(main, footer, "새로고침", "RefreshProfileRecovery", func(): show(main))
	MultiplayerUI.button(main, footer, "설정으로", "ProfileRecoveryBack", main._build_settings_screen)
	if entries.is_empty():
		choice.add_item("복구할 수 있는 사본이 없습니다")
		choice.disabled = true
		restore.disabled = true
		preview.text = "진행도를 미리 보관해 두면 이 목록에서 되살릴 수 있습니다. 손상된 원본은 수정하지 않고, 복구한 JSON 사본을 위 보관 위치에 넣은 뒤 새로고침하세요."
	else:
		var update_preview := func(index: int):
			preview.text = _summary(entries[index].data)
			preview.tooltip_text = ProjectSettings.globalize_path(String(entries[index].path))
		choice.item_selected.connect(update_preview)
		choice.select(0)
		update_preview.call(0)

static func _confirm(main, entry: Dictionary) -> void:
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
	details.add_child(_label("이 사본으로 진행도를 되돌립니다.", UIKit.GOLD))
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	details.add_child(_label("현재 진행도와 원본을 보관한 뒤 복구합니다. 보관이나 저장에 실패하면 현재 진행도를 유지합니다.\n현재 설정과 전송 대기 기록을 유지하며, 이미 전송한 과거 결과는 다시 보내지 않습니다."))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileRestoreStatus"
	details.add_child(status)
	MultiplayerUI.button(main, dialog, "보관 후 복구", "ConfirmProfileRestore", func():
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
		show(main, "진행도를 복구했습니다. 복구 전 진행도도 사본 목록에 보관했습니다."), true)
	MultiplayerUI.button(main, dialog, "취소", "CancelProfileRestore", main._dismiss_action_overlay)
