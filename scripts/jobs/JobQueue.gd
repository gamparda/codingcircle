extends RefCounted
## The main server's list of jobs. A job is a list of chunks; a chunk is pending, leased to one worker for a short
## time (renewed by that worker's heartbeat) or done. Whoever is slow, crashes or quits simply loses the lease and the
## chunk goes back to pending, so a finished chunk is never repeated and an unfinished one is never lost.
## All times are seconds from any steady clock handed in by the caller, which keeps this testable.

const JobRunner = preload("res://scripts/jobs/JobRunner.gd")

const LEASE_SECONDS := 30.0
const MAX_JOBS := 100 # finished jobs beyond this are forgotten, oldest first

var jobs: Dictionary = {}
var order: Array = []
var next_id := 1
var finished: Array = [] # ids of jobs completed since the last drain

## Plans and queues a job. Returns {"ok", "id", "error"}.
func submit(type: String, params: Dictionary, title: String, submitter: String, now: float) -> Dictionary:
	var planned := JobRunner.plan(type, params)
	if not bool(planned.ok):
		return {"ok": false, "id": 0, "error": String(planned.error)}
	var chunks: Array = []
	for chunk_params in planned.chunks:
		chunks.append({"params": chunk_params, "state": "pending", "worker": "", "lease_until": 0.0, "since": now, "result": {}})
	var id := next_id
	next_id += 1
	jobs[id] = {"id": id, "type": type, "title": title if not title.is_empty() else JobRunner.title_for(type), "submitter": submitter,
		"created": now, "done": false, "chunks": chunks}
	order.append(id)
	_forget_old()
	return {"ok": true, "id": id, "error": ""}

func _forget_old() -> void:
	while order.size() > MAX_JOBS:
		var removable := -1
		for index in order.size():
			if bool(jobs[order[index]].done):
				removable = index
				break
		if removable < 0:
			return
		jobs.erase(order[removable])
		order.remove_at(removable)

## Hands the first waiting chunk the worker is allowed to do. `min_age_for(type)` (optional) is how long a chunk must
## have been waiting before this worker may take it: the main server lets assist servers have first pick.
func claim(worker: String, capabilities: Array, now: float, min_age_for: Callable = Callable()) -> Dictionary:
	for id in order:
		var job: Dictionary = jobs[id]
		if bool(job.done) or not capabilities.has(JobRunner.capability_for(String(job.type))):
			continue
		var min_age := float(min_age_for.call(String(job.type))) if min_age_for.is_valid() else 0.0
		for index in job.chunks.size():
			var chunk: Dictionary = job.chunks[index]
			if chunk.state == "pending" and now - float(chunk.since) >= min_age:
				chunk.state = "leased"
				chunk.worker = worker
				chunk.lease_until = now + LEASE_SECONDS
				return {"job": id, "chunk": index, "type": job.type, "params": chunk.params, "lease": LEASE_SECONDS}
	return {}

## A heartbeat: everything the worker holds stays its own for another lease.
func renew(worker: String, now: float) -> int:
	var renewed := 0
	for id in order:
		for chunk in jobs[id].chunks:
			if chunk.state == "leased" and chunk.worker == worker:
				chunk.lease_until = now + LEASE_SECONDS
				renewed += 1
	return renewed

## Takes back every chunk whose lease ran out. Returns how many.
func expire(now: float) -> int:
	var reclaimed := 0
	for id in order:
		for chunk in jobs[id].chunks:
			if chunk.state == "leased" and now >= float(chunk.lease_until):
				_reopen(chunk, now)
				reclaimed += 1
	return reclaimed

## The worker is leaving ("here is how far I got"): finished chunks stay done, the rest goes back to pending.
func release(worker: String, now: float) -> int:
	var released := 0
	for id in order:
		for chunk in jobs[id].chunks:
			if chunk.state == "leased" and chunk.worker == worker:
				_reopen(chunk, now)
				released += 1
	return released

func _reopen(chunk: Dictionary, now: float) -> void:
	chunk.state = "pending"
	chunk.worker = ""
	chunk.lease_until = 0.0
	chunk.since = now

