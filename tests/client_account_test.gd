extends SceneTree
# The device side of accounts (ClientAccount + the settings AccountPanel) against a real server, with a
# fake Google sign-in plugin: guest, sign-up with the age check, saved session, resume, rename, delete.
const AccountTest = preload("res://tests/account_test.gd")
const ClientAccount = preload("res://scripts/accounts/ClientAccount.gd")
const AccountPanel = preload("res://scripts/ui/AccountPanel.gd")
const PORT := 27996

var checks := 0
var failures := 0
var key: CryptoKey

## Stands in for the Android plugin: answers signIn with a token for `subject`, or fails with `fail_code`.
class FakePlugin extends Object:
	signal sign_in_succeeded(token: String)
	signal sign_in_failed(code: String, detail: String)
	var key: CryptoKey
	var subject := "google-player"
	var fail_code := ""
	var client_id := ""
	var signed_out := 0
	func signIn(web_client_id: String, nonce: String) -> void:
		client_id = web_client_id
		if not fail_code.is_empty():
			sign_in_failed.emit.call_deferred(fail_code, "")
			return
		var claims := AccountTest.claims(nonce, int(Time.get_unix_time_from_system()), {"sub": subject})
		sign_in_succeeded.emit.call_deferred(AccountTest.token(key, claims))
	func signOut() -> void:
		signed_out += 1

class StubMain extends Node:
	var account
	func _styled_button(text_value: String, _color: Color, _filled: bool = false) -> Button:
		var button := Button.new()
		button.text = text_value
		return button

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	return controller

func make_account(client, plugin) -> Node:
	var account := ClientAccount.new()
	client.get_parent().add_child(account)
	account.setup(client, plugin)
	return account

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	return predicate.call()

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("client account watchdog"); quit(1))
	key = Crypto.new().generate_rsa(2048)
	var directory := "user://client_account_%d" % Time.get_ticks_usec()
	ClientAccount.save_path = directory + "_device.json"
	var server = make_controller("Server")
	if not server.start_dedicated_server(PORT): quit(1); return
	server.configure_accounts(directory, false)
	server.google.keys = {"test-key": key}
	var client = make_controller("player")
	var plugin := FakePlugin.new(); plugin.key = key
	var account := make_account(client, plugin)
	check(account.state == "guest" and not account.is_signed_in(), "a new device plays as a guest")
	check(not account.sign_in() and not String(account.message).is_empty(), "sign-in waits for a server connection")

	client.connect_to_server("127.0.0.1", PORT)
	if not await wait_for(func(): return client.client_connection_state == "lobby"):
		check(false, "the client reaches the lobby"); quit(1); return
	check(not account.sign_in() and account.blocker().contains("보안"), "sign-in needs a verified connection")
	client.client_transport_verified = true # the test server uses the development identity

	plugin.fail_code = "cancelled"
	check(account.sign_in() and account.state == "busy", "sign-in starts")
	check(await wait_for(func(): return account.state == "guest"), "a cancelled Google sign-in goes back to guest")
	check(String(account.message).contains("취소"), "the cancellation is explained")

	plugin.fail_code = ""
	account.sign_in()
	check(await wait_for(func(): return account.state == "needs_nickname"), "a new Google account is asked for a nickname")
	check(plugin.client_id == ClientAccount.GoogleIdToken.DEFAULT_CLIENT_IDS[0], "the plugin is asked for the game's web client ID")
	check(not account.create("마왕", false) and account.state == "needs_nickname", "the age confirmation is required")
	check(not account.create("", true), "an empty nickname is refused on the device")

	var main := StubMain.new(); main.account = account; root.add_child(main)
	var panel: Control = AccountPanel.create(main)
	main.add_child(panel)
	check(panel.find_child("AccountCreateButton", true, false) != null and panel.find_child("AccountAgeCheck", true, false) != null, "the panel shows the sign-up form")
	check(panel.find_child("AccountCreateButton", true, false).disabled, "account creation stays disabled until the age box is ticked")

	check(account.create("마왕", true), "sign-up is sent")
	check(await wait_for(func(): return account.state == "signed_in"), "the account is created")
	check(account.nickname == "마왕" and account.online and String(account.session).length() == 64, "the device holds the session and nickname")
	check(FileAccess.file_exists(ClientAccount.save_path), "the session is saved on the device")
	await process_frame
	check((panel.find_child("AccountStatus", true, false) as Label).text.contains("마왕"), "the panel follows the account state")
	check(panel.find_child("AccountDeleteButton", true, false) != null and panel.find_child("AccountSignInButton", true, false) == null, "a signed-in panel offers rename, sign-out and delete")

	# A fresh start of the game: the saved session comes back and resumes on the next verified connection.
	var restarted := make_account(client, plugin)
	check(restarted.state == "signed_in" and restarted.nickname == "마왕" and not restarted.online, "a restart loads the saved account")
	account.queue_free()
	restarted.resume()
	check(await wait_for(func(): return restarted.online), "the saved session resumes")
	account = restarted
	main.account = account

	check(account.rename("마왕군주"), "rename is sent")
	check(await wait_for(func(): return account.nickname == "마왕군주" and account.state == "signed_in"), "rename updates the device copy")
	check(String(JSON.parse_string(FileAccess.get_file_as_string(ClientAccount.save_path)).nickname) == "마왕군주", "the new nickname is saved")

	account.session = "0".repeat(64)
	account.resume()
	check(await wait_for(func(): return account.state == "guest"), "an expired session falls back to guest")
	check(not FileAccess.file_exists(ClientAccount.save_path), "the expired session is removed from the device")

	account.sign_in()
	check(await wait_for(func(): return account.state == "signed_in" and account.nickname == "마왕군주"), "signing in again opens the existing account")
	check(account.delete_account(), "delete is sent")
	check(await wait_for(func(): return account.state == "guest"), "deleting the account signs out")
	check(server.accounts.find_by_subject("google-player").is_empty() and not FileAccess.file_exists(ClientAccount.save_path), "the account is gone from the server and the device")
	check(plugin.signed_out == 1, "the remembered Google account choice is cleared")

	account.sign_in()
	check(await wait_for(func(): return account.state == "needs_nickname"), "the same Google account can sign up again")
	client.disconnect_from_server()
	check(await wait_for(func(): return account.state == "guest"), "losing the connection cancels sign-up")

	await create_timer(0.2).timeout
	server.multiplayer.multiplayer_peer.close()
	for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	plugin.free()
	if failures == 0: print("PASS: %d client account checks" % checks)
	quit(1 if failures else 0)
