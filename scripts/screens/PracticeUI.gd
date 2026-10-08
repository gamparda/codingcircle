extends RefCounted
## PracticeUI: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const Localization = preload("res://scripts/Localization.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")
const MetaStatsUI = preload("res://scripts/screens/MetaStatsUI.gd")

## Today's (or this week's) challenge: decks, rule twists, best score, the leaderboard, then "도전 시작".
static func _show_daily_brief(main, period: String = "daily") -> void:
	var challenge := DailyChallenge.current(period)
	var key := String(challenge.key)
	var weekly := DailyChallenge.is_weekly(challenge)
	var board_key := DailyChallenge.board_key(challenge)
	var stamp := "%s-%s-%s" % [key.substr(0, 4), key.substr(4, 2), key.substr(6, 2)]
	var column = main._action_panel(("주간 도전  ·  %s 주" if weekly else "일일 도전  ·  %s") % stamp, Rect2(200, 30, 880, 660))
	var twist_lines := PackedStringArray()
	for id in DailyChallenge.modifier_ids(challenge):
		var info := DailyChallenge.modifier_info(String(id))
		twist_lines.append("%s  ·  %s" % [Localization.text(String(info.name)), Localization.text(String(info.desc))])
	var twist := MultiplayerUI.label("\n".join(twist_lines), 19, MultiplayerUI.GOLD)
	twist.name = "DailyModifier"
	twist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(twist)
	column.add_child(MultiplayerUI.label(Localization.text("상대: %02d단계 %s AI") % [DailyChallenge.effective_stage(challenge), ServerAI.stage_name(DailyChallenge.effective_stage(challenge))], 15))
	column.add_child(MultiplayerUI.label("이번 주의 고정 덱" if weekly else "오늘의 고정 덱", 14, MultiplayerUI.GOLD))
	var icons := HBoxContainer.new()
	icons.name = "DailyDeck"
	icons.add_theme_constant_override("separation", 12)
	column.add_child(icons)
	for kind in challenge.units:
		var holder := VBoxContainer.new()
		icons.add_child(holder)
		var icon := TextureRect.new()
		icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
		icon.custom_minimum_size = Vector2(70, 92)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		holder.add_child(icon)
		var caption := MultiplayerUI.label(String(BattleModel.UNIT_NAMES[kind]), 12, MultiplayerUI.MUTED)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		holder.add_child(caption)
	var structure_names := PackedStringArray()
	for kind in challenge.structures:
		structure_names.append({"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}.get(kind, kind))
	column.add_child(MultiplayerUI.label(Localization.text("구조물: %s") % " · ".join(structure_names), 14, MultiplayerUI.MUTED))
	var entry: Dictionary = main.save_data.get(DailyChallenge.store_name(challenge), {}).get(key, {})
	var mark := " ✓" if bool(entry.get("won", false)) else ""
	var best_text := Localization.text("이번 주 최고 점수 %d점%s") % [int(entry.get("score", 0)), mark] if weekly else Localization.text("오늘의 최고 점수 %d점%s  ·  연속 %d일") % [int(entry.get("score", 0)), mark, DailyChallenge.streak(main.save_data, key)]
	var best := MultiplayerUI.label(best_text, 15, MultiplayerUI.GOLD)
	best.name = "DailyBest"
	column.add_child(best)
	column.add_child(MultiplayerUI.label("승리하면 점수를 받습니다. 남은 기지 체력이 많고 빠를수록 높습니다. 전투는 리플레이로 저장되어 공유할 수 있습니다.", 12, MultiplayerUI.MUTED))
	var board_box := VBoxContainer.new()
	board_box.name = "DailyBoardRows"
	board_box.add_theme_constant_override("separation", 3)
	column.add_child(board_box)
	MetaStatsUI.fill_board(board_box, board_key)
	var refresh := func(data: Dictionary):
		if is_instance_valid(board_box) and String(data.date) == board_key:
			MetaStatsUI.fill_board(board_box, board_key)
	main.network.daily_board_received.connect(refresh)
	board_box.tree_exited.connect(func(): if main.network.daily_board_received.is_connected(refresh): main.network.daily_board_received.disconnect(refresh))
	main.network.send_daily_board_request(board_key, MetaStats.install_id(main.save_data) if MetaStats.sharing(main.save_data) else "")
	column.add_child(MetaStatsUI.share_toggle(main))
	MultiplayerUI.button(main, column, "도전 시작", "StartDailyChallenge", func(): main._dismiss_action_overlay(); main._start_daily_challenge(period), true)
	MultiplayerUI.button(main, column, "돌아가기", "CloseDailyBrief", main._dismiss_action_overlay)

static func _show_stage_brief(main, stage: int) -> void:
	if not main.campaign_mode or stage>int(main.save_data.campaign_unlocked): return
	var column = main._action_panel("%02d · %s" % [stage,ServerAI.stage_name(stage)],Rect2(200,130,880,460))
	column.add_child(MultiplayerUI.label(CampaignBrief.goal(stage),19))
	column.add_child(MultiplayerUI.label("상대 덱",14,MultiplayerUI.GOLD))
	var deck := MultiplayerUI.label(CampaignBrief.enemy_deck(stage),16); deck.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; column.add_child(deck)
	column.add_child(MultiplayerUI.label(CampaignBrief.conditions(stage),15,MultiplayerUI.GOLD))
	var record: Dictionary = main.save_data.campaign_records[stage-1]
	column.add_child(MultiplayerUI.label("최고 %s · 최단 %s" % ["★".repeat(int(record.best_stars)),"%.0f초"%float(record.fastest_win) if float(record.fastest_win)>0 else "기록 없음"],14,MultiplayerUI.MUTED))
	MultiplayerUI.button(main,column,"전투 시작","StartCampaignStage",func(): main._dismiss_action_overlay(); main._start_local_ai_battle(stage))
	MultiplayerUI.button(main,column,"돌아가기","CloseCampaignBrief",main._dismiss_action_overlay)

static func _show_practice_deck(main) -> void:
	if main.campaign_mode: return
	var column = main._action_panel("연습 상대 덱",Rect2(220,70,840,580))
	column.add_child(MultiplayerUI.label("병력 3종 · 구조물 3종",15,MultiplayerUI.MUTED))
	var units: Array = main.practice.enemy_units.duplicate() if not main.practice.enemy_units.is_empty() else ServerAI.stage_unit_deck(main.current_ai_stage)
	var structures: Array = main.practice.enemy_structures.duplicate() if not main.practice.enemy_structures.is_empty() else ServerAI.stage_structure_deck(main.current_ai_stage)
	var unit_grid := GridContainer.new(); unit_grid.columns=4; unit_grid.add_theme_constant_override("h_separation",12); column.add_child(unit_grid)
	for kind in BattleModel.UNIT_NAMES:
		if kind=="skeleton": continue
		var button := CheckButton.new(); button.text = BattleModel.UNIT_NAMES[kind]; button.button_pressed = units.has(kind); button.toggled.connect(func(on):
			if on: units.append(kind)
			else: units.erase(kind)); unit_grid.add_child(button)
	var structure_grid := GridContainer.new(); structure_grid.columns=4; column.add_child(structure_grid)
	for kind in BattleModel.STRUCTURE_STATS:
		var button := CheckButton.new(); button.text = {"wall":"방벽","swamp":"늪","turret":"포탑","generator":"발전기"}[kind]; button.button_pressed = structures.has(kind); button.toggled.connect(func(on):
			if on: structures.append(kind)
			else: structures.erase(kind)); structure_grid.add_child(button)
	var error := MultiplayerUI.label("",15,Color("#ff8a96")); column.add_child(error)
	MultiplayerUI.button(main,column,"적용","ApplyPracticeDeck",func():
		if not main.practice.set_enemy_deck(units,structures): error.text="서로 다른 병력 3종과 구조물 3종을 선택하세요."; return
		main._dismiss_action_overlay()
		if main.battle_active and main.local_ai_mode: main._restart_practice()
	)
	MultiplayerUI.button(main,column,"단계 기본 덱","DefaultPracticeDeck",func(): main.practice.enemy_units.clear(); main.practice.enemy_structures.clear(); main._dismiss_action_overlay(); main._restart_practice() if main.battle_active and main.local_ai_mode else main._build_ai_stage_screen(false))
	MultiplayerUI.button(main,column,"닫기","ClosePracticeDeck",main._dismiss_action_overlay)

static func _add_practice_controls(main) -> void:
	var row := HBoxContainer.new(); row.name = "PracticeControls"; row.position = Vector2(164,98); row.size = Vector2(342,44); row.z_index=10; row.add_theme_constant_override("separation",6); main.root_background.add_child(row)
	main.practice_pause_button = main._styled_button("일시정지",Color("#3d647d")); main.practice_pause_button.name="PracticePauseButton"; main.practice_pause_button.custom_minimum_size = Vector2(90,44); main.practice_pause_button.add_theme_font_size_override("font_size",12); main.practice_pause_button.pressed.connect(main._toggle_practice_pause); row.add_child(main.practice_pause_button)
	main.practice_speed_button = main._styled_button("%.1f배" % main.practice.speed,Color("#3d647d")); main.practice_speed_button.name="PracticeSpeedButton"; main.practice_speed_button.custom_minimum_size = Vector2(66,44); main.practice_speed_button.add_theme_font_size_override("font_size",12); main.practice_speed_button.pressed.connect(func(): main.practice.cycle_speed(); main.practice_used_tools=true; main.local_recorder=null; main.practice_speed_button.text="%.1f배"%main.practice.speed); row.add_child(main.practice_speed_button)
	var reset = main._styled_button("초기화",Color("#596174")); reset.name="PracticeResetButton"; reset.custom_minimum_size=Vector2(74,44); reset.add_theme_font_size_override("font_size",12); reset.pressed.connect(main._restart_practice); row.add_child(reset)
	var settings = main._styled_button("상대 덱",Color("#596174")); settings.custom_minimum_size=Vector2(84,44); settings.add_theme_font_size_override("font_size",12); settings.pressed.connect(main._show_practice_deck); row.add_child(settings)

static func _confirm_surrender(main) -> void:
	if not main.battle_active or main.result_shown or main.network.client_is_spectator: return
	var column = main._action_panel("항복할까요?",Rect2(400,230,480,260))
	column.add_child(MultiplayerUI.label("이 경기는 패배로 종료됩니다.",16,MultiplayerUI.MUTED))
	MultiplayerUI.button(main,column,"항복","ConfirmSurrender",func():
		main._dismiss_action_overlay()
		if main.local_ai_mode:
			main.local_model.winner=1-main.own_side; main._on_snapshot(main.local_model.snapshot())
		else: main.network.send_surrender()
	)
	MultiplayerUI.button(main,column,"계속하기","CancelSurrender",main._dismiss_action_overlay)
