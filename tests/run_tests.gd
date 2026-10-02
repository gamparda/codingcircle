extends SceneTree

var failures := 0
var checks := 0

func expect_true(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func expect_eq(actual, expected, message: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		printerr("FAIL: %s (actual=%s expected=%s)" % [message, actual, expected])

func _init() -> void:
	var BattleModel = load("res://scripts/BattleModel.gd")
	expect_true(BattleModel != null, "BattleModel script loads")
	if BattleModel == null:
		finish()
		return

	var model = BattleModel.new()
	var SaveData = load("res://scripts/SaveData.gd")
	expect_true(SaveData != null, "SaveData script loads")
	var Localization = load("res://scripts/Localization.gd")
	expect_true(Localization != null, "Localization script loads")
	if Localization != null:
		expect_eq(Localization.SUPPORTED_LOCALES, ["ko"], "Korean is the only supported locale")
		expect_true(Localization.catalog_is_complete(), "every locale contains the complete translation key set")
		expect_eq(Localization.normalize_locale("en_US"), "ko", "regional English locale resolves to English")
		expect_eq(Localization.normalize_locale("zh-Hans-CN"), "ko", "Simplified Chinese locale resolves correctly")
		expect_eq(Localization.normalize_locale("de_DE"), "ko", "unsupported system locale falls back to Korean")
		for locale in ["en", "fr", "zh_CN", "ru", "es"]:
			Localization.install(locale)
			expect_true(Localization.text("설정") == "설정", "%s translates a representative settings label" % locale)
			expect_true(Localization.text("선택 덱: %s  ·  온라인은 전용 서버 권한형  ·  AI는 완전 오프라인").contains("%s"), "%s preserves format placeholders" % locale)
		Localization.install("ko")
	var legacy_save: Dictionary = SaveData.default_data()
	expect_eq(legacy_save.settings.language, "ko", "new saves default to Korean")
	legacy_save.settings.language = "fr"
	expect_eq(SaveData.sanitize(legacy_save).settings.language, "ko", "selected language survives save sanitization")
	legacy_save.settings.language = "invalid"
	expect_eq(SaveData.sanitize(legacy_save).settings.language, "ko", "invalid saved language falls back safely")
	legacy_save.deck_presets[0] = {
		"name": "내 점프 덱",
		"units": ["shield", "archer", "healer"],
		"structures": ["jump_pad", "turret", "generator"],
	}
	var migrated_save: Dictionary = SaveData.sanitize(legacy_save)
	expect_eq(migrated_save.deck_presets[0].name, "내 점프 덱", "removed jump-pad migration preserves preset name")
	expect_true(not migrated_save.deck_presets[0].structures.has("jump_pad"), "removed jump pad is replaced during save migration")
	expect_true(migrated_save.deck_presets[0].structures.has("turret") and migrated_save.deck_presets[0].structures.has("generator"), "save migration preserves remaining custom structures")
	expect_true(BattleModel._valid_deck(migrated_save.deck_presets[0].structures, BattleModel.STRUCTURE_STATS), "migrated structure deck remains valid")
	model.resources[0] = 0.0
	expect_eq(model.spawn_unit(0, "swordsman"), false, "cannot spawn without resources")
	model.resources[0] = 100.0
	expect_eq(model.spawn_unit(0, "swordsman"), true, "spawns with enough resources")
	expect_eq(int(model.resources[0]), 70, "cost is deducted once")
	expect_eq(model.units.size(), 1, "exactly one unit is created")

	var income_before: float = model.resources[0]
	model.tick(1.0)
	expect_true(model.resources[0] > income_before, "resources regenerate")

	var duel = BattleModel.new()
	duel.resources = [100.0, 100.0]
	duel.spawn_unit(0, "swordsman")
	duel.spawn_unit(1, "swordsman")
	duel.units[0].x = 620.0
	duel.units[1].x = 650.0
	var hp_before: float = duel.units[1].hp
	duel.tick(0.01)
	expect_eq(duel.units[1].hp, hp_before, "newly engaged units wait for their first attack tick")
	duel.tick(float(duel.units[0].interval))
	expect_true(duel.units[1].hp < hp_before, "units attack enemies in range")
	var swordsman_stats: Dictionary = BattleModel.UNIT_STATS.swordsman
	var archer_stats: Dictionary = BattleModel.UNIT_STATS.archer
	expect_true(float(swordsman_stats.cost) >= 30.0, "swordsman is not underpriced")
	expect_true(float(swordsman_stats.damage) / float(swordsman_stats.interval) <= 8.0, "swordsman keeps the currently deployed DPS cap")
	expect_eq(int(BattleModel.UNIT_STATS.shield.hp), 400, "shield health is reduced moderately from 480")
	expect_true(
		(float(swordsman_stats.damage) / float(swordsman_stats.interval)) / float(swordsman_stats.cost)
		<= (float(archer_stats.damage) / float(archer_stats.interval)) / float(archer_stats.cost) * 1.6,
		"swordsman cost efficiency stays near other damage units"
	)
	expect_eq(int(BattleModel.UNIT_STATS.archer.range), 280, "archer keeps its established long range")
	expect_eq(int(BattleModel.UNIT_STATS.archer.damage), 15, "archer damage is reduced")
	expect_eq(float(BattleModel.UNIT_STATS.healer.damage), 0.0, "mage is a pure support unit")
	expect_eq(float(BattleModel.UNIT_STATS.healer.heal), 0.0, "mage has no healing")
	for kind in BattleModel.UNIT_STATS:
		expect_true(float(BattleModel.UNIT_STATS[kind].interval) >= 1.2, "%s respects the minimum attack/heal interval" % kind)
	expect_true(BattleModel.new().has_method("unit_stat_summary"), "unit stat summary API exists")
	if BattleModel.new().has_method("unit_stat_summary"):
		var stat_summary: String = BattleModel.unit_stat_summary("swordsman")
		expect_true(stat_summary.contains("체력") and stat_summary.contains("공격력") and stat_summary.contains("DPS") and stat_summary.contains("공격 간격") and stat_summary.contains("사거리") and stat_summary.contains("이동"), "unit stat summary exposes all combat stats")
	expect_true(BattleModel.new().has_method("battle_stat_summary"), "battle stat summary API exists")
	if BattleModel.new().has_method("battle_stat_summary"):
		var battle_summary: String = BattleModel.battle_stat_summary()
		expect_true(battle_summary.contains("방벽") and battle_summary.contains("늪") and not battle_summary.contains("점프대"), "battle stat summary exposes only active structures")
		expect_true(battle_summary.contains("기지 체력") and battle_summary.contains("자원") and not battle_summary.contains("제한시간"), "battle stat summary reflects unlimited battle duration")
		expect_true(battle_summary.contains("마법사"), "battle stat summary exposes the mage role")

	var structures = BattleModel.new()
	structures.resources[0] = 200.0
	expect_true(structures.place_structure(0, "wall", 500.0), "wall can be placed in own zone")
	expect_true(not structures.place_structure(0, "wall", 900.0), "wall cannot be placed in enemy zone")
	expect_true(not structures.place_structure(0, "swamp", 520.0), "v0.4 minimum structure spacing is enforced")
	expect_true(structures.place_structure(0, "swamp", 400.0), "swamp can be placed with valid spacing")
	expect_true(structures.place_structure(0, "turret", 300.0), "turret can be placed with valid spacing")
	expect_true(not structures.place_structure(0, "wall", 200.0), "structure limit is enforced")
	var placement_bounds = BattleModel.new()
	placement_bounds.resources = [200.0, 200.0]
	expect_true(placement_bounds.place_structure(0, "wall", BattleModel.BLUE_BUILD_MAX), "blue forward boundary scales with the map")
	var red_placement_bounds = BattleModel.new()
	red_placement_bounds.resources = [200.0, 200.0]
	expect_true(red_placement_bounds.place_structure(1, "wall", BattleModel.RED_BUILD_MIN), "red forward boundary scales with the map")
	expect_true(not placement_bounds.place_structure(0, "wall", BattleModel.BLUE_BUILD_MAX + 1.0), "blue cannot place beyond its boundary")
	expect_true(not placement_bounds.place_structure(1, "wall", BattleModel.RED_BUILD_MIN - 1.0), "red cannot place beyond its boundary")

	var base_rush = BattleModel.new()
	base_rush.resources[0] = 100.0
	base_rush.spawn_unit(0, "swordsman")
	base_rush.units[0].x = BattleModel.FIELD_RIGHT - 20.0
	base_rush.units[0].damage = 999.0
	base_rush.tick(float(base_rush.units[0].interval) + 0.01)
	expect_eq(base_rush.winner, 0, "destroying the enemy base ends the match")

	var mage_attack = BattleModel.new()
	mage_attack.resources = [150.0, 150.0]
	mage_attack.configure_deck(0, ["healer", "shield", "archer"], ["wall", "turret", "swamp"])
	mage_attack.spawn_unit(0, "healer")
	mage_attack.spawn_unit(1, "swordsman")
	mage_attack.units[0].x = 400.0
	mage_attack.units[1].x = 500.0
	var enemy_hp_before: float = mage_attack.units[1].hp
	var mage_x_before: float = mage_attack.units[0].x
	mage_attack.tick(float(mage_attack.units[0].interval) + 0.01)
	expect_eq(mage_attack.units[1].hp, enemy_hp_before, "mage never damages an enemy in range")
	expect_eq(mage_attack.units[0].x, mage_x_before, "mage stops instead of passing through an enemy")

	var mage_heal = BattleModel.new()
	mage_heal.resources[0] = 150.0
	mage_heal.configure_deck(0, ["healer", "shield", "archer"], ["wall", "turret", "swamp"])
	mage_heal.spawn_unit(0, "shield")
	mage_heal.spawn_unit(0, "healer")
	mage_heal.units[0].x = 400.0
	mage_heal.units[1].x = 400.0
	mage_heal.units[0].hp -= 50.0
	mage_heal.units[0].speed = 0.0
	var ally_hp_before: float = mage_heal.units[0].hp
	mage_heal.tick(0.01)
	expect_eq(mage_heal.units[0].hp, ally_hp_before, "mage never heals a wounded ally")
	expect_eq(mage_heal.support_attack_speed(mage_heal.units[0]), 1.03, "mage grants timed attack speed instead of healing")

	var mage_wall = BattleModel.new()
	mage_wall.resources = [150.0, 200.0]
	mage_wall.configure_deck(0, ["healer", "shield", "archer"], ["wall", "turret", "swamp"])
	mage_wall.spawn_unit(0, "healer")
	mage_wall.place_structure(1, "wall", 800.0)
	mage_wall.units[0].x = 680.0
	var wall_hp_before: float = mage_wall.structures[0].hp
	var wall_block_x: float = mage_wall.units[0].x
	mage_wall.tick(float(mage_wall.units[0].interval) + 0.01)
	expect_eq(mage_wall.structures[0].hp, wall_hp_before, "mage never damages an enemy wall")
	expect_eq(mage_wall.units[0].x, wall_block_x, "mage stops instead of passing through an enemy wall")

	var MatchRegistry = load("res://scripts/MatchRegistry.gd")
	expect_true(MatchRegistry != null, "MatchRegistry script loads")
	if MatchRegistry != null:
		var registry = MatchRegistry.new()
		expect_true(registry.create_room(11, "CAT234"), "server creates a coded room")
		expect_true(not registry.create_room(22, "CAT234"), "duplicate room codes are rejected")
		var paired: Dictionary = registry.join_room(22, "CAT234")
		expect_eq(paired.get(11), 0, "first player is assigned side 0")
		expect_eq(paired.get(22), 1, "second player is assigned side 1")
		expect_true(registry.has_match(11) and registry.has_match(22), "both peers belong to a server match")
		registry.remove_player(11)
		expect_true(not registry.has_match(11) and not registry.has_match(22), "disconnect removes the whole match")

	var ServerAI = load("res://scripts/ServerAI.gd")
	expect_true(ServerAI != null, "ServerAI script loads")
	if ServerAI != null:
		expect_eq(ServerAI.stage_name(1), "입문", "AI stage 1 has a label")
		expect_eq(ServerAI.stage_name(8), "최종전", "AI stage 10 has a label")
		var ai_model = BattleModel.new()
		ai_model.resources[1] = 150.0
		var ai = ServerAI.new(1, 5)
		ai.update(ai_model, 1.0)
		expect_true(ai_model.units.any(func(unit): return unit.side == 1), "AI spends server-owned resources to spawn a unit")
		ai_model.spawn_unit(0, "swordsman")
		ai_model.units.back().x = 1100.0
		ai.update(ai_model, 8.0)
		expect_true(ai_model.structures.any(func(structure): return structure.side == 1), "AI responds to a nearby threat with a legal defensive structure")

		var easy_model = BattleModel.new()
		var hard_model = BattleModel.new()
		easy_model.resources[1] = 150.0
		hard_model.resources[1] = 150.0
		var easy_ai = ServerAI.new(1, 1)
		var hard_ai = ServerAI.new(1, 8)
		easy_ai.update(easy_model, 0.1)
		hard_ai.update(hard_model, 0.1)
		var easy_unit: Dictionary = easy_model.units[0]
		var hard_unit: Dictionary = hard_model.units[0]
		expect_true(float(hard_unit.max_hp) / float(BattleModel.UNIT_STATS[hard_unit.kind].hp) > float(easy_unit.max_hp) / float(BattleModel.UNIT_STATS[easy_unit.kind].hp), "higher stages strengthen AI unit health relative to the selected role")
		expect_true(float(hard_unit.damage) / float(BattleModel.UNIT_STATS[hard_unit.kind].damage) > float(easy_unit.damage) / float(BattleModel.UNIT_STATS[easy_unit.kind].damage), "higher stages strengthen AI unit damage relative to the selected role")
		var long_model = BattleModel.new()
		long_model.elapsed = 240.0
		long_model.resources[1] = 0.0
		var long_ai = ServerAI.new(1, 1)
		long_ai.spawn_timer = 999.0
		long_ai.update(long_model, 1.0)
		expect_true(long_ai.long_battle_tier(long_model.elapsed) >= 2, "long battles increase the AI buff tier")
		expect_true(long_model.resources[1] > 0.0, "long-battle AI buff grants progressive income")

	var NetworkController = load("res://scripts/NetworkController.gd")
	expect_true(NetworkController != null, "NetworkController script loads")
	expect_eq(NetworkController.disconnect_message_for_state("connecting"), "서버 연결 실패", "failed handshake is not mislabeled as an established-server disconnect")
	expect_eq(NetworkController.disconnect_message_for_state("connected"), "서버와 연결이 끊어졌습니다", "established connection loss keeps the disconnect message")
	expect_eq(NetworkController.connection_candidates("ruellyya.kr", "211.176.222.145"), ["ruellyya.kr", "211.176.222.145"], "official IP fallback follows the domain candidate")
	expect_eq(NetworkController.connection_candidates("127.0.0.1", "127.0.0.1"), ["127.0.0.1"], "duplicate fallback candidates are removed")
	var network_policy = NetworkController.new()
	var active_model = BattleModel.new()
	expect_true(not network_policy.can_accept_rematch(active_model), "active matches reject rematch requests")
	active_model.winner = 0
	expect_true(network_policy.can_accept_rematch(active_model), "finished matches allow rematch requests")
	network_policy.accepting_players = false
	expect_true(not network_policy.can_accept_rematch(active_model), "server drain rejects rematch requests")

	var accepted_requests := 0
	for index in range(NetworkController.MAX_REQUESTS_PER_SECOND):
		if network_policy.can_process_request(7, 1000):
			accepted_requests += 1
	expect_eq(accepted_requests, NetworkController.MAX_REQUESTS_PER_SECOND, "RPC rate limit accepts the configured burst")
	expect_true(not network_policy.can_process_request(7, 1000), "RPC rate limit rejects excess requests")
	expect_true(network_policy.can_process_request(7, 2001), "RPC rate limit resets after one second")
	expect_true(NetworkController.is_safe_command_text("swordsman"), "known-size command text is accepted")
	expect_true(not NetworkController.is_safe_command_text("x".repeat(33)), "oversized command text is rejected")
	expect_true(not NetworkController.is_safe_command_text("wall&whoami"), "metacharacter command text is rejected")
	expect_true(NetworkController.is_safe_position(640.0), "finite structure position is accepted")
	expect_true(not NetworkController.is_safe_position(NAN), "NaN structure position is rejected")
	expect_true(not NetworkController.is_safe_position(INF), "infinite structure position is rejected")
	expect_true(NetworkController.is_valid_room_code("CAT234"), "six-character room codes are accepted")
	expect_true(not NetworkController.is_valid_room_code("cat123") and not NetworkController.is_valid_room_code("TOO-LONG"), "malformed room codes are rejected")
	var safe_snapshot: Dictionary = BattleModel.new().snapshot()
	expect_true(not safe_snapshot.has("heal_pads"), "authoritative snapshot keeps the deployed stable key set")
	expect_true(NetworkController.is_valid_snapshot(safe_snapshot), "authoritative model snapshot is accepted")
	var deployed_snapshot: Dictionary = safe_snapshot.duplicate(true)
	deployed_snapshot.erase("heal_pads")
	expect_true(NetworkController.is_valid_snapshot(deployed_snapshot), "client accepts the deployed server snapshot schema")
	var short_snapshot: Dictionary = safe_snapshot.duplicate(true)
	short_snapshot.resources = [10.0]
	expect_true(not NetworkController.is_valid_snapshot(short_snapshot), "short resource arrays are rejected")
	var unknown_unit_snapshot: Dictionary = safe_snapshot.duplicate(true)
	unknown_unit_snapshot.units = [{"id": 1, "side": 0, "kind": "intruder", "x": 1.0, "hp": 1.0, "max_hp": 1.0, "speed": 1.0}]
	expect_true(not NetworkController.is_valid_snapshot(unknown_unit_snapshot), "unknown unit kinds are rejected")
	var wrong_type_snapshot: Dictionary = safe_snapshot.duplicate(true)
	wrong_type_snapshot.units = [{"id": 1, "side": "zero", "kind": "shield", "x": 1.0, "hp": 1.0, "max_hp": 1.0, "speed": 1.0}]
	expect_true(not NetworkController.is_valid_snapshot(wrong_type_snapshot), "string match sides are rejected instead of coerced")
	var oversized_snapshot: Dictionary = safe_snapshot.duplicate(true)
	oversized_snapshot.units.resize(NetworkController.MAX_SNAPSHOT_UNITS + 1)
	expect_true(not NetworkController.is_valid_snapshot(oversized_snapshot), "oversized unit arrays are rejected")
	var extra_key_snapshot: Dictionary = safe_snapshot.duplicate(true)
	extra_key_snapshot.debug_payload = {"nested": [1, 2, 3]}
	expect_true(not NetworkController.is_valid_snapshot(extra_key_snapshot), "unexpected snapshot keys are rejected")
	var impossible_resource_snapshot: Dictionary = safe_snapshot.duplicate(true)
	impossible_resource_snapshot.resources = [-1.0, 999999.0]
	expect_true(not NetworkController.is_valid_snapshot(impossible_resource_snapshot), "implausible resource values are rejected")
	var endless_snapshot: Dictionary = safe_snapshot.duplicate(true)
	endless_snapshot.elapsed = 604801.0
	expect_true(NetworkController.is_valid_snapshot(endless_snapshot), "endless battles keep accepting snapshots beyond seven days")
	endless_snapshot.elapsed = INF
	expect_true(not NetworkController.is_valid_snapshot(endless_snapshot), "non-finite elapsed times remain rejected")
	var populated_model = BattleModel.new()
	expect_true(populated_model.spawn_unit(0, "swordsman"), "snapshot fixture unit spawns")
	var fractional_id_snapshot: Dictionary = populated_model.snapshot()
	fractional_id_snapshot.units[0].id = 1.5
	expect_true(not NetworkController.is_valid_snapshot(fractional_id_snapshot), "non-integral unit IDs are rejected")
	expect_true(NetworkController.is_valid_match_side(0) and NetworkController.is_valid_match_side(1), "valid match sides are accepted")
	expect_true(not NetworkController.is_valid_match_side(-1) and not NetworkController.is_valid_match_side(2), "invalid match sides are rejected")
	var admission_policy = NetworkController.new()
	expect_true(not admission_policy.allow_test_room_codes, "production servers reject client-selected room creation by default")
	admission_policy.accepting_players = false
	expect_true(not admission_policy.can_accept_room_request(), "draining servers reject room creation and joining")
	admission_policy.accepting_players = true
	expect_true(admission_policy.peer_should_disconnect_for_drain(500), "drain disconnects unmatched connected peers")
	for peer_id in range(1, 9):
		expect_true(admission_policy.register_peer_address(peer_id, "127.0.0.1"), "per-address admission accepts peer %d" % peer_id)
	expect_true(admission_policy.register_peer_address(99, "127.0.0.1"), "per-address admission allows peers beyond the former cap")
	admission_policy.release_peer_address(1)
	expect_true(admission_policy.register_peer_address(100, "127.0.0.1"), "per-address admission recovers after disconnect")
	for attempt in range(20):
		var reconnect_id := 1000 + attempt
		expect_true(admission_policy.register_peer_address(reconnect_id, "198.51.100.7"), "normal repeated reconnect %d is never temporarily blocked" % attempt)
		admission_policy.release_peer_address(reconnect_id)
	for match_id in range(40):
		admission_policy.models[match_id] = BattleModel.new()
	expect_true(admission_policy.can_create_match(), "active matches do not impose an admission quota")
	admission_policy.free()
	network_policy.free()

	var UpdateManager = load("res://scripts/UpdateManager.gd")
	expect_true(UpdateManager != null, "UpdateManager script loads")
	if UpdateManager != null:
		expect_true(UpdateManager.is_newer_version("0.3.2", "0.3.1"), "newer patch version is detected")
		expect_true(UpdateManager.is_newer_version("0.4.0", "0.3.99"), "newer minor version is detected")
		expect_true(not UpdateManager.is_newer_version("0.3.1", "0.3.1"), "same version is not an update")
		expect_true(not UpdateManager.is_newer_version("0.2.9", "0.3.0"), "older version is rejected")

	var Bootstrap = load("res://scripts/Bootstrap.gd")
	expect_true(Bootstrap != null, "Android content bootstrap script loads")
	if Bootstrap != null:
		expect_eq(Bootstrap.build_versions({"version": "0.5.0", "binary_version": "0.4.9"}), {"content": "0.5.0", "binary": "0.4.9"}, "Android bootstrap keeps bundled content and APK versions independent")
		expect_eq(Bootstrap.build_versions({"version": "0.4.8"}), {"content": "0.4.8", "binary": "0.4.8"}, "legacy bundled build metadata safely shares one version")
		expect_eq(Bootstrap.preferred_locale({"settings": {"language": "ru"}}, "en_US"), "ko", "bootstrap honors the saved language before drawing update UI")
		expect_eq(Bootstrap.preferred_locale({}, "zh-Hans-CN"), "ko", "bootstrap uses the supported system language on first launch")
		var content_manifest := {
			"version": "0.5.0",
			"android_binary_version": "0.4.4",
			"android_apk_url": "https://gamparda.github.io/codingcircle/CatWar.apk",
			"android_sha256": "b".repeat(64),
			"content_pack_version": "0.4.4",
			"content_pack_commit": "0123456789abcdef0123456789abcdef01234567",
			"content_pack_url": "https://gamparda.github.io/codingcircle/CatWarContent.pck",
			"content_pack_sha256": "a".repeat(64),
		}
		expect_true(Bootstrap.validate_content_manifest(content_manifest), "official signed-build content metadata is accepted")
		expect_eq(Bootstrap.manifest_android_binary_version(content_manifest), "0.4.4", "Android APK gating uses its independent binary version")
		expect_true(not Bootstrap.requires_apk_update(Bootstrap.manifest_android_binary_version(content_manifest), "0.4.4", "https://gamparda.github.io/codingcircle/CatWar.apk"), "a newer Windows installer version does not force an Android APK update")
		var legacy_binary_manifest: Dictionary = content_manifest.duplicate(true)
		legacy_binary_manifest.erase("android_binary_version")
		expect_eq(Bootstrap.manifest_android_binary_version(legacy_binary_manifest), "0.5.0", "legacy manifests fall back to the shared binary version")
		var untrusted_manifest: Dictionary = content_manifest.duplicate(true)
		untrusted_manifest.content_pack_url = "https://example.com/CatWarContent.pck"
		expect_true(not Bootstrap.validate_content_manifest(untrusted_manifest), "untrusted content pack origins are rejected")
		var missing_apk_manifest: Dictionary = content_manifest.duplicate(true)
		missing_apk_manifest.erase("android_apk_url")
		expect_true(not Bootstrap.validate_content_manifest(missing_apk_manifest), "new content manifests cannot omit APK replacement metadata")
		var untrusted_apk_manifest: Dictionary = content_manifest.duplicate(true)
		untrusted_apk_manifest.android_apk_url = "https://example.com/CatWar.apk"
		expect_true(not Bootstrap.validate_content_manifest(untrusted_apk_manifest), "APK replacement URL must use the official update origin")
		var invalid_apk_hash_manifest: Dictionary = content_manifest.duplicate(true)
		invalid_apk_hash_manifest.android_sha256 = "not-a-hash"
		expect_true(not Bootstrap.validate_content_manifest(invalid_apk_hash_manifest), "APK replacement metadata requires a valid SHA-256")
		expect_true(Bootstrap.should_install_content("0.4.5", "0.4.4", "a".repeat(40), "b".repeat(40)), "newer content versions are installed")
		expect_true(Bootstrap.should_install_content("0.4.4", "0.4.4", "a".repeat(40), "b".repeat(40)), "rebuilt content with a new commit is installed")
		expect_true(not Bootstrap.should_install_content("0.4.3", "0.4.4", "a".repeat(40), "b".repeat(40)), "older content packs never replace a newer version")
		expect_true(Bootstrap.PACK_BOOT_STABILITY_SECONDS >= 3.0, "new content packs must survive a stability window before rollback is disabled")
		expect_true(Bootstrap.requires_apk_update("0.4.5", "0.4.4", "https://gamparda.github.io/codingcircle/CatWar.apk"), "newer Android binary versions require an APK update message")
		expect_true(not Bootstrap.requires_apk_update("0.4.4", "0.4.4", "https://gamparda.github.io/codingcircle/CatWar.apk"), "same Android binary version does not require APK replacement")

	var Main = load("res://scripts/Main.gd")
	expect_true(Main != null, "Main script loads")
	expect_eq(Main.build_binary_version(), "0.4.18", "Korean-only release updates the native Android bootstrap")
	expect_eq(Main.build_version(), "0.6.3", "content pack version advances independently")
	expect_true(NetworkController.is_valid_room_code(Main.DEFAULT_SMOKE_ROOM_CODE), "default smoke room code follows production room-code rules")
	expect_true(Main.apk_update_required("Android", "0.4.4", "0.4.5"), "new content warns when it runs on an older Android APK")
	expect_true(not Main.apk_update_required("Android", "0.4.5", "0.4.5"), "matching Android APK and content versions do not warn")
	expect_true(not Main.apk_update_required("Windows", "0.4.4", "0.4.5"), "desktop content never shows the APK warning")
	expect_true(not Main.server_update_safe([], 1), "connected pre-room peers block server update safety")
	expect_true(Main.server_update_safe([], 0), "an idle disconnected server is safe to update")
	var active_server_model: RefCounted = BattleModel.new()
	expect_true(not Main.server_update_safe([active_server_model], 0), "an unfinished match blocks server update safety")
	active_server_model.winner = 0
	expect_true(Main.server_update_safe([active_server_model], 0), "finished matches no longer block server update safety")
	if Main != null:
		expect_eq(Main.OFFICIAL_SERVER_ADDRESS, "ruellyya.kr", "official server address is fixed")
		expect_eq(Main.OFFICIAL_SERVER_FALLBACK_ADDRESS, "211.176.222.145", "official server has a DNS-failure fallback address")
		expect_eq(Main.OFFICIAL_SERVER_LAN_ADDRESS, "192.168.0.4", "official server LAN route targets the dedicated Linux host")
		expect_eq(Main.official_connection_candidates(["192.168.0.3"]), ["211.176.222.145", "192.168.0.4", "ruellyya.kr"], "public server address is attempted before any guessed private route")
		expect_eq(Main.official_connection_candidates(PackedStringArray(["192.168.0.3"])), ["211.176.222.145", "192.168.0.4", "ruellyya.kr"], "runtime packed local-address lists retain the LAN fallback")
		expect_eq(Main.official_connection_candidates(["10.0.0.2"]), ["211.176.222.145", "ruellyya.kr"], "external clients try the direct game endpoint first")
		expect_eq(Main.OFFICIAL_SERVER_PORT, 7777, "official server port is fixed")
		expect_true(Main.smoke_connect_allowed(true, "127.0.0.1"), "exported smoke client may connect to loopback")
		expect_true(Main.smoke_connect_allowed(true, "127.0.0.2"), "exported fallback smoke may use another loopback address")
		expect_true(Main.smoke_connect_allowed(true, "dns-failure.invalid"), "exported fallback smoke may use the reserved non-resolving test domain")
		expect_true(Main.smoke_connect_allowed(true, "localhost"), "exported smoke client may connect to localhost")
		expect_true(Main.smoke_connect_allowed(true, "192.168.0.4"), "exported smoke client may verify the fixed LAN route to the dedicated server")
		expect_true(not Main.smoke_connect_allowed(true, "192.168.0.5"), "exported smoke client cannot target arbitrary private hosts")
		expect_true(not Main.smoke_connect_allowed(true, "example.com"), "smoke client cannot target external hosts")
		expect_true(not Main.smoke_connect_allowed(false, "127.0.0.1"), "normal clients cannot use smoke connect arguments")
		expect_true(Main.BATTLE_BGM is AudioStreamWAV, "provided WAV is imported as the battle BGM")
		expect_true(Main.BATTLE_BGM.get_length() > 13.0, "battle BGM contains the full supplied audio")

	var BattleView = load("res://scripts/BattleView.gd")
	expect_true(BattleView != null, "BattleView loads with animated unit textures")
	for role in ["tanker", "healer", "archer", "swordsman"]:
		for frame in range(6):
			var texture_path := "res://assets/units/animations/%s/walk_%d.png" % [role, frame]
			var texture = load(texture_path)
			expect_true(texture != null, "%s walk frame %d loads" % [role, frame])
			if texture != null:
				expect_true(texture.get_width() > 0 and texture.get_height() > 0, "%s walk frame %d has dimensions" % [role, frame])

	finish()

func finish() -> void:
	if failures == 0:
		print("PASS: %d checks" % checks)
		quit(0)
	else:
		printerr("FAILED: %d of %d checks" % [failures, checks])
		quit(1)
