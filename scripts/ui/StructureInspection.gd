extends RefCounted
## Read-only inspection in live battles. A gesture starts in the battlefield's
## GUI, but Main captures its end before another control can receive the release.

const Lifetime = preload("res://scripts/ui/StructureLifetime.gd")
const FONT = preload("res://assets/fonts/BlackHanSans-Regular.ttf")
const NAMES := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
const DRAG_DISTANCE := 14.0

var enabled := false
var selected_id := -1
var touch_index := -1
var mouse_down := false
var start_position := Vector2.ZERO
var pressed_id := -1
var canceled := false
var spectator := false
var suppress_emulated_mouse := false

func cancel(view) -> void:
	selected_id = -1
	canceled = true
	view.queue_redraw()

func reset(view) -> void:
	cancel(view)
	touch_index = -1
	mouse_down = false
	pressed_id = -1
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

func selected(view) -> Dictionary:
	for structure in view.snapshot.get("structures", []):
		if int(structure.get("id", -1)) == selected_id and float(structure.get("hp", 0.0)) > 0.0:
			return structure
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
	var structure := structure_at(view, position)
	if structure.is_empty() and selected_id < 0: return false
	start_position = position
	pressed_id = int(structure.get("id", -1))
	canceled = false
	if event is InputEventScreenTouch:
		touch_index = event.index
		suppress_emulated_mouse = true
	else: mouse_down = true
	return true

func _move(view, position: Vector2) -> void:
	if not Rect2(Vector2.ZERO, view.size).has_point(position) or position.distance_to(start_position) > DRAG_DISTANCE:
		canceled = true

func _release(view, position: Vector2, interrupted: bool) -> void:
	_move(view, position)
	if enabled and not canceled and not interrupted:
		var structure := structure_at(view, position)
		var released_id := int(structure.get("id", -1))
		if released_id == pressed_id:
			selected_id = -1 if released_id == selected_id else released_id
			view.queue_redraw()
	touch_index = -1
	mouse_down = false
	pressed_id = -1

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
	var structure := selected(view)
	if structure.is_empty(): return
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
	var width := minf(340.0, maxf(1.0, view.size.x - 24.0))
	var left := clampf(body.get_center().x - width * 0.5, 12.0, maxf(12.0, view.size.x - width - 12.0))
	var card := Rect2(left, 28.0, width, 142.0)
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
	view.draw_string(FONT, Vector2(left + 12.0, 152.0), "같은 구조물 · 빈 전장 · Esc로 닫기", HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, 12, Color("#8995ad"))
