extends RefCounted
## Ranked ban phase: shows the opponent's deck and lets the player remove one of its cards from the coming
## battle (RankedFlow). The battle starts when both have chosen or the time runs out; no choice means no ban.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const SpellArt = preload("res://scripts/ui/SpellArt.gd")

static func show(main, data: Dictionary) -> void:
	if not is_instance_valid(main.root_background):
		return
	var dialog = main._action_panel("랭크 대전 · 카드 금지", Rect2(170, 130, 940, 420))
	main.action_overlay.name = "BanOverlay"
	var note := MultiplayerUI.label("상대 덱에서 이번 경기에 쓰지 못하게 할 카드 1장을 고르세요.", 16, UIKit.TEXT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.add_child(note)
	var status := MultiplayerUI.label("", 15, UIKit.GOLD)
	status.name = "BanStatus"
	var grid := GridContainer.new()
	grid.name = "BanChoices"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	dialog.add_child(grid)
	var buttons: Array = []
	for kind in data.units + data.structures:
		var name: String = String(BattleModel.UNIT_NAMES.get(kind, BattleModel.STRUCTURE_NAMES.get(kind, kind)))
		var button: Button = main._styled_button(name, Color("#8f3a4a"), false)
		button.name = "Ban_" + String(kind)
		button.custom_minimum_size = Vector2(200, 96)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.icon = _card_art(String(kind))
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_constant_override("icon_max_width", 64)
		var chosen := String(kind)
		button.pressed.connect(func():
			if not main.network.send_ban(chosen):
				status.text = "서버에 연결되어 있지 않습니다."
				return
			for other in buttons: other.disabled = true
			button.modulate = Color(1.0, 0.6, 0.6)
			status.text = "%s 금지 · 상대의 선택을 기다리는 중..." % name)
		buttons.append(button)
		grid.add_child(button)
	dialog.add_child(status)
	_count_down(main, status, buttons, ceili(float(data.seconds)))

static func _card_art(kind: String) -> Texture2D:
	var icon: Texture2D = SpellArt.icon(kind)
	if icon != null:
		return icon
	if BattleModel.UNIT_STATS.has(kind):
		return load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
	return null

static func _count_down(main, status: Label, buttons: Array, seconds: int) -> void:
	if not is_instance_valid(status):
		return
	if not buttons.any(func(button): return is_instance_valid(button) and button.disabled):
		status.text = "남은 시간 %d초 · 고르지 않으면 금지 없이 시작합니다." % maxi(0, seconds)
	if seconds > 0:
		main.get_tree().create_timer(1.0).timeout.connect(func(): _count_down(main, status, buttons, seconds - 1))
