extends RefCounted
## Android opens with this screen until the server confirms a Google account (ClientAccount.unlocked).
## It connects to the official server by itself; a saved account resumes on the connection, a new player
## signs in and creates an account here. The PC version never shows it.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ServerLink = preload("res://scripts/ServerLink.gd")
const AccountPanel = preload("res://scripts/ui/AccountPanel.gd")

static func show(main, message: String = "") -> void:
	main.multiplayer_screen = ""
	main.battle_active = false
	main.result_shown = false
	main._clear_screen()
	main.root_background = main._make_background()

	var center := CenterContainer.new()
	center.name = "LoginGate"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main.root_background.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 560
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)

	var title := Label.new()
	title.text = "Keepfall"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UIKit.GOLD)
	column.add_child(title)

	column.add_child(AccountPanel.create(main, true))

	var status := Label.new()
	status.name = "LoginGateStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color("#9aa5c0"))
	status.text = Localization.text(message)
	column.add_child(status)
	main.status_label = status

	var retry = main._styled_button(Localization.text("서버에 다시 연결"), Color("#3d4a6b"), false)
	retry.name = "LoginGateRetry"
	retry.pressed.connect(func(): _connect(main, status))
	column.add_child(retry)
	var quit = main._styled_button(Localization.text("종료"), Color("#596174"), false)
	quit.name = "LoginGateQuit"
	quit.pressed.connect(main._quit_game)
	column.add_child(quit)

	_connect(main, status)

## A saved session resumes through ClientAccount's server_ready hook; the panel follows the account state.
static func _connect(main, status: Label) -> void:
	ServerLink.run(main, func(): main.account.resume(), func(text: String):
		if is_instance_valid(status): status.text = Localization.text(text))
