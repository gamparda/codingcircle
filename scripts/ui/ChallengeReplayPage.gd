extends VBoxContainer
## Keep only the current page's cards; metadata and completed scores live separately.

signal cards_changed
signal page_ready
signal card_removed(entry: Dictionary)

const UIKit = preload("res://scripts/ui/UIKit.gd")
const PAGE_SIZE := 8

var page := 0
var page_count := 1
var match_count := 0
var loading := false
var _current: Array = []
var _pending: Array = []
var _factory: Callable
var _state: Dictionary
var _headings: Array[Label] = []

func setup(factory: Callable, state: Dictionary) -> void:
	_factory = factory
	_state = state
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 10)
	for _group in 2:
		var heading := Label.new()
		heading.add_theme_font_size_override("font_size", 16)
		heading.add_theme_color_override("font_color", UIKit.GOLD)
		heading.visible = false
		add_child(heading)
		_headings.append(heading)
	set_process(false)

func render(matches: Array, requested_page: int, anchor_path: String = "") -> void:
	match_count = matches.size()
	page_count = maxi(1, int(ceil(float(match_count) / float(PAGE_SIZE))))
	page = clampi(requested_page, 0, page_count - 1)
	if not anchor_path.is_empty():
		for index in matches.size():
			if String(matches[index].path) == anchor_path:
				page = int(index / PAGE_SIZE)
				break
	_state["page"] = page
	var next := matches.slice(page * PAGE_SIZE, mini((page + 1) * PAGE_SIZE, match_count))
	var paths := {}
	for entry in next: paths[String(entry.path)] = true
	for entry in _current:
		if paths.has(String(entry.path)): continue
		if entry.has("card"):
			card_removed.emit(entry)
			var card: Control = entry.card
			remove_child(card)
			card.queue_free()
			entry.erase("card")
			entry.erase("deck_buttons")
	_current = next
	_pending.clear()
	for entry in _current:
		if not entry.has("card"): _pending.append(entry)
	for group in 2:
		var on_page := 0
		var total := 0
		for entry in _current:
			if int(bool(entry.unknown)) == group: on_page += 1
		for entry in matches:
			if int(bool(entry.unknown)) == group: total += 1
		_headings[group].visible = on_page > 0
		_headings[group].text = ("기록의 버전 확인됨" if group == 0 else "버전 미상 · 날짜만 일치") + " · 이 쪽 %d개 / 검색 결과 %d개" % [on_page, total]
	_arrange()
	loading = not _pending.is_empty()
	set_process(loading)
	cards_changed.emit()
	if not loading: page_ready.emit()

func controls() -> Array[Control]:
	var result: Array[Control] = []
	for entry in _current:
		if not entry.has("card"): continue
		for button in entry.deck_buttons: result.append(button)
		result.append(entry.card.find_child("AnalyzeChallengeScore", true, false))
		result.append(entry.card.find_child("WatchChallengeReplay", true, false))
	return result

func anchor_path(scroll: ScrollContainer) -> String:
	# Remember the first card intersecting the viewport even when Refresh has focus.
	var top := scroll.get_global_rect().position.y
	for entry in _current:
		if not entry.has("card"): continue
		var rect: Rect2 = entry.card.get_global_rect()
		if rect.end.y > top: return String(entry.path)
	return String(_current[0].path) if not _current.is_empty() else ""

func _process(_delta: float) -> void:
	if not _alive():
		_pending.clear()
		set_process(false)
		return
	var deadline := Time.get_ticks_usec() + 4000
	var built := 0
	while not _pending.is_empty():
		var entry: Dictionary = _pending.pop_front()
		var card: Control = _factory.call(entry)
		entry["card"] = card
		add_child(card)
		built += 1
		if built >= 2 or Time.get_ticks_usec() >= deadline: break
	_arrange()
	loading = not _pending.is_empty()
	set_process(loading)
	cards_changed.emit()
	if not loading: page_ready.emit()

func _arrange() -> void:
	var index := 0
	for group in 2:
		move_child(_headings[group], index)
		index += 1
		for entry in _current:
			if int(bool(entry.unknown)) != group or not entry.has("card"): continue
			move_child(entry.card, index)
			index += 1

func _alive() -> bool:
	if not is_inside_tree(): return false
	var node: Node = self
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true
