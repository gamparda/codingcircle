extends RefCounted
## Read-only unit/structure inspection in live battles. A gesture starts in the battlefield's
## GUI, but Main captures its end before another control can receive the release.

const Lifetime = preload("res://scripts/ui/StructureLifetime.gd")
const UnitInspection = preload("res://scripts/ui/UnitInspection.gd")
const UISounds = preload("res://scripts/ui/UISounds.gd")
const FONT = preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const NAMES := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
const DRAG_DISTANCE := 14.0
const BUTTON_HEIGHT := 58.0

var enabled := false
var selected_id := -1
var selected_collection := "structures"
var touch_index := -1
var mouse_down := false
var start_position := Vector2.ZERO
var pressed_id := -1
var pressed_collection := "structures"
var pressed_targets: Array = []
var cycle_targets: Array = []
var canceled := false
var spectator := false
var suppress_emulated_mouse := false
var card_anchor_ratio := -1.0
var card_has_unit := false
var pressed_action := ""
var pressed_card := Rect2()
var pressed_action_rect := Rect2()
var pressed_source_id := -1
var pressed_source_collection := "structures"

func cancel(view) -> void:
	selected_id = -1
	selected_collection = "structures"
	cycle_targets.clear()
	pressed_targets.clear()
	card_anchor_ratio = -1.0
	card_has_unit = false
	canceled = true
	view.queue_redraw()

func reset(view) -> void:
	cancel(view)
	touch_index = -1
	mouse_down = false
	pressed_id = -1
	pressed_collection = "structures"
	pressed_action = ""
	suppress_emulated_mouse = false

func sync(main) -> void:
	var view = main.battle_view
	spectator = main.network.client_is_spectator
	enabled = main.battle_active and not main.result_shown and not main.finale_active and not main.current_snapshot.is_empty() and int(main.current_snapshot.get("winner", -1)) == -1
	enabled = enabled and view.selected_structure.is_empty() and not view.inspect_mode and not main.placement_pending and not main.local_battle_backgrounded
	enabled = enabled and not is_instance_valid(main.stats_overlay) and not is_instance_valid(main.report_overlay) and not is_instance_valid(main.action_overlay) and not is_instance_valid(main.local_pause_overlay)
	enabled = enabled and not (is_instance_valid(main.battle_chat_panel) and main.battle_chat_panel.visible)
	if main.local_ai_mode:
		enabled = enabled and not main.practice.paused
	else:
		enabled = enabled and not main.awaiting_battle_snapshot and not main.network.client_reconnecting and not main.network_paused
	if not enabled:
		if selected_id >= 0 or not canceled: cancel(view)
	elif selected_id >= 0 and selected(view).is_empty():
		cancel(view)
	elif selected_id >= 0 and cycle_targets.size() > 1:
		prune_cycle_targets(view)

func selected(view) -> Dictionary:
	return entity(view, selected_collection, selected_id)

func entity(view, collection: String, id: int) -> Dictionary:
	if id < 0: return {}
	for item in view.snapshot.get(collection, []):
		if int(item.get("id", -1)) == id and float(item.get("hp", 0.0)) > 0.0:
			return item
	return {}

func body_rect(view, structure: Dictionary) -> Rect2:
	var x: float = view.world_to_screen_x(float(structure.x))
	var lane_y: float = view.size.y * 0.72
	match String(structure.kind):
		"swamp": return Rect2(x - 68.0, lane_y - 28.0, 136.0, 52.0)
		"turret": return Rect2(x - 32.0, lane_y - 66.0, 64.0, 78.0)
		_: return Rect2(x - 30.0, lane_y - 86.0, 60.0, 98.0)

