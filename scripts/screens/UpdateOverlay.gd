extends RefCounted
## UpdateOverlay: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const ANDROID_APK_URL := "https://gamparda.github.io/codingcircle/CatWar.apk"

static func _on_update_started(main, version: String) -> void:
	if main.running_as_server:
		print("MANDATORY_UPDATE_FOUND version=%s" % version)
		return
	if is_instance_valid(main.update_overlay) or not is_instance_valid(main.root_background):
		return
	main.update_overlay = ColorRect.new()
	main.update_overlay.color = Color(0.025, 0.03, 0.055, 0.96)
	main.update_overlay.position = Vector2.ZERO
	main.update_overlay.size = Vector2(1280, 720)
	main.update_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	main.update_overlay.z_index = 200
	main.root_background.add_child(main.update_overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(340, 205)
	panel.size = Vector2(600, 310)
	var style = main._panel_style(Color("#11141e"), Color("#7170ff"), 18)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.65)
	style.shadow_size = 30
	panel.add_theme_stylebox_override("panel", style)
	main.update_overlay.add_child(panel)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(600, 310)
	panel.add_child(inner)
	var overline := Label.new()
	overline.text = "MANDATORY UPDATE"
	overline.position = Vector2(0, 38)
	overline.size = Vector2(600, 22)
	overline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overline.add_theme_font_size_override("font_size", 11)
	overline.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(overline)
	var title := Label.new()
	title.text = Localization.text("새 버전 %s") % version
	title.position = Vector2(0, 66)
	title.size = Vector2(600, 54)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#f5f7fb"))
	inner.add_child(title)
	main.update_message_label = Label.new()
	main.update_message_label.text = Localization.text("업데이트를 준비하고 있습니다...")
	main.update_message_label.position = Vector2(45, 135)
	main.update_message_label.size = Vector2(510, 34)
	main.update_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.update_message_label.add_theme_color_override("font_color", Color("#a7afc0"))
	inner.add_child(main.update_message_label)
	main.update_progress_bar = ProgressBar.new()
	main.update_progress_bar.position = Vector2(65, 190)
	main.update_progress_bar.size = Vector2(470, 14)
	main.update_progress_bar.max_value = 100.0
	main.update_progress_bar.show_percentage = false
	main.update_progress_bar.add_theme_stylebox_override("background", main._panel_style(Color("#080a0f"), Color(1.0, 1.0, 1.0, 0.06), 7))
	main.update_progress_bar.add_theme_stylebox_override("fill", main._panel_style(Color("#7170ff"), Color("#828fff"), 7))
	inner.add_child(main.update_progress_bar)
	main.update_note_label = Label.new()
	main.update_note_label.text = Localization.text("경기 중에는 설치하지 않으며, 완료 후 게임이 자동으로 재시작됩니다.")
	main.update_note_label.position = Vector2(25, 232)
	main.update_note_label.size = Vector2(550, 36)
	main.update_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main.update_note_label.add_theme_font_size_override("font_size", 12)
	main.update_note_label.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(main.update_note_label)

static func _show_android_apk_notice(main) -> void:
	main._on_update_started(main.build_binary_version())
	if not is_instance_valid(main.update_overlay):
		return
	main.update_message_label.text = Localization.text("APK 업데이트가 필요합니다.")
	main.update_progress_bar.visible = false
	main.update_note_label.text = Localization.text("새 APK를 설치한 뒤 게임을 다시 실행해 주세요.")
	var download_button = main._styled_button(Localization.text("APK 다운로드"), Color("#7170ff"), true)
	download_button.position = Vector2(580, 420)
	download_button.size = Vector2(120, 50)
	download_button.pressed.connect(func(): OS.shell_open(ANDROID_APK_URL))
	main.update_overlay.add_child(download_button)

static func _on_update_status(main, message: String, progress: float) -> void:
	if main.running_as_server:
		print("UPDATE_STATUS %s" % message)
		return
	if is_instance_valid(main.update_message_label):
		main.update_message_label.text = message
	if is_instance_valid(main.update_progress_bar) and progress >= 0.0:
		main.update_progress_bar.value = progress * 100.0

static func _on_update_failed(main, message: String) -> void:
	if main.running_as_server:
		printerr("UPDATE_FAILED %s; retrying in 10 seconds" % message)
		return
	if is_instance_valid(main.update_message_label):
		main.update_message_label.text = message + Localization.text("\n10초 후 자동으로 다시 시도합니다.")
	if is_instance_valid(main.update_progress_bar):
		main.update_progress_bar.value = 0.0
