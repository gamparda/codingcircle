extends RefCounted
## Pause only the local simulation; networking, UI and persistence keep processing.

const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

static func can_pause(main) -> bool:
	return main.local_ai_mode and main.battle_active and is_instance_valid(main.local_model) and main.local_model.winner == -1 and not main.result_shown and not main.finale_active and is_instance_valid(main.battle_view)

static func is_paused(main) -> bool:
	return main.local_ai_mode and (main.practice.paused or is_instance_valid(main.stats_overlay) or is_instance_valid(main.action_overlay) or is_instance_valid(main.report_overlay))

static func pause(main, automatic: bool = false) -> void:
	if not can_pause(main) or is_instance_valid(main.local_pause_overlay):
		return
	main.local_pause_focus = main.get_viewport().gui_get_focus_owner()
	main.practice.paused = true
	main.local_battle_skip_delta = true
	if is_instance_valid(main.practice_pause_button):
		main.practice_pause_button.text = "계속"
	main.battle_view.reset_build_touch()
	main.battle_view.set_process(false)
	main._refresh_purchase_buttons(main.latest_resources)
	main.local_pause_overlay = ColorRect.new()
	main.local_pause_overlay.name = "LocalBattlePauseOverlay"
	main.local_pause_overlay.color = Color(0.02, 0.03, 0.05, 0.92)
	main.local_pause_overlay.size = Vector2(1280, 720)
	main.local_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.local_pause_overlay.z_index = 180
	main.root_background.add_child(main.local_pause_overlay)
	var column := MultiplayerUI.panel(main, main.local_pause_overlay, "LocalBattlePausePanel", Rect2(350, 220, 580, 280))
	column.add_child(MultiplayerUI.label("전투 일시정지", 26, MultiplayerUI.GOLD))
	var message := MultiplayerUI.label("앱을 벗어나 전투를 멈췄습니다. 준비되면 계속하세요." if automatic else "잠시 쉬어 가세요. 준비되면 계속하세요.", 16, MultiplayerUI.MUTED)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var hint := MultiplayerUI.label("전투 시간·자원·생산 대기는 멈춰 있습니다.\n계속하기 또는 Space로 재개합니다.", 14, MultiplayerUI.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	var resume := MultiplayerUI.button(main, column, "계속하기 · Space", "ResumeLocalBattle", main._resume_local_battle, true)
	resume.custom_minimum_size.y = 58
	resume.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	resume.grab_focus()

static func resume(main) -> void:
	if not can_pause(main) or main.local_battle_backgrounded:
		return
	var previous_focus: Control = main.local_pause_focus
	dismiss(main)
	main.practice.paused = false
	if is_instance_valid(main.practice_pause_button):
		main.practice_pause_button.text = "일시정지"
	main.battle_view.reset_build_touch()
	main.battle_view.set_process(not is_paused(main))
	main._refresh_purchase_buttons(main.latest_resources)
	# An interruption may cover an existing stats/confirmation panel. Keep that
	# panel and its pause intact, and restore the control the player was using.
	if is_instance_valid(previous_focus) and previous_focus.is_inside_tree() and previous_focus.is_visible_in_tree() and not (previous_focus is BaseButton and previous_focus.disabled):
		previous_focus.grab_focus()
	elif is_instance_valid(main.practice_pause_button):
		main.practice_pause_button.grab_focus()

static func dismiss(main) -> void:
	if is_instance_valid(main.local_pause_overlay):
		# Stop intercepting pointer events before the queued deletion is processed.
		main.local_pause_overlay.hide()
		main.local_pause_overlay.queue_free()
	main.local_pause_overlay = null
	main.local_pause_focus = null

static func handle_key(main, event: InputEventKey) -> bool:
	if is_instance_valid(main.local_pause_overlay):
		# Keep Tab/Enter and battle hotkeys from activating controls underneath.
		# F11 remains a global window action.
		if event.keycode == KEY_F11: return false
		if event.pressed and not event.echo:
			if event.keycode == KEY_TAB:
				var button := main.local_pause_overlay.find_child("ResumeLocalBattle", true, false) as Button
				if button != null: button.grab_focus()
			elif event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER] and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and not event.shift_pressed:
				resume(main)
		return true
	if not event.pressed or event.echo or event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed or not can_pause(main) or main._battle_text_has_focus():
		return false
	if is_instance_valid(main.stats_overlay) and event.keycode == KEY_ESCAPE and not is_instance_valid(main.action_overlay) and not is_instance_valid(main.report_overlay):
		main._dismiss_stats_panel()
		return true
	if event.keycode != KEY_SPACE or is_instance_valid(main.stats_overlay) or is_instance_valid(main.action_overlay) or is_instance_valid(main.report_overlay):
		return false
	pause(main)
	return true
