extends RefCounted
## Tutorial: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")

static func _begin_tutorial(main) -> void:
	main.tutorial_step = 0
	var banner := PanelContainer.new()
	banner.name = "FirstBattleGuide"
	banner.position = Vector2(320, 94)
	banner.size = Vector2(640, 68)
	banner.z_index = 20
	banner.add_theme_stylebox_override("panel", main._panel_style(Color("#151c2c"), Color("#f6c85f"), 12))
	main.root_background.add_child(banner)
	main.tutorial_banner = banner
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(640, 68)
	banner.add_child(inner)
	main.tutorial_hint = Label.new()
	main.tutorial_hint.name = "FirstBattleHint"
	main.tutorial_hint.position = Vector2(14, 7)
	main.tutorial_hint.size = Vector2(506, 54)
	main.tutorial_hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	main.tutorial_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main.tutorial_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.tutorial_hint.add_theme_font_size_override("font_size", 16)
	main.tutorial_hint.add_theme_color_override("font_color", Color("#f5f7fb"))
	inner.add_child(main.tutorial_hint)
	var skip = main._styled_button(Localization.text("건너뛰기"), Color("#697386"), false)
	skip.name = "SkipFirstBattleGuide"
	skip.position = Vector2(524, 12)
	skip.size = Vector2(104, 44)
	skip.pressed.connect(main._finish_tutorial)
	inner.add_child(skip)
	main._update_tutorial_hint()

static func _update_tutorial_hint(main) -> void:
	if not is_instance_valid(main.tutorial_hint):
		return
	match main.tutorial_step:
		0: main.tutorial_hint.text = Localization.text("첫 전투: 아래 유닛을 눌러 소환하세요.")
		1: main.tutorial_hint.text = Localization.text("구조물을 고른 뒤 전장에 설치하세요.")
		2: main.tutorial_hint.text = Localization.text("자원은 시간이 지나면 회복됩니다. 잠시 기다려 보세요.")

static func _tutorial_advance(main, completed_step: int) -> void:
	if not main.local_ai_mode or main.tutorial_step != completed_step:
		return
	if main.tutorial_step == 2:
		main._finish_tutorial()
		return
	main.tutorial_step += 1
	if main.tutorial_step == 2:
		main.tutorial_low_resource = float(main.local_model.resources[main.own_side])
	main._update_tutorial_hint()

static func _finish_tutorial(main) -> void:
	if main.tutorial_step < 0:
		return
	main.save_data.tutorial_completed = true
	SaveData.save_data(main.save_data)
	main.tutorial_step = -1
	if is_instance_valid(main.tutorial_banner):
		main.tutorial_banner.queue_free()
	main.tutorial_banner = null
	main.tutorial_hint = null
