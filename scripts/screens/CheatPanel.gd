extends RefCounted
## The cheat panel for super and hyper accounts (pause menu in solo battles, ☰ menu online). Solo cheats run on
## the device and mark the battle (main.cheats_used): it then counts for no record, star, statistic,
## achievement or title, and an endless run keeps that mark across resumes. Online the server applies them.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")

const Cheats = preload("res://scripts/Cheats.gd")

## Toggle id -> label.
const TOGGLES := {"resources": "자원 무한", "cooldowns": "생산·주문 대기 없음", "castle": "내 성 무적"}

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
		if action in Cheats.TOGGLES:
			if main.cheat_flags.has(action): main.cheat_flags.erase(action)
			else: main.cheat_flags[action] = true
		if action == "lose": main.cheat_flags.erase("castle")

static func show(main) -> void:
	if not usable(main):
		return
	var endless: bool = main.local_ai_mode and not main.endless_run.is_empty()
	var column = main._action_panel(Localization.text("치트"), Rect2(340, 70, 600, 580))
	main.action_overlay.name = "CheatOverlay"
	column.add_child(MultiplayerUI.label(Localization.text("치트를 쓴 판은 기록·별·전적·업적·칭호에 들어가지 않습니다." if main.local_ai_mode else "온라인 대전에서 치트를 쓰면 상대에게 알림이 가고, 랭크 대전은 양쪽 모두 점수에 반영되지 않습니다."), 14, MultiplayerUI.MUTED))
	for id in TOGGLES:
		var toggle := String(id)
		MultiplayerUI.button(main, column, "%s · %s" % [Localization.text(String(TOGGLES[id])), Localization.text("켜짐") if _toggled(main, toggle) else Localization.text("꺼짐")], "Cheat_" + toggle, func():
			_act(main, toggle)
			show(main))
	MultiplayerUI.button(main, column, Localization.text("자원 가득 채우기"), "CheatFillResources", func():
		_act(main, "fill")
		main._dismiss_action_overlay())
	if endless:
		MultiplayerUI.button(main, column, Localization.text("이번 웨이브 건너뛰기"), "CheatSkipWave", func():
			_mark(main)
			skip_wave(main)
			main._dismiss_action_overlay())
		MultiplayerUI.button(main, column, Localization.text("웨이브 +5"), "CheatWaveJump", func():
			_mark(main)
			main.endless_run.director.wave += 5
			skip_wave(main)
			main._dismiss_action_overlay())
		MultiplayerUI.button(main, column, Localization.text("강화 골라 받기"), "CheatBoons", func(): _boon_picker(main))
	else:
		var win = MultiplayerUI.button(main, column, Localization.text("즉시 승리"), "CheatWin", func():
			_act(main, "win")
			main._dismiss_action_overlay())
		UIKit.style_button(win, UIKit.GOLD_DEEP, false, 16)
	var lose = MultiplayerUI.button(main, column, Localization.text("즉시 패배"), "CheatLose", func():
		_act(main, "lose")
		main._dismiss_action_overlay())
	UIKit.style_button(lose, UIKit.DANGER, false, 16)
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseCheats", main._dismiss_action_overlay)

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
