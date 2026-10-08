extends Node
## The helper side of the job system, used by the assist server window and (later) by game clients that lend their
## spare CPU. It connects to the main server, introduces itself, then repeatedly asks for one chunk, computes it on a
## background thread (as many at once as the chosen core count) and sends the answer back. It keeps its lease alive
## with heartbeats, hands unfinished work back when asked to wrap up, and reconnects on its own when the link drops.

const JobRunner = preload("res://scripts/jobs/JobRunner.gd")
const LogBuffer = preload("res://scripts/assist/LogBuffer.gd")

signal state_changed(state: String)
signal chunk_finished(job_id: int, chunk_index: int)
signal job_result(job_id: int, result: Dictionary)
signal stopped

const HEARTBEAT_SECONDS := 2.0
const IDLE_POLL_SECONDS := 2.0
const WRAP_SECONDS := 30.0
const RECONNECT_DELAYS := [3.0, 6.0, 12.0, 20.0]

## One chunk being computed on its own thread.
class ChunkTask extends RefCounted:
	var job := 0
	var chunk := 0
	var type := ""
	var params := {}
	var thread := Thread.new()
	var mutex := Mutex.new()
	var done := false
	var cancelled := false
	var failed := false
	var answer := {}
	var fraction := 0.0
	var started_at := 0.0

	func start() -> void:
		started_at = float(Time.get_ticks_msec()) / 1000.0
		thread.start(_work)

	func _work() -> void:
		var run = preload("res://scripts/jobs/JobRunner.gd").new_run(type, params)
		var finished := false
		if run == null:
			mutex.lock()
			failed = true
			done = true
			mutex.unlock()
			return
		while not finished:
			mutex.lock()
			var stop := cancelled
			mutex.unlock()
			if stop:
				return
			finished = run.step(20)
			mutex.lock()
			fraction = run.progress()
			mutex.unlock()
		mutex.lock()
		answer = run.result()
		fraction = 1.0
		done = true
		mutex.unlock()

	func is_done() -> bool:
		mutex.lock()
		var value := done
		mutex.unlock()
		return value

	func progress() -> float:
		mutex.lock()
		var value := fraction
		mutex.unlock()
		return value

	func cancel() -> void:
		mutex.lock()
		cancelled = true
		mutex.unlock()

	func join() -> void:
		if thread.is_started():
			thread.wait_to_finish()

var network
var journal := LogBuffer.new()
var config := {"candidates": ["127.0.0.1"], "port": 7777, "token": "", "name": "보조 서버", "role": "assist",
	"capabilities": ["balance", "replay", "selftest"], "cores": 2, "auto_reconnect": true}
var state := "offline" # offline | connecting | joining | idle | working | paused | wrapping | stopped
var tasks: Array = []
var paused := false
var overview: Dictionary = {}
var stats := {"chunks": 0, "busy_seconds": 0.0, "started": 0.0}
var want_online := false
var claim_in_flight := false
var next_claim_at := 0.0
var heartbeat_at := 0.0
var wrap_deadline := -1.0
var reconnect_at := -1.0
var attempts := 0
var last_error := ""

func setup(net) -> void:
	network = net
	network.client_assist_mode = true
	network.server_ready.connect(_on_server_ready)
	network.assist_welcomed.connect(_on_welcomed)
	network.assist_assigned.connect(_on_assigned)
	network.assist_idle_received.connect(_on_idle)
	network.assist_wrap_up_received.connect(func(): begin_wrap_up("메인 서버가 마무리를 요청했습니다"))
	network.assist_overview_received.connect(func(data): overview = data)
	network.assist_job_result_received.connect(func(id, result): job_result.emit(id, result))
	stats.started = _now()

func _now() -> float:
	return float(Time.get_ticks_msec()) / 1000.0

func _set_state(next: String) -> void:
	if next != state:
		state = next
		state_changed.emit(state)

func capabilities() -> Array:
	return config.capabilities.filter(func(entry): return JobRunner.CAPABILITIES.has(entry))

func cores() -> int:
	return clampi(int(config.cores), 1, 64)

func is_online() -> bool:
	return state in ["joining", "idle", "working", "paused", "wrapping"]

# ---------- connecting ----------

func start() -> void:
	want_online = true
	attempts = 0
	reconnect_at = -1.0
	_connect()

func _connect() -> void:
	_set_state("connecting")
	journal.add("info", "메인 서버에 연결하는 중... (%s)" % ", ".join(PackedStringArray(config.candidates)))
	network.client_assist_mode = true
	if not network.connect_to_candidates(config.candidates, int(config.port)):
		_failed("서버 주소가 올바르지 않습니다.")

func _failed(reason: String) -> void:
	last_error = reason
	journal.add("warn", reason)
	_cancel_all()
	if want_online and bool(config.auto_reconnect):
		var delay: float = RECONNECT_DELAYS[mini(attempts, RECONNECT_DELAYS.size() - 1)]
		attempts += 1
		reconnect_at = _now() + delay
		_set_state("offline")
		journal.add("info", "%d초 뒤 다시 연결합니다." % int(delay))
	else:
		_set_state("offline")

func _on_server_ready() -> void:
	if state != "connecting":
		return
	_set_state("joining")
	network.assist_send_hello(String(config.token), String(config.name), capabilities(), cores(), String(config.role))

