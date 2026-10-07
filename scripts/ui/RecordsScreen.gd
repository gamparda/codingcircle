extends "res://scripts/ui/SubMenuFrame.gd"
## Personal record screen. Static layout is in scenes/ui/RecordsScreen.tscn.

func populate(save_data: Dictionary) -> void:
	var stats: Dictionary = save_data.stats
	var online_rate := 0.0 if int(stats.online_completed) == 0 else float(stats.online_wins) / float(stats.online_completed) * 100.0
	$Column/Summary.text = Localization.text("AI  ·  경기 %d  /  승 %d  /  패 %d  /  최고 캠페인 %02d  /  별 %d\n\n온라인  ·  완료 %d  /  승 %d  /  패 %d  /  무 %d  /  중단 %d  /  승률 %.1f%%") % [stats.ai_matches, stats.ai_wins, stats.ai_losses, stats.highest_campaign, stats.total_stars, stats.online_completed, stats.online_wins, stats.online_losses, stats.online_draws, stats.online_interrupted, online_rate]
	var lines: Array = []
	for stage in ServerAI.MAX_STAGE:
		var record: Dictionary = save_data.campaign_records[stage]
		lines.append(Localization.text("%02d %-5s  %s  도전 %d / 승 %d  최단 %.1f초  최고 기지 HP %d") % [stage + 1, ServerAI.stage_name(stage + 1), "★".repeat(record.best_stars) + "☆".repeat(3 - record.best_stars), record.attempts, record.wins, record.fastest_win, int(record.best_base_hp)])
	$Column/CampaignRecords.text = "\n".join(lines)
