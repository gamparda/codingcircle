extends RefCounted
## Touch scrolling over buttons. A ScrollContainer only scrolls by drag when the touch reaches it, but a button
## (or panel) stops the touch by default, so lists full of buttons did not scroll when dragged on a phone.
## Every button and panel inside a ScrollContainer lets the touch pass on, and buttons act on release: a drag
## that turns into a scroll cancels the press (ScrollContainer notifies its children), a tap still presses.

static func on_node_added(node: Node) -> void:
	if node is BaseButton or node is Panel or node is PanelContainer:
		_adapt.call_deferred(node)

static func _adapt(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_inside_tree() or control.mouse_filter != Control.MOUSE_FILTER_STOP:
		return
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer:
			control.mouse_filter = Control.MOUSE_FILTER_PASS
			if control is BaseButton:
				control.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			return
		parent = parent.get_parent()