func _on_welcomed(ok: bool, message: String) -> void:
	if not ok:
		want_online = false
		last_error = message
		journal.add("error", "연결이 거부되었습니다: %s" % message)
		network.disconnect_from_server()
		_set_state("offline")
		return
	attempts = 0
	claim_in_flight = false
	heartbeat_at = 0.0
	next_claim_at = 0.0
	journal.add("info", "메인 서버에 연결되었습니다. 받을 작업: %s, 코어 %d개" % [", ".join(PackedStringArray(capabilities())), cores()])
	_set_state("idle")

# ---------- the working loop ----------

func _process(_delta: float) -> void:
	if network == null:
		return
	var now := _now()
	if state == "connecting" and network.client_connection_state == "idle":
		_failed("메인 서버에 연결하지 못했습니다.")
	elif state in ["joining", "idle", "working", "paused", "wrapping"] and network.client_connection_state == "idle":
		_failed("메인 서버와 연결이 끊어졌습니다. 진행 중이던 조각은 메인 서버가 회수합니다.")
	elif state == "offline" and want_online and reconnect_at > 0.0 and now >= reconnect_at:
		reconnect_at = -1.0
		_connect()
	if not is_online() or state == "joining":
		return
	_collect_finished()
	if now >= heartbeat_at:
		heartbeat_at = now + HEARTBEAT_SECONDS
		network.assist_send_heartbeat()
	if state == "wrapping":
		_wrap_step(now)
		return
	if not paused and tasks.size() < cores() and not claim_in_flight and now >= next_claim_at:
		claim_in_flight = true
		network.assist_send_claim()
	_set_state("paused" if paused else ("working" if not tasks.is_empty() else "idle"))

func _on_assigned(job_id: int, chunk_index: int, type: String, params: Dictionary, _lease: float) -> void:
	claim_in_flight = false
	if state == "wrapping" or not capabilities().has(JobRunner.capability_for(type)):
		return
	var task := ChunkTask.new()
	task.job = job_id
	task.chunk = chunk_index
	task.type = type
	task.params = params
	tasks.append(task)
	task.start()
	next_claim_at = 0.0
	journal.add("info", "작업 #%d · 조각 %d 시작 (%s)" % [job_id, chunk_index + 1, JobRunner.title_for(type)])

func _on_idle() -> void:
	claim_in_flight = false
	next_claim_at = _now() + IDLE_POLL_SECONDS

func _collect_finished() -> void:
	for task in tasks.duplicate():
		if not task.is_done():
			continue
		task.join()
		tasks.erase(task)
		var seconds: float = _now() - float(task.started_at)
		stats.busy_seconds += seconds
		if task.failed:
			journal.add("error", "작업 #%d · 조각 %d: 알 수 없는 작업이라 건너뜁니다." % [task.job, task.chunk + 1])
			continue
		stats.chunks += 1
		network.assist_send_chunk(task.job, task.chunk, task.answer)
		journal.add("info", "작업 #%d · 조각 %d 완료 (%.1f초) · 결과 전송" % [task.job, task.chunk + 1, seconds])
		chunk_finished.emit(task.job, task.chunk)

## Progress of the chunks being computed right now: [{job, chunk, type, fraction}].
func running() -> Array:
	return tasks.map(func(task): return {"job": task.job, "chunk": task.chunk, "type": task.type, "fraction": task.progress()})

func set_paused(value: bool) -> void:
	paused = value
	journal.add("info", "일시정지했습니다. 새 조각을 받지 않습니다." if value else "다시 시작합니다.")

# ---------- leaving ----------

## "여기까지 했습니다, 마무리하세요": stop taking chunks, give running ones a little time, then say goodbye.
func begin_wrap_up(reason: String = "종료 버튼을 눌렀습니다") -> void:
	if state in ["wrapping", "stopped", "offline"]:
		if state == "offline":
			_finish()
		return
	journal.add("info", "%s. 하던 조각을 마무리합니다 (최대 %d초)." % [reason, int(WRAP_SECONDS)])
	wrap_deadline = _now() + WRAP_SECONDS
	_set_state("wrapping")

func _wrap_step(now: float) -> void:
	if tasks.is_empty():
		_finish()
	elif now >= wrap_deadline:
		journal.add("warn", "시간이 지나 조각 %d개를 메인 서버에 돌려줍니다." % tasks.size())
		_cancel_all()
		_finish()

func _finish() -> void:
	want_online = false
	if network != null and network.client_is_online():
		network.assist_send_goodbye()
	journal.add("info", "메인 서버에 작업 종료를 알렸습니다.")
	if network != null:
		network.disconnect_from_server()
	_set_state("stopped")
	stopped.emit()

## Immediate stop: the running chunks are dropped and the main server takes them back at once.
func stop_now() -> void:
	journal.add("warn", "즉시 종료합니다. 진행 중인 조각 %d개는 메인 서버가 회수합니다." % tasks.size())
	_cancel_all()
	_finish()

func _cancel_all() -> void:
	for task in tasks:
		task.cancel()
	for task in tasks:
		task.join()
	tasks.clear()
	claim_in_flight = false

func _exit_tree() -> void:
	_cancel_all()

## Sends a new job to the main server (this window can also be where experiments are ordered from).
func submit_job(type: String, params: Dictionary, title: String = "") -> void:
	if not is_online():
		journal.add("warn", "메인 서버에 연결된 뒤에 작업을 요청할 수 있습니다.")
		return
	network.assist_send_submit(type, params, title)
	journal.add("info", "작업을 요청했습니다: %s" % (title if not title.is_empty() else JobRunner.title_for(type)))
