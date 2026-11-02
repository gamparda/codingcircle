extends RefCounted
## The phone's back button (Android "go back"): instead of closing the app it does what the screen's own back
## or close control does. A dialog closes first; a battle opens its menu (pause in solo battles); a screen
## with a ← button goes back; on the main menu a second press within EXIT_WINDOW quits.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")

const EXIT_WINDOW_MSEC := 2000
## Buttons that close what is on top, and buttons that go back a screen.
const CLOSE_TEXTS := ["닫기", "취소", "계속하기"]
static var _exit_armed_at := -100000

static func go_back(main) -> void:
	var target := _top_control(main)
	if target != null:
		_exit_armed_at = -100000
		target.pressed.emit()
		return
	if main.battle_active and not main.result_shown:
		_exit_armed_at = -100000
		if main.local_ai_mode:
			preload("res://scripts/screens/LocalBattlePause.gd").pause(main)
		else:
			preload("res://scripts/screens/BattleHud.gd")._online_menu(main)
		return
	var now := Time.get_ticks_msec()
	if now - _exit_armed_at <= EXIT_WINDOW_MSEC:
		main.get_tree().quit()
		return
	_exit_armed_at = now
	var toast := ToastLabel.new()
	toast.name = "BackExitToast"
	toast.tone = UIKit.TEXT
	toast.text = Localization.text("뒤로 버튼을 한 번 더 누르면 종료합니다.")
	main.add_child(toast)
	toast.place_center(640.0, 640.0)
	main.get_tree().create_timer(float(EXIT_WINDOW_MSEC) / 1000.0).timeout.connect(func():
		if is_instance_valid(toast): toast.queue_free())

## The control the back button should press: the newest visible close button of a dialog, else the
## screen's ← button. Null when there is none (a battle without a dialog, or the main menu).
static func _top_control(main) -> Button:
	var close: Button = null
	var back: Button = null
	for node in main.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree() or button.disabled:
			continue
		var text := button.text.strip_edges()
		if text in CLOSE_TEXTS or text.begins_with("▶  계속하기") or String(button.name).begins_with("Close"):
			close = button
		elif text == "←" or String(button.name).ends_with("BackButton") or String(button.name) == "SubMenuBack":
			back = button
	return close if close != null else back
