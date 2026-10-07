extends RefCounted
## ResultScreens: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const Report = preload("res://scripts/BattleReport.gd")

static func _show_result(main, winner: int) -> void:
	main._dismiss_result_overlay()
	main._dismiss_stats_panel()
	if is_instance_valid(main.tutorial_banner):
		main.tutorial_banner.queue_free()
	main.tutorial_banner = null
	main.tutorial_hint = null
	main.tutorial_step = -1
	main.result_shown = true
	main.updater.set_safe_to_update(true)
	main.updater.check_for_update()
	var awarded_stars := 0
	var growth_before := SaveData.campaign_growth_level(main.save_data)
	if not main.result_recorded and not main.network.client_is_spectator:
		main.result_recorded = true
		if main.local_ai_mode:
			if main.local_recorder != null and is_instance_valid(main.local_model):
				if main.local_recorder.ticks > 0: main.last_replay_path = BattleReplay.save(main.local_recorder.finish(main.local_model), "stage%d" % main.current_ai_stage)
				main.local_recorder = null
			if main.campaign_mode:
				awarded_stars = SaveData.record_campaign(main.save_data, main.current_ai_stage, winner == main.own_side, float(main.current_snapshot.elapsed), float(main.current_snapshot.base_hp[main.own_side]), winner == 2)
			elif not main.practice_used_tools:
				main.save_data.stats.ai_matches += 1
				main.save_data.stats.ai_wins += 1 if winner == main.own_side else 0
				main.save_data.stats.ai_losses += 1 if winner != main.own_side and winner != 2 else 0
		else:
			main.save_data.stats.online_completed += 1
			main.save_data.stats.online_wins += 1 if winner == main.own_side else 0
			main.save_data.stats.online_losses += 1 if winner != main.own_side and winner != 2 else 0
			main.save_data.stats.online_draws += 1 if winner == 2 else 0
		SaveData.save_data(main.save_data)
	var overlay := PanelContainer.new()
	overlay.name = "ResultOverlay"
	main.result_overlay = overlay
	overlay.position = Vector2(350, 155)
	overlay.size = Vector2(580, 410)
	var result_color := Color("#f6c85f") if winner == main.own_side else Color("#8f98ad")
	var overlay_style = main._panel_style(Color("#121923"), Color(result_color.r, result_color.g, result_color.b, 0.55), 18)
	overlay_style.shadow_color = Color(0.0, 0.0, 0.0, 0.58)
	overlay_style.shadow_size = 28
	overlay.add_theme_stylebox_override("panel", overlay_style)
	main.root_background.add_child(overlay)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(580, 410)
	overlay.add_child(inner)
	var overline := Label.new()
	overline.text = "MATCH COMPLETE"
	overline.position = Vector2(0, 36)
	overline.size = Vector2(580, 24)
	overline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overline.add_theme_font_size_override("font_size", 11)
	overline.add_theme_color_override("font_color", Color("#747d91"))
	inner.add_child(overline)
	var result := Label.new()
	result.text = "전투 종료" if main.network.client_is_spectator else (Localization.text("무승부") if winner == 2 else (Localization.text("승리") if winner == main.own_side else Localization.text("패배")))
	result.position = Vector2(0, 64)
	result.size = Vector2(580, 82)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 52)
	result.add_theme_color_override("font_color", result_color)
	inner.add_child(result)
	var advances = main.local_ai_mode and main.campaign_mode and winner == main.own_side and main.current_ai_stage < ServerAI.MAX_STAGE
	var note := Label.new()
	if main.local_ai_mode:
		note.text = Localization.text("%02d단계 승리 · 최고 ★ %d · 다음 단계 해금") % [main.current_ai_stage, awarded_stars] if main.campaign_mode and winner == main.own_side else Localization.text("%02d단계 결과가 개인 전적에 저장되었습니다.") % main.current_ai_stage
		if not main.campaign_mode and main.practice_used_tools: note.text = "실험 설정 결과는 전적에 기록하지 않습니다."
	else:
		note.text = "같은 방에서 덱을 바꾸고 다시 대전할 수 있습니다." if not main.network.client_session.is_empty() else Localization.text("두 플레이어가 모두 준비하면 다시 시작합니다.")
	note.position = Vector2(0, 157)
	note.size = Vector2(580, 34)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_color_override("font_color", Color("#8f98ad"))
	inner.add_child(note)
	var details := Label.new()
	details.name = "ResultDetails"
	details.text = main.result_details(main.current_snapshot, main.own_side, String(main.battle_preset.get("name", "")))
	details.position = Vector2(32, 193)
	details.size = Vector2(516, 54)
	details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details.add_theme_font_size_override("font_size", 15)
	details.add_theme_color_override("font_color", Color("#dce1ec"))
	inner.add_child(details)
	if main.current_snapshot.has("battle_report"):
		var report_button = main._styled_button("전투 요약",Color("#3d647d"))
		report_button.name = "BattleReportButton"; report_button.position = Vector2(395,25); report_button.size = Vector2(155,44)
		report_button.pressed.connect(main._show_battle_report); inner.add_child(report_button)
	if main.local_ai_mode and main.campaign_mode:
		var growth := Label.new()
		growth.name = "CampaignGrowthReward"
		growth.text = CampaignBrief.result_conditions(main.current_ai_stage,winner==main.own_side,float(main.current_snapshot.elapsed),float(main.current_snapshot.base_hp[main.own_side])) + "\n" + ("첫 클리어 보상 · 병력 +3% · 자원 +0.5/초 · 보유 +10 · 시작 +5" if SaveData.campaign_growth_level(main.save_data)>growth_before else main._campaign_growth_summary())
		growth.position = Vector2(25, 250)
		growth.size = Vector2(530, 44)
		growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		growth.add_theme_font_size_override("font_size", 12)
		growth.add_theme_color_override("font_color", Color("#f0d592"))
		inner.add_child(growth)
	var rematch_text := Localization.text("다시 도전") if main.local_ai_mode else ("대기실로" if not main.network.client_session.is_empty() else Localization.text("재경기 준비"))
	var rematch = main._styled_button(rematch_text, Color("#5e6ad2"), true)
	rematch.position = Vector2(25 if advances else 65, 306)
	rematch.size = Vector2(165 if advances else 215, 58)
	rematch.pressed.connect(func():
		rematch.disabled = true
		if main.local_ai_mode:
			main._start_local_ai_battle(main.current_ai_stage, true)
		elif not main.network.client_session.is_empty():
			main.network.request_session_return.rpc_id(1)
		else:
			rematch.text = Localization.text("상대 준비 대기 중")
			main.network.send_rematch()
	)
	inner.add_child(rematch)
	if advances:
		var next_stage = main._styled_button(Localization.text("다음 단계"), Color("#3d8f83"), true)
		next_stage.position = Vector2(207, 306)
		next_stage.size = Vector2(165, 58)
		next_stage.pressed.connect(func():
			next_stage.disabled = true
			main._start_local_ai_battle(main.current_ai_stage + 1, true)
		)
		inner.add_child(next_stage)
	var back = main._styled_button(Localization.text("단계 선택") if main.local_ai_mode else Localization.text("이전 화면으로"), Color("#697386"), false)
	back.name = "BackToMenuButton"
	back.position = Vector2(389 if advances else 300, 306)
	back.size = Vector2(165 if advances else 215, 58)
	if main.local_ai_mode:
		back.pressed.connect(main._build_ai_stage_screen.bind(main.campaign_mode))
	else:
		back.pressed.connect(main._exit_battle_to_menu)
	inner.add_child(back)

