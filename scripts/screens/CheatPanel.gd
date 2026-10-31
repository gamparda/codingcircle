extends RefCounted
## The cheat panel for super and hyper accounts (pause menu in solo battles, ☰ menu online). Solo cheats run on
## the device and mark the battle (main.cheats_used): it then counts for no record, star, statistic,
## achievement or title, and an endless run keeps that mark across resumes. Online the server applies them.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")

const Cheats = preload("res://scripts/Cheats.gd")

static func usable(main) -> bool:
	return main.battle_active and main.account.can_cheat() and not main.network.client_is_spectator and (not main.local_ai_mode or is_instance_valid(main.local_model))

## Which toggles are on: the model's own state in solo battles, what this client asked for online.
static func _toggled(main, id: String) -> bool:
	return main.local_model.cheats[main.own_side].has(id) if main.local_ai_mode else main.cheat_flags.has(id)

## Runs a shared cheat: on the device in solo battles, on the server (which checks the role) online.
static func _act(main, action: String) -> void:
	if main.local_ai_mode:
		_mark(main)
		Cheats.perform(main.local_model, main.own_side, action)
		return
	if main.network.send_cheat(action):
		main.cheats_used = true
		if Cheats.TOGGLES.has(action):
			if main.cheat_flags.has(action): main.cheat_flags.erase(action)
			else: main.cheat_flags[action] = true
		if action == "lose": main.cheat_flags.erase("castle")

static func show(main) -> void:
	if not usable(main):
		return
	var endless: bool = main.local_ai_mode and not main.endless_run.is_empty()
	var expedition: bool = main.local_ai_mode and not main.expedition_run.is_empty()
	var column = main._action_panel(Localization.text("치트"), Rect2(190, 40, 900, 640))
	main.action_overlay.name = "CheatOverlay"
	column.add_child(MultiplayerUI.label(Localization.text("치트를 쓴 판은 기록·별·전적·업적·칭호에 들어가지 않습니다." if main.local_ai_mode else "온라인 대전에서 치트를 쓰면 상대에게 알림이 가고, 랭크 대전은 양쪽 모두 점수에 반영되지 않습니다."), 14, MultiplayerUI.MUTED))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var grid := _section(list, "켜고 끄기")
	for id in Cheats.TOGGLES:
		var toggle := String(id)
		var on := _toggled(main, toggle)
		var button = _add(main, grid, "%s · %s" % [Localization.text(String(Cheats.TOGGLES[id])), Localization.text("켜짐") if on else Localization.text("꺼짐")], "Cheat_" + toggle, func():
			_act(main, toggle)
			show(main))
		if on: UIKit.style_button(button, UIKit.GOLD_DEEP, false, 15)
	grid = _section(list, "한 번 쓰기")
	for id in Cheats.ONE_SHOTS:
		var action := String(id)
		if endless and action in ["win", "siege"]:
			continue # the waves have no castle
		var button = _add(main, grid, Localization.text(String(Cheats.ONE_SHOTS[id])), "Cheat_" + action, func():
			_act(main, action)
			main._dismiss_action_overlay())
		if action == "win": UIKit.style_button(button, UIKit.GOLD_DEEP, false, 15)
		if action == "lose": UIKit.style_button(button, UIKit.DANGER, false, 15)
	if endless:
		grid = _section(list, "무한 방어")
		_add(main, grid, Localization.text("이번 웨이브 건너뛰기"), "CheatSkipWave", func():
			_mark(main)
			skip_wave(main)
			main._dismiss_action_overlay())
		_add(main, grid, Localization.text("웨이브 +5"), "CheatWaveJump", func():
			_mark(main)
			main.endless_run.director.wave += 5
			skip_wave(main)
			main._dismiss_action_overlay())
		_add(main, grid, Localization.text("강화 골라 받기"), "CheatBoons", func(): _boon_picker(main))
		_add(main, grid, Localization.text("강화 모두 받기(각 1개)"), "CheatAllBoons", func():
			_mark(main)
			var director = main.endless_run.director
			for id in RunBoons.RELICS:
				if not director.boons.has(id): director.boons.append(String(id))
			main.local_model.modifiers[1 - director.WAVE_SIDE] = RunBoons.combine(director.boons)
			main._dismiss_action_overlay())
	if expedition:
		grid = _section(list, "원정")
		_add(main, grid, Localization.text("골드 +500"), "CheatGold", func():
			_mark(main)
			main.expedition_run.gold = int(main.expedition_run.gold) + 500
			main._dismiss_action_overlay())
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseCheats", main._dismiss_action_overlay)

static func _section(list: VBoxContainer, title: String) -> GridContainer:
	list.add_child(MultiplayerUI.label(Localization.text(title), 16, UIKit.ACCENT))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	list.add_child(grid)
	return grid

static func _add(main, grid: GridContainer, text: String, node_name: String, callback: Callable) -> Button:
	var button = main._styled_button(text, Color("#7a6248"), false)
	button.name = node_name
	button.custom_minimum_size = Vector2(400, 46)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(callback)
	grid.add_child(button)
	return button

static func _mark(main) -> void:
	main.cheats_used = true
	main.practice_used_tools = true
	main.local_recorder = null

## Ends the wave in progress at once: its units vanish and the wave counts as beaten.
static func skip_wave(main) -> void:
	var director = main.endless_run.director
	var model: BattleModel = main.local_model
	model.units = model.units.filter(func(unit): return int(unit.side) != director.WAVE_SIDE)
	director.queue.clear()

static func _boon_picker(main) -> void:
	var column = main._action_panel(Localization.text("강화 골라 받기"), Rect2(240, 60, 800, 600))
	main.action_overlay.name = "CheatBoonOverlay"
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for id in RunBoons.RELICS:
		var relic: Dictionary = RunBoons.RELICS[id]
		var pick := String(id)
		var button = main._styled_button("%s %s" % [relic.icon, Localization.text(String(relic.name))], Color("#7a6248"), false)
		button.name = "CheatBoon_" + pick
		button.custom_minimum_size = Vector2(360, 48)
		button.pressed.connect(func():
			_mark(main)
			var director = main.endless_run.director
			director.boons.append(pick)
			main.local_model.modifiers[1 - director.WAVE_SIDE] = RunBoons.combine(director.boons)
			main._dismiss_action_overlay())
		grid.add_child(button)
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseCheatBoons", main._dismiss_action_overlay)

## Marks every campaign stage of this device's profile cleared with three stars.
static func clear_campaign(main) -> void:
	for stage in range(1, 9):
		SaveData.record_campaign(main.save_data, stage, true, 1.0, BattleModel.BASE_MAX_HP)
	main._save_profile()
