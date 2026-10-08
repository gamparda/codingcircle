extends RefCounted
## ResultScreens: screen/UI code moved out of Main.gd. `main` is the Main node; state stays on Main.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const CampaignBrief = preload("res://scripts/CampaignBrief.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const HpBar = preload("res://scripts/ui/HpBar.gd")
const ReplayAnalysis = preload("res://scripts/ReplayAnalysis.gd")
const Achievements = preload("res://scripts/Achievements.gd")
const DailyChallenge = preload("res://scripts/DailyChallenge.gd")
const ToastLabel = preload("res://scripts/ui/ToastLabel.gd")
const Report = preload("res://scripts/BattleReport.gd")
const MetaStats = preload("res://scripts/MetaStats.gd")

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
	var unlocked: Array = []
	if not main.result_recorded and not main.network.client_is_spectator:
		main.result_recorded = true
		if main.local_ai_mode:
			if main.local_recorder != null and is_instance_valid(main.local_model):
				if main.local_recorder.ticks > 0: main.last_replay_path = BattleReplay.save(main.local_recorder.finish(main.local_model), "stage%d" % main.current_ai_stage)
				main.local_recorder = null
			if not main.daily_challenge.is_empty():
				var snap: Dictionary = main.current_snapshot
				DailyChallenge.record(main.save_data, main.daily_challenge, winner == main.own_side, float(snap.get("base_hp", [0.0, 0.0])[main.own_side]), float(snap.get("elapsed", 0.0)))
			if main.campaign_mode:
				awarded_stars = SaveData.record_campaign(main.save_data, main.current_ai_stage, winner == main.own_side, float(main.current_snapshot.elapsed), float(main.current_snapshot.base_hp[main.own_side]), winner == 2)
			elif main.daily_challenge.is_empty() and main.draft_context.is_empty() and not main.practice_used_tools:
				main.save_data.stats.ai_matches += 1
				main.save_data.stats.ai_wins += 1 if winner == main.own_side else 0
				main.save_data.stats.ai_losses += 1 if winner != main.own_side and winner != 2 else 0
		else:
			main.save_data.stats.online_completed += 1
			main.save_data.stats.online_wins += 1 if winner == main.own_side else 0
			main.save_data.stats.online_losses += 1 if winner != main.own_side and winner != 2 else 0
			main.save_data.stats.online_draws += 1 if winner == 2 else 0
		unlocked = _judge_achievements(main, winner)
		_share_result(main, winner)
		SaveData.save_data(main.save_data)
	var screen := Control.new()
	screen.name = "ResultOverlay"
	screen.position = Vector2.ZERO
	screen.size = Vector2(1280, 720)
	screen.mouse_filter = Control.MOUSE_FILTER_STOP
	main.result_overlay = screen
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.62)
	dim.size = Vector2(1280, 720)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(dim)
	# Online results get an extra strip for the opponent and the player's record.
	var strip_extra := 0.0 if main.local_ai_mode else 56.0
	var notes_extra := 40.0 + (28.0 if not unlocked.is_empty() else 0.0) # summary line, plus a row for new achievements
	var extra := strip_extra + notes_extra
	var overlay := PanelContainer.new()
	overlay.name = "ResultPanel"
	overlay.position = Vector2(350, 155 - extra * 0.5)
	overlay.size = Vector2(580, 410 + extra)
	var won: bool = winner == main.own_side
	var result_color := UIKit.GOLD if won else (UIKit.TEXT_MUTED if winner == 2 else UIKit.DANGER.lightened(0.15))
	overlay.add_theme_stylebox_override("panel", UIKit.box(UIKit.SURFACE_HI.lerp(result_color, 0.08), UIKit.SURFACE.darkened(0.2), Color(result_color.r, result_color.g, result_color.b, 0.7), 18, 1.5, 1.0, Color(result_color.r, result_color.g, result_color.b, 0.35) if won else Color(0, 0, 0, 0), 0.12, 16))
	screen.add_child(overlay)
	main.root_background.add_child(screen)
	UIKit.reveal(overlay, 0.35, 18.0)
	UIKit.UISounds.play("victory" if won else ("click" if winner == 2 else "defeat"), -6.0)
	dim.modulate.a = 0.0
	dim.create_tween().tween_property(dim, "modulate:a", 1.0, 0.3)
	var inner := Control.new()
	inner.custom_minimum_size = Vector2(580, 410 + extra)
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
	result.position = Vector2(0, 54)
	result.size = Vector2(580, 76)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.display(result, 62, result_color)
	result.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
	result.add_theme_constant_override("outline_size", 8)
	inner.add_child(result)
	if main.local_ai_mode and main.campaign_mode and won:
		var stars := HBoxContainer.new()
		stars.name = "ResultStars"
		stars.position = Vector2(0, 122)
		stars.size = Vector2(580, 34)
		stars.alignment = BoxContainer.ALIGNMENT_CENTER
		stars.add_theme_constant_override("separation", 10)
		inner.add_child(stars)
		for star_index in 3:
			var star := Label.new()
			star.text = "★" if star_index < awarded_stars else "☆"
			star.add_theme_font_size_override("font_size", 30)
			star.add_theme_color_override("font_color", UIKit.GOLD if star_index < awarded_stars else UIKit.TEXT_DIM)
			star.pivot_offset = Vector2(15, 17)
			star.scale = Vector2.ZERO
			stars.add_child(star)
			var pop := star.create_tween()
			pop.tween_interval(0.35 + 0.18 * star_index)
			pop.tween_property(star, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var advances = main.local_ai_mode and main.campaign_mode and winner == main.own_side and main.current_ai_stage < ServerAI.MAX_STAGE
	var note := Label.new()
	if main.local_ai_mode:
		note.text = Localization.text("%02d단계 승리 · 최고 ★ %d · 다음 단계 해금") % [main.current_ai_stage, awarded_stars] if main.campaign_mode and winner == main.own_side else Localization.text("%02d단계 결과가 개인 전적에 저장되었습니다.") % main.current_ai_stage
		if not main.campaign_mode and main.practice_used_tools: note.text = "실험 설정 결과는 전적에 기록하지 않습니다."
		if not main.ghost_context.is_empty():
			var branch: bool = String(main.ghost_context.mode) == "branch"
			note.text = Localization.text("이 결과는 전적에 기록되지 않는 실험입니다.") if branch else (Localization.text("고스트를 이겼습니다! 전적에는 기록되지 않습니다.") if winner == main.own_side else Localization.text("고스트에게 졌습니다. 다시 도전해 보세요."))
		elif not main.daily_challenge.is_empty():
			note.text = DailyChallenge.result_note(main.daily_challenge, main.save_data, winner == main.own_side)
		elif not main.draft_context.is_empty():
			note.text = Localization.text("드래프트 승리! 전적에는 기록되지 않습니다.") if winner == main.own_side else Localization.text("드래프트에서 졌습니다. 다시 뽑아 도전해 보세요.")
	else:
		note.text = "같은 방에서 덱을 바꾸고 다시 대전할 수 있습니다." if not main.network.client_session.is_empty() else Localization.text("두 플레이어가 모두 준비하면 다시 시작합니다.")
	note.position = Vector2(0, 160)
	note.size = Vector2(580, 30)
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
		growth.text = CampaignBrief.result_conditions(main.current_ai_stage,winner==main.own_side,float(main.current_snapshot.elapsed),float(main.current_snapshot.base_hp[main.own_side])) + "\n" + (BattleModel.campaign_reward_text() if SaveData.campaign_growth_level(main.save_data)>growth_before else main._campaign_growth_summary())
		growth.position = Vector2(25, 250)
		growth.size = Vector2(530, 44)
		growth.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		growth.add_theme_font_size_override("font_size", 12)
		growth.add_theme_color_override("font_color", Color("#f0d592"))
		inner.add_child(growth)
	if not main.local_ai_mode:
		inner.add_child(_match_strip(main, winner, Vector2(28, 252), 524))
	var notes_y := 300.0 + strip_extra
	var summary_text := "" if main.network.client_is_spectator else ReplayAnalysis.summary_line(main.battle_curve, winner, main.own_side)
	if not summary_text.is_empty():
		var summary_label := Label.new()
		summary_label.name = "MatchSummaryLine"
		summary_label.text = "▸  " + Localization.text(summary_text)
		summary_label.position = Vector2(28, notes_y)
		summary_label.size = Vector2(524, 30)
		summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		summary_label.add_theme_font_size_override("font_size", 14)
		summary_label.add_theme_color_override("font_color", UIKit.GOLD)
		summary_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(summary_label)
	if not unlocked.is_empty():
		var names := PackedStringArray()
		for entry in unlocked:
			names.append("%s %s" % [entry.icon, Localization.text(String(entry.name))])
		var toast := ToastLabel.new()
		toast.name = "AchievementToast"
		toast.tone = UIKit.GOLD
		toast.text = Localization.text("업적 달성!  ") + "   ".join(names)
		inner.add_child(toast)
		toast.place_center(290.0, notes_y + 32.0)
		UIKit.UISounds.play("victory", -12.0)
	var rematch_text := Localization.text("다시 도전") if main.local_ai_mode else ("대기실로" if not main.network.client_session.is_empty() else Localization.text("재경기 준비"))
	var rematch = main._styled_button(rematch_text, Color("#5e6ad2"), true)
	rematch.position = Vector2(25 if advances else 65, 306 + extra)
	rematch.size = Vector2(165 if advances else 215, 58)
	rematch.pressed.connect(func():
		rematch.disabled = true
		if main.local_ai_mode and not main.ghost_context.is_empty():
			main._restart_context()
		elif main.local_ai_mode and not main.draft_context.is_empty():
			main._build_draft_screen(int(main.draft_context.stage))
		elif main.local_ai_mode and not main.daily_challenge.is_empty():
			main._start_daily_challenge(String(main.daily_challenge.get("period", "daily")))
		elif main.local_ai_mode:
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
		next_stage.position = Vector2(207, 306 + extra)
		next_stage.size = Vector2(165, 58)
		next_stage.pressed.connect(func():
			next_stage.disabled = true
			main._start_local_ai_battle(main.current_ai_stage + 1, true)
		)
		inner.add_child(next_stage)
	var back = main._styled_button(Localization.text("단계 선택") if main.local_ai_mode else Localization.text("이전 화면으로"), Color("#697386"), false)
	back.name = "BackToMenuButton"
	back.position = Vector2(389 if advances else 300, 306 + extra)
	back.size = Vector2(165 if advances else 215, 58)
	if main.local_ai_mode and not main.ghost_context.is_empty():
		back.pressed.connect(main._build_replay_list)
	elif main.local_ai_mode and (not main.daily_challenge.is_empty() or not main.draft_context.is_empty()):
		back.pressed.connect(main._build_connect_screen)
	elif main.local_ai_mode:
		back.pressed.connect(main._build_ai_stage_screen.bind(main.campaign_mode))
	else:
		back.pressed.connect(main._exit_battle_to_menu)
	inner.add_child(back)

## Opponent card + personal online record, shown under the result details of online matches.
static func _match_strip(main, winner: int, at: Vector2, width: float) -> Control:
	var strip := HBoxContainer.new()
	strip.name = "MatchStrip"
	strip.position = at
	strip.size = Vector2(width, 64)
	strip.add_theme_constant_override("separation", 12)
	var spectator: bool = main.network.client_is_spectator
	var opponent_side: int = 1 - int(main.own_side)
	var members: Array = main.network.client_session.get("members", []).filter(func(member): return member.role == "player")
	var opponent_name: String = String(main._report_side_name(opponent_side))
	var deck: Array = []
	if members.size() == 2:
		deck = members[opponent_side].deck.units
	var tone := UIKit.TEAM_RED if opponent_side == 1 else UIKit.TEAM_BLUE
	# Opponent card.
	var card := PanelContainer.new()
	card.name = "OpponentCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI.lerp(tone, 0.10), UIKit.SURFACE.darkened(0.1), Color(tone.r, tone.g, tone.b, 0.6), 12, 1.0, 0.0, Color(0, 0, 0, 0), 0.08), 12, 8))
	strip.add_child(card)
	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 10)
	card.add_child(card_row)
	var avatar := PanelContainer.new()
	avatar.custom_minimum_size = Vector2(44, 44)
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(tone.r, tone.g, tone.b, 0.25)
	ring.border_color = tone
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(22)
	ring.anti_aliasing = true
	avatar.add_theme_stylebox_override("panel", ring)
	card_row.add_child(avatar)
	var initial := Label.new()
	initial.text = opponent_name.left(1).to_upper() if not opponent_name.is_empty() else "?"
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UIKit.display(initial, 20, tone.lightened(0.4))
	avatar.add_child(initial)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_row.add_child(names)
	var caption := Label.new()
	caption.text = Localization.text("상대") if not spectator else Localization.text("상대 진영")
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", UIKit.TEXT_DIM)
	names.add_child(caption)
	var nickname := Label.new()
	nickname.name = "OpponentName"
	nickname.text = opponent_name
	nickname.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nickname.add_theme_font_size_override("font_size", 16)
	names.add_child(nickname)
	var deck_row := HBoxContainer.new()
	deck_row.add_theme_constant_override("separation", 0)
	card_row.add_child(deck_row)
	for kind in deck:
		var icon := TextureRect.new()
		icon.texture = load("res://assets/units/%s.png" % ("tanker" if kind == "shield" else kind))
		icon.custom_minimum_size = Vector2(28, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		deck_row.add_child(icon)
	if spectator:
		return strip
	# Record card: wins / losses / draws and win-rate bar.
	var stats: Dictionary = main.save_data.stats
	var total := int(stats.online_completed)
	var wins := int(stats.online_wins)
	var losses := int(stats.online_losses)
	var draws := int(stats.online_draws)
	var rate := 0.0 if total == 0 else float(wins) / float(total)
	var record := PanelContainer.new()
	record.name = "RecordCard"
	record.custom_minimum_size.x = 214
	record.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI, UIKit.SURFACE.darkened(0.1), Color(UIKit.GOLD.r, UIKit.GOLD.g, UIKit.GOLD.b, 0.5), 12, 1.0, 0.0, Color(0, 0, 0, 0), 0.08), 12, 8))
	strip.add_child(record)
	var record_box := VBoxContainer.new()
	record_box.add_theme_constant_override("separation", 4)
	record.add_child(record_box)
	var headline := Label.new()
	headline.name = "RecordSummary"
	headline.text = Localization.text("내 온라인 전적  %d승 %d패 %d무") % [wins, losses, draws]
	headline.add_theme_font_size_override("font_size", 12)
	headline.add_theme_color_override("font_color", UIKit.TEXT)
	record_box.add_child(headline)
	var bar := HpBar.new()
	bar.color = UIKit.SUCCESS
	bar.pulse_below = 0.0
	bar.show_ticks = false
	bar.custom_minimum_size = Vector2(190, 8)
	bar.max_value = 1.0
	bar.value = rate
	record_box.add_child(bar)
	var percent := Label.new()
	percent.text = Localization.text("승률 %d%%  ·  %d경기") % [roundi(rate * 100.0), total]
	percent.add_theme_font_size_override("font_size", 11)
	percent.add_theme_color_override("font_color", UIKit.GOLD)
	record_box.add_child(percent)
	return strip

