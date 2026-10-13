extends Node
## One request per response channel. Lives under the network, beyond any one screen.
## Upload replies have no request ID: keep abandoned uploads until their reply is drained
## or the transport changes, so a late code cannot be assigned to a different replay.

const ServerLink = preload("res://scripts/ServerLink.gd")
const RESPONSE_SECONDS := 12.0

var network
var channel := ""
var key := ""
var sent := false
var generation := -1
var owner_ref: WeakRef
var on_result := Callable()
var on_failure := Callable()
var on_status := Callable()
var deadline := 0
var poll: Timer

static func start(main, owner: Node, kind: String, payload: String, result: Callable, failure: Callable, status: Callable) -> void:
	var node_name := "ReplayRequest_" + kind
	var request = main.network.get_node_or_null(NodePath(node_name))
	if request != null and request.sent and request.generation != main.network.client_connection_generation:
		request._finish_failure("서버 연결이 바뀌었습니다. 다시 시도하세요.")
		request = null
	if request != null:
		if request._owner_alive():
			failure.call("다른 리플레이 요청을 처리 중입니다. 응답을 기다려 주세요.")
			return
		if request.sent and kind == "upload" and request.key != payload:
			failure.call("이전 코드 발급 응답을 기다리고 있습니다. 복사 버튼으로 먼저 공유할 수 있습니다.")
			return
		if not request.sent or request.key == payload:
			request.key = payload
			request._observe(owner, result, failure, status)
			return
		request._dispose()
	request = load("res://scripts/ui/ReplayRequest.gd").new()
	request.name = node_name
	request.network = main.network
	request.channel = kind
	request.key = payload
	main.network.add_child(request)
	request._connect_response()
	request.poll = Timer.new()
	request.poll.wait_time = 0.25
	request.poll.timeout.connect(request._poll)
	request.add_child(request.poll)
	request.poll.start()
	request._observe(owner, result, failure, status)
	# ServerLink may finish connecting after this request has been cancelled/freed.
	# Keep its shared connection alive, but never send through an abandoned request.
	var request_ref := weakref(request)
	var send := func():
		var current = request_ref.get_ref()
		if is_instance_valid(current) and current.is_inside_tree() and not current.is_queued_for_deletion():
			current._send()
	var link_status := func(text: String):
		var current = request_ref.get_ref()
		if is_instance_valid(current) and current.is_inside_tree() and not current.is_queued_for_deletion():
			current._link_status(text)
	ServerLink.run(main, send, link_status)

## Stop observing a download without closing its owner or interrupting other channels.
## The server may still send an already requested replay; disconnect before unlocking UI.
static func cancel_fetch(main, owner: Node) -> bool:
	var request = main.network.get_node_or_null(NodePath("ReplayRequest_fetch"))
	if request == null or request.owner_ref == null or request.owner_ref.get_ref() != owner:
		return false
	request._dispose()
	return true

func _observe(owner: Node, result: Callable, failure: Callable, status: Callable) -> void:
	_detach()
	owner_ref = weakref(owner)
	on_result = result
	on_failure = failure
	on_status = status
	deadline = Time.get_ticks_msec() + int(RESPONSE_SECONDS * 1000.0)
	owner.tree_exited.connect(_detach, CONNECT_ONE_SHOT)
	on_status.call("응답을 기다리는 중..." if sent else "요청 준비 중...")

func _owner_alive() -> bool:
	if owner_ref == null:
		return false
	var owner = owner_ref.get_ref()
	if not is_instance_valid(owner) or not owner.is_inside_tree():
		return false
	# queue_free leaves controls valid until the frame ends; reject queued ancestors too.
	var node: Node = owner
	while node != null:
		if node.is_queued_for_deletion():
			return false
		node = node.get_parent()
	return true

func _detach() -> void:
	if owner_ref != null:
		var owner = owner_ref.get_ref()
		if is_instance_valid(owner) and owner.tree_exited.is_connected(_detach):
			owner.tree_exited.disconnect(_detach)
	owner_ref = null
	on_result = Callable()
	on_failure = Callable()
	on_status = Callable()

func _connect_response() -> void:
	if channel == "upload":
		network.replay_code_received.connect(_uploaded)
	elif channel == "fetch":
		network.shared_replay_received.connect(_fetched)
	else:
		network.recent_replays_received.connect(_recent)

func _send() -> void:
	if not _owner_alive():
		_dispose()
		return
	if not network.client_is_online():
		_finish_failure("서버 연결이 끊겼습니다. 다시 시도하세요.")
		return
	sent = true
	generation = network.client_connection_generation
	deadline = Time.get_ticks_msec() + int(RESPONSE_SECONDS * 1000.0)
	on_status.call("응답을 기다리는 중...")
	if channel == "upload":
		network.send_replay_upload(key)
	elif channel == "fetch":
		network.send_replay_fetch(key)
	else:
		network.send_recent_request()

func _link_status(text: String) -> void:
	if text == "서버에 접속 중...":
		if _owner_alive():
			on_status.call(text)
	else:
		_finish_failure(text)

func _poll() -> void:
	if sent and (generation != network.client_connection_generation or not network.client_is_online()):
		_finish_failure("서버 연결이 끊겼습니다. 다시 시도하세요.")
		return
	if not _owner_alive():
		_detach()
		if sent and channel == "fetch":
			_dispose()
		return
	if Time.get_ticks_msec() >= deadline:
		var failure := on_failure
		_detach()
		failure.call("서버 응답이 지연되고 있습니다. 다시 시도하거나 복사 버튼으로 공유하세요." if channel == "upload" else "서버 응답 시간이 초과되었습니다. 다시 시도하세요.")
		if sent and channel == "fetch":
			_dispose()

func _uploaded(code: String) -> void:
	_complete(code)

func _fetched(code: String, text: String) -> void:
	if code == key:
		_complete(text)

func _recent(rows: Array) -> void:
	_complete(rows)

func _complete(value: Variant) -> void:
	if not sent:
		return
	var callback := on_result if generation == network.client_connection_generation and _owner_alive() else Callable()
	_dispose()
	if callback.is_valid():
		callback.call(value)

func _finish_failure(text: String) -> void:
	var callback := on_failure if _owner_alive() else Callable()
	_dispose()
	if callback.is_valid():
		callback.call(text)

func _dispose() -> void:
	_detach()
	if is_instance_valid(poll):
		poll.stop()
	_disconnect_response()
	if get_parent() != null:
		get_parent().remove_child(self)
	queue_free()

func _disconnect_response() -> void:
	if not is_instance_valid(network):
		return
	if network.replay_code_received.is_connected(_uploaded):
		network.replay_code_received.disconnect(_uploaded)
	if network.shared_replay_received.is_connected(_fetched):
		network.shared_replay_received.disconnect(_fetched)
	if network.recent_replays_received.is_connected(_recent):
		network.recent_replays_received.disconnect(_recent)

func _exit_tree() -> void:
	_detach()
	_disconnect_response()
