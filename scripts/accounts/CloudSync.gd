extends Node
## Keeps the signed-in account's progress on the server (CloudSaves) in step with this device. On each
## confirmed connection it loads the server copy and then:
##   - nothing stored yet, or only this device changed since the last sync -> upload this device's progress;
##   - only the server copy changed (or this device has no progress yet)  -> load it here;
##   - both changed                                                       -> ask which one to keep.
## Afterwards changed progress is uploaded every CHECK_SECONDS outside battles. When the game runs offline
## (ClientAccount offline grace) it quietly retries the server every RECONNECT_SECONDS.

signal conflict(server_text: String)
signal applied(message: String)

const ServerLink = preload("res://scripts/ServerLink.gd")

## Tests point it somewhere harmless.
static var save_path := SaveData.SAVE_PATH

const CHECK_SECONDS := 20.0
const RECONNECT_SECONDS := 300.0

var main
var network
var account
## "idle" | "loading" | "storing" | "conflict"
var phase := "idle"
## True after this connection's first load finished.
var checked := false
var server_revision := 0
var pending_hash := ""
var check_elapsed := 0.0
## Starts full so a game opened offline tries the server right away.
var reconnect_elapsed := RECONNECT_SECONDS
var message := ""
## The server copy waiting for the player's choice while `phase` is "conflict".
var conflict_text := ""

func setup(main_node) -> void:
	main = main_node
	network = main.network
	account = main.account
	network.cloud_save_received.connect(_on_loaded)
	network.cloud_save_stored.connect(_on_stored)
	account.changed.connect(_on_account_changed)

func _on_account_changed() -> void:
	if not account.online:
		checked = false
		if phase in ["loading", "storing"] or account.session.is_empty():
			phase = "idle"
			conflict_text = ""
		return
	if not checked and phase == "idle":
		load_server()

func load_server() -> bool:
	if not network.send_cloud_load():
		return false
	phase = "loading"
	return true

func _process(delta: float) -> void:
	if account == null or account.session.is_empty():
		return
	if not account.online:
		reconnect_elapsed += delta
		if reconnect_elapsed >= RECONNECT_SECONDS and not main.battle_active and main.link_enabled and not network.client_is_online():
			reconnect_elapsed = 0.0
			ServerLink.run(main, func(): pass, Callable(), false)
		return
	reconnect_elapsed = 0.0
	check_elapsed += delta
	if check_elapsed < CHECK_SECONDS:
		return
	check_elapsed = 0.0
	if checked and phase == "idle" and not main.battle_active and dirty():
		upload(account.cloud_revision)

func local_text() -> String:
	return SaveData.cloud_text(main.save_data)

## This device's progress differs from what was last in sync with the server.
func dirty() -> bool:
	return local_text().sha256_text() != account.cloud_hash

func upload(expected: int) -> bool:
	var text := local_text()
	if not network.send_cloud_store(expected, text):
		return false
	phase = "storing"
	pending_hash = text.sha256_text()
	return true

func _on_loaded(revision: int, text: String) -> void:
	if phase != "loading" or revision < 0:
		return
	phase = "idle"
	checked = true
	server_revision = revision
	var local := local_text()
	if revision == 0:
		upload(0)
	elif text.sha256_text() == local.sha256_text():
		_mark_synced(revision, local.sha256_text())
	elif revision == account.cloud_revision:
		if dirty(): upload(revision)
	elif (not dirty() and account.cloud_revision > 0) or SaveData.is_fresh(main.save_data):
		apply_server(revision, text)
	else:
		phase = "conflict"
		conflict_text = text
		conflict.emit(text)

## Keeps the server copy (conflict choice, or the automatic cases above).
func apply_server(revision: int, text: String) -> bool:
	var result: Dictionary = SaveData.apply_cloud(main.save_data, text, save_path)
	phase = "idle"
	conflict_text = ""
	if not result.ok:
		message = String(result.error)
		applied.emit(message)
		return false
	main.save_data = result.data
	main.network.client_nickname = String(main.save_data.nickname)
	main._profile_saved()
	_mark_synced(revision, local_text().sha256_text())
	message = "서버에 저장된 진행도를 불러왔습니다."
	applied.emit(message)
	return true

## Keeps this device's progress (conflict choice): replaces the server copy it was compared with.
func keep_local() -> bool:
	phase = "idle"
	conflict_text = ""
	return upload(server_revision)

func _on_stored(ok: bool, revision: int, error: String) -> void:
	if phase != "storing":
		return
	phase = "idle"
	if ok:
		_mark_synced(revision, pending_hash)
	elif error == "conflict":
		load_server()
	elif error == "too_large":
		message = "진행도가 너무 커서 서버에 저장하지 못했습니다."

func _mark_synced(revision: int, content_hash: String) -> void:
	server_revision = revision
	account.cloud_revision = revision
	account.cloud_hash = content_hash
	account.save()