## Updates streaks and unlocks achievements for a finished, countable battle. Experiments return [].
## Queues the finished solo battle for the community statistics (only when the player opted in) and sends
## it right away when a server connection happens to be open.
static func _share_result(main, winner: int) -> void:
	if not main.local_ai_mode or not main.ghost_context.is_empty() or not main.draft_context.is_empty() or not is_instance_valid(main.local_model) or not MetaStats.sharing(main.save_data):
		return
	var mode := "daily" if not main.daily_challenge.is_empty() else ("campaign" if main.campaign_mode else ("practice" if not main.practice_used_tools else ""))
	if mode == "":
		return
	var side: int = main.own_side
	var result := 0 if winner == side else (2 if winner == 2 else 1)
	MetaStats.queue_report(main.save_data, main.local_model.unit_decks[side], main.local_model.structure_decks[side], result, mode)
	if mode == "daily" and result == 0:
		var entry: Dictionary = main.save_data.get(DailyChallenge.store_name(main.daily_challenge), {}).get(String(main.daily_challenge.key), {})
		MetaStats.queue_daily(main.save_data, DailyChallenge.board_key(main.daily_challenge), int(entry.get("score", 0)), float(entry.get("seconds", 0.0)))
	MetaStats.flush(main.save_data, main.network)

