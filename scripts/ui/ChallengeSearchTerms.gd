extends ScrollContainer
## Keep active search words reachable even when all candidate cards are hidden.

signal term_removed(field: int, term: String)
signal close_requested

const UIKit = preload("res://scripts/ui/UIKit.gd")
const FIELD_NAMES := ["전체", "내 덱 (블루)", "상대 덱 (레드)"]
const STRUCTURE_NAMES := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}

var _row: HBoxContainer
var _buttons: Array[Control] = []

func _init() -> void:
	name = "ChallengeSearchTerms"
	custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT + 18
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	scroll_deadzone = 16
	get_h_scroll_bar().focus_mode = Control.FOCUS_NONE
	tooltip_text = "현재 검색어를 하나씩 해제합니다. 좌우로 스크롤하거나 Tab으로 이동할 수 있습니다."
	_row = HBoxContainer.new()
	_row.name = "Terms"
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)
	visible = false

func buttons() -> Array[Control]:
	return _buttons

func sync_queries(queries: PackedStringArray, fallback: Control) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	var focus_index := _buttons.find(focused)
	var existing := {}
	for button in _buttons: existing[String(button.name)] = button
	var current: Array[Control] = []
	for field in queries.size():
		var seen := {}
		for term in _terms(queries[field]):
			var key: String = term.to_lower()
			if seen.has(key): continue
			seen[key] = true
			var node_name := "RemoveChallengeTerm%d_%s" % [field, key.sha256_text()]
			var button: Button = existing.get(node_name)
			if button == null:
				var tone: Color = [UIKit.TEAL, UIKit.TEAM_BLUE, UIKit.TEAM_RED][field]
				button = UIKit.style_button(Button.new(), tone, false, 14)
				button.name = node_name
				button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
				button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
				button.mouse_filter = Control.MOUSE_FILTER_PASS
				button.pressed.connect(_remove_term.bind(button, field, key))
				button.gui_input.connect(_handle_input.bind(button))
				_row.add_child(button)
			existing.erase(node_name)
			var title: String = term
			if field > 0: title = String(BattleModel.UNIT_NAMES.get(key, STRUCTURE_NAMES.get(key, term)))
			button.text = "%s: %s ×" % [FIELD_NAMES[field], title.left(22) + ("…" if title.length() > 22 else "")]
			button.tooltip_text = "%s 검색의 ‘%s’ 단어만 해제합니다. 같은 단어의 중복·대소문자 변형도 해제하며 부분 검색어·다른 검색칸·결과·클립 조건은 유지합니다." % [FIELD_NAMES[field], term]
			_row.move_child(button, current.size())
			current.append(button)
	for button in existing.values():
		_row.remove_child(button)
		button.queue_free()
	_buttons = current
	visible = not current.is_empty()
	# A disappearing word moves focus to a nearby word, then to the result scroll.
	# Removing a condition on touch never focuses a LineEdit and opens a keyboard.
	if focus_index >= 0 and focused not in current:
		var target: Control = current[mini(focus_index, current.size() - 1)] if not current.is_empty() else fallback
		target.grab_focus()

func _remove_term(button: Button, field: int, term: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not button.is_visible_in_tree(): return
	button.grab_focus()
	term_removed.emit(field, term)

func _handle_input(event: InputEvent, button: Button) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		button.accept_event()
		close_requested.emit()

static func _terms(query: String) -> PackedStringArray:
	return query.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false)
