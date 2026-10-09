extends SceneTree
## Helper-program jobs: planning, chunk leases, hand-backs, the main server doing the work itself, persistence.

const JobRunner = preload("res://scripts/jobs/JobRunner.gd")
const JobQueue = preload("res://scripts/jobs/JobQueue.gd")
const AssistHub = preload("res://scripts/jobs/AssistHub.gd")
const BattleReplay = preload("res://scripts/BattleReplay.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func _run_to_end(run) -> Dictionary:
	var guard := 0
	while not run.step(50) and guard < 100000:
		guard += 1
	return run.result()

func run() -> void:
	# Planning.
	var decks := JobRunner.all_unit_decks()
	var kinds := BattleModel.UNIT_STATS.size()
	check(decks.size() == kinds * (kinds - 1) * (kinds - 2) / 6 and decks.all(func(deck): return BattleModel._valid_deck(deck, BattleModel.UNIT_STATS)), "every legal three-unit deck is listed once (%d)" % decks.size())
	var plan := JobRunner.plan("balance", {"stage": 3, "matches": 45})
	check(bool(plan.ok) and plan.chunks.size() == decks.size() * 3, "45 matches per deck become three chunks (20, 20, 5)")
	var one_deck: Array = plan.chunks.filter(func(chunk): return chunk.units == decks[0])
	check(one_deck.map(func(chunk): return int(chunk.count)) == [20, 20, 5] and one_deck.map(func(chunk): return int(chunk.offset)) == [0, 20, 40], "chunks cover matches 0-19, 20-39, 40-44")
	check(not bool(JobRunner.plan("balance", {"decks": [["shield", "shield", "archer"]]}).ok) and not bool(JobRunner.plan("nonsense", {}).ok), "bad decks and unknown types are refused")
	check(not bool(JobRunner.plan("balance", {"matches": 200, "stage": 3, "decks": decks + decks + decks + decks + decks + decks}).ok), "an experiment bigger than the chunk limit is refused")
	check(JobRunner.plan("balance", {"stage": 99, "matches": 5000, "decks": [["shield", "archer", "healer"]]}).chunks.size() == 10, "stage and matches are clamped (200 matches in ten chunks)")
	check(not bool(JobRunner.plan("replay", {"texts": []}).ok) and not bool(JobRunner.plan("replay", {"texts": [5]}).ok) and int(JobRunner.plan("selftest", {"chunks": 4}).chunks.size()) == 4, "replay and self-test planning")

	# Running chunks is deterministic and offsets give different matches.
	var chunk := {"units": ["shield", "archer", "healer"], "structures": ["wall", "swamp", "turret"], "stage": 1, "offset": 0, "count": 2}
	var first := _run_to_end(JobRunner.new_run("balance", chunk))
	var again := _run_to_end(JobRunner.new_run("balance", chunk))
	check(JSON.stringify(first) == JSON.stringify(again) and int(first.matches) == 2, "the same chunk always gives the same result")
	var shifted := chunk.duplicate()
	shifted.offset = 40
	var other := _run_to_end(JobRunner.new_run("balance", shifted))
	check(int(other.matches) == 2 and (float(other.seconds) != float(first.seconds) or int(other.wins) != int(first.wins)), "a different offset plays different matches")
	var self_test := _run_to_end(JobRunner.new_run("selftest", {"value": 21}))
	check(int(self_test.value) == 42, "the self-test chunk answers")
	var model := BattleModel.new()
	var recorder := BattleReplay.Recorder.new(model, BattleReplay.DEFAULT_HZ, {}, {"mode": "quick"})
	for tick in 90:
		if tick == 0 and model.spawn_unit(0, "swordsman"):
			recorder.on_spawn(0, "swordsman")
		model.tick(1.0 / 30.0)
		recorder.on_tick()
	model.winner = 0
	var good := BattleReplay.to_share_text(recorder.finish(model))
	var verified := _run_to_end(JobRunner.new_run("replay", {"text": good}))
	check(bool(verified.valid) and bool(verified.ok), "a genuine replay verifies")
	check(not bool(_run_to_end(JobRunner.new_run("replay", {"text": "garbage"})).valid), "garbage is reported invalid")
	var combined := JobRunner.combine("replay", [{}, {}], [verified, {"valid": false, "ok": false}])
	check(int(combined.checked) == 2 and int(combined.ok) == 1 and combined.failed == [1], "replay results combine")

	# Leases, hand-backs and reclaiming.
	var queue := JobQueue.new()
	var submitted := queue.submit("selftest", {"chunks": 4}, "", "tester", 0.0)
	check(bool(submitted.ok) and queue.pending_count() == 4, "a job is queued as pending chunks")
	var a := queue.claim("a", ["selftest"], 1.0)
	var b := queue.claim("b", ["selftest"], 1.0)
	check(a.chunk == 0 and b.chunk == 1 and queue.claim("x", ["balance"], 1.0).is_empty(), "chunks go out in order and only to workers who may do them")
	check(queue.held_by("a") == 1 and queue.pending_count() == 2, "leased chunks are not pending")
	check(queue.expire(10.0) == 0 and queue.renew("a", 25.0) == 1, "a heartbeat renews the lease")
	check(queue.expire(40.0) == 1 and queue.held_by("a") == 1 and queue.held_by("b") == 0, "a silent worker loses its chunk, a heart-beating one keeps it")
	check(queue.complete(1, 1, {"value": 4}, 41.0) and not queue.complete(1, 1, {"value": 999}, 42.0), "the first result for a chunk wins")
	check(queue.release("a", 43.0) == 1 and queue.held_by("a") == 0, "saying goodbye hands the unfinished chunk back")
	var reclaimed := queue.claim("c", ["selftest"], 44.0)
	check(reclaimed.chunk == 0, "the handed-back chunk is picked up again")
	for index in [0, 1, 2, 3]:
		if queue.jobs[1].chunks[index].state != "done":
			queue.complete(1, index, {"value": (index + 1) * 2}, 50.0)
	check(queue.jobs[1].done and queue.drain_finished() == [1] and queue.drain_finished().is_empty(), "the job finishes once, with a notification")
	check(int(queue.result_of(1).sum) == 20 and queue.summary(1).done_chunks == 4, "the answer combines every chunk")
	var restored := JobQueue.new()
	restored.load_dict(JSON.parse_string(JSON.stringify(queue.to_dict())), 100.0)
	check(restored.jobs.has(1) and restored.jobs[1].done and int(restored.result_of(1).sum) == 20 and restored.next_id == 2, "a finished job survives a restart (through JSON)")
	var mid := JobQueue.new()
	mid.submit("selftest", {"chunks": 3}, "", "t", 0.0)
	mid.claim("w", ["selftest"], 1.0)
	mid.complete(1, 0, {"value": 2}, 2.0)
	mid.claim("w", ["selftest"], 3.0)
	var mid_copy := JobQueue.new()
	mid_copy.load_dict(JSON.parse_string(JSON.stringify(mid.to_dict())), 10.0)
	check(mid_copy.summary(1).done_chunks == 1 and mid_copy.summary(1).leased == 0 and mid_copy.pending_count() == 2, "after a restart finished chunks stay done and leases are void")
	check(JobQueue.new().claim("w", ["selftest"], 0.0).is_empty(), "an empty queue has nothing to give")

	# The hub: tokens, versions, capabilities and hand-over rules.
	var hub := AssistHub.new()
	hub.configure("", false, 0.0)
	check(not hub.enabled() and not bool(hub.hello(1, "x", AssistHub.PROTOCOL, [], 4, "assist", 0.0).ok), "switched off nothing is accepted")
	hub.configure("", true, 0.0)
	check(hub.enabled(), "there is no password: it is on by default")
	check(not bool(hub.hello(1, "보조1", 99, ["selftest"], 4, "assist", 0.0).ok), "a different protocol version is refused")
	check(not bool(hub.hello(1, "", AssistHub.PROTOCOL, ["selftest"], 4, "assist", 0.0).ok) and not bool(hub.hello(1, "x", AssistHub.PROTOCOL, ["selftest"], 4, "boss", 0.0).ok), "bad names and roles are refused")
	check(bool(hub.hello(1, "보조1", AssistHub.PROTOCOL, ["selftest", "nonsense"], 4, "assist", 0.0).ok) and hub.peers[1].capabilities == ["selftest"], "an accepted helper keeps only known capabilities")
	check(not bool(hub.submit(5, "selftest", {"chunks": 2}, "", 0.0).ok), "strangers cannot submit jobs")
	var job := hub.submit(1, "selftest", {"chunks": 3}, "점검", 1.0)
	check(bool(job.ok), "a connected helper can submit a job")
	var limits := AssistHub.new()
	limits.configure("", true, 0.0)
	# Light limits against a flood: helper PCs cannot order work, one peer has a few open jobs, the queue has a cap.
	limits.hello(1, "보조", AssistHub.PROTOCOL, ["selftest"], 2, "assist", 0.0)
	limits.hello(2, "도우미", AssistHub.PROTOCOL, ["selftest"], 2, "helper", 0.0)
	check(not bool(limits.submit(2, "selftest", {"chunks": 2}, "", 1.0).ok), "a helper PC cannot submit jobs")
	check(bool(limits.submit(1, "selftest", {"chunks": 1}, "", 1.0).ok) and bool(limits.submit(1, "selftest", {"chunks": 1}, "", 1.0).ok) and bool(limits.submit(1, "selftest", {"chunks": 1}, "", 1.0).ok), "up to three jobs may be open")
	check(not bool(limits.submit(1, "selftest", {"chunks": 1}, "", 1.0).ok), "a fourth open job is refused")
	var crowded := AssistHub.new()
	crowded.configure("", true, 0.0)
	for peer in AssistHub.MAX_HELPERS:
		crowded.hello(100 + peer, "pc%d" % peer, AssistHub.PROTOCOL, ["selftest"], 1, "helper", 0.0)
	check(not bool(crowded.hello(999, "late", AssistHub.PROTOCOL, ["selftest"], 1, "helper", 0.0).ok) and bool(crowded.hello(100, "pc0", AssistHub.PROTOCOL, ["selftest"], 1, "helper", 0.0).ok), "too many helpers are turned away but a known one may say hello again")
	var main_busy := AssistHub.new()
	main_busy.configure("", true, 0.0)
	# While a capable helper is connected the main server leaves the chunks to it for a while...
	var claimed := hub.claim(1, 2.0)
	check(claimed.chunk == 0 and hub.workers_for("selftest") == 1, "the helper gets the first chunk")
	for step in 60:
		hub.tick(3.0 + float(step) * 0.1, 0.1, false)
	check(hub.local_done_chunks == 0 and hub.queue.pending_count() == 2, "the main server waits for a capable helper")
	# ...but takes over once nobody picks them up in time, with no helper's help needed.
	for step in 400:
		hub.heartbeat(1, 10.0 + float(step) * 0.1)
		hub.tick(10.0 + float(step) * 0.1, 0.5, false)
	check(hub.local_done_chunks == 2 and hub.queue.pending_count() == 0, "after the patience time the main server does the waiting chunks itself (%d)" % hub.local_done_chunks)
	check(hub.chunk_done(1, 1, 0, {"value": 2}, 60.0), "the helper's result for its own chunk is accepted")
	check(hub.queue.jobs[1].done and hub.result_for(1).sum == 2 + 4 + 6, "the job is finished and its answer is combined from all three workers")
	var kinds_seen := hub.drain_events().map(func(event): return event.type)
	check(kinds_seen.has("joined") and kinds_seen.has("job_done") and kinds_seen.has("submitted"), "events describe what happened")

	# Nobody connected at all: the main server does everything alone, but not while it is busy.
	var alone := AssistHub.new()
	alone.configure("", true, 0.0)
	alone.queue.submit("selftest", {"chunks": 5}, "", "x", 0.0)
	for step in 10:
		alone.tick(float(step) * 0.5, 0.5, true)
	check(alone.local_done_chunks == 0, "a busy main server does not start jobs")
	for step in 100:
		alone.tick(10.0 + float(step) * 0.5, 0.5, false)
	check(alone.local_done_chunks == 5 and alone.queue.jobs[1].done, "an idle main server finishes the whole job without any helper")

	# Leaving: goodbye releases the chunks, a dropped connection does too, and the wrap-up request blocks new work.
	var leaving := AssistHub.new()
	leaving.configure("", true, 0.0)
	leaving.hello(7, "보조", AssistHub.PROTOCOL, ["selftest"], 2, "assist", 0.0)
	leaving.hello(8, "도우미", AssistHub.PROTOCOL, ["selftest"], 2, "helper", 0.0)
	leaving.queue.submit("selftest", {"chunks": 4}, "", "x", 0.0)
	leaving.claim(7, 1.0)
	leaving.claim(8, 1.0)
	check(leaving.request_wrap_up(8) and leaving.claim(8, 2.0).is_empty(), "a helper asked to wrap up gets no new chunk")
	check(leaving.goodbye(7, 3.0) == 1 and leaving.queue.pending_count() == 3 and not leaving.is_registered(7), "goodbye hands the unfinished chunk back")
	check(leaving.peer_gone(8, 4.0) == 1 and leaving.queue.pending_count() == 4, "a dropped connection does the same")
	leaving.hello(9, "조용한", AssistHub.PROTOCOL, ["selftest"], 2, "assist", 100.0)
	leaving.claim(9, 100.0)
	leaving.tick(100.0 + AssistHub.PEER_TIMEOUT + 1.0, 0.0, true)
	check(not leaving.is_registered(9) and leaving.queue.pending_count() == 4, "a helper that goes silent is dropped and its chunk comes back")

	# The main server hands out its own errands: every shared replay is re-checked, and a daily balance survey runs while a helper is online.
	var auto_dir := "user://job_auto_test"
	DirAccess.make_dir_recursive_absolute(auto_dir)
	var errand := AssistHub.new()
	errand.configure(auto_dir, true, 0.0)
	check(errand.audit_replay("ABC123", "not a replay", 0.0) and not errand.audit_replay("ABC123", "not a replay", 0.0), "a shared replay is queued for checking once")
	check(errand.queue.pending_count() == 1 and errand.queue.jobs[1].title.contains("ABC123") and errand.audit_counts().pending == 1, "it waits as a job in the queue")
	var clock := 1.0
	for step in 300:
		errand.tick(clock, 0.1, false, 1000.0)
		clock += 0.1
		if errand.audit_counts().pending == 0:
			break
	check(errand.audit_counts().failed == 1 and errand.auto.audit.ABC123 == "failed", "the main server checked it itself and the broken replay is flagged")
	check(errand.drain_events().any(func(event): return String(event.type) == "audit" and not bool(event.ok)), "the failure is reported")
	check(errand.queue.jobs.size() == 1, "without a helper no survey is started")
	var surveyor := AssistHub.new()
	surveyor.configure(auto_dir + "/s", true, 0.0)
	surveyor.hello(1, "보조", AssistHub.PROTOCOL, ["balance"], 4, "assist", 0.0)
	surveyor.tick(1.0, 0.0, true, 1000000.0)
	check(surveyor.queue.jobs.is_empty(), "no survey while the main server is busy with matches")
	surveyor.tick(1.0, 0.0, false, 1000000.0)
	check(surveyor.queue.jobs.size() == 1 and surveyor.queue.jobs[1].type == "balance" and surveyor.queue.jobs[1].title.contains("3단계") and int(surveyor.auto.next_stage) == 4, "a survey starts once a helper is online")
	surveyor.tick(1.0, 0.0, false, 1000000.0 + AssistHub.SURVEY_INTERVAL * 2.0)
	check(surveyor.queue.jobs.size() == 1, "and a new one waits until the last has finished")
	surveyor.dirty = true
	surveyor.save(10.0)
	var restarted := AssistHub.new()
	restarted.configure(auto_dir + "/s", true, 0.0)
	check(is_equal_approx(float(restarted.auto.last_survey), 1000000.0) and int(restarted.auto.next_stage) == 4, "the schedule survives a restart")
	for folder in [auto_dir + "/s/jobs", auto_dir + "/jobs"]:
		for file in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(folder + "/" + file)
		DirAccess.remove_absolute(folder)
	DirAccess.remove_absolute(auto_dir + "/s")
	DirAccess.remove_absolute(auto_dir)

	# Saved queue survives a restart of the main server.
	var dir := "user://job_queue_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var saver := AssistHub.new()
	saver.configure(dir, true, 0.0)
	saver.queue.submit("selftest", {"chunks": 3}, "저장", "x", 0.0)
	saver.dirty = true
	saver.save(5.0)
	var loaded := AssistHub.new()
	loaded.configure(dir, true, 100.0)
	check(loaded.queue.jobs.has(1) and loaded.queue.pending_count() == 3, "the queue is read back after a restart")
	for file in DirAccess.get_files_at(dir + "/jobs"):
		DirAccess.remove_absolute(dir + "/jobs/" + file)
	DirAccess.remove_absolute(dir + "/jobs")
	DirAccess.remove_absolute(dir)
	print("job_queue_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
