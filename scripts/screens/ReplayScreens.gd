extends RefCounted
## Replay list and player entry points (menu → 리플레이).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const ReplayViewer = preload("res://scripts/ui/ReplayViewer.gd")
const MenuScreens = preload("res://scripts/screens/MenuScreens.gd")
const REPLAY_LIST_SCREEN := preload("res://scenes/ui/ReplayListScreen.tscn")

static func describe(replay: Dictionary) -> Dictionary:
	var meta: Dictionary = replay.get("meta", {})
	var result: Dictionary = replay.get("result", {})
	var mode := String(meta.get("mode", ""))
	var title := "방 대전"
	if mode == "campaign":
		title = "캠페인 %d단계" % int(meta.get("stage", 1))
	elif mode == "practice":
		title = "연습 %d단계" % int(meta.get("stage", 1))
	elif mode == "quick":
		title = "빠른 대전"
	var winner := int(result.get("winner", -1))
	var outcome := "무승부"
	if mode == "campaign" or mode == "practice":
		outcome = "승리" if winner == 0 else ("패배" if winner == 1 else "무승부")
	else:
		outcome = "블루 승" if winner == 0 else ("레드 승" if winner == 1 else "무승부")
	var seconds := int(float(result.get("elapsed", 0.0)))
	return {"title": title, "outcome": outcome, "winner": winner, "duration": "%02d:%02d" % [seconds / 60, seconds % 60]}

static func _stamp(path: String) -> String:
	var file := path.get_file()
	if file.length() >= 15 and file.substr(8, 1) == "_":
		return "%s-%s-%s  %s:%s" % [file.substr(0, 4), file.substr(4, 2), file.substr(6, 2), file.substr(9, 2), file.substr(11, 2)]
	return file.get_basename()

static func _build_replay_list(main) -> void:
	var frame = MenuScreens._show_scene(main, REPLAY_LIST_SCREEN, "리플레이", "저장된 전투를 다시 보고 분석합니다 (최근 %d개)" % BattleReplay.MAX_SAVED)
	var column: VBoxContainer = frame.column
	var rows: VBoxContainer = column.get_node("ReplayScroll/ReplayRows")
	var status: Label = column.get_node("ReplayStatus")
	var paths: Array = BattleReplay.list_saved()
	var shown := 0
	for path in paths:
		var replay := BattleReplay.load_file(path)
		if replay.is_empty():
			continue
		shown += 1
		rows.add_child(_replay_card(main, String(path), replay))
	if shown == 0:
		var empty := VBoxContainer.new()
		empty.name = "NoReplays"
		empty.custom_minimum_size.y = 260
		empty.add_theme_constant_override("separation", 10)
		rows.add_child(empty)
		var icon := Label.new()
		icon.text = "▶"
		icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.display(icon, 56, UIKit.GOLD)
		empty.add_child(icon)
		var message := Label.new()
		message.text = Localization.text("아직 저장된 리플레이가 없습니다")
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UIKit.display(message, 22, UIKit.TEXT)
		empty.add_child(message)
		var hint := Label.new()
		hint.text = Localization.text("캠페인이나 온라인 전투를 끝까지 치르면 자동으로 저장됩니다.")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
		empty.add_child(hint)
	var back: Button = column.get_node("Footer/ReplayBack")
	UIKit.style_button(back, Color("#697386"), false, 16)
	back.text = Localization.text("메인 화면으로")
	back.pressed.connect(main._build_connect_screen)
	var import_button: Button = column.get_node("Footer/ImportReplayButton")
	UIKit.style_button(import_button, UIKit.TEAL, false, 16)
	import_button.text = Localization.text("클립보드에서 가져오기")
	import_button.pressed.connect(func(): status.text = import_text(main, DisplayServer.clipboard_get()))