func structure_at(view, position: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_distance := INF
	for structure in view.snapshot.get("structures", []):
		if float(structure.get("hp", 0.0)) <= 0.0 or not NAMES.has(String(structure.get("kind", ""))): continue
		var rect := body_rect(view, structure)
		if not rect.has_point(position): continue
		var distance := position.distance_squared_to(rect.get_center())
		if distance < best_distance:
			best_distance = distance
			best = structure
	return best

func targets_at(view, position: Vector2) -> Array:
	var targets: Array = []
	# The first tap retains foreground/nearest priority. Subsequent taps can
	# reach every overlapping unit, including structures hidden underneath.
	for unit in UnitInspection.units_at(view, position):
		targets.append({"collection": "units", "id": int(unit.id)})
	var structures: Array = []
	var order := 0
	for structure in view.snapshot.get("structures", []):
		order += 1
		if float(structure.get("hp", 0.0)) <= 0.0 or not NAMES.has(String(structure.get("kind", ""))): continue
		var rect := body_rect(view, structure)
		if rect.has_point(position):
			structures.append({"id": int(structure.id), "distance": position.distance_squared_to(rect.get_center()), "order": order})
	structures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.distance) != float(b.distance): return float(a.distance) < float(b.distance)
		return int(a.order) < int(b.order)
	)
	for structure in structures:
		targets.append({"collection": "structures", "id": int(structure.id)})
	return targets

func target_index(targets: Array, collection: String, id: int) -> int:
	for index in targets.size():
		var target: Dictionary = targets[index]
		if String(target.collection) == collection and int(target.id) == id: return index
	return -1

func ordered_targets(view, position: Vector2) -> Array:
	var hits := targets_at(view, position)
	if target_index(hits, selected_collection, selected_id) < 0: return hits
	# Preserve the order of surviving candidates even when interpolation,
	# marching or a new snapshot changes which one is nearest to the pointer.
	var pending := {"units": {}, "structures": {}}
	for hit in hits:
		pending[String(hit.collection)][int(hit.id)] = hit
	var ordered: Array = []
	for previous in cycle_targets:
		var collection := String(previous.collection)
		var id := int(previous.id)
		if pending[collection].has(id):
			ordered.append(pending[collection][id])
			pending[collection].erase(id)
	for hit in hits:
		if pending[String(hit.collection)].has(int(hit.id)): ordered.append(hit)
	return ordered

func prune_cycle_targets(view) -> void:
	# Linear lookup avoids a snapshot scan per candidate in a crowded army.
	# Keep the original tap group for keyboard browsing as the army moves.
	var live := {"units": {}, "structures": {}}
	for collection in live:
		for item in view.snapshot.get(collection, []):
			if float(item.get("hp", 0.0)) > 0.0:
				live[collection][int(item.get("id", -1))] = true
	var remaining: Array = []
	for target in cycle_targets:
		if live[String(target.collection)].has(int(target.id)): remaining.append(target)
	cycle_targets = remaining

func cycle_selection(view, direction: int) -> void:
	prune_cycle_targets(view)
	var index := target_index(cycle_targets, selected_collection, selected_id)
	if index < 0 or cycle_targets.size() < 2: return
	var target: Dictionary = cycle_targets[posmod(index + direction, cycle_targets.size())]
	selected_collection = String(target.collection)
	selected_id = int(target.id)
	view.queue_redraw()

func navigation_hint() -> String:
	var index := target_index(cycle_targets, selected_collection, selected_id)
	if index < 0 or cycle_targets.size() < 2: return ""
	return "겹침 %d/%d · 재선택/Tab: 다음" % [index + 1, cycle_targets.size()]

func card_rect(view) -> Rect2:
	var item := selected(view)
	if item.is_empty(): return Rect2()
	var body := UnitInspection.body_rect(view, item) if selected_collection == "units" else body_rect(view, item)
	var anchor: float = card_anchor_ratio * view.size.x if card_anchor_ratio >= 0.0 else body.get_center().x
	var width := minf(380.0, maxf(1.0, view.size.x - 24.0))
	var left := clampf(anchor - width * 0.5, 12.0, maxf(12.0, view.size.x - width - 12.0))
	# Reserve the taller unit layout for the whole tap group. Neither marching
	# nor switching to a structure (or losing a neighbour) moves the buttons.
	var footer_y := 224.0 if card_has_unit or selected_collection == "units" else 132.0
	return Rect2(left, 28.0, width, footer_y + BUTTON_HEIGHT + 12.0 - 28.0)

func action_rects(card: Rect2) -> Dictionary:
	var gap := 8.0
	var width := maxf(1.0, (card.size.x - 24.0 - gap * 2.0) / 3.0)
	var y := card.end.y - 12.0 - BUTTON_HEIGHT
	return {
		"previous": Rect2(card.position.x + 12.0, y, width, BUTTON_HEIGHT),
		"next": Rect2(card.position.x + 12.0 + width + gap, y, width, BUTTON_HEIGHT),
		"close": Rect2(card.position.x + 12.0 + (width + gap) * 2.0, y, width, BUTTON_HEIGHT),
	}

