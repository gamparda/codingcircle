extends Node
## Keeps navigation in this screen only; no browser state is written to the save.

var _root: Control
var _scroll: ScrollContainer
var _choice: OptionButton
var _search: LineEdit
var _state: Dictionary
var _restoring := false
var _revision := 0

func setup(root: Control, scroll: ScrollContainer, choice: OptionButton, search: LineEdit, state: Dictionary) -> void:
	_root = root
	_scroll = scroll
	_choice = choice
	_search = search
	_state = state
	_scroll.focus_mode = Control.FOCUS_ALL
	_scroll.gui_input.connect(_on_scroll_input)
	_scroll.get_v_scroll_bar().value_changed.connect(_remember_scroll)
	get_viewport().gui_focus_changed.connect(_remember_focus)
	_restore_after_layout()

func _alive() -> bool:
	if not is_inside_tree() or not is_instance_valid(_root): return false
	# Main queues the background ancestor when navigating to another screen.
	var node: Node = _root
	while is_instance_valid(node):
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true

func _remember_scroll(value: float) -> void:
	if _alive() and not _restoring:
		_state.scroll = int(value)

func _remember_focus(control: Control) -> void:
	if not _alive() or _restoring or not is_instance_valid(control): return
	# Confirmation overlays have their own focus and must not replace this bookmark.
	if _root.is_ancestor_of(control):
		_state.focus_path = String(_root.get_path_to(control))

func _usable(control: Control) -> bool:
	return is_instance_valid(control) and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled)

func _collapsed_section_toggle(control: Control) -> Control:
	# A dialog may have changed the shared fold bookmark since this control was focused.
	var node: Node = control
	while is_instance_valid(node) and node != _root:
		if String(node.name).ends_with("SectionDetails") and node is Control and not node.is_visible_in_tree():
			var prefix := String(node.name).trim_suffix("SectionDetails")
			var toggle := node.get_parent().get_node_or_null(NodePath(prefix + "Toggle")) as Control
			if _usable(toggle): return toggle
		node = node.get_parent()
	return null

func _restore_after_layout() -> void:
	_revision += 1
	_restoring = true
	get_tree().process_frame.connect(_restore.bind(int(_state.get("scroll", 0)), String(_state.get("focus_path", "")), _revision), CONNECT_ONE_SHOT)

func _restore(position: int, path: String, revision: int) -> void:
	if not _alive() or revision != _revision: return
	var target: Control
	if not path.is_empty(): target = _root.get_node_or_null(NodePath(path)) as Control
	# If a missing/filtered file disables the old action, return to the chooser.
	# Never focus a different restore/delete action or select a replacement file.
	var fallback := not path.is_empty() and not _usable(target)
	if fallback:
		var toggle := _collapsed_section_toggle(target)
		target = toggle if _usable(toggle) else _choice if _usable(_choice) else _search
	if path.is_empty(): target = _scroll
	if _usable(target): target.grab_focus()
	# Focus following is deferred by ScrollContainer. Restore the bookmark after it.
	var target_path := String(_root.get_path_to(target)) if _usable(target) else ""
	get_tree().process_frame.connect(_finish_restore.bind(position, target_path, fallback, revision), CONNECT_ONE_SHOT)

func _finish_restore(position: int, path: String, fallback: bool, revision: int) -> void:
	if not _alive() or revision != _revision: return
	var target: Control
	if not path.is_empty(): target = _root.get_node_or_null(NodePath(path)) as Control
	var bar := _scroll.get_v_scroll_bar()
	_scroll.scroll_vertical = clampi(position, 0, maxi(0, int(bar.max_value - bar.page)))
	if fallback and _usable(target): _scroll.ensure_control_visible(target)
	_restoring = false
	_remember_scroll(_scroll.scroll_vertical)
	_remember_focus(target)

func _input(event: InputEvent) -> void:
	if not _restoring or not _alive(): return
	if (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or event is InputEventScreenDrag:
		_revision += 1
		_restoring = false
		_remember_scroll(_scroll.scroll_vertical)
		_remember_focus(get_viewport().gui_get_focus_owner())

func _on_scroll_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	var bar := _scroll.get_v_scroll_bar()
	var target := _scroll.scroll_vertical
	match event.keycode:
		KEY_UP: target -= 48
		KEY_DOWN: target += 48
		KEY_PAGEUP: target -= maxi(48, int(bar.page))
		KEY_PAGEDOWN: target += maxi(48, int(bar.page))
		KEY_HOME: target = 0
		KEY_END: target = int(bar.max_value - bar.page)
		_: return
	# A user's navigation always wins over a pending layout restoration.
	_revision += 1
	_restoring = false
	_scroll.scroll_vertical = clampi(target, 0, maxi(0, int(bar.max_value - bar.page)))
	_remember_scroll(_scroll.scroll_vertical)
	_scroll.accept_event()