static func _replay_card(main, path: String, replay: Dictionary) -> Control:
	var info := describe(replay)
	var tone := UIKit.SUCCESS if info.outcome in ["승리", "블루 승"] else (UIKit.DANGER if info.outcome in ["패배", "레드 승"] else UIKit.TEXT_MUTED)
	var card := PanelContainer.new()
	card.name = "ReplayCard"
	card.custom_minimum_size.y = 84
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE, Color(tone.r, tone.g, tone.b, 0.45), 12, 1.0, 0.3, Color(0, 0, 0, 0), 0.08), 16, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(86, 0)
	chip.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(Color(tone.r, tone.g, tone.b, 0.22), Color(tone.r, tone.g, tone.b, 0.08), Color(tone.r, tone.g, tone.b, 0.8), 10, 1.0, 0.0, Color(0, 0, 0, 0), 0.0), 8, 6))
	row.add_child(chip)
	var outcome := Label.new()
	outcome.text = String(info.outcome)
	outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	outcome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.display(outcome, 18, tone.lightened(0.4))
	chip.add_child(outcome)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(text)
	var title := Label.new()
	title.text = "%s  ·  %s" % [Localization.text(String(info.title)), info.duration]
	title.add_theme_font_size_override("font_size", 18)
	text.add_child(title)
	var stamp := Label.new()
	stamp.text = _stamp(path)
	stamp.add_theme_font_size_override("font_size", 12)
	stamp.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	text.add_child(stamp)
	for side in 2:
		var deck_row := HBoxContainer.new()
		deck_row.add_theme_constant_override("separation", 2)
		deck_row.tooltip_text = "블루 덱" if side == 0 else "레드 덱"
		row.add_child(deck_row)
		for kind in replay.setup.unit_decks[side]:
			var icon := TextureRect.new()
			icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
			icon.custom_minimum_size = Vector2(34, 46)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			deck_row.add_child(icon)
		if side == 0:
			var versus := Label.new()
			versus.text = "VS"
			versus.add_theme_color_override("font_color", UIKit.TEXT_DIM)
			row.add_child(versus)
	var play = main._styled_button("재생", UIKit.ACCENT, true)
	play.name = "PlayReplayButton"
	play.custom_minimum_size = Vector2(100, 46)
	play.pressed.connect(main._play_replay.bind(path))
	row.add_child(play)
	var share = main._styled_button("복사", UIKit.TEAL, false)
	share.name = "ShareReplayButton"
	share.custom_minimum_size = Vector2(80, 46)
	share.tooltip_text = Localization.text("공유용 텍스트를 클립보드에 복사합니다")
	share.pressed.connect(func():
		DisplayServer.clipboard_set(BattleReplay.to_share_text(replay))
		share.text = "복사됨 ✓")
	row.add_child(share)
	var delete = main._styled_button("삭제", UIKit.DANGER, false)
	delete.name = "DeleteReplayButton"
	delete.custom_minimum_size = Vector2(80, 46)
	delete.pressed.connect(func():
		DirAccess.remove_absolute(path)
		main._build_replay_list())
	row.add_child(delete)
	return card

## Saves a pasted share text as a replay. Returns the message to show the player.
static func import_text(main, text: String) -> String:
	var replay := BattleReplay.from_share_text(text)
	if replay.is_empty():
		return Localization.text("가져올 수 없습니다. 복사한 리플레이 텍스트가 맞는지 확인하세요.")
	var meta: Dictionary = replay.get("meta", {})
	meta["imported"] = true
	replay["meta"] = meta
	var path := BattleReplay.save(replay, "imported")
	if path == "":
		return Localization.text("저장하지 못했습니다.")
	main._build_replay_list()
	var status = main.find_child("ReplayStatus", true, false)
	var verdict := BattleReplay.verify(replay)
	var message := Localization.text("리플레이를 가져왔습니다.") if bool(verdict.ok) else Localization.text("가져왔지만 현재 규칙에서는 기록과 결과가 달라질 수 있습니다.")
	if status is Label:
		status.text = message
	return message

static func _play_replay(main, path: String) -> void:
	var replay := BattleReplay.load_file(path)
	if replay.is_empty():
		main._build_replay_list()
		return
	main.battle_active = false
	main._clear_screen()
	main.root_background = main._make_background()
	var info := describe(replay)
	var viewer := ReplayViewer.new()
	viewer.open(replay, "%s  ·  %s" % [Localization.text(String(info.title)), info.duration])
	viewer.closed.connect(func(): main._build_replay_list())
	main.root_background.add_child(viewer)
	main.replay_viewer = viewer
