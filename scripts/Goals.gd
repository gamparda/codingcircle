extends RefCounted
## Starter goals for new players: a short checklist that points at the game's main modes, in the order a
## newcomer would want to try them. Most goals are derived from the save file's statistics; the rest are
## flags set by the screens when the player does the thing (save.goals).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")

const DEFS := [
	{"id": "first_win", "title": "첫 승리", "desc": "캠페인 1단계를 이겨 보세요.", "go": "캠페인"},
	{"id": "edit_deck", "title": "내 덱 만들기", "desc": "덱 편성에서 병력 3종과 구조물 3종을 골라 저장해 보세요.", "go": "덱 편성"},
	{"id": "daily", "title": "일일 도전", "desc": "오늘의 일일 도전에서 승리해 보세요.", "go": "일일 도전"},
	{"id": "draft", "title": "드래프트", "desc": "AI와 번갈아 병력을 뽑아 싸워 보세요.", "go": "드래프트"},
	{"id": "watch_replay", "title": "리플레이 보기", "desc": "저장된 전투를 다시 보고 장면에 메모를 남겨 보세요.", "go": "리플레이"},
	{"id": "online", "title": "온라인 대전", "desc": "온라인에서 다른 플레이어와 한 판 치러 보세요.", "go": "멀티플레이"},
]

static func ids() -> Array:
	return DEFS.map(func(entry): return String(entry.id))

static func is_done(save: Dictionary, id: String) -> bool:
	var stats: Dictionary = save.get("stats", {})
	match id:
		"first_win": return int(stats.get("highest_campaign", 0)) >= 1
		"daily": return int(stats.get("daily_completed", 0)) >= 1
		"online": return int(stats.get("online_completed", 0)) >= 1
	return bool(save.get("goals", {}).get(id, false))

static func done_ids(save: Dictionary) -> Array:
	return ids().filter(func(id): return is_done(save, String(id)))

static func done_count(save: Dictionary) -> int:
	return done_ids(save).size()

static func all_done(save: Dictionary) -> bool:
	return done_count(save) >= DEFS.size()

## Records that the player did a flag-based goal.
static func mark(save: Dictionary, id: String) -> void:
	if not ids().has(id):
		return
	var flags: Dictionary = save.get("goals", {})
	flags[id] = true
	save["goals"] = flags

## The first goal that is still open, or {}.
static func next_goal(save: Dictionary) -> Dictionary:
	for entry in DEFS:
		if not is_done(save, String(entry.id)):
			return entry
	return {}

static func definition(id: String) -> Dictionary:
	for entry in DEFS:
		if String(entry.id) == id:
			return entry
	return {}

## Goals completed since `before` (an earlier done_ids result).
static func gained(save: Dictionary, before: Array) -> Array:
	return done_ids(save).filter(func(id): return not before.has(id)).map(func(id): return definition(String(id)))

static func open(main, id: String) -> void:
	main._dismiss_action_overlay()
	match id:
		"first_win": main._build_ai_stage_screen(true)
		"edit_deck": main._build_deck_screen()
		"daily": main._show_daily_brief()
		"draft": main._build_draft_screen()
		"watch_replay": main._build_replay_list()
		"online": main._open_multiplayer()

## Menu chip with the progress; hidden once everything is done.
static func add_chip(main) -> void:
	if all_done(main.save_data):
		return
	var chip = main._styled_button(Localization.text("시작 목표 %d / %d") % [done_count(main.save_data), DEFS.size()], UIKit.TEAL)
	chip.name = "GoalsChip"
	chip.position = Vector2(714, 22)
	chip.size = Vector2(170, 42)
	chip.custom_minimum_size = Vector2(0, 0)
	chip.add_theme_font_size_override("font_size", 14)
	chip.pressed.connect(func(): show_list(main))
	main.root_background.add_child(chip)

static func show_list(main) -> void:
	var dialog = main._action_panel("시작 목표", Rect2(240, 50, 800, 620))
	dialog.add_child(MultiplayerUI.label("%d / %d 완료  ·  하나씩 해 보면 게임의 주요 모드를 모두 만나게 됩니다." % [done_count(main.save_data), DEFS.size()], 14, MultiplayerUI.MUTED))
	var list := VBoxContainer.new()
	list.name = "GoalList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	dialog.add_child(list)
	var next_id := String(next_goal(main.save_data).get("id", ""))
	for entry in DEFS:
		var finished := is_done(main.save_data, String(entry.id))
		var card := PanelContainer.new()
		card.name = "GoalRow"
		var tone := UIKit.SUCCESS if finished else (UIKit.GOLD if String(entry.id) == next_id else UIKit.EDGE_SOFT)
		card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(tone.r, tone.g, tone.b, 0.7), 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 16, 8))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		card.add_child(line)
		var mark := Label.new()
		mark.name = "GoalMark"
		mark.text = "✓" if finished else "○"
		mark.add_theme_font_size_override("font_size", 22)
		mark.add_theme_color_override("font_color", tone)
		line.add_child(mark)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(text)
		var title := Label.new()
		title.text = Localization.text(String(entry.title))
		title.add_theme_font_size_override("font_size", 17)
		title.add_theme_color_override("font_color", UIKit.TEXT_MUTED if finished else UIKit.TEXT)
		text.add_child(title)
		var desc := Label.new()
		desc.text = Localization.text(String(entry.desc))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		text.add_child(desc)
		if not finished:
			var go = main._styled_button(Localization.text(String(entry.go)), UIKit.ACCENT, String(entry.id) == next_id)
			go.name = "GoalGo_" + String(entry.id)
			go.custom_minimum_size = Vector2(120, 40)
			var goal_id := String(entry.id)
			go.pressed.connect(func(): open(main, goal_id))
			line.add_child(go)
		list.add_child(card)
	MultiplayerUI.button(main, dialog, "닫기", "CloseGoals", main._dismiss_action_overlay)

## Two short lines for the result screen: what was just achieved and what to try next.
static func result_lines(save: Dictionary, before: Array) -> Array:
	var lines: Array = []
	for entry in gained(save, before):
		lines.append({"text": "목표 달성 ▸ %s" % Localization.text(String(entry.title)), "tone": "gold"})
	var next := next_goal(save)
	if not next.is_empty():
		lines.append({"text": "다음 추천 ▸ %s  ·  %s" % [Localization.text(String(next.title)), Localization.text(String(next.go))], "tone": "muted"})
	return lines
