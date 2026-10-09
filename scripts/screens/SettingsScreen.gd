extends RefCounted
## SettingsScreen: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const DataReset = preload("res://scripts/DataReset.gd")

const SETTINGS_PAGES := [
	{"id": "audio", "title": "오디오", "hint": "음량과 음소거"},
	{"id": "display", "title": "화면", "hint": "화질, 창 크기, 프레임"},
	{"id": "battle", "title": "전투 연출", "hint": "피해 숫자와 효과"},
	{"id": "keys", "title": "전투 단축키", "hint": "카드를 사는 키"},
	{"id": "helper", "title": "계산 돕기", "hint": "남는 CPU로 서버 돕기"},
	{"id": "data", "title": "데이터", "hint": "저장된 정보 관리"},
]

static func _build_settings_screen(main, mobile_layout_override: bool = false) -> void:
	var outer = main._submenu(Localization.text("설정"), "분류를 고른 뒤 값을 바꾸고, 아래의 설정 저장을 눌러야 적용됩니다.")
	var mobile_layout := OS.has_feature("mobile") or mobile_layout_override
	var settings: Dictionary = main.save_data.settings
	main.binding_draft = BattleBindings.sanitize(settings.get("battle_keys"))

	# Body: category rail on the left (a wrapping row of chips on phones) and the page of the chosen category beside it.
	var body := BoxContainer.new()
	body.name = "SettingsBody"
	body.vertical = mobile_layout
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)
	var rail: Container
	if mobile_layout:
		rail = HFlowContainer.new()
		(rail as HFlowContainer).add_theme_constant_override("h_separation", 8)
		(rail as HFlowContainer).add_theme_constant_override("v_separation", 8)
	else:
		rail = VBoxContainer.new()
		(rail as VBoxContainer).add_theme_constant_override("separation", 8)
		rail.custom_minimum_size.x = 210
	rail.name = "SettingsRail"
	body.add_child(rail)
	var scroll := ScrollContainer.new()
	scroll.name = "SettingsScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 16
	body.add_child(scroll)
	if mobile_layout:
		main.settings_touch_scroll = scroll
	var column := VBoxContainer.new()
	column.name = "SettingsColumn"
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var pages := {}
	var tabs := {}
	for entry in SETTINGS_PAGES:
		var page := VBoxContainer.new()
		page.name = "SettingsPage_%s" % entry.id
		page.add_theme_constant_override("separation", 10)
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_child(page)
		pages[entry.id] = page
		var tab: Button = main._styled_button(Localization.text(entry.title), Color("#3d4a6b"), false)
		tab.name = "SettingsTab_%s" % entry.id
		tab.tooltip_text = Localization.text(entry.hint)
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT if not mobile_layout else HORIZONTAL_ALIGNMENT_CENTER
		rail.add_child(tab)
		tabs[entry.id] = tab
	var show_page := func(id: String):
		for key in pages:
			pages[key].visible = key == id
			tabs[key].add_theme_color_override("font_color", UIKit.GOLD if key == id else Color("#c9d1e6"))
			tabs[key].self_modulate = Color(1.7, 1.7, 2.4) if key == id else Color(0.85, 0.87, 0.95)
			tabs[key].text = ("▸ " if key == id and not mobile_layout else "") + Localization.text(_page_title(String(key)))
		scroll.scroll_vertical = 0
	for key in tabs:
		tabs[key].pressed.connect(show_page.bind(String(key)))

	var dirty := Label.new()
	dirty.name = "SettingsDirty"
	dirty.add_theme_color_override("font_color", Color("#f0d592"))
	dirty.add_theme_font_size_override("font_size", 14)
	dirty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dirty.text = ""
	var mark_dirty := func(_value = null): dirty.text = Localization.text("● 저장하지 않은 변경이 있습니다")

	# ---- audio
	_add_settings_section(main, pages.audio, "오디오")
	var controls := GridContainer.new()
	controls.columns = 3
	controls.add_theme_constant_override("h_separation", 20)
	controls.add_theme_constant_override("v_separation", 14)
	pages.audio.add_child(controls)
	var master := HSlider.new(); master.name = "MasterVolumeSlider"; master.min_value = 0.0; master.max_value = 1.0; master.step = 0.05; master.value = settings.master_volume
	var bgm := HSlider.new(); bgm.name = "BGMVolumeSlider"; bgm.min_value = 0.0; bgm.max_value = 1.0; bgm.step = 0.05; bgm.value = settings.bgm_volume
	var sfx := HSlider.new(); sfx.name = "SFXVolumeSlider"; sfx.min_value = 0.0; sfx.max_value = 1.0; sfx.step = 0.05; sfx.value = settings.sfx_volume
	master.value_changed.connect(main._preview_bus_volume.bind("Master"))
	bgm.value_changed.connect(main._preview_bus_volume.bind("BGM"))
	sfx.value_changed.connect(main._preview_bus_volume.bind("SFX"))
	for pair in [[Localization.text("전체 음량"), master], [Localization.text("BGM 음량"), bgm], [Localization.text("효과음 음량"), sfx]]:
		var label := Label.new(); label.text = pair[0]; label.custom_minimum_size.x = 150; controls.add_child(label)
		var slider: HSlider = pair[1]
		slider.custom_minimum_size = Vector2(0 if mobile_layout else 360, 28)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		controls.add_child(slider)
		var readout := Label.new()
		readout.custom_minimum_size.x = 56
		readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		readout.add_theme_color_override("font_color", UIKit.GOLD)
		readout.text = "%d%%" % roundi(slider.value * 100.0)
		slider.value_changed.connect(func(value): readout.text = "%d%%" % roundi(value * 100.0))
		slider.value_changed.connect(mark_dirty)
		controls.add_child(readout)
	var muted := CheckButton.new(); muted.text = Localization.text("음소거"); muted.button_pressed = settings.muted
	muted.toggled.connect(func(enabled): AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), enabled))
	muted.toggled.connect(mark_dirty)
	pages.audio.add_child(muted)

	# ---- display
	_add_settings_section(main, pages.display, "화면")
	var quality_row := HBoxContainer.new()
	var quality_label := Label.new()
	quality_label.text = Localization.text("화질")
	quality_label.custom_minimum_size.x = 150
	quality_row.add_child(quality_label)
	var quality := OptionButton.new()
	quality.name = "GraphicsQualitySelector"
	quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	quality.tooltip_text = Localization.text("고르면 창 크기, 프레임, 전투 연출이 한꺼번에 맞춰집니다")
	var quality_options: Array = SaveData.GRAPHICS_QUALITIES.duplicate()
	if String(settings.graphics_quality) == "custom":
		quality_options.append("custom")
	for key in quality_options:
		quality.add_item(Localization.text({"auto": "자동", "high": "높음", "medium": "중간", "low": "낮음", "custom": "사용자 지정"}[key]))
	quality.select(max(0, quality_options.find(String(settings.graphics_quality))))
	quality_row.add_child(quality)
	pages.display.add_child(quality_row)
	var fullscreen := CheckButton.new(); fullscreen.name = "FullscreenToggle"; fullscreen.text = Localization.text("전체화면 (F11)").replace(" (F11)", "") if mobile_layout else Localization.text("전체화면 (F11)"); fullscreen.button_pressed = settings.fullscreen; pages.display.add_child(fullscreen)
	var vsync := CheckButton.new(); vsync.text = "VSync"; vsync.button_pressed = settings.vsync; pages.display.add_child(vsync)
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
		pages.display.add_child(window_size)
	var fps_limit := OptionButton.new()
	for option in [30, 60, 120, 144, 240]: fps_limit.add_item(Localization.text("FPS 제한 %d") % option, option)
	var fps_options := [30, 60, 120, 144, 240]
	fps_limit.select(max(0, fps_options.find(int(settings.fps_limit))))
	if mobile_layout:
		hidden_display.add_child(fps_limit)
	else:
		fps_limit.name = "FPSSelector"
		pages.display.add_child(fps_limit)

	# ---- battle effects
	_add_settings_section(main, pages.battle, "전투 연출")
	var damage_numbers := CheckButton.new(); damage_numbers.text = Localization.text("피해 숫자"); damage_numbers.button_pressed = settings.damage_numbers; pages.battle.add_child(damage_numbers)
	var shake := CheckButton.new(); shake.text = Localization.text("화면 흔들림"); shake.button_pressed = settings.screen_shake; pages.battle.add_child(shake)
	var effects := CheckButton.new(); effects.text = Localization.text("전투 효과"); effects.button_pressed = settings.battle_effects; pages.battle.add_child(effects)
	var intensity_row := HBoxContainer.new()
	var intensity_label := Label.new(); intensity_label.text = Localization.text("효과 강도"); intensity_label.custom_minimum_size.x = 150; intensity_row.add_child(intensity_label)
	var intensity := HSlider.new(); intensity.name = "EffectIntensitySlider"; intensity.min_value = 0.2; intensity.max_value = 1.0; intensity.step = 0.1; intensity.value = settings.effect_intensity; intensity.tooltip_text = Localization.text("효과 강도")
	intensity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	intensity.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	intensity.custom_minimum_size = Vector2(0 if mobile_layout else 360, 28)
	intensity_row.add_child(intensity); pages.battle.add_child(intensity_row)
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

	# ---- key bindings (builds its own heading and grid)
	main._add_binding_settings(pages.keys)

	# ---- helper
	_add_settings_section(main, pages.helper, "계산 돕기")
	var helper_note := Label.new()
	helper_note.text = Localization.text("서버가 큰 계산을 맡길 때, 이 컴퓨터의 남는 CPU를 빌려줍니다. 메뉴 화면에서만 일하고 전투 중에는 쉬며, 포트를 열 필요는 없습니다.")
	helper_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	helper_note.add_theme_font_size_override("font_size", 14)
	helper_note.add_theme_color_override("font_color", Color("#9aa5c0"))
	pages.helper.add_child(helper_note)
	var helper_toggle := CheckButton.new()
	helper_toggle.name = "HelperToggle"
	helper_toggle.text = Localization.text("남는 CPU로 서버의 계산 돕기")
	helper_toggle.button_pressed = bool(settings.get("helper_enabled", false))
	pages.helper.add_child(helper_toggle)
	var helper_row := HBoxContainer.new()
	pages.helper.add_child(helper_row)
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
	helper_cores.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	helper_row.add_child(helper_cores)
	var update_helper_label := func(): helper_label.text = Localization.text("사용할 CPU 코어  %d / %d") % [int(helper_cores.value), int(helper_cores.max_value)]
	helper_cores.value_changed.connect(func(_value): update_helper_label.call())
	update_helper_label.call()

	# ---- data
	_add_settings_section(main, pages.data, "데이터")
	var data_note := Label.new()
	data_note.text = Localization.text("전적, 덱, 설정, 리플레이는 이 기기에만 저장됩니다.")
	data_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data_note.add_theme_font_size_override("font_size", 14)
	data_note.add_theme_color_override("font_color", Color("#9aa5c0"))
	pages.data.add_child(data_note)
	var reset_button = main._styled_button(Localization.text("데이터 전체 초기화"), Color("#8f3a4a"), false)
	reset_button.name = "DataResetButton"
	reset_button.tooltip_text = Localization.text("이 기기에 저장된 전적·덱·설정·리플레이를 모두 지웁니다")
	reset_button.pressed.connect(func(): DataReset.show_confirm(main))
	pages.data.add_child(reset_button)

	for control in [fullscreen, vsync, damage_numbers, shake, effects, helper_toggle]:
		control.toggled.connect(mark_dirty)
	for control in [quality, window_size, fps_limit]:
		control.item_selected.connect(mark_dirty)
	for control in [intensity, helper_cores]:
		control.value_changed.connect(mark_dirty)

	# ---- footer: unsaved-changes note, cancel, save
	var footer := HBoxContainer.new()
	footer.name = "SettingsFooter"
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	footer.add_child(dirty)
	var back = main._styled_button(Localization.text("취소"), Color("#697386"), false)
	back.custom_minimum_size.x = 150
	back.pressed.connect(func(): main._apply_settings(); main._build_connect_screen())
	footer.add_child(back)
	var save_button = main._styled_button(Localization.text("설정 저장"), Color("#5e6ad2"), true)
	save_button.name = "SettingsSaveButton"
	save_button.custom_minimum_size.x = 220
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
	footer.add_child(save_button)
	show_page.call("audio")

static func _page_title(id: String) -> String:
	for entry in SETTINGS_PAGES:
		if String(entry.id) == id:
			return String(entry.title)
	return id

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
		var button = main._styled_button("",Color("#3d647d")); button.name="BindingSlot%d"%index; button.custom_minimum_size=Vector2(0,44); button.size_flags_horizontal=Control.SIZE_EXPAND_FILL; button.add_theme_font_size_override("font_size",14); button.pressed.connect(main._begin_binding_capture.bind(index)); grid.add_child(button); main.binding_buttons.append(button)
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
