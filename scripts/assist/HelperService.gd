extends Node
## "계산 돕기" inside the normal game: the player's PC lends some CPU to the main server's job queue. It uses its own,
## separate network connection (so it can never disturb the lobby or a battle) and pauses while a battle is running.

const AssistWorker = preload("res://scripts/assist/AssistWorker.gd")

var worker
var network
var holder: Node = null
var pause_check := Callable()

func is_running() -> bool:
	return worker != null

## `settings`: {candidates, port, token, name, cores, capabilities?}.
func start(settings: Dictionary) -> void:
	stop()
	holder = Node.new()
	holder.name = "HelperHolder"
	get_tree().root.add_child(holder)
	get_tree().set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new()
	bootstrap.name = "Bootstrap"
	holder.add_child(bootstrap)
	var main_node := Node.new()
	main_node.name = "Main"
	bootstrap.add_child(main_node)
	network = NetworkController.new()
	network.name = "NetworkController"
	main_node.add_child(network)
	worker = AssistWorker.new()
	worker.name = "HelperWorker"
	add_child(worker)
	worker.setup(network)
	worker.config.candidates = settings.get("candidates", ["127.0.0.1"])
	worker.config.port = int(settings.get("port", NetworkController.DEFAULT_PORT))
	worker.config.token = String(settings.get("token", ""))
	worker.config.name = String(settings.get("name", "PC")).left(24)
	worker.config.cores = clampi(int(settings.get("cores", 1)), 1, 64)
	worker.config.role = "helper"
	worker.config.capabilities = settings.get("capabilities", ["balance", "replay"])
	worker.start()

func stop() -> void:
	if worker != null:
		worker.stop_now()
		worker.queue_free()
		worker = null
	if holder != null:
		holder.queue_free()
		holder = null
	network = null

func _process(_delta: float) -> void:
	if worker != null and pause_check.is_valid():
		worker.paused = bool(pause_check.call())

func _exit_tree() -> void:
	if worker != null and network != null and network.client_is_online():
		network.assist_send_goodbye()
