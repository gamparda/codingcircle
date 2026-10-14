extends RefCounted
## Transient overview navigation; never holds references to an outgoing screen.

static func capture(panel) -> Dictionary:
	var focused: Control = panel.get_viewport().gui_get_focus_owner()
	return {"scroll": panel.scroll.scroll_vertical, "focus": String(focused.name) if focused != null and panel.is_ancestor_of(focused) else ""}

static func configure(panel) -> void:
	panel.scroll.follow_focus = true
	var cancel := func(event: InputEvent):
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or event is InputEventScreenDrag or (event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0):
			panel.navigation_pending = false
	for control in panel.focus_controls:
		control.gui_input.connect(cancel)
	panel.scroll.get_v_scroll_bar().gui_input.connect(cancel)

static func restore(panel, state: Dictionary) -> void:
	if state.is_empty() or not _can_restore(panel): return
	for _frame in 2:
		if not _can_restore(panel): return
		await panel.get_tree().process_frame
	if not _can_restore(panel): return
	var focused: Control = panel.get_viewport().gui_get_focus_owner()
	if focused == null or focused == panel.focus_controls.back():
		for control in panel.focus_controls:
			if String(control.name) == String(state.get("focus", "")):
				control.grab_focus()
				break
	# Let ScrollContainer's deferred follow-focus finish before restoring pixels.
	await panel.get_tree().process_frame
	if not _can_restore(panel): return
	panel.scroll.scroll_vertical = maxi(0, int(state.get("scroll", 0)))
	panel.navigation_pending = false

static func _can_restore(panel) -> bool:
	return is_instance_valid(panel) and panel.navigation_pending and panel.is_inside_tree() and not panel.is_queued_for_deletion() and panel.is_visible_in_tree() and is_instance_valid(panel.main.stats_overlay) and panel.main.stats_overlay.is_ancestor_of(panel) and not is_instance_valid(panel.main.local_pause_overlay) and not is_instance_valid(panel.main.action_overlay) and not is_instance_valid(panel.main.report_overlay) and not is_instance_valid(panel.main.result_overlay)
