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
	expect_true(float(BattleModel.UNIT_STATS.healer.damage) > 0.0, "mage can damage enemies")
	expect_true(float(BattleModel.UNIT_STATS.healer.heal) > 0.0, "mage can heal allies")
	for kind in BattleModel.UNIT_STATS:
		expect_true(float(BattleModel.UNIT_STATS[kind].interval) >= 1.2, "%s respects the minimum attack/heal interval" % kind)
	expect_true(BattleModel.new().has_method("unit_stat_summary"), "unit stat summary API exists")
	if BattleModel.new().has_method("unit_stat_summary"):
		var stat_summary: String = BattleModel.unit_stat_summary("swordsman")
		expect_true(stat_summary.contains("체력") and stat_summary.contains("공격력") and stat_summary.contains("DPS") and stat_summary.contains("공격 간격") and stat_summary.contains("사거리") and stat_summary.contains("이동"), "unit stat summary exposes all combat stats")
	expect_true(BattleModel.new().has_method("battle_stat_summary"), "battle stat summary API exists")
	if BattleModel.new().has_method("battle_stat_summary"):
		var battle_summary: String = BattleModel.battle_stat_summary()
		expect_true(battle_summary.contains("방벽") and battle_summary.contains("점프대") and battle_summary.contains("늪"), "battle stat summary exposes every structure")
		expect_true(battle_summary.contains("기지 체력") and battle_summary.contains("자원") and battle_summary.contains("제한시간"), "battle stat summary exposes global combat rules")
		expect_true(battle_summary.contains("마법사"), "battle stat summary exposes the mage role")

	var structures = BattleModel.new()
	structures.resources[0] = 200.0
	expect_true(structures.place_structure(0, "wall", 500.0), "wall can be placed in own zone")
	expect_true(not structures.place_structure(0, "wall", 900.0), "wall cannot be placed in enemy zone")
	expect_true(not structures.place_structure(0, "swamp", 520.0), "v0.4 minimum structure spacing is enforced")
	expect_true(structures.place_structure(0, "swamp", 400.0), "swamp can be placed with valid spacing")
	expect_true(structures.place_structure(0, "jump_pad", 300.0), "jump pad can be placed with valid spacing")
	expect_true(not structures.place_structure(0, "wall", 200.0), "structure limit is enforced")
	var placement_bounds = BattleModel.new()
	placement_bounds.resources = [200.0, 200.0]
	expect_true(placement_bounds.place_structure(0, "wall", 610.0), "blue placement boundary moves 10 units toward center")
	var red_placement_bounds = BattleModel.new()
	red_placement_bounds.resources = [200.0, 200.0]
	expect_true(red_placement_bounds.place_structure(1, "wall", 670.0), "red placement boundary moves 10 units toward center")
	expect_true(not placement_bounds.place_structure(0, "wall", 611.0), "blue cannot place beyond its reduced boundary")
	expect_true(not placement_bounds.place_structure(1, "wall", 669.0), "red cannot place beyond its reduced boundary")

	var base_rush = BattleModel.new()
	base_rush.resources[0] = 100.0
	base_rush.spawn_unit(0, "swordsman")
	base_rush.units[0].x = 1170.0
	base_rush.units[0].damage = 999.0
	base_rush.tick(float(base_rush.units[0].interval) + 0.01)
	expect_eq(base_rush.winner, 0, "destroying the enemy base ends the match")

	var mage_attack = BattleModel.new()
	mage_attack.resources = [150.0, 150.0]
	mage_attack.configure_deck(0, ["healer", "shield", "archer"], ["wall", "jump_pad", "swamp"])
	mage_attack.spawn_unit(0, "healer")
	mage_attack.spawn_unit(1, "swordsman")
	mage_attack.units[0].x = 400.0
	mage_attack.units[1].x = 500.0
	var enemy_hp_before: float = mage_attack.units[1].hp
	var mage_x_before: float = mage_attack.units[0].x
	mage_attack.tick(float(mage_attack.units[0].interval) + 0.01)
	expect_true(mage_attack.units[1].hp < enemy_hp_before, "mage damages an enemy in range")
	expect_eq(mage_attack.units[0].x, mage_x_before, "mage stops instead of passing through an enemy")

	var mage_heal = BattleModel.new()
	mage_heal.resources[0] = 150.0
	mage_heal.configure_deck(0, ["healer", "shield", "archer"], ["wall", "jump_pad", "swamp"])
	mage_heal.spawn_unit(0, "shield")
	mage_heal.spawn_unit(0, "healer")
	mage_heal.units[0].x = 400.0
	mage_heal.units[1].x = 400.0
	mage_heal.units[0].hp -= 50.0
	var ally_hp_before: float = mage_heal.units[0].hp
	mage_heal.tick(float(mage_heal.units[1].interval) + 0.01)
	expect_true(mage_heal.units[0].hp > ally_hp_before, "mage heals a wounded ally in range")
	expect_true(mage_heal.units[0].hp <= mage_heal.units[0].max_hp, "mage healing never exceeds maximum health")

	var mage_wall = BattleModel.new()
	mage_wall.resources = [150.0, 200.0]
	mage_wall.configure_deck(0, ["healer", "shield", "archer"], ["wall", "jump_pad", "swamp"])
	mage_wall.spawn_unit(0, "healer")
	mage_wall.place_structure(1, "wall", 680.0)
	mage_wall.units[0].x = 560.0
	var wall_hp_before: float = mage_wall.structures[0].hp
	var wall_block_x: float = mage_wall.units[0].x
	mage_wall.tick(float(mage_wall.units[0].interval) + 0.01)
	expect_true(mage_wall.structures[0].hp < wall_hp_before, "mage damages an enemy wall in range")
	expect_eq(mage_wall.units[0].x, wall_block_x, "mage stops instead of passing through an enemy wall")

	var MatchRegistry = load("res://scripts/MatchRegistry.gd")
	expect_true(MatchRegistry != null, "MatchRegistry script loads")
	if MatchRegistry != null:
		var registry = MatchRegistry.new()
		expect_eq(registry.add_player(11), {}, "first player waits")
		var paired: Dictionary = registry.add_player(22)
		expect_eq(paired.get(11), 0, "first player is assigned side 0")
		expect_eq(paired.get(22), 1, "second player is assigned side 1")
		expect_true(registry.has_match(11) and registry.has_match(22), "both peers belong to a server match")
		registry.remove_player(11)
		expect_true(not registry.has_match(11) and not registry.has_match(22), "disconnect removes the whole match")

	var ServerAI = load("res://scripts/ServerAI.gd")
	expect_true(ServerAI != null, "ServerAI script loads")
	if ServerAI != null:
		expect_eq(ServerAI.stage_name(1), "입문", "AI stage 1 has a label")
		expect_eq(ServerAI.stage_name(10), "최종전", "AI stage 10 has a label")
		var ai_model = BattleModel.new()
		ai_model.resources[1] = 150.0
		var ai = ServerAI.new(1, 5)
		ai.update(ai_model, 1.0)
		expect_true(ai_model.units.any(func(unit): return unit.side == 1), "AI spends server-owned resources to spawn a unit")
		ai.update(ai_model, 8.0)
		expect_true(ai_model.structures.any(func(structure): return structure.side == 1), "unlocked AI stages place structures through normal game rules")

		var easy_model = BattleModel.new()
		var hard_model = BattleModel.new()
		easy_model.resources[1] = 150.0
		hard_model.resources[1] = 150.0
		var easy_ai = ServerAI.new(1, 1)
		var hard_ai = ServerAI.new(1, 10)
		easy_ai.update(easy_model, 0.1)
		hard_ai.update(hard_model, 0.1)
		expect_true(float(hard_model.units[0].max_hp) > float(easy_model.units[0].max_hp), "higher stages strengthen AI unit health")
		expect_true(float(hard_model.units[0].damage) > float(easy_model.units[0].damage), "higher stages strengthen AI unit damage")

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
	var populated_model = BattleModel.new()
	expect_true(populated_model.spawn_unit(0, "swordsman"), "snapshot fixture unit spawns")
	var fractional_id_snapshot: Dictionary = populated_model.snapshot()
	fractional_id_snapshot.units[0].id = 1.5
	expect_true(not NetworkController.is_valid_snapshot(fractional_id_snapshot), "non-integral unit IDs are rejected")
	expect_true(NetworkController.is_valid_match_side(0) and NetworkController.is_valid_match_side(1), "valid match sides are accepted")
	expect_true(not NetworkController.is_valid_match_side(-1) and not NetworkController.is_valid_match_side(2), "invalid match sides are rejected")
	var admission_policy = NetworkController.new()
	for peer_id in range(1, NetworkController.MAX_CONNECTIONS_PER_ADDRESS + 1):
		expect_true(admission_policy.register_peer_address(peer_id, "127.0.0.1"), "per-address admission accepts peer %d" % peer_id)
	expect_true(not admission_policy.register_peer_address(99, "127.0.0.1"), "per-address admission rejects excess peers")
	admission_policy.release_peer_address(1)
	expect_true(admission_policy.register_peer_address(99, "127.0.0.1"), "per-address admission recovers after disconnect")
	for strike in range(NetworkController.EARLY_DISCONNECT_LIMIT):
		admission_policy.record_early_disconnect("198.51.100.7", 5000 + strike)
	expect_true(admission_policy.is_address_temporarily_blocked("198.51.100.7", 6000), "repeated early disconnects trigger a temporary block")
	expect_true(not admission_policy.is_address_temporarily_blocked("198.51.100.7", 5000 + NetworkController.ABUSE_BLOCK_MSEC + 100), "temporary connection block expires")
	admission_policy.mark_server_forced_disconnect(200)
	expect_true(not admission_policy.should_penalize_disconnect(200, 1000, 2000), "server-forced orphan disconnect is not penalized")
	expect_true(admission_policy.should_penalize_disconnect(201, 1000, 2000), "voluntary quick disconnect is penalized")
	for match_id in range(NetworkController.MAX_ACTIVE_MATCHES):
		admission_policy.models[match_id] = BattleModel.new()
	expect_true(not admission_policy.can_create_match(), "active match cap prevents model exhaustion")
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
		var content_manifest := {
			"content_pack_version": "0.4.4",
			"content_pack_commit": "0123456789abcdef0123456789abcdef01234567",
			"content_pack_url": "https://gamparda.github.io/codingcircle/CatWarContent.pck",
			"content_pack_sha256": "a".repeat(64),
		}
		expect_true(Bootstrap.validate_content_manifest(content_manifest), "official signed-build content metadata is accepted")
		var untrusted_manifest: Dictionary = content_manifest.duplicate(true)
		untrusted_manifest.content_pack_url = "https://example.com/CatWarContent.pck"
		expect_true(not Bootstrap.validate_content_manifest(untrusted_manifest), "untrusted content pack origins are rejected")
		expect_true(Bootstrap.should_install_content("0.4.5", "0.4.4", "a".repeat(40), "b".repeat(40)), "newer content versions are installed")
		expect_true(Bootstrap.should_install_content("0.4.4", "0.4.4", "a".repeat(40), "b".repeat(40)), "rebuilt content with a new commit is installed")
		expect_true(not Bootstrap.should_install_content("0.4.3", "0.4.4", "a".repeat(40), "b".repeat(40)), "older content packs never replace a newer version")

	var Main = load("res://scripts/Main.gd")
	expect_true(Main != null, "Main script loads")
	if Main != null:
		expect_eq(Main.OFFICIAL_SERVER_ADDRESS, "ruellyya.kr", "official server address is fixed")
		expect_eq(Main.OFFICIAL_SERVER_FALLBACK_ADDRESS, "211.176.222.145", "official server has a DNS-failure fallback address")
		expect_eq(Main.OFFICIAL_SERVER_LAN_ADDRESS, "192.168.0.4", "official server LAN route targets the dedicated Linux host")
		expect_eq(Main.official_connection_candidates(["192.168.0.3"]), ["192.168.0.4", "ruellyya.kr", "211.176.222.145"], "same-LAN clients try the dedicated server private route first")
		expect_eq(Main.official_connection_candidates(PackedStringArray(["192.168.0.3"])), ["192.168.0.4", "ruellyya.kr", "211.176.222.145"], "runtime packed local-address lists use the LAN route")
		expect_eq(Main.official_connection_candidates(["10.0.0.2"]), ["ruellyya.kr", "211.176.222.145"], "external clients keep domain and public-IP candidates")
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
