extends RefCounted
## 원정 (expedition) screens: the menu brief, the starting relic, the act map, rest, shop, deck, rewards and the
## run's end, plus its battles. The run lives in main.expedition_run ({} outside the mode, ExpeditionRun data
## otherwise) and is saved to the profile after every step, so leaving the app never loses more than a battle.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const ExpeditionRun = preload("res://scripts/run/ExpeditionRun.gd")
const RunBoons = preload("res://scripts/run/RunBoons.gd")
const RunRecords = preload("res://scripts/run/RunRecords.gd")

const SPEEDS := [1.0, 2.0]
const MAX_STEPS := 16
const NODE_TEXT := {"battle": "⚔ 전투", "elite": "💀 정예", "rest": "🔥 휴식", "shop": "💰 상점", "boss": "👑 보스"}
const NODE_COLOR := {"battle": Color("#3d647d"), "elite": Color("#8f4652"), "rest": Color("#3d8f83"), "shop": Color("#a07a2c"), "boss": Color("#8b3fa6")}

static func active(main) -> bool:
	return not main.expedition_run.is_empty()

static func in_battle(main) -> bool:
	return main.local_ai_mode and active(main) and String(main.expedition_run.status) == "battle"

static func card_name(kind: String) -> String:
	return String(BattleModel.UNIT_NAMES.get(kind, BattleModel.STRUCTURE_NAMES.get(kind, kind)))

static func card_label(run: Dictionary, kind: String) -> String:
	var stars := int(run.stars.get(kind, 0))
	return card_name(kind) + (" " + "★".repeat(stars) if stars > 0 else "")

static func _save(main) -> void:
	var run: Dictionary = main.expedition_run
	if String(run.status) in ["won", "lost"]:
		return
	RunRecords.expedition(main.save_data).saved = ExpeditionRun.to_saved(run)
	main._save_profile()

