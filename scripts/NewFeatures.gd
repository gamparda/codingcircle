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
			SaveData.save_data(main.save_data)
			if is_instance_valid(tag):
				tag.queue_free()
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
	main._dismiss_action_overlay()
	match id:
		"weekly": main._show_daily_brief("weekly")
		"draft": main._build_draft_screen()
		"replay_share": main._build_replay_list()
		"deck_stats": main._build_deck_screen()
	var feature := _find(id)
	if not feature.is_empty():
		mark_button_seen(main.save_data, String(feature.button))
		SaveData.save_data(main.save_data)

static func _find(id: String) -> Dictionary:
	for feature in FEATURES:
		if String(feature.id) == id:
			return feature
	return {}

static func show_list(main) -> void:
	var dialog = main._action_panel("새 기능", Rect2(240, 70, 800, 580))
	dialog.add_child(MultiplayerUI.label("눌러서 바로 써 볼 수 있습니다.", 14, MultiplayerUI.MUTED))
	var list := VBoxContainer.new()
	list.name = "NewFeatureList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	dialog.add_child(list)
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
		title.text = Localization.text(String(feature.title)) + ("   NEW" if fresh else "")
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
		open.custom_minimum_size = Vector2(100, 44)
		var feature_id := String(feature.id)
		open.pressed.connect(func(): open_feature(main, feature_id))
		line.add_child(open)
		list.add_child(card)
	MultiplayerUI.button(main, dialog, "닫기", "CloseNewFeatures", main._dismiss_action_overlay)
