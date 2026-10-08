extends RefCounted
## The main server's side of the helper programs: who is connected, what they may do, and the job queue. The main server
## is always able to do the work itself (at low priority, so matches and the lobby are never slowed down); assist servers
## and helper PCs only make it faster. Nothing here depends on a helper being online.

const JobRunner = preload("res://scripts/jobs/JobRunner.gd")
const JobQueue = preload("res://scripts/jobs/JobQueue.gd")
const RoomSessions = preload("res://scripts/RoomSessions.gd")
const ServerStats = preload("res://scripts/ServerStats.gd")

const PROTOCOL := 2
## There is no password: anyone who can reach the server may help. These limits keep a stranger from flooding it.
const MAX_HELPERS := 32
const MAX_OPEN_JOBS_PER_PEER := 3
const MAX_QUEUED_CHUNKS := 6000
const PATIENCE_SECONDS := 20.0 # how long a chunk waits for a helper before the main server does it itself
const PEER_TIMEOUT := 30.0 # a helper silent for this long is dropped (its chunks come back through the lease)
const LOCAL_SHARE := 0.25 # share of one core the main server may spend on jobs
const LOCAL_WORKER := "main"
const MAX_CREDIT_MSEC := 100.0
const SAVE_INTERVAL := 5.0

var queue := JobQueue.new()
var accepting := true
var dir := ""
var peers: Dictionary = {} # peer id -> {name, capabilities, cores, role, seen, wrapping}
var events: Array = []
var local_run = null
var local_ref := {}
var local_credit := 0.0
var local_done_chunks := 0
var results: Dictionary = {}
var dirty := false
var last_save := -1000.0

## `allow` false (environment CATWAR_ASSIST=off) switches the whole helper system off.
func configure(directory: String, allow: bool = true, now: float = 0.0) -> void:
	accepting = allow
	dir = "" if directory.is_empty() else directory.path_join("jobs")
	if not dir.is_empty():
		DirAccess.make_dir_recursive_absolute(dir)
		queue.load_dict(ServerStats.read_json(dir.path_join("queue.json")), now)
	dirty = false

func enabled() -> bool:
	return accepting

## {"ok", "message"}. `role` is "assist" (a server program) or "helper" (a player's game client).
func hello(peer: int, name: String, version: int, capabilities: Array, cores: int, role: String, now: float) -> Dictionary:
	if not enabled():
		return {"ok": false, "message": "이 서버는 보조 프로그램을 받지 않습니다."}
	if peers.size() >= MAX_HELPERS and not peers.has(peer):
		return {"ok": false, "message": "연결된 도우미가 너무 많습니다."}
	if version != PROTOCOL:
		return {"ok": false, "message": "프로그램 버전이 맞지 않습니다. 같은 버전으로 업데이트해 주세요."}
	if not RoomSessions.safe_text(name, 24) or not role in ["assist", "helper"]:
		return {"ok": false, "message": "이름이 올바르지 않습니다."}
	var allowed: Array = capabilities.filter(func(entry): return entry is String and JobRunner.CAPABILITIES.has(entry))
	peers[peer] = {"name": name.strip_edges(), "capabilities": allowed, "cores": clampi(cores, 1, 256), "role": role, "seen": now, "wrapping": false}
	events.append({"type": "joined", "name": name.strip_edges(), "role": role, "capabilities": allowed})
	return {"ok": true, "message": "연결되었습니다."}

func is_registered(peer: int) -> bool:
	return peers.has(peer)

func worker_id(peer: int) -> String:
	return "peer:%d" % peer

## How many connected helpers can do this kind of job (and are not winding down).
func workers_for(type: String) -> int:
	var capability := JobRunner.capability_for(type)
	var count := 0
	for peer in peers:
		if not bool(peers[peer].wrapping) and peers[peer].capabilities.has(capability):
			count += 1
	return count

func claim(peer: int, now: float) -> Dictionary:
	if not peers.has(peer) or bool(peers[peer].wrapping):
		return {}
	var assignment := queue.claim(worker_id(peer), peers[peer].capabilities, now)
	if not assignment.is_empty():
		dirty = true
		events.append({"type": "assigned", "name": peers[peer].name, "job": assignment.job, "chunk": assignment.chunk})
	return assignment

func heartbeat(peer: int, now: float) -> void:
	if peers.has(peer):
		peers[peer].seen = now
		queue.renew(worker_id(peer), now)

func chunk_done(peer: int, job_id: int, chunk_index: int, result: Dictionary, now: float) -> bool:
	if not peers.has(peer):
		return false
	peers[peer].seen = now
	var accepted := queue.complete(job_id, chunk_index, result, now)
	if accepted:
		dirty = true
		events.append({"type": "chunk_done", "name": peers[peer].name, "job": job_id, "chunk": chunk_index})
		_collect_finished(now)
	return accepted

## "Wrap it up": the helper sends what it finished (via chunk_done) and then says goodbye; the rest returns to the pool
## and the main server (or another helper) decides who does it.
func goodbye(peer: int, now: float) -> int:
	if not peers.has(peer):
		return 0
	var released := queue.release(worker_id(peer), now)
	events.append({"type": "left", "name": peers[peer].name, "released": released})
	peers.erase(peer)
	dirty = true
	return released

