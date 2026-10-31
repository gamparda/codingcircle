extends RefCounted
## 칭호: every title by group, how to earn it (hidden ones stay "???" until earned), and the button that wears
## an owned one beside the player's name. Opens over the current screen; changes go to the server at once.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")

static func show(main) -> void:
	var account = main.account
	account.new_titles.clear()
	var column = main._action_panel(Localization.text("칭호"), Rect2(240, 60, 800, 600))
	main.action_overlay.name = "TitlesOverlay"
	var worn_text := Localization.text("지금 다는 칭호 · %s") % (Titles.badge(account.worn) if not account.worn.is_empty() else Localization.text("없음"))
	var worn := MultiplayerUI.label(worn_text, 16, MultiplayerUI.GOLD)
	worn.name = "TitlesWorn"
	column.add_child(worn)
	column.add_child(MultiplayerUI.label(Localization.text("랭크 대전과 대기실에서 닉네임 앞에 보입니다. 혼자 하는 모드의 칭호는 서버가 전투를 다시 계산해 확인한 뒤 줍니다."), 13, MultiplayerUI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var group := ""
	for id in Titles.CATALOG:
		var entry: Dictionary = Titles.CATALOG[id]
		var owned: bool = account.titles.has(id)
		if bool(entry.get("hidden", false)) and not owned and String(entry.group) == "특별":
			continue # role titles are not something to chase
		if String(entry.group) != group:
			group = String(entry.group)
			list.add_child(MultiplayerUI.label(Localization.text(group), 17, UIKit.ACCENT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		list.add_child(row)
		var secret: bool = bool(entry.get("hidden", false)) and not owned
		var text := MultiplayerUI.label("%s%s\n%s" % ["✓ " if owned else "", Titles.badge(id) if not secret else "[???]", Localization.text(String(entry.how)) if not secret else Localization.text("숨겨진 칭호")], 15, Color.WHITE if owned else MultiplayerUI.MUTED)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		if owned:
			var wearing: bool = account.worn == id
			var button = main._styled_button(Localization.text("해제") if wearing else Localization.text("장착"), Color("#697386") if wearing else Color("#7a6248"), not wearing)
			button.name = "WearTitle_" + String(id)
			button.custom_minimum_size = Vector2(110, 44)
			var pick := "" if wearing else String(id)
			button.pressed.connect(func():
				account.wear(pick)
				main._dismiss_action_overlay())
			row.add_child(button)
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseTitles", main._dismiss_action_overlay)