func begin_card_action(view, position: Vector2) -> void:
	pressed_card = card_rect(view)
	pressed_action = "surface"
	pressed_action_rect = pressed_card
	pressed_source_id = selected_id
	pressed_source_collection = selected_collection
	prune_cycle_targets(view)
	var rects := action_rects(pressed_card)
	for action in rects:
		var rect: Rect2 = rects[action]
		if not rect.has_point(position): continue
		if action != "close" and cycle_targets.size() < 2: break
		pressed_action = action
		pressed_action_rect = rect
		if action != "close":
			var index := target_index(cycle_targets, selected_collection, selected_id)
			if index < 0:
				pressed_action = "surface"
				break
			var direction := -1 if action == "previous" else 1
			var target: Dictionary = cycle_targets[posmod(index + direction, cycle_targets.size())]
			pressed_collection = String(target.collection)
			pressed_id = int(target.id)
		break

func release_card_action(view, position: Vector2) -> void:
	# Resolve the target on press, just as battlefield taps do. If it dies,
	# do not silently skip to a different neighbour when the finger lifts.
	if selected_id != pressed_source_id or selected_collection != pressed_source_collection: return
	if card_rect(view) != pressed_card or not pressed_action_rect.has_point(position): return
	if pressed_action == "close":
		cancel(view)
		UISounds.play("back")
	elif pressed_action in ["previous", "next"]:
		prune_cycle_targets(view)
		if target_index(cycle_targets, pressed_collection, pressed_id) < 0 or entity(view, pressed_collection, pressed_id).is_empty(): return
		selected_collection = pressed_collection
		selected_id = pressed_id
		UISounds.play("click")

func target_at(view, position: Vector2) -> Dictionary:
	# Units are drawn above structures. Resolve the visible foreground first;
	# separate collections also prevent colliding unit/structure IDs.
	var unit := UnitInspection.unit_at(view, position)
	if not unit.is_empty(): return {"collection": "units", "id": int(unit.id)}
	var structure := structure_at(view, position)
	return {"collection": "structures", "id": int(structure.get("id", -1))}

func begin_gui_input(view, event: InputEvent) -> bool:
	if not enabled or touch_index >= 0 or mouse_down: return false
	if event.device == InputEvent.DEVICE_ID_EMULATION: return false
	var position: Vector2
	if event is InputEventScreenTouch and event.pressed and not event.canceled:
		position = event.position
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not event.canceled:
		position = event.position
	else:
		return false
	pressed_action = ""
	var over_card := selected_id >= 0 and card_rect(view).has_point(position)
	var candidates := [] if over_card else ordered_targets(view, position)
	var target := {"collection": "structures", "id": -1}
	if not candidates.is_empty():
		var index := target_index(candidates, selected_collection, selected_id)
		target = candidates[(index + 1) % candidates.size()] if index >= 0 and candidates.size() > 1 else candidates[0]
	if int(target.id) < 0 and selected_id < 0: return false
	start_position = position
	pressed_id = int(target.id)
	pressed_collection = String(target.collection)
	pressed_targets = candidates
	if over_card: begin_card_action(view, position)
	canceled = false
	if event is InputEventScreenTouch:
		touch_index = event.index
		suppress_emulated_mouse = true
	else: mouse_down = true
	view.queue_redraw()
	return true

func _move(view, position: Vector2) -> void:
	if not Rect2(Vector2.ZERO, view.size).has_point(position) or position.distance_to(start_position) > DRAG_DISTANCE:
		canceled = true
	if not pressed_action.is_empty() and not pressed_action_rect.has_point(position): canceled = true
	view.queue_redraw()

