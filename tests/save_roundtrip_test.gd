extends SceneTree

func _init() -> void:
	var data := SaveData.default_data()
	SaveData.record_campaign(data, 3, true, 60.0, 450.0)
	data.last_deck = 2
	data.settings.fps_limit = 144
	var loaded := SaveData.sanitize(JSON.parse_string(JSON.stringify(data)))
	var ok: bool = loaded.campaign_unlocked == 4 and loaded.last_deck == 2 and loaded.settings.fps_limit == 144 and loaded.campaign_records[2].best_stars == 3 and loaded.stats.ai_wins == 1
	print("SAVE_JSON_ROUNDTRIP preserved=", ok, " unlocked=", loaded.campaign_unlocked, " stars=", loaded.campaign_records[2].best_stars)
	quit(0 if ok else 1)
