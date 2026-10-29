extends RefCounted
## "What is new" guidance: a gold NEW tag on the menu buttons that lead to features the player has not
## opened yet, plus a short list with shortcuts. Only features of the current release line belong here;
## older ones are dropped from FEATURES when they stop being news.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

const MAX_SEEN := 60
## button: name of the main-menu button that leads there (the tag sits on it and goes away when it is pressed).
const FEATURES := [
	{"id": "expedition", "button": "ExpeditionButton", "title": "원정", "desc": "세 막의 갈림길을 골라 나아가며 카드·유물·강화를 모아 보스를 쓰러뜨리는 로그라이크 모드입니다."},
	{"id": "endless", "button": "EndlessButton", "title": "무한 방어", "desc": "끝없이 몰려오는 웨이브를 막으며 강화를 골라 쌓습니다. 몇 웨이브까지 버티는지 기록에 도전하세요."},
	{"id": "weekly", "button": "WeeklyButton", "title": "주간 도전", "desc": "한 주 동안 모두에게 같은 덱과 두 가지 규칙 변형이 주어지는 더 어려운 도전입니다."},
	{"id": "draft", "button": "DraftButton", "title": "드래프트", "desc": "AI와 번갈아 병력을 뽑아 덱을 만들고 싸웁니다. 먼저 뽑으면 상대가 못 씁니다."},
	{"id": "replay_share", "button": "ReplaysButton", "title": "리플레이 공유와 메모", "desc": "6자리 코드로 공유하고, 최근 온라인 전투를 보고, 장면마다 메모를 남길 수 있습니다."},
	{"id": "live_rooms", "button": "MultiplayerButton", "title": "라이브 전투 목록", "desc": "멀티플레이 방 목록에서 진행 중인 전투의 닉네임과 덱을 보고 바로 관전할 수 있습니다."},
	{"id": "viewer_tools", "button": "ReplaysButton", "title": "리플레이 뷰어 강화", "desc": "구간 반복, 유닛 정보 패널, 휠 확대와 이동을 쓸 수 있습니다."},
	{"id": "deck_stats", "button": "DeckButton", "title": "전체 승률 표시", "desc": "덱 편성 카드에 온라인 전체 선택률과 승률이 표시됩니다."},
]

static func is_seen(save: Dictionary, id: String) -> bool:
	return save.get("seen_features", []).has(id)

static func unseen(save: Dictionary) -> Array:
	return FEATURES.filter(func(feature): return not is_seen(save, String(feature.id)))

static func mark_seen(save: Dictionary, id: String) -> void:
	var seen: Array = save.get("seen_features", [])
	if not seen.has(id):
		seen.append(id)
		while seen.size() > MAX_SEEN:
			seen.pop_front()
	save["seen_features"] = seen

## Marks everything that hangs off one menu button.
static func mark_button_seen(save: Dictionary, button_name: String) -> void:
	for feature in FEATURES:
		if String(feature.button) == button_name:
			mark_seen(save, String(feature.id))

static func features_for(button_name: String) -> Array:
	return FEATURES.filter(func(feature): return String(feature.button) == button_name)

## Puts the NEW tag on the buttons of unseen features. `scope` is the menu column.
static func decorate(main, scope: Node) -> void:
	for feature in unseen(main.save_data):
		var button = scope.find_child(String(feature.button), true, false)
		if button == null or button.find_child("NewTag", false, false) != null:
			continue
		var tag := Label.new()
		tag.name = "NewTag"
		tag.text = "NEW"
		tag.add_theme_font_size_override("font_size", 10)
		tag.add_theme_color_override("font_color", Color("#2b1d02"))
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pill := StyleBoxFlat.new()
		pill.bg_color = UIKit.GOLD
		pill.set_corner_radius_all(8)
		pill.content_margin_left = 6
		pill.content_margin_right = 6
		pill.content_margin_top = 1
		pill.content_margin_bottom = 1
		tag.add_theme_stylebox_override("normal", pill)
		button.add_child(tag)
		var place := func(): tag.position = Vector2(button.size.x - tag.size.x - 6.0, -6.0)
		button.resized.connect(place)
		tag.resized.connect(place)
		place.call()
		var name_of_button := String(feature.button)
		button.pressed.connect(func():
			mark_button_seen(main.save_data, name_of_button)
			main._save_profile()
			_refresh_menu(main)
		, CONNECT_ONE_SHOT)