static func _show_battle_report(main) -> void:
	if not Report.valid(main.current_snapshot.get("battle_report",[])): return
	main._dismiss_battle_report()
	main.report_overlay = ColorRect.new(); main.report_overlay.name = "BattleReportOverlay"; main.report_overlay.color = Color(0.02,0.03,0.05,0.97); main.report_overlay.size = Vector2(1280,720); main.report_overlay.z_index = 150; main.root_background.add_child(main.report_overlay)
	var content := MultiplayerUI.panel(main,main.report_overlay,"BattleReportPanel",Rect2(80,40,1120,640))
	content.add_child(MultiplayerUI.label("전투 요약",28,MultiplayerUI.GOLD))
	var columns := HBoxContainer.new(); columns.add_theme_constant_override("separation",28); columns.size_flags_vertical = Control.SIZE_EXPAND_FILL; content.add_child(columns)
	for side in 2:
		var column := VBoxContainer.new(); column.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_theme_constant_override("separation",14); columns.add_child(column)
		var data: Dictionary = main.current_snapshot.battle_report[side]
		column.add_child(MultiplayerUI.label(main._report_side_name(side),22))
		column.add_child(MultiplayerUI.label("사용 자원 %d · 건설 %d
처치 %d · 실제 피해 %d" % [roundi(float(data.resources_spent)),int(data.structures_built),int(data.kills),roundi(float(data.damage))],16,MultiplayerUI.GOLD))
		for text in Report.lines(data): column.add_child(MultiplayerUI.label(text,14,MultiplayerUI.MUTED))
	content.add_child(MultiplayerUI.label("피해는 실제로 감소시킨 체력입니다. 해골의 처치·피해는 네크로맨서에 합산합니다.",12,MultiplayerUI.MUTED))
	MultiplayerUI.button(main,content,"닫기","CloseBattleReportButton",main._dismiss_battle_report)

static func _report_side_name(main, side: int) -> String:
	if main.local_ai_mode: return "내 전투" if side==main.own_side else "상대 AI"
	var players: Array = main.network.client_session.get("members",[]).filter(func(member): return member.role=="player")
	return String(players[side].nickname) if players.size()==2 else ("내 전투" if side==main.own_side else "상대 전투")
