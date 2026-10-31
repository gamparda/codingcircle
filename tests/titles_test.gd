extends SceneTree
## Titles and roles: the hyper account binding, appointing super accounts, wearing titles, ranked titles and
## season awards, and the server's re-simulation of offline feats (campaign win, endless run) including
## tampered logs it must refuse.

const AccountStore = preload("res://scripts/accounts/AccountStore.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")
const TitleVerifier = preload("res://scripts/accounts/TitleVerifier.gd")
const TitleFlow = preload("res://scripts/net/TitleFlow.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
const WaveDirector = preload("res://scripts/run/WaveDirector.gd")

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	_roles_and_titles()
	_campaign_proof()
	_endless_proof()
	_cheats()
	print("titles_test checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _store() -> AccountStore:
	var store := AccountStore.new()
	store.configure("")
	return store

func _roles_and_titles() -> void:
	var store := _store()
	var hyper: String = store.create("sub-hyper", "감파르다", AccountStore.HYPER_CREATED_BEFORE - 100).id
	var other: String = store.create("sub-other", "손님", AccountStore.HYPER_CREATED_BEFORE - 50).id
	store.bind_hyper()
	check(store.role_of(hyper) == "hyper" and store.titles_of(hyper).has("founder"), "the existing 감파르다 account becomes the hyper account")
	check(store.appoint(other, "감파르다", false) == "forbidden", "only the hyper account appoints")
	check(store.appoint(hyper, "손님", true) == "" and store.role_of(other) == "super" and store.titles_of(other).has("warden"), "the hyper account appoints a super account by nickname")
	check(store.super_nicknames() == ["손님"], "super accounts are listed")
	check(store.appoint(hyper, "없는사람", true) == "no_account", "an unknown nickname is refused")
	check(store.appoint(hyper, "감파르다", false) == "forbidden" and store.role_of(hyper) == "hyper", "the hyper account cannot be dismissed")
	check(store.wear(other, "warden") == "" and store.worn_title(other) == "warden", "an owned title can be worn")
	check(store.appoint(hyper, "손님", false) == "" and store.role_of(other) == "" and not store.titles_of(other).has("warden") and store.worn_title(other) == "", "dismissal takes the role title off")
	check(store.wear(other, "ranked_1600") == "not_owned", "a title not owned cannot be worn")

	# A later sign-up under the hyper nickname never inherits the role.
	var late := _store()
	var newcomer: String = late.create("sub-late", "감파르다", AccountStore.HYPER_CREATED_BEFORE + 10).id
	late.bind_hyper()
	check(late.role_of(newcomer) == "", "an account created after the cutoff is not bound as hyper")
	# Renaming keeps the role on the account, not the name.
	check(store.rename(hyper, "새이름") == "" and store.role_of(hyper) == "hyper", "the role stays with the account after a rename")

	# Ranked titles.
	var player: String = store.create("sub-ranked", "랭커", 1).id
	for i in Titles.STREAK:
		store.record_ranked(player, 1000 + 25 * (i + 1), "wins")
	check(store.titles_of(player).has("ranked_streak") and store.titles_of(player).has("ranked_1200"), "a ten-win streak and a 1200 rating earn their titles")
	store.record_ranked(player, 1100, "losses")
	check(int(store.accounts[player].progress.streak) == 0, "a loss ends the streak")
	store.record_summons(player, Titles.NECRO_SUMMONS)
	check(store.titles_of(player).has("necro_lord"), "raising enough skeletons earns the hidden title")
	check(store.leaderboard(5).any(func(row): return row.has("title")), "leaderboard rows carry the worn title")
	# Season awards: the finished season's top ten.
	store.accounts[player].season = "2026-09"
	store.awarded_seasons = []
	store.award_seasons()
	check(store.titles_of(player).has("ranked_season_top") and store.awarded_seasons.has("2026-09"), "the top ten of a finished season get the season title")
	# Cheats hand out every title except the role ones.
	var given := store.grant_all(other)
	check(not given.has("founder") and given.has("endless_30"), "the title cheat gives the catalog without role titles")
	# Wire shape the client accepts.
	var state := {"role": "super", "owned": ["warden"], "worn": "warden", "supers": [], "error": "", "granted": [], "verified": ""}
	check(TitleFlow.valid_state(state), "a title state passes the client check")
	state.owned = ["made_up"]
	check(not TitleFlow.valid_state(state), "unknown titles are rejected")

func _run_job(kind: String, data: Variant) -> Dictionary:
	var job = TitleVerifier.create(kind, JSON.stringify(data), "acct", 2)
	var guard := 0
	while not job.step(200000) and guard < 10000:
		guard += 1
	return job.result

## Plays campaign stage 1 the way BattleFlow sets it up, with a simple scripted player, and records it.
func _campaign_replay() -> Dictionary:
	var model := BattleModel.new()
	model.configure_campaign_growth(0, 8)
	model.configure_deck(0, ["shield", "swordsman", "archer", "berserker"], ["wall", "turret", "generator", "swamp"])
	model.configure_deck(1, ServerAI.stage_unit_deck(1), ServerAI.stage_structure_deck(1))
	model.resources[1] = minf(BattleModel.MAX_RESOURCE, 45.0)
	model.configure_base_health(1, 320.0)
	var ai := ServerAI.new(1, 1)
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {"side": 1, "stage": 1}, {"mode": "campaign", "stage": 1})
	var order := ["shield", "swordsman", "archer", "berserker"]
	var step := 0
	while model.winner == -1 and recorder.ticks < 30 * 600:
		if recorder.ticks % 45 == 0:
			var kind: String = order[step % order.size()]
			if model.spawn_unit(0, kind):
				recorder.on_spawn(0, kind)
				step += 1
		ai.update(model, 1.0 / 30.0)
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	return recorder.finish(model)

func _campaign_proof() -> void:
	var replay := _campaign_replay()
	check(int(replay.result.winner) == 0, "the scripted player wins stage 1")
	var outcome := _run_job("campaign", replay)
	check(bool(outcome.get("ok")) and bool(outcome.get("won")) and int(outcome.get("stars", 0)) >= 1, "a real campaign win is verified (%s)" % str(outcome))
	var forged: Dictionary = replay.duplicate(true)
	forged.result.winner = 0
	forged.result.state_hash = "0".repeat(64)
	check(String(_run_job("campaign", forged).get("error")) == "mismatch", "a made-up result is refused")
	var weak: Dictionary = replay.duplicate(true)
	weak.setup.base_max_hp[1] = 10.0
	weak.setup.base_hp[1] = 10.0
	check(String(_run_job("campaign", weak).get("error")) == "mismatch", "a weakened opponent is refused")
	var puppet: Dictionary = replay.duplicate(true)
	puppet.commands.append({"t": int(puppet.result.ticks), "s": 1, "c": "spawn", "k": "swordsman"})
	check(String(_run_job("campaign", puppet).get("error")) == "mismatch", "commands for the AI side are refused")
	check(String(_run_job("campaign", {"nope": 1}).get("error")) == "invalid", "garbage is refused")

## Plays an endless run the way EndlessFlow does, saving and resuming once, and logs it.
func _endless_log(resume_at_wave: int) -> Dictionary:
	var units := ["shield", "swordsman", "archer", "berserker"]
	var structures := ["wall", "turret", "generator", "swamp"]
	var run_seed := 4242
	var segments: Array = []
	var saved := {}
	var resumed := false
	while true:
		var model := BattleModel.new()
		model.configure_deck(0, units, structures)
		var director := WaveDirector.new(run_seed + int(saved.get("wave", 1)) * 7919, int(saved.get("wave", 1)), saved.get("boons", []))
		director.setup(model)
		if not saved.is_empty():
			model.base_hp[0] = minf(float(model.base_max_hp[0]), float(saved.base_hp))
		var segment := {"start": {"wave": int(saved.get("wave", 1)), "boons": saved.get("boons", []).duplicate(), "base_hp": float(model.base_hp[0]) if saved.is_empty() else float(saved.base_hp), "seed": run_seed, "units": units, "structures": structures},
			"commands": [], "choices": [], "end": "", "ticks": 0}
		segments.append(segment)
		var cut := false
		while model.winner == -1 and segment.ticks < 30 * 1800:
			if director.awaiting_choice:
				var id: String = director.offers[0]
				director.choose(model, id)
				segment.choices.append({"t": segment.ticks, "id": id})
				if not resumed and director.wave == resume_at_wave:
					saved = {"wave": director.wave + 1, "boons": director.boons.duplicate(), "base_hp": float(model.base_hp[0])}
					segment.end = "save"
					resumed = true
					cut = true
					break
			if segment.ticks % 40 == 0:
				var kind: String = units[(segment.ticks / 40) % units.size()]
				if model.spawn_unit(0, kind):
					segment.commands.append({"t": segment.ticks, "c": "spawn", "k": kind})
			director.update(model, 1.0 / 30.0)
			model.tick(1.0 / 30.0)
			segment.ticks += 1
		if cut:
			continue
		segment.end = "end"
		return {"segments": segments, "waves": director.waves_cleared()}
	return {}

func _endless_proof() -> void:
	var log := _endless_log(2)
	var waves := int(log.waves)
	log.erase("waves")
	check(log.segments.size() == 2, "the run was saved and resumed once")
	var outcome := _run_job("endless", log)
	check(bool(outcome.get("ok")) and int(outcome.get("waves", -1)) == waves, "a resumed endless run is verified with its waves (%s vs %d)" % [str(outcome), waves])
	var stretched: Dictionary = log.duplicate(true)
	stretched.segments[1].start.base_hp = BattleModel.BASE_MAX_HP
	stretched.segments[1].start.wave = int(stretched.segments[1].start.wave) + 5
	check(String(_run_job("endless", stretched).get("error")) == "mismatch", "a resume that does not continue the save point is refused")
	var boosted: Dictionary = log.duplicate(true)
	boosted.segments[0].start.boons = ["war_drum"]
	check(String(_run_job("endless", boosted).get("error")) == "mismatch", "a run that starts with boons is refused")
	var store := _store()
	var id: String = store.create("sub-endless", "수비대", 1).id
	var earned := store.record_endless(id, 30, true, true)
	check(earned.has("endless_10") and earned.has("endless_30") and earned.has("endless_flawless") and earned.has("endless_melee"), "verified waves earn the endless titles")
	check(store.record_campaign(id, 8, 3, true).has("campaign_flawless"), "an untouched stage 8 win earns its title")

func _cheats() -> void:
	var Cheats = load("res://scripts/Cheats.gd")
	var model := BattleModel.new()
	check(Cheats.perform(model, 0, "resources") and model.cheats[0].has("resources"), "a toggle switches on")
	model.resources[0] = 0.0
	model.tick(1.0 / 30.0)
	check(is_equal_approx(float(model.resources[0]), model.resource_capacity(0)), "infinite resources refill every tick")
	Cheats.perform(model, 0, "castle")
	model.base_hp[0] = 10.0
	model.tick(1.0 / 30.0)
	check(float(model.base_hp[0]) == float(model.base_max_hp[0]), "an invincible castle heals every tick")
	check(not Cheats.perform(model, 0, "teleport"), "unknown cheats do nothing")
	Cheats.perform(model, 0, "win")
	model.tick(1.0 / 30.0)
	check(model.winner == 0, "instant win ends the battle for the cheater")
	var endless := BattleModel.new()
	WaveDirector.new(1).setup(endless)
	check(not Cheats.perform(endless, 0, "win"), "there is no base to win against in endless defense")