## Stores a chunk's result. A late result from a worker that lost its lease is still good (chunks are deterministic) as
## long as nobody finished that chunk first. Returns whether it was accepted.
func complete(job_id: int, chunk_index: int, result: Dictionary, now: float) -> bool:
	if not jobs.has(job_id):
		return false
	var job: Dictionary = jobs[job_id]
	if chunk_index < 0 or chunk_index >= job.chunks.size() or job.chunks[chunk_index].state == "done":
		return false
	var chunk: Dictionary = job.chunks[chunk_index]
	chunk.state = "done"
	chunk.worker = ""
	chunk.result = result
	if job.chunks.all(func(entry): return entry.state == "done") and not bool(job.done):
		job.done = true
		job["finished_at"] = now
		finished.append(job_id)
	return true

func drain_finished() -> Array:
	var ids := finished.duplicate()
	finished.clear()
	return ids

## Chunks nobody is working on, optionally only those a given capability list could do.
func pending_count(capabilities: Array = []) -> int:
	var count := 0
	for id in order:
		var job: Dictionary = jobs[id]
		if not capabilities.is_empty() and not capabilities.has(JobRunner.capability_for(String(job.type))):
			continue
		for chunk in job.chunks:
			if chunk.state == "pending":
				count += 1
	return count

func held_by(worker: String) -> int:
	var count := 0
	for id in order:
		for chunk in jobs[id].chunks:
			if chunk.state == "leased" and chunk.worker == worker:
				count += 1
	return count

func summary(id: int) -> Dictionary:
	if not jobs.has(id):
		return {}
	var job: Dictionary = jobs[id]
	var counts := {"pending": 0, "leased": 0, "done": 0}
	for chunk in job.chunks:
		counts[chunk.state] += 1
	return {"id": id, "type": job.type, "title": job.title, "total": job.chunks.size(), "pending": counts.pending, "leased": counts.leased,
		"done_chunks": counts.done, "done": bool(job.done), "submitter": job.submitter}

## The combined answer of a finished job, {} while it is still running.
func result_of(id: int) -> Dictionary:
	if not jobs.has(id) or not bool(jobs[id].done):
		return {}
	var job: Dictionary = jobs[id]
	var chunk_params: Array = job.chunks.map(func(chunk): return chunk.params)
	var chunk_results: Array = job.chunks.map(func(chunk): return chunk.result)
	return JobRunner.combine(String(job.type), chunk_params, chunk_results)

## Newest-first summaries for the status screen.
func overview(limit: int = 8) -> Array:
	var list: Array = []
	for index in range(order.size() - 1, -1, -1):
		list.append(summary(int(order[index])))
		if list.size() >= limit:
			break
	return list

func totals() -> Dictionary:
	var out := {"pending": 0, "leased": 0, "done": 0, "jobs": order.size(), "jobs_done": 0}
	for id in order:
		if bool(jobs[id].done):
			out.jobs_done += 1
		for chunk in jobs[id].chunks:
			out[chunk.state] += 1
	return out

# ---------- persistence ----------

func to_dict() -> Dictionary:
	return {"jobs": jobs.duplicate(true), "order": order.duplicate(), "next_id": next_id}

## Restores a saved queue. Leases do not survive a restart: leased chunks wait again.
func load_dict(data: Variant, now: float) -> void:
	jobs = {}
	order = []
	finished = []
	next_id = 1
	if not data is Dictionary or not data.get("jobs") is Dictionary or not data.get("order") is Array:
		return
	next_id = maxi(1, int(data.get("next_id", 1)))
	for id in data.order:
		var key := str(int(id))
		var raw = data.jobs.get(key, data.jobs.get(int(id)))
		if not raw is Dictionary or not JobRunner.known(String(raw.get("type", ""))) or not raw.get("chunks") is Array:
			continue
		var chunks: Array = []
		for chunk in raw.chunks:
			if not chunk is Dictionary or not chunk.get("params") is Dictionary:
				continue
			var done: bool = String(chunk.get("state", "pending")) == "done"
			chunks.append({"params": chunk.params, "state": "done" if done else "pending", "worker": "", "lease_until": 0.0, "since": now,
				"result": chunk.get("result", {}) if done and chunk.get("result") is Dictionary else {}})
		if chunks.is_empty():
			continue
		var job_id := int(id)
		jobs[job_id] = {"id": job_id, "type": String(raw.type), "title": String(raw.get("title", "")), "submitter": String(raw.get("submitter", "")),
			"created": float(raw.get("created", now)), "done": chunks.all(func(entry): return entry.state == "done"), "chunks": chunks}
		order.append(job_id)
		next_id = maxi(next_id, job_id + 1)
