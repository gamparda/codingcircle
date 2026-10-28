extends SceneTree
# CloudSync on two devices of one account against a real server: the first device uploads, a new device
# takes the server progress, changes on both sides ask which to keep. Also the offline grace for sign-in.
const AccountTest = preload("res://tests/account_test.gd")
const ClientAccountTest = preload("res://tests/client_account_test.gd")
const ClientAccount = preload("res://scripts/accounts/ClientAccount.gd")
const CloudSync = preload("res://scripts/accounts/CloudSync.gd")
const PORT := 27998

var checks := 0
var failures := 0

class Device extends Node:
	var network
	var account
	var cloud_sync
	var save_data: Dictionary = SaveData.default_data()
	var battle_active := false
	var link_enabled := false
	var saved := 0
	func _profile_saved() -> void:
		saved += 1

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func wait_until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 6000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	return predicate.call()

func make_device(label: String, key: CryptoKey) -> Device:
	var holder := Node.new(); holder.name = label; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var device := Device.new(); device.name = "Main"; bootstrap.add_child(device)
	var controller := NetworkController.new(); controller.name = "NetworkController"; device.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	device.network = controller
	var plugin = ClientAccountTest.FakePlugin.new(); plugin.key = key; plugin.subject = "google-same-person"
	device.account = ClientAccount.new(); device.add_child(device.account); device.account.setup(controller, plugin)
	device.cloud_sync = CloudSync.new(); device.add_child(device.cloud_sync); device.cloud_sync.setup(device)
	return device

func connect_device(device: Device) -> bool:
	device.network.connect_to_server("127.0.0.1", PORT)
	if not await wait_until(func(): return device.network.client_connection_state == "lobby"): return false
	device.network.client_transport_verified = true
	return true

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("cloud sync watchdog"); quit(1))
	var key := Crypto.new().generate_rsa(2048)
	var directory := "user://cloud_sync_%d" % Time.get_ticks_usec()
	ClientAccount.save_path = directory + "_account.json"
	CloudSync.save_path = directory + "_save.json"
	var server = make_controller_server(directory, key)
	if server == null: quit(1); return

	# Device A has progress and signs up: its progress becomes the server copy.
	var a := make_device("phone", key)
	a.save_data.stats.ai_matches = 3; a.save_data.stats.ai_wins = 2
	if not await connect_device(a): check(false, "device A connects"); quit(1); return
	a.account.sign_in()
	await wait_until(func(): return a.account.state == "needs_nickname")
	a.account.create("마왕", true)
	check(await wait_until(func(): return a.account.cloud_revision == 1), "the first device uploads its progress")
	check(not a.cloud_sync.dirty(), "after the upload the device is in sync")

	# Device B is new: it takes the server progress and keeps its own settings.
	server.cloud_store_times.clear()
	ClientAccount.save_path = directory + "_tablet_account.json" # a different device
	var b := make_device("tablet", key)
	b.save_data.settings.master_volume = 0.1
	if not await connect_device(b): check(false, "device B connects"); quit(1); return
	b.account.sign_in()
	check(await wait_until(func(): return b.account.cloud_revision == 1 and int(b.save_data.stats.ai_matches) == 3), "a new device loads the server progress")
	check(is_equal_approx(float(b.save_data.settings.master_volume), 0.1), "device settings are not synced")
	check(b.saved == 1 and FileAccess.file_exists(CloudSync.save_path), "loaded progress is saved on the device")

	# A plays more and uploads; B also played offline: B must choose.
	server.cloud_store_times.clear()
	a.save_data.stats.ai_matches = 5
	check(a.cloud_sync.upload(a.account.cloud_revision), "device A uploads new progress")
	check(await wait_until(func(): return a.account.cloud_revision == 2), "the server has revision 2")
	b.save_data.stats.ai_matches = 7
	var conflicts := []
	b.cloud_sync.conflict.connect(func(text): conflicts.append(text))
	b.network.disconnect_from_server()
	await wait_until(func(): return not b.account.online)
	if not await connect_device(b): check(false, "device B reconnects"); quit(1); return
	b.account.resume()
	check(await wait_until(func(): return conflicts.size() == 1), "progress changed on both sides asks the player")
	check(b.cloud_sync.phase == "conflict" and int(JSON.parse_string(conflicts[0]).stats.ai_matches) == 5, "the choice shows the server progress")
	server.cloud_store_times.clear()
	check(b.cloud_sync.keep_local(), "keeping this device's progress uploads it")
	check(await wait_until(func(): return b.account.cloud_revision == 3), "the device's choice becomes revision 3")
	check(int(JSON.parse_string(server.cloud.read(server.peer_accounts.values()[0]).data).stats.ai_matches) == 7, "the server holds the kept progress")

	# Offline grace: a saved account plays offline for a week after the server last confirmed it.
	ClientAccount.required_override = 1
	var offline := ClientAccount.new()
	offline.session = "a".repeat(64)
	var now := int(Time.get_unix_time_from_system())
	offline.verified_at = now - 86400
	check(offline.unlocked(), "a recently confirmed account plays offline")
	offline.verified_at = now - ClientAccount.OFFLINE_GRACE_SECONDS - 60
	check(not offline.unlocked(), "after the grace period the server must confirm again")
	offline.verified_at = now + 3600
	check(not offline.unlocked(), "a clock set back does not extend the grace")
	offline.free()
	ClientAccount.required_override = -1

	for device in [a, b]: device.network.disconnect_from_server()
	await create_timer(0.2).timeout
	server.multiplayer.multiplayer_peer.close()
	preload("res://scripts/ServerBackup.gd")._remove_tree(directory)
	for path in [directory + "_account.json", ClientAccount.save_path, CloudSync.save_path]: DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(SaveData.recovery_dir(CloudSync.save_path))
	if failures == 0: print("PASS: %d cloud sync checks" % checks)
	quit(1 if failures else 0)

func make_controller_server(directory: String, key: CryptoKey):
	var holder := Node.new(); holder.name = "Server"; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var server := NetworkController.new(); server.name = "NetworkController"; main.add_child(server)
	if not server.start_dedicated_server(PORT): return null
	server.configure_accounts(directory, false)
	server.google.keys = {"test-key": key}
	return server