func _release(view, position: Vector2, interrupted: bool) -> void:
	_move(view, position)
	if enabled and not canceled and not interrupted and not pressed_action.is_empty():
		release_card_action(view, position)
	elif enabled and not canceled and not interrupted:
		var matches := false
		if pressed_id < 0:
			matches = int(target_at(view, position).id) < 0
		elif pressed_collection == "units":
			var unit := entity(view, pressed_collection, pressed_id)
			# Track the original unit during the tap, even if a neighbour moves
			# closer. Never switch the target merely because the army is moving.
			matches = not unit.is_empty() and UnitInspection.hit_rect(view, unit).has_point(position)
		else:
			var structure := entity(view, pressed_collection, pressed_id)
			matches = not structure.is_empty() and body_rect(view, structure).has_point(position)
		if matches:
			var toggle_off := pressed_id == selected_id and pressed_collection == selected_collection
			if toggle_off or pressed_id < 0:
				cancel(view)
			else:
				if target_index(pressed_targets, selected_collection, selected_id) < 0:
					var item := entity(view, pressed_collection, pressed_id)
					var body := UnitInspection.body_rect(view, item) if pressed_collection == "units" else body_rect(view, item)
					card_anchor_ratio = body.get_center().x / maxf(1.0, view.size.x)
					card_has_unit = false
				for target in pressed_targets:
					if String(target.collection) == "units": card_has_unit = true
				selected_id = pressed_id
				selected_collection = pressed_collection
				cycle_targets = pressed_targets
				prune_cycle_targets(view)
				view.queue_redraw()
	touch_index = -1
	mouse_down = false
	pressed_id = -1
	pressed_targets = []
	pressed_action = ""
	view.queue_redraw()

func handle_input(main, event: InputEvent) -> bool:
	sync(main)
	var view = main.battle_view
	# The original touch owns this tap, including an emulated release over a HUD
	# card or a panel that appeared while the finger was down. A fresh real touch
	# clears a leftover marker if the platform never emitted its counterpart.
	if event is InputEventScreenTouch and event.pressed and touch_index < 0:
		suppress_emulated_mouse = false
	if event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION and event.button_index == MOUSE_BUTTON_LEFT and suppress_emulated_mouse:
		if not event.pressed: suppress_emulated_mouse = false
		return true
	if event is InputEventKey:
		if enabled and selected_id >= 0 and cycle_targets.size() > 1 and event.keycode == KEY_TAB and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if event.pressed:
				canceled = true
				main.unit_purchase_hold.cancel()
				if not event.echo: cycle_selection(view, -1 if event.shift_pressed else 1)
			return true
		if enabled and selected_id >= 0 and event.pressed and event.keycode == KEY_ESCAPE:
			cancel(view)
			main.unit_purchase_hold.cancel()
			return true
		# A battle hotkey may change the selected card while a finger is down.
		if event.pressed: canceled = true
		return false
	if event is InputEventScreenDrag and event.index == touch_index:
		_move(view, view.get_global_transform_with_canvas().affine_inverse() * event.position)
		return true
	if event is InputEventScreenTouch and (not event.pressed or event.canceled) and event.index == touch_index:
		_release(view, view.get_global_transform_with_canvas().affine_inverse() * event.position, event.canceled)
		return true
	if event is InputEventMouseMotion and mouse_down and event.device != InputEvent.DEVICE_ID_EMULATION:
		_move(view, view.get_global_transform_with_canvas().affine_inverse() * event.position)
		return true
	if event is InputEventMouseButton and mouse_down and event.button_index == MOUSE_BUTTON_LEFT and (not event.pressed or event.canceled) and event.device != InputEvent.DEVICE_ID_EMULATION:
		_release(view, view.get_global_transform_with_canvas().affine_inverse() * event.position, event.canceled)
		return true
	# Other fingers/buttons remain available to the HUD, but invalidate this tap.
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION:
		canceled = true
	return false

