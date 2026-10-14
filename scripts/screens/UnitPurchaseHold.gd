extends RefCounted
## One deliberate hold at a time. Captured releases outlive cancellation so a
## disabled card or a newly opened panel cannot receive the end of the gesture.

const HOLD_DELAY_MSEC := 350
const EMULATED_DEVICE := -1

var button: Button
var key_code := 0
var touch_index := -1
var mouse_hold := false
var repeat_at := 0
var repeating := false
var captured_keys: Dictionary = {}
var captured_touches: Dictionary = {}
var captured_mouse := false

func can_hold(main) -> bool:
	if not main.battle_active or main.local_battle_backgrounded or not main._battle_purchase_block_reason().is_empty(): return false
	if main.placement_pending or main._battle_text_has_focus(): return false
	if is_instance_valid(main.stats_overlay) or is_instance_valid(main.report_overlay) or is_instance_valid(main.action_overlay): return false
	if is_instance_valid(main.local_pause_overlay) or is_instance_valid(main.update_overlay): return false
	return not (is_instance_valid(main.battle_chat_panel) and main.battle_chat_panel.visible)

func cancel() -> void:
	if is_instance_valid(button):
		var hint := button.get_node_or_null("RepeatPurchaseHint") as Label
		if hint != null: hint.hide()
	button = null
	key_code = 0
	touch_index = -1
	mouse_hold = false
	repeat_at = 0
	repeating = false

func reset() -> void:
	cancel()
	captured_keys.clear()
	captured_touches.clear()
	captured_mouse = false

func _begin(main, card: Button) -> void:
	cancel()
	if is_instance_valid(main.battle_view): main.battle_view.reset_build_touch()
	button = card
	repeat_at = Time.get_ticks_msec() + HOLD_DELAY_MSEC
	if not card.disabled: card.grab_focus()
	_refresh_hint()

func begin_key(main, card: Button, code: int) -> void:
	if not can_hold(main): return
	_begin(main, card)
	key_code = code
	captured_keys[code] = true

func _contains(card: Button, point: Vector2) -> bool:
	if not is_instance_valid(card) or not card.is_inside_tree() or card.is_queued_for_deletion() or not card.is_visible_in_tree(): return false
	var local_point := card.get_global_transform_with_canvas().affine_inverse() * point
	return Rect2(Vector2.ZERO, card.size).has_point(local_point)

func _card_at(main, point: Vector2) -> Button:
	for card in main.purchase_buttons:
		if is_instance_valid(card) and card.has_meta("unit_kind") and _contains(card, point): return card
	return null

func _purchase(main, card: Button) -> void:
	# All purchases still pass through the same signal, model/server validation,
	# client rate gate, tutorial and replay recording as a single card activation.
	if can_hold(main) and is_instance_valid(card) and not card.disabled and main.purchase_buttons.has(card):
		card.pressed.emit()

func _release_pointer(main, point: Vector2, canceled: bool = false) -> void:
	var card := button
	var tap := not repeating and not canceled and _contains(card, point)
	cancel()
	if tap: _purchase(main, card)

func _refresh_hint() -> void:
	if not is_instance_valid(button): return
	var hint := button.get_node_or_null("RepeatPurchaseHint") as Label
	if hint == null: return
	hint.text = "반복 생산 중" if repeating else "유지하면 반복"
	hint.modulate = Color(2.5, 2.5, 2.5, 1.0) if button.disabled else Color.WHITE
	hint.show()

func advance(main) -> void:
	if button == null: return
	if not is_instance_valid(button) or not can_hold(main) or not button.is_inside_tree() or button.is_queued_for_deletion() or not button.is_visible_in_tree() or not main.purchase_buttons.has(button):
		cancel()
		return
	if mouse_hold and not _contains(button, main.get_viewport().get_mouse_position()):
		cancel()
		return
	if Time.get_ticks_msec() < repeat_at: return
	repeating = true
	_refresh_hint()
	if button.disabled: return
	# Never catch up with a burst after a slow frame. In addition to the existing
	# gate, wait at least one normal production interval between repeat attempts.
	repeat_at = Time.get_ticks_msec() + HOLD_DELAY_MSEC
	_purchase(main, button)

func handle_input(main, event: InputEvent) -> bool:
	if button != null and (not is_instance_valid(button) or not can_hold(main)): cancel()
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if captured_keys.has(code):
			if not event.pressed:
				captured_keys.erase(code)
				if key_code == code: cancel()
			elif event.ctrl_pressed or event.alt_pressed or event.meta_pressed: cancel()
			return true
		# A different action cancels the previous hold; releasing it never restores
		# an older key. Echo cannot start a hold after a modal or focus transition.
		if event.pressed and not event.echo: cancel()
		return false
	if event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag:
		# Godot may emulate either direction. Only physical pointer events own a
		# hold; their synthetic counterpart must not activate a second purchase.
		if event.device == EMULATED_DEVICE:
			# Do not intercept an overlay's emulated clicks just because there is
			# a unit card underneath it, or an old canceled contact is still down.
			var point: Vector2 = event.get("position")
			return can_hold(main) and _card_at(main, point) != null
	if event is InputEventScreenTouch:
		if (not event.pressed or event.canceled) and captured_touches.has(event.index):
			captured_touches.erase(event.index)
			if touch_index == event.index: _release_pointer(main, event.position, event.canceled)
			return true
		if event.pressed:
			captured_touches.erase(event.index)
			cancel()
			if event.canceled or not can_hold(main): return false
			var card := _card_at(main, event.position)
			if card == null: return false
			captured_touches[event.index] = true
			_begin(main, card)
			touch_index = event.index
			return true
	elif event is InputEventScreenDrag and captured_touches.has(event.index):
		if touch_index == event.index and not _contains(button, event.position): cancel()
		return true
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT:
			if event.pressed: cancel()
			return false
		if (not event.pressed or event.canceled) and captured_mouse:
			captured_mouse = false
			if mouse_hold: _release_pointer(main, event.position, event.canceled)
			return true
		if event.pressed:
			captured_mouse = false
			cancel()
			if event.canceled or not can_hold(main): return false
			var card := _card_at(main, event.position)
			if card == null: return false
			captured_mouse = true
			_begin(main, card)
			mouse_hold = true
			return true
	elif event is InputEventMouseMotion and captured_mouse:
		if mouse_hold and not _contains(button, event.position): cancel()
		return true
	return false
