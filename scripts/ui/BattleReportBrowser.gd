extends Node
## Match-local reading bookmarks and keyboard navigation for the result summary.

var _main
var _root: Control
var _scroll: ScrollContainer
var _close: Button
var _state: Dictionary
var _return_focus: Control
var _restoring := false
var _revision := 0

func setup(main, scroll: ScrollContainer, close: Button, state: Dictionary, return_focus: Control) -> void:
	name = "BattleReportBrowser"
	_main = main
	_root = get_parent() as Control
	_scroll = scroll
	_close = close
	_state = state
	_return_focus = return_focus
	_scroll.get_v_scroll_bar().value_changed.connect(_remember_scroll)
	get_viewport().gui_focus_changed.connect(_remember_focus)
	_restoring = true
	# Own keyboard focus immediately, even before the deferred layout restoration.
	_scroll.grab_focus()
	_revision += 1
	get_tree().process_frame.connect(_restore.bind(_revision), CONNECT_ONE_SHOT)

func _alive() -> bool:
	if not is_inside_tree() or not is_instance_valid(_root) or not _root.is_visible_in_tree(): return false
	var node: Node = _root
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true

func _usable(control: Control) -> bool:
	return is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and control.disabled)

func _remember_scroll(value: float) -> void:
	if _alive() and not _restoring: _state.scroll = int(value)

func _remember_focus(control: Control) -> void:
	# Closing the summary should retain the last reading/metric control.
	if _alive() and not _restoring and _usable(control) and (control == _scroll or _scroll.is_ancestor_of(control)):
		_state.focus_path = String(_root.get_path_to(control))

func _restore(revision: int) -> void:
	if not _alive() or revision != _revision: return
	var path := String(_state.get("focus_path", ""))
	var target: Control = _scroll
	if not path.is_empty(): target = _root.get_node_or_null(NodePath(path)) as Control
	if not _usable(target): target = _scroll
	target.grab_focus()
	# ScrollContainer follows focus after layout; apply the reading position later.
	get_tree().process_frame.connect(_finish_restore.bind(revision), CONNECT_ONE_SHOT)

func _finish_restore(revision: int) -> void:
	if not _alive() or revision != _revision: return
	_scroll.scroll_vertical = maxi(0, int(_state.get("scroll", 0)))
	_restoring = false
	_remember_scroll(_scroll.scroll_vertical)
	_remember_focus(get_viewport().gui_get_focus_owner())

func _cancel_restore() -> void:
	if not _restoring: return
	_revision += 1
	_restoring = false

func _input(event: InputEvent) -> void:
	if not _alive(): return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventScreenTouch and event.pressed) or event is InputEventScreenDrag:
		_cancel_restore()

func remember_before_close() -> void:
	if not _alive(): return
	if not _restoring:
		_remember_scroll(_scroll.scroll_vertical)
		_remember_focus(get_viewport().gui_get_focus_owner())
	_revision += 1
	if _usable(_return_focus) and not _root.is_ancestor_of(_return_focus):
		_return_focus.grab_focus()
	elif is_instance_valid(_main.result_overlay):
		var button := _main.result_overlay.find_child("BattleReportButton", true, false) as Control
		if _usable(button): button.grab_focus()

func handle_key(event: InputEventKey) -> bool:
	if not _alive() or event.keycode == KEY_F11: return false
	if not event.pressed: return false
	_cancel_restore()
	if event.keycode == KEY_ESCAPE:
		_main._dismiss_battle_report()
		return true
	if event.keycode == KEY_TAB:
		var controls: Array[Control] = [_scroll]
		for metric in ["damage", "kills"]:
			var button := _root.find_child("BattleReportMetric_" + metric, true, false) as Control
			if _usable(button): controls.append(button)
		controls.append(_close)
		var index := controls.find(get_viewport().gui_get_focus_owner())
		if index < 0: index = 0 if event.shift_pressed else -1
		controls[posmod(index + (-1 if event.shift_pressed else 1), controls.size())].grab_focus()
		return true
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return false
	var page := maxi(48, roundi(_scroll.size.y * 0.8))
	match event.keycode:
		KEY_PAGEUP: _scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical - page)
		KEY_PAGEDOWN: _scroll.scroll_vertical += page
		KEY_HOME: _scroll.scroll_vertical = 0
		KEY_END: _scroll.scroll_vertical = roundi(_scroll.get_v_scroll_bar().max_value)
		KEY_UP, KEY_DOWN:
			if not _scroll.has_focus(): return false
			_scroll.scroll_vertical = maxi(0, _scroll.scroll_vertical + (48 if event.keycode == KEY_DOWN else -48))
		_: return false
	return true
