extends RefCounted
## 무한 방어 (endless defense): the menu brief, the battle loop with its wave breaks and boon picks, the HUD
## additions and the result. The run state lives in main.endless_run ({} outside the mode):
##   {"director": WaveDirector, "speed", "seconds_before" (time survived before a resumed wave), "seed",
##    "shown_wave", "outcome": {} until the run ends}

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")
const WaveDirector = preload("res://scripts/run/WaveDirector.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")
const RunRecords = preload("res://scripts/run/RunRecords.gd")

const SPEEDS := [1.0, 2.0]
## Simulation steps per frame at most, so a slow frame never snowballs.
const MAX_STEPS := 16

static func active(main) -> bool:
	return main.local_ai_mode and not main.endless_run.is_empty()

static func show_brief(main) -> void:
	var record := RunRecords.endless(main.save_data)
	var saved: Dictionary = record.saved
	var column = main._action_panel(Localization.text("무한 방어"), Rect2(300, 100, 680, 520))
	main.action_overlay.name = "EndlessBriefOverlay"
	var intro := MultiplayerUI.label(Localization.text("끝없이 몰려오는 적을 막아 내세요. 웨이브를 막을 때마다 자원을 받고 강화 3개 중 하나를 고릅니다. 강화는 겹쳐 쌓입니다. 5웨이브마다 보스가 나오고, 그때마다 적이 더 강해집니다."), 15, MultiplayerUI.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	var best := Localization.text("최고 기록 · 웨이브 %d 돌파 · 도전 %d회") % [int(record.best_wave), int(record.runs)] if int(record.runs) > 0 else Localization.text("아직 기록이 없습니다.")
	var best_label := MultiplayerUI.label(best, 16, MultiplayerUI.GOLD)
	best_label.name = "EndlessBestRecord"
	column.add_child(best_label)
	column.add_child(MultiplayerUI.label(Localization.text("사용할 덱 · %s") % String(main._active_preset().name), 15))
	if not saved.is_empty():
		var resume = MultiplayerUI.button(main, column, Localization.text("이어하기 · 웨이브 %d부터 (기지 %d · 강화 %d개)") % [int(saved.wave), int(saved.base_hp), saved.boons.size()], "EndlessResume", func(): start(main, saved), true)
		resume.custom_minimum_size.y = 56
	var fresh = MultiplayerUI.button(main, column, Localization.text("새로 시작") if not saved.is_empty() else Localization.text("시작"), "EndlessStart", func(): start(main), saved.is_empty())
	fresh.custom_minimum_size.y = 56
	if not saved.is_empty():
		column.add_child(MultiplayerUI.label(Localization.text("새로 시작하면 저장된 도전은 사라집니다."), 13, MultiplayerUI.MUTED))
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseEndlessBrief", main._dismiss_action_overlay)

## Starts a run with the active deck, or resumes `saved` (RunRecords) at its wave.
static func start(main, saved: Dictionary = {}) -> void:
	main._dismiss_action_overlay()
	var units: Array = saved.units if not saved.is_empty() else main._active_preset().units
	var structures: Array = saved.structures if not saved.is_empty() else main._active_preset().structures
	main.ghost_context = {}
	main.daily_challenge = {}
	main.draft_context = {}
	main.campaign_mode = false
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	# Not a practice battle: never counted in the AI record, shared or recorded as a replay.
	main.practice_used_tools = true
	main._reset_battle_result()
	main.current_ai_stage = 1
	main.own_side = 0
	var model := BattleModel.new()
	model.configure_deck(0, units, structures)
	var run_seed := int(saved.seed) if not saved.is_empty() else randi_range(1, 2147483646)
	if saved.is_empty():
		RunRecords.endless(main.save_data).saved = {}
	var director := WaveDirector.new(run_seed + int(saved.get("wave", 1)) * 7919, int(saved.get("wave", 1)), saved.get("boons", []))
	director.setup(model)
	if not saved.is_empty():
		model.base_hp[0] = minf(float(model.base_max_hp[0]), float(saved.base_hp))
	main.endless_run = {"director": director, "speed": 1.0, "seconds_before": float(saved.get("seconds", 0.0)), "seed": run_seed, "shown_wave": 0, "outcome": {}}
	main.local_model = model
	main.local_ai = director
	main.battle_preset = {"name": Localization.text("무한 방어"), "units": units.duplicate(), "structures": structures.duplicate()}
	main._build_battle_screen()
	main.local_step_accumulator = 0.0
	main.local_recorder = null
	main._on_snapshot(model.snapshot())

## The battle loop's step for this mode (instead of the fixed-rate step of recorded battles).
static func step(main, delta: float) -> void:
	var run: Dictionary = main.endless_run
	var director = run.director
	var model: BattleModel = main.local_model
	if director.awaiting_choice:
		offer(main)
		return
	main.local_step_accumulator = minf(main.local_step_accumulator + minf(delta, 0.25) * float(run.speed), MAX_STEPS / 30.0)
	var tick := 1.0 / 30.0
	while main.local_step_accumulator >= tick and model.winner == -1 and not director.awaiting_choice:
		director.update(model, tick)
		model.tick(tick)
		main.local_step_accumulator -= tick
	if director.awaiting_choice:
		main.local_step_accumulator = 0.0

## Labels after each snapshot: the wave in the clock card and the enemy side's health card.
static func refresh(main) -> void:
	var run: Dictionary = main.endless_run
	var director = run.director
	var enemies: int = director._enemies(main.local_model) + director.queue.size()
	var mode_label := main.root_background.find_child("BattleModeLabel", true, false) as Label if is_instance_valid(main.root_background) else null
	if mode_label != null:
		mode_label.text = Localization.text("무한 방어 · 웨이브 %d%s") % [director.wave, " · 보스" if WaveDirector.is_boss_wave(director.wave) else ""]
	if is_instance_valid(main.red_hp_label):
		main.red_hp_label.text = Localization.text("남은 적 %d") % enemies if director.wave > 0 else Localization.text("곧 시작")
	if is_instance_valid(main.red_hp_bar):
		main.red_hp_bar.max_value = 1.0
		main.red_hp_bar.value = 1.0 if enemies > 0 else 0.0
	if int(run.shown_wave) != director.wave and director.wave > 0:
		run.shown_wave = director.wave
		var banner = run.get("banner")
		if is_instance_valid(banner):
			banner.text = Localization.text("보스 웨이브 %d!") % director.wave if WaveDirector.is_boss_wave(director.wave) else Localization.text("웨이브 %d") % director.wave
			main.get_tree().create_timer(2.5).timeout.connect(func():
				if is_instance_valid(banner) and banner.text.contains(str(director.wave)):
					banner.text = "")

## Pause, speed and owned boons, in place of the practice tools.
static func add_controls(main) -> void:
	var row := HBoxContainer.new()
	row.name = "EndlessControls"
	row.position = Vector2(164, 98)
	row.size = Vector2(342, 44)
	row.z_index = 10
	row.add_theme_constant_override("separation", 6)
	main.root_background.add_child(row)
	main.practice_pause_button = main._styled_button(Localization.text("일시정지"), Color("#3d647d"))
	main.practice_pause_button.name = "EndlessPauseButton"
	main.practice_pause_button.custom_minimum_size = Vector2(90, 44)
	main.practice_pause_button.add_theme_font_size_override("font_size", 12)
	main.practice_pause_button.pressed.connect(main._toggle_practice_pause)
	row.add_child(main.practice_pause_button)
	var speed = main._styled_button("1배속", Color("#3d647d"))
	speed.name = "EndlessSpeedButton"
	speed.custom_minimum_size = Vector2(76, 44)
	speed.add_theme_font_size_override("font_size", 12)
	speed.tooltip_text = Localization.text("전투 속도를 1배·2배로 바꿉니다.")
	speed.pressed.connect(func():
		var run: Dictionary = main.endless_run
		run.speed = SPEEDS[(SPEEDS.find(float(run.speed)) + 1) % SPEEDS.size()]
		speed.text = "%d배속" % int(run.speed))
	row.add_child(speed)
	var boons = main._styled_button(Localization.text("내 강화"), Color("#596174"))
	boons.name = "EndlessBoonsButton"
	boons.custom_minimum_size = Vector2(90, 44)
	boons.add_theme_font_size_override("font_size", 12)
	boons.pressed.connect(func(): show_boons(main))
	row.add_child(boons)
	var banner := ToastLabel.new()
	banner.name = "EndlessWaveBanner"
	banner.tone = UIKit.GOLD
	banner.add_theme_font_size_override("font_size", 22)
	main.root_background.add_child(banner)
	banner.place_center(640.0, 200.0)
	main.endless_run["banner"] = banner

static func show_boons(main) -> void:
	var director = main.endless_run.director
	var column = main._action_panel(Localization.text("내 강화"), Rect2(300, 110, 680, 500))
	var counts := {}
	for id in director.boons:
		counts[id] = int(counts.get(id, 0)) + 1
	if counts.is_empty():
		column.add_child(MultiplayerUI.label(Localization.text("아직 고른 강화가 없습니다. 웨이브를 막으면 고를 수 있습니다."), 15, MultiplayerUI.MUTED))
	for id in counts:
		var relic: Dictionary = RunBoons.RELICS[id]
		column.add_child(MultiplayerUI.label("%s %s%s · %s" % [relic.icon, Localization.text(String(relic.name)), " ×%d" % counts[id] if int(counts[id]) > 1 else "", RunBoons.describe(String(id))], 15))
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseEndlessBoons", main._dismiss_action_overlay)

## The wave-break pick: three boons, one of which the player takes. The battle stays paused meanwhile.
static func offer(main) -> void:
	if is_instance_valid(main.action_overlay):
		return
	var director = main.endless_run.director
	main.unit_purchase_hold.cancel()
	var boss: bool = WaveDirector.is_boss_wave(director.wave)
	var column = main._action_panel(Localization.text("웨이브 %d 방어 성공!") % director.wave, Rect2(200, 130, 880, 430))
	main.action_overlay.name = "EndlessBoonOverlay"
	column.add_child(MultiplayerUI.label(Localization.text("자원 +%d · 강화 하나를 고르세요. 이번 도전이 끝날 때까지 유지되고 겹쳐 쌓입니다.") % int(WaveDirector.BOSS_BONUS if boss else WaveDirector.CLEAR_BONUS), 15, MultiplayerUI.MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	var first: Button = null
	for id in director.offers:
		var relic: Dictionary = RunBoons.RELICS[id]
		var owned: int = director.boons.count(id)
		var card = main._styled_button("%s\n%s\n\n%s%s" % [relic.icon, Localization.text(String(relic.name)), RunBoons.describe(String(id)), Localization.text("\n(보유 %d)") % owned if owned > 0 else ""], UIKit.GOLD_DEEP if String(relic.rarity) == "boss" else (Color("#8b6cf6") if String(relic.rarity) == "rare" else Color("#3d647d")), false)
		card.name = "EndlessBoon_" + String(id)
		card.custom_minimum_size = Vector2(260, 220)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", 17)
		var pick := String(id)
		card.pressed.connect(func(): choose(main, pick))
		row.add_child(card)
		if first == null:
			first = card
	if first != null:
		first.grab_focus()

static func choose(main, id: String) -> void:
	var run: Dictionary = main.endless_run
	if run.is_empty() or not is_instance_valid(main.local_model):
		return
	var director = run.director
	var model: BattleModel = main.local_model
	director.choose(model, id)
	main._dismiss_action_overlay()
	main.local_battle_skip_delta = true
	# A break is a safe point: leaving the app now resumes from the next wave.
	RunRecords.endless(main.save_data).saved = {"wave": director.wave + 1, "boons": director.boons.duplicate(), "base_hp": float(model.base_hp[0]),
		"units": model.unit_decks[0].duplicate(), "structures": model.structure_decks[0].duplicate(), "seed": int(run.seed),
		"seconds": float(run.seconds_before) + model.elapsed}
	main._save_profile()
	main._refresh_purchase_buttons(main.latest_resources)

## Records the finished run once; the result screen shows the returned outcome.
static func record(main) -> Dictionary:
	var run: Dictionary = main.endless_run
	if not run.outcome.is_empty():
		return run.outcome
	var director = run.director
	var seconds := float(run.seconds_before) + float(main.local_model.elapsed if is_instance_valid(main.local_model) else 0.0)
	var cleared: int = director.waves_cleared()
	var best := RunRecords.record_endless(main.save_data, cleared, seconds)
	run.outcome = {"waves": cleared, "seconds": seconds, "best": best, "best_wave": int(RunRecords.endless(main.save_data).best_wave)}
	return run.outcome

static func result_title(outcome: Dictionary) -> String:
	return Localization.text("웨이브 %d 돌파") % int(outcome.waves)

static func result_note(outcome: Dictionary) -> String:
	var time := "%d분 %d초" % [int(outcome.seconds) / 60, int(outcome.seconds) % 60]
	if bool(outcome.best):
		return Localization.text("신기록! · %s 버텼습니다.") % time
	return Localization.text("%s 버텼습니다 · 최고 기록 웨이브 %d") % [time, int(outcome.best_wave)]