## Top-right chip with the number of unseen features; opens the list.
static func add_chip(main) -> void:
	var count := unseen(main.save_data).size()
	if count == 0:
		return
	var chip = main._styled_button(Localization.text("새 기능 %d개") % count, UIKit.GOLD_DEEP)
	chip.name = "NewFeaturesChip"
	chip.position = Vector2(900, 22)
	chip.size = Vector2(170, 42)
	chip.custom_minimum_size = Vector2(0, 0)
	chip.add_theme_font_size_override("font_size", 14)
	chip.pressed.connect(func(): show_list(main))
	main.root_background.add_child(chip)

static func open_feature(main, id: String) -> void:
	var feature := _find(id)
	if feature.is_empty(): return
	# Features sharing a menu button must also share its destination and seen state.
	var destination: Callable
	match String(feature.button):
		"WeeklyButton": destination = main._show_daily_brief.bind("weekly")
		"DraftButton": destination = main._build_draft_screen
		"EndlessButton": destination = func(): preload("res://scripts/screens/EndlessFlow.gd").show_brief(main)
		"ExpeditionButton": destination = func(): preload("res://scripts/screens/ExpeditionFlow.gd").show_brief(main)
		"ReplaysButton": destination = main._build_replay_list
		"DeckButton": destination = main._build_deck_screen
		"MultiplayerButton": destination = main._open_multiplayer
		_: return
	main._dismiss_action_overlay()
	destination.call()
	mark_button_seen(main.save_data, String(feature.button))
	main._save_profile()
	_refresh_menu(main)

## Weekly briefings keep the menu alive, so refresh its tags and count without rebuilding it.
static func _refresh_menu(main) -> void:
	var background: Control = main.root_background
	if not is_instance_valid(background) or background.is_queued_for_deletion(): return
	var chip := background.find_child("NewFeaturesChip", true, false) as Button
	if chip != null:
		var count := unseen(main.save_data).size()
		chip.text = Localization.text("새 기능 %d개") % count
		chip.visible = count > 0
	for feature in FEATURES:
		if not features_for(String(feature.button)).all(func(item): return is_seen(main.save_data, String(item.id))): continue
		var button := background.find_child(String(feature.button), true, false) as Button
		if button == null: continue
		var tag := button.find_child("NewTag", false, false)
		if tag != null: tag.queue_free()

static func _find(id: String) -> Dictionary:
	for feature in FEATURES:
		if String(feature.id) == id:
			return feature
	return {}