static func _label(text: String, size: int = 15, color: Color = UIKit.TEXT) -> Label:
	var label := MultiplayerUI.label(text, size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

# --- menu --------------------------------------------------------------------

static func show_brief(main) -> void:
	var record := RunRecords.expedition(main.save_data)
	var saved := ExpeditionRun.from_saved(record.saved)
	var column = main._action_panel(Localization.text("원정"), Rect2(300, 90, 680, 540))
	main.action_overlay.name = "ExpeditionBriefOverlay"
	column.add_child(_label(Localization.text("세 막으로 이어진 원정을 떠납니다. 갈림길마다 전투·정예·휴식·상점 중 하나를 골라 나아가고, 막의 끝에서 보스와 싸웁니다. 기지 체력은 전투가 끝나도 회복되지 않으니 아껴 쓰세요. 이기면 골드와 새 카드를 얻고, 유물과 카드 강화(★)로 덱을 키웁니다. 기지가 무너지면 원정이 끝납니다."), 15, MultiplayerUI.MUTED))
	var best := int(record.best)
	var reached := Localization.text("완주") if best >= ExpeditionRun.ACTS * ExpeditionRun.LAYERS else Localization.text("%d막 %d/%d 돌파") % [best / ExpeditionRun.LAYERS + 1, best % ExpeditionRun.LAYERS, ExpeditionRun.LAYERS]
	var best_text := Localization.text("아직 기록이 없습니다.") if int(record.runs) == 0 else Localization.text("최고 기록 · %s · 완주 %d회 · 도전 %d회") % [reached, int(record.clears), int(record.runs)]
	var best_label := _label(best_text, 16, MultiplayerUI.GOLD)
	best_label.name = "ExpeditionBestRecord"
	column.add_child(best_label)
	column.add_child(_label(Localization.text("시작 덱 · %s") % String(main._active_preset().name), 15))
	if not saved.is_empty():
		var resume = MultiplayerUI.button(main, column, Localization.text("이어하기 · %d막 %d/%d (기지 %d · 골드 %d)") % [int(saved.act), int(saved.layer) + 1, ExpeditionRun.LAYERS, int(saved.base_hp), int(saved.gold)], "ExpeditionResume", func():
			main._dismiss_action_overlay()
			main.expedition_run = saved
			show_map(main), true)
		resume.custom_minimum_size.y = 56
	var fresh = MultiplayerUI.button(main, column, Localization.text("새 원정") if not saved.is_empty() else Localization.text("원정 시작"), "ExpeditionStart", func(): choose_relic(main), saved.is_empty())
	fresh.custom_minimum_size.y = 56
	if not saved.is_empty():
		column.add_child(_label(Localization.text("새 원정을 시작하면 진행 중인 원정은 사라집니다."), 13, MultiplayerUI.MUTED))
	MultiplayerUI.button(main, column, Localization.text("닫기"), "CloseExpeditionBrief", main._dismiss_action_overlay)

## A new run: the active deck plus one of three starting relics.
static func choose_relic(main) -> void:
	main._dismiss_action_overlay()
	var preset: Dictionary = main._active_preset()
	var run_seed := randi_range(1, 2147483646)
	var column = main._submenu(Localization.text("원정 준비"), Localization.text("가져갈 유물 하나를 고르세요. 유물은 원정 내내 효과가 유지됩니다."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	column.add_child(row)
	for id in ExpeditionRun.starting_relics(run_seed, preset.units, preset.structures):
		var relic: Dictionary = RunBoons.RELICS[id]
		var pick := String(id)
		var card = main._styled_button("%s\n%s\n\n%s" % [relic.icon, Localization.text(String(relic.name)), RunBoons.describe(pick)], Color("#3d647d"), false)
		card.name = "ExpeditionRelic_" + pick
		card.custom_minimum_size = Vector2(240, 200)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_theme_font_size_override("font_size", 17)
		card.pressed.connect(func():
			main.expedition_run = ExpeditionRun.create(run_seed, preset.units, preset.structures, pick)
			_save(main)
			show_map(main))
		row.add_child(card)
	var back = main._styled_button(Localization.text("돌아가기"), Color("#697386"), false)
	back.name = "ExpeditionPrepBack"
	back.pressed.connect(main._build_connect_screen)
	column.add_child(back)

# --- map ---------------------------------------------------------------------

static func _status_line(run: Dictionary) -> String:
	var relics := PackedStringArray()
	for id in run.relics:
		relics.append(String(RunBoons.RELICS[id].icon))
	return Localization.text("기지 %d/%d · 골드 %d · 유물 %s") % [int(run.base_hp), int(ExpeditionRun.BASE_MAX), int(run.gold), " ".join(relics) if not relics.is_empty() else "-"]

static func _header(main, column: VBoxContainer) -> void:
	var run: Dictionary = main.expedition_run
	var status := _label(_status_line(run), 16, MultiplayerUI.GOLD)
	status.name = "ExpeditionStatus"
	column.add_child(status)
	var deck := PackedStringArray()
	for kind in run.deck.units + run.deck.structures:
		deck.append(card_label(run, String(kind)))
	column.add_child(_label(Localization.text("덱 · ") + " · ".join(deck), 14, MultiplayerUI.MUTED))

static func show_map(main) -> void:
	var run: Dictionary = main.expedition_run
	match String(run.status):
		"battle":
			start_battle(main)
			return
		"reward":
			show_reward(main)
			return
		"rest":
			show_rest(main)
			return
		"shop":
			show_shop(main)
			return
		"won", "lost":
			show_end(main)
			return
	main.battle_active = false
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	var column = main._submenu(Localization.text("원정 · %d막") % int(run.act), Localization.text("갈 곳을 고르세요 · %d/%d") % [int(run.layer) + 1, ExpeditionRun.LAYERS])
	_header(main, column)
	var map := VBoxContainer.new()
	map.name = "ExpeditionMap"
	map.add_theme_constant_override("separation", 6)
	column.add_child(map)
	for layer in run.map.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		map.add_child(row)
		var step := MultiplayerUI.label("%d" % (layer + 1), 14, UIKit.GOLD if layer == int(run.layer) else UIKit.TEXT_DIM)
		step.custom_minimum_size.x = 28
		row.add_child(step)
		var nodes: Array = run.map[layer]
		for index in nodes.size():
			var node: Dictionary = nodes[index]
			var kind := String(node.type)
			var text := Localization.text(String(NODE_TEXT[kind]))
			if node.has("enemy") and layer == int(run.layer):
				text += " · " + Localization.text(String(node.enemy.name))
			var button = main._styled_button(text, NODE_COLOR[kind], false)
			button.name = "ExpeditionNode_%d_%d" % [layer, index]
			button.custom_minimum_size = Vector2(0, 40 if layer == int(run.layer) else 30)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 14 if layer == int(run.layer) else 12)
			button.disabled = layer != int(run.layer)
			if layer < int(run.layer):
				button.modulate = Color(1, 1, 1, 0.35)
			var choice := index
			button.pressed.connect(func(): _enter(main, choice))
			row.add_child(button)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	for entry in [[Localization.text("덱 정비"), "ExpeditionDeck", func(): show_deck(main)], [Localization.text("원정 포기"), "ExpeditionAbandon", func(): _confirm_abandon(main)], [Localization.text("메인 메뉴로"), "ExpeditionMenu", func(): leave(main)]]:
		var button = main._styled_button(entry[0], Color("#697386"), false)
		button.name = entry[1]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[2])
		actions.add_child(button)

static func _enter(main, index: int) -> void:
	if not ExpeditionRun.choose_node(main.expedition_run, index):
		return
	_save(main)
	show_map(main)

## Back to the main menu; the run stays saved.
static func leave(main) -> void:
	main.expedition_run = {}
	main._build_connect_screen()

static func _confirm_abandon(main) -> void:
	var column = main._action_panel(Localization.text("원정을 포기할까요?"), Rect2(390, 220, 500, 280))
	column.add_child(_label(Localization.text("지금까지의 진행은 기록에 남고 원정은 끝납니다."), 15, MultiplayerUI.MUTED))
	MultiplayerUI.button(main, column, Localization.text("포기"), "ConfirmAbandon", func():
		main._dismiss_action_overlay()
		main.expedition_run.status = "lost"
		show_end(main))
	MultiplayerUI.button(main, column, Localization.text("계속하기"), "CancelAbandon", main._dismiss_action_overlay)

# --- deck --------------------------------------------------------------------

static func show_deck(main) -> void:
	var run: Dictionary = main.expedition_run
	var units: Array = run.deck.units.duplicate()
	var structures: Array = run.deck.structures.duplicate()
	var column = main._submenu(Localization.text("덱 정비"), Localization.text("모은 카드 중에서 병력 4장과 전술 4장을 고르세요."))
	var status := _label("", 15, MultiplayerUI.GOLD)
	status.name = "ExpeditionDeckStatus"
	var save_button = main._styled_button(Localization.text("이 덱으로"), UIKit.ACCENT, true)
	save_button.name = "ExpeditionDeckSave"
	var refresh := func():
		status.text = Localization.text("병력 %d/4 · 전술 %d/4") % [units.size(), structures.size()]
		save_button.disabled = units.size() != BattleModel.DECK_SIZE or structures.size() != BattleModel.DECK_SIZE
	for group in [[run.cards.units, units, Localization.text("병력")], [run.cards.structures, structures, Localization.text("전술")]]:
		column.add_child(MultiplayerUI.label(group[2], 15, UIKit.TEXT_MUTED))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		column.add_child(grid)
		var chosen: Array = group[1]
		for kind in group[0]:
			var toggle := CheckButton.new()
			toggle.name = "ExpeditionCard_" + String(kind)
			toggle.text = card_label(run, String(kind))
			toggle.button_pressed = chosen.has(kind)
			toggle.custom_minimum_size = Vector2(250, 40)
			var card := String(kind)
			toggle.toggled.connect(func(on):
				if on and not chosen.has(card):
					chosen.append(card)
				elif not on:
					chosen.erase(card)
				refresh.call())
			grid.add_child(toggle)
	column.add_child(status)
	save_button.pressed.connect(func():
		if ExpeditionRun.set_deck(run, units, structures):
			_save(main)
			show_map(main))
	column.add_child(save_button)
	var back = main._styled_button(Localization.text("취소"), Color("#697386"), false)
	back.name = "ExpeditionDeckBack"
	back.pressed.connect(func(): show_map(main))
	column.add_child(back)
	refresh.call()

# --- rest and shop -----------------------------------------------------------

static func show_rest(main) -> void:
	var run: Dictionary = main.expedition_run
	var column = main._submenu(Localization.text("🔥 휴식"), Localization.text("기지를 고치거나 카드 하나를 강화하세요."))
	_header(main, column)
	var heal = MultiplayerUI.button(main, column, Localization.text("기지 수리 · 체력 +%d") % int(ExpeditionRun.BASE_MAX * ExpeditionRun.REST_HEAL), "ExpeditionRestHeal", func():
		ExpeditionRun.rest(run)
		_save(main)
		show_map(main), true)
	heal.custom_minimum_size.y = 52
	var step := roundi(BattleModel.STAR_STEP * 100.0)
	column.add_child(_label(Localization.text("카드 강화: ★ 하나마다 병력은 체력·공격, 구조물은 체력이 %d%% 늘고, 마법은 재사용 대기가 %d%% 줄어듭니다. ★★ 병력은 비용도 %d%% 줄어듭니다.") % [step, roundi(BattleModel.STAR_SPELL_STEP * 100.0), roundi((1.0 - BattleModel.STAR_COST_SCALE) * 100.0)], 13, MultiplayerUI.MUTED))
	_upgrade_grid(main, column, func(kind):
		ExpeditionRun.rest(run, kind)
		_save(main)
		show_map(main))

static func _upgrade_grid(main, column: VBoxContainer, on_pick: Callable, prefix: String = "ExpeditionUpgrade_") -> void:
	var run: Dictionary = main.expedition_run
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for kind in run.deck.units + run.deck.structures:
		var button = main._styled_button(card_label(run, String(kind)) + " → ★" + "★".repeat(int(run.stars.get(kind, 0))), Color("#3d647d"), false)
		button.name = prefix + String(kind)
		button.custom_minimum_size = Vector2(250, 44)
		button.add_theme_font_size_override("font_size", 13)
		button.disabled = not ExpeditionRun.can_upgrade(run, String(kind))
		var card := String(kind)
		button.pressed.connect(func(): on_pick.call(card))
		grid.add_child(button)

static func show_shop(main) -> void:
	var run: Dictionary = main.expedition_run
	var shop: Dictionary = run.shop
	var column = main._submenu(Localization.text("💰 상점"), Localization.text("골드로 카드·유물·수리·강화를 삽니다."))
	_header(main, column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	var refresh := func(): show_shop(main)
	for i in shop.cards.size():
		var item: Dictionary = shop.cards[i]
		var index: int = i
		var button = main._styled_button(Localization.text("%s\n%d 골드") % [card_name(String(item.kind)), int(item.price)] if not bool(item.sold) else Localization.text("판매 완료"), Color("#3d647d"), false)
		button.name = "ExpeditionShopCard_%d" % i
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.disabled = bool(item.sold) or int(run.gold) < int(item.price)
		button.pressed.connect(func():
			if ExpeditionRun.buy(run, "card", index):
				_save(main)
				refresh.call())
		row.add_child(button)
	for i in shop.relics.size():
		var item: Dictionary = shop.relics[i]
		var relic: Dictionary = RunBoons.RELICS[item.id]
		var index: int = i
		var button = main._styled_button("%s %s\n%s · %d 골드" % [relic.icon, Localization.text(String(relic.name)), RunBoons.describe(String(item.id)), int(item.price)] if not bool(item.sold) else Localization.text("판매 완료"), Color("#8b6cf6"), false)
		button.name = "ExpeditionShopRelic_%d" % i
		button.custom_minimum_size = Vector2(0, 64)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.disabled = bool(item.sold) or int(run.gold) < int(item.price)
		button.pressed.connect(func():
			if ExpeditionRun.buy(run, "relic", index):
				_save(main)
				refresh.call())
		row.add_child(button)
	var services := HBoxContainer.new()
	services.add_theme_constant_override("separation", 10)
	column.add_child(services)
	var heal = main._styled_button(Localization.text("기지 수리 +%d · %d 골드") % [int(ExpeditionRun.HEAL_AMOUNT), ExpeditionRun.HEAL_PRICE], Color("#3d8f83"), false)
	heal.name = "ExpeditionShopHeal"
	heal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heal.disabled = bool(shop.healed) or int(run.gold) < ExpeditionRun.HEAL_PRICE or float(run.base_hp) >= ExpeditionRun.BASE_MAX
	heal.pressed.connect(func():
		if ExpeditionRun.buy(run, "heal"):
			_save(main)
			refresh.call())
	services.add_child(heal)
	column.add_child(_label(Localization.text("카드 강화 · %d 골드") % ExpeditionRun.UPGRADE_PRICE, 14, MultiplayerUI.MUTED))
	_upgrade_grid(main, column, func(kind):
		if ExpeditionRun.buy(run, "upgrade", -1, kind):
			_save(main)
			refresh.call(), "ExpeditionShopUpgrade_")
	var removable: Array = (run.cards.units + run.cards.structures).filter(func(kind): return ExpeditionRun.can_remove(run, String(kind)))
	if not removable.is_empty() and not bool(shop.removed):
		column.add_child(_label(Localization.text("덱에 없는 카드 버리기 · %d 골드 (카드 보상에 다른 카드가 나올 자리가 생깁니다)") % ExpeditionRun.REMOVE_PRICE, 14, MultiplayerUI.MUTED))
		var remove_row := HBoxContainer.new()
		remove_row.add_theme_constant_override("separation", 8)
		column.add_child(remove_row)
		for kind in removable.slice(0, 6):
			var card := String(kind)
			var button = main._styled_button(card_name(card), Color("#596174"), false)
			button.name = "ExpeditionShopRemove_" + card
			button.disabled = int(run.gold) < ExpeditionRun.REMOVE_PRICE
			button.pressed.connect(func():
				if ExpeditionRun.buy(run, "remove", -1, card):
					_save(main)
					refresh.call())
			remove_row.add_child(button)
	var leave_button = main._styled_button(Localization.text("상점 나가기"), UIKit.ACCENT, true)
	leave_button.name = "ExpeditionShopLeave"
	leave_button.pressed.connect(func():
		ExpeditionRun.leave_shop(run)
		_save(main)
		show_map(main))
	column.add_child(leave_button)

# --- battle ------------------------------------------------------------------

static func start_battle(main) -> void:
	var run: Dictionary = main.expedition_run
	var battle := ExpeditionRun.build_battle(run)
	main.ghost_context = {}
	main.daily_challenge = {}
	main.draft_context = {}
	main.campaign_mode = false
	main.local_ai_mode = true
	main.practice.reset_battle_state()
	main.practice_used_tools = true
	main._reset_battle_result()
	main.expedition_run = run
	run["speed"] = float(run.get("speed", 1.0))
	main.current_ai_stage = int(battle.enemy.stage)
	main.own_side = 0
	main.local_model = battle.model
	main.local_ai = battle.ai
	main.battle_preset = {"name": Localization.text("원정"), "units": run.deck.units.duplicate(), "structures": run.deck.structures.duplicate()}
	main._build_battle_screen()
	main.local_step_accumulator = 0.0
	main.local_recorder = null
	main._on_snapshot(main.local_model.snapshot())

static func step(main, delta: float) -> void:
	var run: Dictionary = main.expedition_run
	main.local_step_accumulator = minf(main.local_step_accumulator + minf(delta, 0.25) * float(run.get("speed", 1.0)), MAX_STEPS / 30.0)
	var tick := 1.0 / 30.0
	while main.local_step_accumulator >= tick and main.local_model.winner == -1:
		main.local_ai.update(main.local_model, tick)
		main.local_model.tick(tick)
		main.local_step_accumulator -= tick

static func add_controls(main) -> void:
	var run: Dictionary = main.expedition_run
	var row := HBoxContainer.new()
	row.name = "ExpeditionControls"
	row.position = Vector2(164, 98)
	row.size = Vector2(342, 44)
	row.z_index = 10
	row.add_theme_constant_override("separation", 6)
	main.root_background.add_child(row)
	main.practice_pause_button = main._styled_button(Localization.text("일시정지"), Color("#3d647d"))
	main.practice_pause_button.name = "ExpeditionPauseButton"
	main.practice_pause_button.custom_minimum_size = Vector2(90, 44)
	main.practice_pause_button.add_theme_font_size_override("font_size", 12)
	main.practice_pause_button.pressed.connect(main._toggle_practice_pause)
	row.add_child(main.practice_pause_button)
	var speed = main._styled_button("%d배속" % int(run.get("speed", 1.0)), Color("#3d647d"))
	speed.name = "ExpeditionSpeedButton"
	speed.custom_minimum_size = Vector2(76, 44)
	speed.add_theme_font_size_override("font_size", 12)
	speed.pressed.connect(func():
		run.speed = SPEEDS[(SPEEDS.find(float(run.get("speed", 1.0))) + 1) % SPEEDS.size()]
		speed.text = "%d배속" % int(run.speed))
	row.add_child(speed)
	var info := MultiplayerUI.label(Localization.text("%d막 · %s") % [int(run.act), Localization.text(String(run.node.enemy.name))], 13, UIKit.GOLD)
	info.name = "ExpeditionBattleInfo"
	row.add_child(info)

## Settles the battle once (the result screen shows it). Returns {"won", "base"}.
static func record(main, winner: int) -> Dictionary:
	var run: Dictionary = main.expedition_run
	if run.has("outcome"):
		return run.outcome
	var won: bool = winner == main.own_side
	var base := float(main.local_model.base_hp[main.own_side]) if is_instance_valid(main.local_model) else 0.0
	ExpeditionRun.finish_battle(run, won, base)
	run["outcome"] = {"won": won, "base": base}
	if won:
		_save(main)
	else:
		run["recorded"] = true
		RunRecords.record_expedition(main.save_data, run)
		main._save_profile()
	return run.outcome

static func result_note(main) -> String:
	var run: Dictionary = main.expedition_run
	if String(run.status) == "lost":
		return Localization.text("기지가 무너져 원정이 끝났습니다 · %d막 %d/%d") % [int(run.act), int(run.layer) + 1, ExpeditionRun.LAYERS]
	return Localization.text("남은 기지 체력 %d · 골드 +%d") % [int(run.base_hp), int(run.reward.get("gold", 0))]

## The result screen's continue button.
static func after_battle(main) -> void:
	var run: Dictionary = main.expedition_run
	run.erase("outcome")
	main.battle_active = false
	main.local_ai_mode = false
	main.local_model = null
	main.local_ai = null
	main.current_snapshot.clear()
	main._dismiss_result_overlay()
	show_map(main)

# --- rewards and the end -----------------------------------------------------

static func show_reward(main) -> void:
	var run: Dictionary = main.expedition_run
	var reward: Dictionary = run.reward
	var column = main._submenu(Localization.text("전투 승리!"), Localization.text("골드 +%d") % int(reward.gold))
	_header(main, column)
	for id in reward.relics:
		var relic: Dictionary = RunBoons.RELICS[id]
		column.add_child(_label(Localization.text("유물 획득 · %s %s · %s") % [relic.icon, Localization.text(String(relic.name)), RunBoons.describe(String(id))], 16, MultiplayerUI.GOLD))
	if not reward.cards.is_empty():
		column.add_child(_label(Localization.text("새 카드 하나를 고르세요. 덱 정비에서 덱에 넣을 수 있습니다."), 15, MultiplayerUI.MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		for kind in reward.cards:
			var card := String(kind)
			var summary := BattleModel.unit_role(card) if BattleModel.UNIT_STATS.has(card) else Localization.text("전술")
			var button = main._styled_button("%s\n%s" % [card_name(card), summary], Color("#3d647d"), false)
			button.name = "ExpeditionRewardCard_" + card
			button.custom_minimum_size = Vector2(0, 90)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			button.pressed.connect(func(): _take(main, card))
			row.add_child(button)
	var skip = main._styled_button(Localization.text("카드 받지 않기") if not reward.cards.is_empty() else Localization.text("계속"), Color("#697386"), reward.cards.is_empty())
	skip.name = "ExpeditionRewardSkip"
	skip.pressed.connect(func(): _take(main, ""))
	column.add_child(skip)

static func _take(main, kind: String) -> void:
	ExpeditionRun.take_reward(main.expedition_run, kind)
	if String(main.expedition_run.status) == "won":
		show_end(main)
		return
	_save(main)
	show_map(main)

static func show_end(main) -> void:
	var run: Dictionary = main.expedition_run
	var won := String(run.status) == "won"
	var record := RunRecords.expedition(main.save_data)
	if not run.has("recorded"):
		run["recorded"] = true
		RunRecords.record_expedition(main.save_data, run)
		main._save_profile()
	var column = main._submenu(Localization.text("원정 완주!") if won else Localization.text("원정 종료"), Localization.text("세 막을 모두 돌파했습니다.") if won else Localization.text("%d막 %d/%d에서 멈췄습니다.") % [int(run.act), int(run.layer) + 1, ExpeditionRun.LAYERS])
	_header(main, column)
	column.add_child(_label(Localization.text("이긴 전투 %d번 · 완주 %d회 · 도전 %d회") % [int(run.won_battles), int(record.clears), int(record.runs)], 16, MultiplayerUI.GOLD))
	var again = main._styled_button(Localization.text("새 원정"), UIKit.ACCENT, true)
	again.name = "ExpeditionAgain"
	again.pressed.connect(func(): choose_relic(main))
	column.add_child(again)
	var back = main._styled_button(Localization.text("메인 메뉴로"), Color("#697386"), false)
	back.name = "ExpeditionEndMenu"
	back.pressed.connect(func(): leave(main))
	column.add_child(back)