## A helper's connection dropped: same as saying goodbye without the courtesy.
func peer_gone(peer: int, now: float) -> int:
	return goodbye(peer, now)

## The main server asks a helper to stop taking work and finish up (used for rolling updates).
func request_wrap_up(peer: int) -> bool:
	if not peers.has(peer):
		return false
	peers[peer].wrapping = true
	return true

func submit(peer: int, type: String, params: Dictionary, title: String, now: float) -> Dictionary:
	if not peers.has(peer):
		return {"ok": false, "id": 0, "error": "먼저 연결해 주세요."}
	if String(peers[peer].role) != "assist":
		return {"ok": false, "id": 0, "error": "이 연결은 작업을 요청할 수 없습니다."}
	var open_jobs := 0
	for id in queue.order:
		if str(queue.jobs[id].submitter) == str(peer) and not bool(queue.jobs[id].done):
			open_jobs += 1
	if open_jobs >= MAX_OPEN_JOBS_PER_PEER:
		return {"ok": false, "id": 0, "error": "진행 중인 작업이 너무 많습니다. 끝난 뒤에 요청해 주세요."}
	var planned := JobRunner.plan(type, params)
	var totals := queue.totals()
	if bool(planned.ok) and int(totals.pending) + int(totals.leased) + planned.chunks.size() > MAX_QUEUED_CHUNKS:
		return {"ok": false, "id": 0, "error": "대기 중인 작업이 너무 많습니다. 잠시 뒤에 다시 요청해 주세요."}
	var outcome := queue.submit(type, params, title, str(peer), now)
	if bool(outcome.ok):
		dirty = true
		events.append({"type": "submitted", "name": peers[peer].name, "job": outcome.id, "title": queue.jobs[outcome.id].title})
	return outcome

## Called every server frame. `busy` pauses the main server's own work while many matches run.
func tick(now: float, delta: float, busy: bool) -> void:
	var reclaimed := queue.expire(now)
	if reclaimed > 0:
		events.append({"type": "reclaimed", "chunks": reclaimed})
		dirty = true
	for peer in peers.keys():
		if now - float(peers[peer].seen) > PEER_TIMEOUT:
			goodbye(int(peer), now)
	if not busy:
		_work_locally(now, delta)
	if dirty and now - last_save >= SAVE_INTERVAL:
		save(now)

func _min_age(type: String) -> float:
	return 0.0 if workers_for(type) == 0 else PATIENCE_SECONDS

## The main server's own share: one chunk at a time, in short slices that add up to LOCAL_SHARE of a core.
func _work_locally(now: float, delta: float) -> void:
	local_credit = minf(MAX_CREDIT_MSEC, local_credit + delta * 1000.0 * LOCAL_SHARE)
	if local_run == null:
		var assignment := queue.claim(LOCAL_WORKER, JobRunner.CAPABILITIES, now, Callable(self, "_min_age"))
		if assignment.is_empty():
			return
		local_ref = assignment
		local_run = JobRunner.new_run(String(assignment.type), assignment.params)
		if local_run == null:
			queue.release(LOCAL_WORKER, now)
			return
		events.append({"type": "assigned", "name": "메인 서버", "job": assignment.job, "chunk": assignment.chunk})
	queue.renew(LOCAL_WORKER, now)
	while local_credit >= 2.0 and local_run != null:
		var started := Time.get_ticks_usec()
		var finished: bool = local_run.step(int(minf(local_credit, 12.0)))
		local_credit -= maxf(1.0, float(Time.get_ticks_usec() - started) / 1000.0)
		if finished:
			if queue.complete(int(local_ref.job), int(local_ref.chunk), local_run.result(), now):
				local_done_chunks += 1
				dirty = true
				events.append({"type": "chunk_done", "name": "메인 서버", "job": local_ref.job, "chunk": local_ref.chunk})
				_collect_finished(now)
			local_run = null
			local_ref = {}

func _collect_finished(_now: float) -> void:
	for id in queue.drain_finished():
		var answer := queue.result_of(id)
		results[id] = answer
		events.append({"type": "job_done", "job": id, "title": queue.jobs[id].title, "submitter": queue.jobs[id].submitter})
		if not dir.is_empty():
			ServerStats.write_json(dir.path_join("result_%d.json" % id), {"id": id, "type": queue.jobs[id].type, "title": queue.jobs[id].title, "result": answer})

func result_for(id: int) -> Dictionary:
	if results.has(id):
		return results[id]
	return queue.result_of(id)

func drain_events() -> Array:
	var list := events.duplicate()
	events.clear()
	return list

func save(now: float) -> void:
	last_save = now
	if dir.is_empty() or not dirty:
		return
	if ServerStats.write_json(dir.path_join("queue.json"), queue.to_dict()):
		dirty = false

## What the assist window shows: the queue, who is connected and what the main server itself is doing.
func overview() -> Dictionary:
	var assists: Array = []
	for peer in peers:
		assists.append({"name": peers[peer].name, "role": peers[peer].role, "cores": peers[peer].cores, "capabilities": peers[peer].capabilities,
			"holding": queue.held_by(worker_id(int(peer))), "wrapping": bool(peers[peer].wrapping)})
	return {"totals": queue.totals(), "jobs": queue.overview(8), "assists": assists,
		"main": {"working": local_run != null, "done_chunks": local_done_chunks}}