static func _judge_achievements(main, winner: int) -> Array:
	var mode := ""
	if not main.local_ai_mode:
		mode = "online"
	elif not main.ghost_context.is_empty():
		mode = "ghost" if String(main.ghost_context.mode) == "ghost" else ""
	elif not main.daily_challenge.is_empty():
		mode = "daily"
	elif not main.draft_context.is_empty():
		mode = "draft"
	elif main.campaign_mode:
		mode = "campaign"
	elif not main.practice_used_tools:
		mode = "practice"
	if mode == "":
		return []
	var won: bool = winner == main.own_side
	if mode != "ghost" and mode != "draft":
		Achievements.record_outcome(main.save_data, won, not won and winner != 2)
	var snapshot: Dictionary = main.current_snapshot
	var reports: Array = snapshot.get("battle_report", [{}, {}])
	var own: Dictionary = reports[main.own_side] if reports.size() == 2 else {}
	return Achievements.evaluate(main.save_data, {
		"mode": mode, "won": won, "seconds": float(snapshot.get("elapsed", 0.0)),
		"own_base": float(snapshot.get("base_hp", [0.0, 0.0])[main.own_side]),
		"own_base_max": float(snapshot.get("base_max_hp", [500.0, 500.0])[main.own_side]),
		"structures_built": int(own.get("structures_built", 0)), "kills": int(own.get("kills", 0)),
		"curve": main.battle_curve, "own_side": main.own_side, "period": String(main.daily_challenge.get("period", "daily"))})

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