func draw(view) -> void:
	if not enabled or selected_id < 0: return
	var item := selected(view)
	if item.is_empty(): return
	var card := card_rect(view)
	if selected_collection == "units":
		UnitInspection.draw(view, item, spectator, "", card)
		draw_card_actions(view, card)
		return
	var structure := item
	var kind := String(structure.kind)
	var stats: Dictionary = BattleModel.STRUCTURE_STATS[kind]
	var side := int(structure.side)
	var team: Color = view.BLUE if view.display_side(side) == 0 else view.RED
	var hp := float(structure.hp)
	var maximum := maxf(1.0, float(structure.get("max_hp", stats.hp)))
	var fraction := clampf(hp / maximum, 0.0, 1.0)
	var health_tone: Color = view.RED_LIGHT if fraction <= 0.25 else Color("#e8edf5")
	var body := body_rect(view, structure)
	view.draw_rect(body, view.GOLD, false, 2.0)
	var width := card.size.x
	var left := card.position.x
	view.draw_line(Vector2(card.get_center().x, card.end.y), Vector2(body.get_center().x, body.position.y), Color(team.r, team.g, team.b, 0.65), 1.5)
	view.draw_rect(card, Color(0.02, 0.03, 0.06, 0.96))
	view.draw_rect(card, team, false, 2.0)
	var side_name := ("블루" if side == 0 else "레드") if spectator else ("아군" if side == view.own_side else "적군")
	view.draw_string(FONT, Vector2(left + 12.0, 56.0), "%s · %s" % [side_name, NAMES[kind]], HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 20, team)
	var health_text := "체력 %d / %d · %d%%%s" % [ceili(hp), ceili(maximum), roundi(fraction * 100.0), " · 파괴 주의" if fraction <= 0.25 else ""]
	view.draw_string(FONT, Vector2(left + 12.0, 82.0), health_text, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 16, health_tone)
	view.draw_rect(Rect2(left + 12.0, 90.0, width - 24.0, 6.0), Color("#313a4a"))
	view.draw_rect(Rect2(left + 12.0, 90.0, (width - 24.0) * fraction, 6.0), health_tone)
	var remaining := Lifetime.remaining(structure, float(view.snapshot.get("elapsed", 0.0)))
	var detail := "수명 제한 없음 · 파괴될 때까지 유지"
	var detail_tone := Color("#b0bbcf")
	if remaining >= 0.0:
		detail = "만료 상태 확인 중" if remaining <= 0.0 else "수명 %s · 만료 %s" % [Lifetime.countdown(remaining), Lifetime.expiry_clock(structure)]
		if remaining <= Lifetime.WARNING_SECONDS:
			detail_tone = view.GOLD
			if remaining > 0.0: detail += " · 임박"
	elif stats.has("lifetime"):
		detail = "수명 정보 없음"
	elif kind == "generator":
		detail = "추가 수입 +%.1f/전투 초 · 수명 제한 없음" % float(stats.income)
	view.draw_string(FONT, Vector2(left + 12.0, 120.0), detail, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 14, detail_tone)
	if card_has_unit:
		view.draw_string(FONT, Vector2(left + 12.0, 152.0), "병력과 구조물을 함께 확인 중", HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 14, Color("#b0bbcf"))
		view.draw_string(FONT, Vector2(left + 12.0, 180.0), "수명·수입은 전투 시간 기준", HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 14, Color("#b0bbcf"))
		view.draw_string(FONT, Vector2(left + 12.0, 212.0), "마지막 전투 상태 기준 · 전투는 계속 진행", HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 12, Color("#8995ad"))
	draw_card_actions(view, card)

func draw_card_actions(view, card: Rect2) -> void:
	var index := target_index(cycle_targets, selected_collection, selected_id)
	var can_cycle := index >= 0 and cycle_targets.size() > 1
	var pointer: Vector2 = view.get_local_mouse_position()
	var labels := {"previous": "‹ 이전", "next": "다음 ›", "close": "닫기 ×"}
	var active_pointer := touch_index >= 0 or mouse_down
	var rects := action_rects(card)
	for action in rects:
		var rect: Rect2 = rects[action]
		var available: bool = action == "close" or can_cycle
		var down: bool = active_pointer and not canceled and pressed_action == action
		var hover: bool = not active_pointer and available and rect.has_point(pointer)
		var fill := Color("#25344e") if down else Color("#1d2b43") if hover else Color("#121b2d")
		var tone: Color = view.GOLD if available else Color("#62708b")
		view.draw_rect(rect, fill)
		view.draw_rect(rect, tone if down or hover else Color("#2b3d5c"), false, 1.5)
		var baseline := rect.position.y + (35.0 if action == "previous" and not can_cycle else 25.0)
		var label: String = "다음 · Tab" if action == "next" and can_cycle else labels[action]
		view.draw_string(FONT, Vector2(rect.position.x + 4.0, baseline), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 16, tone)
		if action == "next":
			var count := "겹침 %d/%d" % [index + 1, cycle_targets.size()] if can_cycle else "대상 1개"
			view.draw_string(FONT, Vector2(rect.position.x + 4.0, rect.position.y + 45.0), count, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 12, tone)
		elif action == "close" or can_cycle:
			view.draw_string(FONT, Vector2(rect.position.x + 4.0, rect.position.y + 45.0), "Esc" if action == "close" else "Shift+Tab", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 8.0, 12, tone)
