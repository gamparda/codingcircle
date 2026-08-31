class_name SaveData
extends RefCounted

const SAVE_VERSION := 1
const SAVE_PATH := "user://catwar_save.json"
const WINDOW_SIZES := ["1280x720", "1600x900", "1920x1080"]
const FPS_LIMITS := [30, 60, 120, 144, 240]
const CAMPAIGN_TARGETS := [
	{"time": 90.0, "base_hp": 400.0}, {"time": 100.0, "base_hp": 390.0},
	{"time": 110.0, "base_hp": 380.0}, {"time": 120.0, "base_hp": 365.0},
	{"time": 130.0, "base_hp": 350.0}, {"time": 145.0, "base_hp": 335.0},
	{"time": 160.0, "base_hp": 320.0}, {"time": 180.0, "base_hp": 300.0},
	{"time": 210.0, "base_hp": 280.0}, {"time": 240.0, "base_hp": 250.0},
]

static func _record() -> Dictionary:
	return {"cleared": false, "best_stars": 0, "fastest_win": 0.0, "best_base_hp": 0.0, "attempts": 0, "wins": 0}

static func _preset(name: String, units: Array, structures: Array) -> Dictionary:
	return {"name": name, "units": units, "structures": structures}

static func default_data() -> Dictionary:
	var campaign_records: Array = []
	for _stage in 10:
		campaign_records.append(_record())
	return {
		"save_version": SAVE_VERSION,
		"campaign_unlocked": 1,
		"campaign_records": campaign_records,
		"deck_presets": [
			_preset("덱 1", ["shield", "archer", "healer"], ["wall", "turret", "generator"]),
			_preset("덱 2", ["swordsman", "archer", "healer"], ["wall", "swamp", "turret"]),
			_preset("덱 3", ["shield", "swordsman", "archer"], ["wall", "jump_pad", "swamp"]),
		],
		"last_deck": 0,
		"settings": {
			"master_volume": 0.8, "bgm_volume": 0.7, "sfx_volume": 0.8, "muted": false,
			"window_size": "1280x720", "fullscreen": true, "vsync": true, "fps_limit": 60,
			"damage_numbers": true, "screen_shake": true, "battle_effects": true, "effect_intensity": 0.65,
		},
		"stats": {
			"ai_matches": 0, "ai_wins": 0, "ai_losses": 0, "highest_campaign": 0, "total_stars": 0,
			"online_completed": 0, "online_wins": 0, "online_losses": 0, "online_draws": 0, "online_interrupted": 0,
		},
	}

static func sanitize(raw: Variant) -> Dictionary:
	var clean := default_data()
	if not raw is Dictionary:
		return clean
	if raw.get("save_version") is int:
		clean.save_version = clampi(int(raw.save_version), 1, SAVE_VERSION)
	if raw.get("campaign_unlocked") is int:
		clean.campaign_unlocked = clampi(int(raw.campaign_unlocked), 1, 10)
	if raw.get("last_deck") is int and int(raw.last_deck) >= 0 and int(raw.last_deck) < 3:
		clean.last_deck = int(raw.last_deck)
	if raw.get("campaign_records") is Array:
		for index in min(10, raw.campaign_records.size()):
			if raw.campaign_records[index] is Dictionary:
				var source: Dictionary = raw.campaign_records[index]
				var record: Dictionary = clean.campaign_records[index]
				if source.get("cleared") is bool: record.cleared = source.cleared
				if source.get("best_stars") is int: record.best_stars = clampi(source.best_stars, 0, 3)
				if source.get("fastest_win") is int or source.get("fastest_win") is float: record.fastest_win = max(0.0, float(source.fastest_win))
				if source.get("best_base_hp") is int or source.get("best_base_hp") is float: record.best_base_hp = clamp(float(source.best_base_hp), 0.0, 500.0)
				if source.get("attempts") is int: record.attempts = max(0, int(source.attempts))
				if source.get("wins") is int: record.wins = clampi(int(source.wins), 0, int(record.attempts))
	if raw.get("deck_presets") is Array and raw.deck_presets.size() == 3:
		for index in 3:
			var preset = raw.deck_presets[index]
			if preset is Dictionary and preset.get("units") is Array and preset.get("structures") is Array:
				if BattleModel._valid_deck(preset.units, BattleModel.UNIT_STATS) and BattleModel._valid_deck(preset.structures, BattleModel.STRUCTURE_STATS):
					clean.deck_presets[index] = {"name": String(preset.get("name", "덱 %d" % (index + 1))).left(20), "units": preset.units.duplicate(), "structures": preset.structures.duplicate()}
	if raw.get("settings") is Dictionary:
		for key in ["master_volume", "bgm_volume", "sfx_volume"]:
			if raw.settings.get(key) is int or raw.settings.get(key) is float:
				clean.settings[key] = clamp(float(raw.settings[key]), 0.0, 1.0)
		if raw.settings.get("effect_intensity") is int or raw.settings.get("effect_intensity") is float:
			clean.settings.effect_intensity = clamp(float(raw.settings.effect_intensity), 0.2, 1.0)
		if raw.settings.get("window_size") is String and WINDOW_SIZES.has(String(raw.settings.window_size)):
			clean.settings.window_size = String(raw.settings.window_size)
		if raw.settings.get("fps_limit") is int and FPS_LIMITS.has(int(raw.settings.fps_limit)):
			clean.settings.fps_limit = int(raw.settings.fps_limit)
		for key in ["muted", "fullscreen", "vsync", "damage_numbers", "screen_shake", "battle_effects"]:
			if raw.settings.get(key) is bool:
				clean.settings[key] = raw.settings[key]
	if raw.get("stats") is Dictionary:
		for key in clean.stats.keys():
			if raw.stats.get(key) is int:
				clean.stats[key] = max(0, int(raw.stats[key]))
	return clean

static func load_data() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return default_data()
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return default_data()
	var parsed = JSON.parse_string(file.get_as_text())
	return sanitize(parsed)

static func save_data(data: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(sanitize(data), "\t"))
	return true

static func campaign_stars(stage: int, won: bool, elapsed: float, remaining_base_hp: float) -> int:
	if not won:
		return 0
	var target: Dictionary = CAMPAIGN_TARGETS[clampi(stage, 1, 10) - 1]
	var stars := 1
	if remaining_base_hp >= float(target.base_hp):
		stars = 2
	if stars == 2 and elapsed <= float(target.time):
		stars = 3
	return stars

static func record_campaign(data: Dictionary, stage: int, won: bool, elapsed: float, remaining_base_hp: float) -> int:
	var index := clampi(stage, 1, 10) - 1
	var record: Dictionary = data.campaign_records[index]
	record.attempts += 1
	if won:
		record.wins += 1
		record.cleared = true
		var stars := campaign_stars(stage, true, elapsed, remaining_base_hp)
		record.best_stars = max(int(record.best_stars), stars)
		record.fastest_win = elapsed if float(record.fastest_win) <= 0.0 else min(float(record.fastest_win), elapsed)
		record.best_base_hp = max(float(record.best_base_hp), remaining_base_hp)
		data.campaign_unlocked = max(int(data.campaign_unlocked), min(10, stage + 1))
		data.stats.highest_campaign = max(int(data.stats.highest_campaign), stage)
	data.stats.ai_matches += 1
	data.stats.ai_wins += 1 if won else 0
	data.stats.ai_losses += 0 if won else 1
	var total := 0
	for stage_record in data.campaign_records:
		total += int(stage_record.best_stars)
	data.stats.total_stars = total
	return int(record.best_stars)
