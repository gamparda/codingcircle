extends RefCounted
## SettingsScreen: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const DataReset = preload("res://scripts/DataReset.gd")

static func _build_settings_screen(main, mobile_layout_override: bool = false) -> void:
	var outer = main._submenu(Localization.text("설정"), "변경 시 자동 저장")
	var mobile_layout := OS.has_feature("mobile") or mobile_layout_override
	var settings: Dictionary = main.save_data.settings
	main.binding_draft = BattleBindings.sanitize(settings.get("battle_keys"))
	var quality_row := HBoxContainer.new()
	var quality_label := Label.new()
	quality_label.text = Localization.text("화질")
	quality_label.custom_minimum_size.x = 180
	quality_row.add_child(quality_label)
	var quality := OptionButton.new()
	quality.name = "GraphicsQualitySelector"
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var quality_options: Array = SaveData.GRAPHICS_QUALITIES.duplicate()
	if String(settings.graphics_quality) == "custom":
		quality_options.append("custom")
	for key in quality_options:
		quality.add_item(Localization.text({"auto": "자동", "high": "높음", "medium": "중간", "low": "낮음", "custom": "사용자 지정"}[key]))
	quality.select(max(0, quality_options.find(String(settings.graphics_quality))))
	quality_row.add_child(quality)
	outer.add_child(quality_row)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 16
	outer.add_child(scroll)
	if mobile_layout:
		main.settings_touch_scroll = scroll
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	main._add_settings_section(column, "오디오")
	var controls := GridContainer.new()
	controls.columns = 2
	column.add_child(controls)
	var master := HSlider.new(); master.name = "MasterVolumeSlider"; master.min_value = 0.0; master.max_value = 1.0; master.step = 0.05; master.value = settings.master_volume
	var bgm := HSlider.new(); bgm.name = "BGMVolumeSlider"; bgm.min_value = 0.0; bgm.max_value = 1.0; bgm.step = 0.05; bgm.value = settings.bgm_volume
	var sfx := HSlider.new(); sfx.name = "SFXVolumeSlider"; sfx.min_value = 0.0; sfx.max_value = 1.0; sfx.step = 0.05; sfx.value = settings.sfx_volume
	master.value_changed.connect(main._preview_bus_volume.bind("Master"))
	bgm.value_changed.connect(main._preview_bus_volume.bind("BGM"))
	sfx.value_changed.connect(main._preview_bus_volume.bind("SFX"))
	controls.columns = 3
	controls.add_theme_constant_override("h_separation", 20)
	controls.add_theme_constant_override("v_separation", 14)
	for pair in [[Localization.text("전체 음량"), master], [Localization.text("BGM 음량"), bgm], [Localization.text("효과음 음량"), sfx]]:
		var label := Label.new(); label.text = pair[0]; label.custom_minimum_size.x = 150; controls.add_child(label)
		var slider: HSlider = pair[1]
		slider.custom_minimum_size = Vector2(520, 28)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		controls.add_child(slider)
		var readout := Label.new()
		readout.custom_minimum_size.x = 56
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.add_theme_color_override("font_color", UIKit.GOLD)
		readout.text = "%d%%" % roundi(slider.value * 100.0)
		slider.value_changed.connect(func(value): readout.text = "%d%%" % roundi(value * 100.0))
		controls.add_child(readout)
	var muted := CheckButton.new(); muted.text = Localization.text("음소거"); muted.button_pressed = settings.muted; muted.toggled.connect(func(enabled): AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), enabled)); column.add_child(muted)
	main._add_settings_section(column, "화면")
	var fullscreen := CheckButton.new(); fullscreen.name = "FullscreenToggle"; fullscreen.text = Localization.text("전체화면 (F11)").replace(" (F11)", "") if mobile_layout else Localization.text("전체화면 (F11)"); fullscreen.button_pressed = settings.fullscreen; column.add_child(fullscreen)
	var vsync := CheckButton.new(); vsync.text = "VSync"; vsync.button_pressed = settings.vsync; column.add_child(vsync)
	if mobile_layout:
		var section_spacer := Control.new()
		section_spacer.custom_minimum_size.y = 28
		column.add_child(section_spacer)
	var hidden_display: Control
	if mobile_layout:
		hidden_display = Control.new()
		hidden_display.visible = false
		outer.add_child(hidden_display)
	var window_size := OptionButton.new()
	for option in ["1280x720", "1600x900", "1920x1080"]: window_size.add_item(option)
	window_size.select(max(0, ["1280x720", "1600x900", "1920x1080"].find(String(settings.window_size))))
	if mobile_layout:
		hidden_display.add_child(window_size)
	else:
		window_size.name = "ResolutionSelector"
		column.add_child(window_size)
	var fps_limit := OptionButton.new()
	for option in [30, 60, 120, 144, 240]: fps_limit.add_item(Localization.text("FPS 제한 %d") % option, option)
	var fps_options := [30, 60, 120, 144, 240]
	fps_limit.select(max(0, fps_options.find(int(settings.fps_limit))))
	if mobile_layout:
		hidden_display.add_child(fps_limit)
	else:
		fps_limit.name = "FPSSelector"
		column.add_child(fps_limit)
	main._add_binding_settings(column)
	main._add_settings_section(column, "전투 연출")
	var damage_numbers := CheckButton.new(); damage_numbers.text = Localization.text("피해 숫자"); damage_numbers.button_pressed = settings.damage_numbers; column.add_child(damage_numbers)
	var shake := CheckButton.new(); shake.text = Localization.text("화면 흔들림"); shake.button_pressed = settings.screen_shake; column.add_child(shake)
	var effects := CheckButton.new(); effects.text = Localization.text("전투 효과"); effects.button_pressed = settings.battle_effects; column.add_child(effects)
	var intensity_row := HBoxContainer.new()
	var intensity_label := Label.new(); intensity_label.text = Localization.text("효과 강도"); intensity_label.custom_minimum_size.x = 132; intensity_row.add_child(intensity_label)
	var intensity := HSlider.new(); intensity.name = "EffectIntensitySlider"; intensity.min_value = 0.2; intensity.max_value = 1.0; intensity.step = 0.1; intensity.value = settings.effect_intensity; intensity.tooltip_text = Localization.text("효과 강도"); intensity.custom_minimum_size.x = 560; intensity_row.add_child(intensity); column.add_child(intensity_row)
	quality.item_selected.connect(func(index: int):
		var key := String(quality_options[index])
		if key == "custom":
			return
		var profile := SaveData.graphics_profile(key, mobile_layout, DisplayServer.screen_get_size())
		window_size.select(SaveData.WINDOW_SIZES.find(String(profile.window_size)))
		fps_limit.select(SaveData.FPS_LIMITS.find(int(profile.fps_limit)))
		damage_numbers.button_pressed = bool(profile.damage_numbers)
		shake.button_pressed = bool(profile.screen_shake)
		effects.button_pressed = bool(profile.battle_effects)
		intensity.value = float(profile.effect_intensity)
	)
	_add_settings_section(main, column, Localization.text("계산 돕기"))
	var helper_toggle := CheckButton.new()
	helper_toggle.name = "HelperToggle"
	helper_toggle.text = Localization.text("남는 CPU로 서버의 계산 돕기 (전투 중에는 쉽니다)")
	helper_toggle.button_pressed = bool(settings.get("helper_enabled", false))
	column.add_child(helper_toggle)
	var helper_row := HBoxContainer.new()
	column.add_child(helper_row)
	var helper_label := Label.new()
	helper_label.name = "HelperCoresLabel"
	helper_label.custom_minimum_size.x = 220
	helper_row.add_child(helper_label)
	var helper_cores := HSlider.new()
	helper_cores.name = "HelperCores"
	helper_cores.min_value = 1
	helper_cores.max_value = maxi(1, OS.get_processor_count() / 2)
	helper_cores.step = 1
	helper_cores.value = clampi(int(settings.get("helper_cores", 1)), 1, int(helper_cores.max_value))
	helper_cores.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	helper_row.add_child(helper_cores)
	var update_helper_label := func(): helper_label.text = Localization.text("사용할 CPU 코어  %d / %d") % [int(helper_cores.value), int(helper_cores.max_value)]
	helper_cores.value_changed.connect(func(_value): update_helper_label.call())
	update_helper_label.call()
	_add_settings_section(main, column, Localization.text("데이터"))
	var reset_button = main._styled_button(Localization.text("데이터 전체 초기화"), Color("#8f3a4a"), false)
	reset_button.name = "DataResetButton"
	reset_button.tooltip_text = Localization.text("이 기기에 저장된 전적·덱·설정·리플레이를 모두 지웁니다")
	reset_button.pressed.connect(func(): DataReset.show_confirm(main))
	column.add_child(reset_button)
	var save_button = main._styled_button(Localization.text("설정 저장"), Color("#5e6ad2"), true)
	save_button.name = "SettingsSaveButton"
	save_button.pressed.connect(func():
		settings.master_volume = master.value; settings.bgm_volume = bgm.value; settings.sfx_volume = sfx.value
		settings.muted = muted.button_pressed; settings.fullscreen = fullscreen.button_pressed; settings.vsync = vsync.button_pressed
		settings.window_size = window_size.get_item_text(window_size.selected); settings.fps_limit = fps_limit.get_item_id(fps_limit.selected)
		settings.damage_numbers = damage_numbers.button_pressed; settings.screen_shake = shake.button_pressed; settings.battle_effects = effects.button_pressed; settings.effect_intensity = intensity.value
		settings.graphics_quality = String(quality_options[quality.selected])
		if String(settings.graphics_quality) != "custom":
			var profile := SaveData.graphics_profile(String(settings.graphics_quality), mobile_layout, DisplayServer.screen_get_size())
			for key in profile:
				if settings[key] != profile[key]:
					settings.graphics_quality = "custom"
					break
		settings.language = "ko"
		settings.helper_enabled = helper_toggle.button_pressed
		settings.helper_cores = int(helper_cores.value)
		settings.battle_keys = main.binding_draft.duplicate()
		SaveData.save_data(main.save_data); Localization.install(String(settings.language)); main._apply_settings(); main._apply_helper_settings()
		main._build_connect_screen(Localization.text("설정을 저장했습니다."))
	)
	outer.add_child(save_button)
	var back = main._styled_button(Localization.text("취소"), Color("#697386"), false); back.pressed.connect(func(): main._apply_settings(); main._build_connect_screen()); outer.add_child(back)