static func show_list(main) -> void:
	var background: Control = main.root_background
	var return_focus: Control = main.get_viewport().gui_get_focus_owner()
	var focus_ref: WeakRef = weakref(return_focus) if return_focus != null else null
	var dialog = main._action_panel("새 기능", Rect2(220, 48, 840, 624))
	var summary := MultiplayerUI.label("아직 확인하지 않은 기능 %d개 / %d개 · 열기를 눌러 바로 써 보세요." % [unseen(main.save_data).size(), FEATURES.size()], 14, MultiplayerUI.MUTED)
	summary.name = "NewFeatureSummary"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(summary)
	var scroll := ScrollContainer.new()
	scroll.name = "NewFeatureScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 120
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 16
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_ALL
	dialog.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "NewFeatureList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var controls: Array[Control] = [scroll]
	var first_unseen: Button = null
	for feature in FEATURES:
		var card := PanelContainer.new()
		card.name = "NewFeatureRow"
		var fresh := not is_seen(main.save_data, String(feature.id))
		card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, UIKit.GOLD if fresh else UIKit.EDGE_SOFT, 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 16, 10))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		card.add_child(line)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var title := Label.new()
		title.text = Localization.text(String(feature.title)) + ("   NEW" if fresh else Localization.text("   ✓ 확인함"))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", UIKit.GOLD if fresh else UIKit.TEXT)
		text.add_child(title)
		var desc := Label.new()
		desc.text = Localization.text(String(feature.desc))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		text.add_child(desc)
		var open = main._styled_button(Localization.text("열기"), UIKit.ACCENT, fresh)
		open.name = "OpenFeature_" + String(feature.id)
		open.custom_minimum_size = Vector2(100, UIKit.TOUCH_MIN_HEIGHT)
		open.tooltip_text = Localization.text(String(feature.desc))
		var feature_id := String(feature.id)
		open.pressed.connect(func():
			if _list_active(main, background, dialog): open_feature(main, feature_id))
		line.add_child(open)
		list.add_child(card)
		controls.append(open)
		if fresh and first_unseen == null: first_unseen = open
	var close_dialog := func():
		if not _list_active(main, background, dialog): return
		main._dismiss_action_overlay()
		background.get_tree().process_frame.connect(_restore_menu_focus.bind(main, background, focus_ref), CONNECT_ONE_SHOT)
	var close := MultiplayerUI.button(main, dialog, "닫기", "CloseNewFeatures", close_dialog)
	close.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT
	controls.append(close)
	for index in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		control.focus_neighbor_top = previous
		control.focus_neighbor_left = previous
		control.focus_neighbor_bottom = next
		control.focus_neighbor_right = next
		control.gui_input.connect(func(event: InputEvent):
			if not _list_active(main, background, dialog): return
			if not event is InputEventKey or not event.pressed: return
			if control == scroll and event.keycode in [KEY_UP, KEY_DOWN]:
				control.accept_event()
				scroll.scroll_vertical += 40 if event.keycode == KEY_DOWN else -40
				return
			match event.keycode:
				KEY_ESCAPE:
					control.accept_event()
					close_dialog.call()
				KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
					control.accept_event()
					scroll.grab_focus()
					match event.keycode:
						KEY_PAGEUP: scroll.scroll_vertical -= int(scroll.size.y)
						KEY_PAGEDOWN: scroll.scroll_vertical += int(scroll.size.y)
						KEY_HOME: scroll.scroll_vertical = 0
						KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		)
	var initial: Control = first_unseen if first_unseen != null else controls[1]
	initial.grab_focus()
	# Wait for container layout so the first unseen row can be brought into view.
	dialog.get_tree().process_frame.connect(func():
		if not _list_active(main, background, dialog): return
		var focused: Control = main.get_viewport().gui_get_focus_owner()
		if is_instance_valid(focused) and list.is_ancestor_of(focused): scroll.ensure_control_visible(focused)
	, CONNECT_ONE_SHOT)

static func _list_active(main, background: Control, dialog: Control) -> bool:
	return is_instance_valid(background) and not background.is_queued_for_deletion() \
		and main.root_background == background and is_instance_valid(dialog) and not dialog.is_queued_for_deletion() \
		and is_instance_valid(main.action_overlay) and not main.action_overlay.is_queued_for_deletion() \
		and main.action_overlay.is_ancestor_of(dialog)

static func _restore_menu_focus(main, background: Control, focus_ref: WeakRef) -> void:
	if not is_instance_valid(background) or background.is_queued_for_deletion() or main.root_background != background or is_instance_valid(main.action_overlay): return
	var target: Control = focus_ref.get_ref() if focus_ref != null else null
	if not is_instance_valid(target) or not target.is_visible_in_tree() or not background.is_ancestor_of(target):
		target = background.find_child("NewFeaturesChip", true, false) as Control
	if target == null or not target.is_visible_in_tree():
		target = background.find_child("MultiplayerButton", true, false) as Control
	if target == null or not target.is_visible_in_tree() or (target is BaseButton and target.disabled): return
	target.grab_focus()