static func _add_settings_section(main, parent: VBoxContainer, title: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 6
	parent.add_child(spacer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var accent := ColorRect.new()
	accent.color = UIKit.GOLD
	accent.custom_minimum_size = Vector2(4, 22)
	row.add_child(accent)
	var heading := Label.new()
	heading.text = Localization.text(title)
	heading.add_theme_font_size_override("font_size", 19)
	heading.add_theme_color_override("font_color", UIKit.GOLD)
	row.add_child(heading)
	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 6)
	parent.add_child(divider)
static func _add_binding_settings(main, column: VBoxContainer) -> void:
	main._add_settings_section(column,"전투 단축키")
	var grid := GridContainer.new(); grid.name="BattleKeyBindings"; grid.columns=3; grid.add_theme_constant_override("h_separation",12); grid.add_theme_constant_override("v_separation",8); column.add_child(grid)
	for index in 6:
		var button = main._styled_button("",Color("#3d647d")); button.name="BindingSlot%d"%index; button.custom_minimum_size=Vector2(250,44); button.add_theme_font_size_override("font_size",14); button.pressed.connect(main._begin_binding_capture.bind(index)); grid.add_child(button); main.binding_buttons.append(button)
	main.binding_hint = Label.new(); main.binding_hint.name="BindingHint"; main.binding_hint.text="변경할 항목을 누르고 새 키를 입력하세요."; main.binding_hint.add_theme_font_size_override("font_size",13); main.binding_hint.add_theme_color_override("font_color",Color("#f0d592")); column.add_child(main.binding_hint)
	var reset = main._styled_button("단축키 기본값 복원",Color("#596174")); reset.name="ResetBattleBindings"; reset.pressed.connect(func(): main._cancel_binding_capture(); main.binding_draft=BattleBindings.DEFAULTS.duplicate(); main._refresh_binding_buttons()); column.add_child(reset)
	main._refresh_binding_buttons()

static func _refresh_binding_buttons(main) -> void:
	for index in main.binding_buttons.size():
		if is_instance_valid(main.binding_buttons[index]): main.binding_buttons[index].text="%s · %s"%[BattleBindings.LABELS[index],BattleBindings.key_name(int(main.binding_draft[index]))]

static func _begin_binding_capture(main, index: int) -> void:
	main._cancel_binding_capture()
	main.binding_capture_index=index
	main.binding_capture_overlay=ColorRect.new(); main.binding_capture_overlay.name="BindingCaptureOverlay"; main.binding_capture_overlay.color=Color(0.02,0.03,0.05,0.96); main.binding_capture_overlay.size=Vector2(1280,720); main.binding_capture_overlay.z_index=170; main.root_background.add_child(main.binding_capture_overlay)
	var column := MultiplayerUI.panel(main,main.binding_capture_overlay,"BindingCapturePanel",Rect2(300,220,680,280))
	column.add_child(MultiplayerUI.label("%s · 새 키 입력"%BattleBindings.LABELS[index],24,MultiplayerUI.GOLD))
	main.binding_hint=MultiplayerUI.label("새 키를 누르세요. Esc는 변경 취소입니다.",14,MultiplayerUI.MUTED); main.binding_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; column.add_child(main.binding_hint)
	MultiplayerUI.button(main,column,"취소","CancelBindingCapture",main._cancel_binding_capture)

static func _cancel_binding_capture(main) -> void:
	main.binding_capture_index=-1
	if is_instance_valid(main.binding_capture_overlay): main.binding_capture_overlay.queue_free()
	main.binding_capture_overlay=null
	if is_instance_valid(main.root_background): main.binding_hint=main.root_background.find_child("BindingHint",true,false) as Label
