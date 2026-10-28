extends SceneTree
# Accounts over real ENet/DTLS RPCs: sign-in, sign-up with a nickname, resume, rename, sign-out, delete.
const AccountTest = preload("res://tests/account_test.gd")
const PORT := 27994

var checks := 0
var failures := 0
var server
var alice
var bob
var key: CryptoKey
var results: Dictionary = {}
var nonces: Dictionary = {}

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
	controller.account_result_received.connect(func(result): results[label] = result)
	controller.account_nonce_received.connect(func(nonce): nonces[label] = nonce)
	return controller

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 5000
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	return predicate.call()

## Asks for a nonce, signs a Google-like token for `subject` and sends it; returns the server's answer.
func sign_in(client, label: String, subject: String, nonce_override: String = "") -> Dictionary:
	nonces.erase(label); results.erase(label)
	client.account_request_nonce()
	if not await wait_for(func(): return nonces.has(label)): return {}
	var now := int(Time.get_unix_time_from_system())
	var claims := AccountTest.claims(nonces[label] if nonce_override.is_empty() else nonce_override, now, {"sub": subject})
	client.account_sign_in(AccountTest.token(key, claims))
	return await answer(label)

func answer(label: String) -> Dictionary:
	await wait_for(func(): return results.has(label))
	var result: Dictionary = results.get(label, {})
	results.erase(label)
	return result

func run() -> void:
	create_timer(40.0).timeout.connect(func(): printerr("account wire watchdog"); quit(1))
	key = Crypto.new().generate_rsa(2048)
	var directory := "user://account_wire_%d" % Time.get_ticks_usec()
	server = make_controller("Server")
	if not server.start_dedicated_server(PORT): quit(1); return
	server.configure_accounts(directory, false)
	server.google.keys = {"test-key": key}
	alice = make_controller("alice"); bob = make_controller("bob")
	for client in [alice, bob]: client.connect_to_server("127.0.0.1", PORT)
	if not await wait_for(func(): return alice.client_connection_state == "lobby" and bob.client_connection_state == "lobby"):
		check(false, "clients reach the lobby"); quit(1); return

	check(not alice.account_request_nonce() and not alice.account_sign_in("x") and not alice.account_resume("x"), "credentials are never sent over an unverified connection")
	# The test server uses the development identity; pretend the official certificate was verified.
	alice.client_transport_verified = true; bob.client_transport_verified = true

	var first := await sign_in(alice, "alice", "google-alice")
	check(first.get("action") == "login" and first.get("error") == "needs_nickname" and first.get("session") == "", "a new Google account is asked for a nickname")
	alice.account_create("마왕")
	var created := await answer("alice")
	check(created.get("error") == "" and String(created.get("session")).length() == 64 and created.get("nickname") == "마왕", "sign-up returns a session and the nickname")
	var alice_session := String(created.get("session"))
	check(server.peer_accounts.has(alice.multiplayer.get_unique_id()), "the server binds the connection to the account")

	check((await sign_in(bob, "bob", "google-bob")).get("error") == "needs_nickname", "a second person signs in")
	bob.account_create("마왕")
	check((await answer("bob")).get("error") == "nickname_taken", "nicknames are unique across accounts")
	bob.account_create("용사")
	var bob_created := await answer("bob")
	check(bob_created.get("error") == "", "the second account is created with another nickname")
	bob.account_create("또다른")
	check((await answer("bob")).get("error") == "not_signed_in", "one Google sign-in creates at most one account")

	check((await sign_in(bob, "bob", "google-bob", "ffffffffffffffffffffffffffffffff")).get("error") == "invalid_token", "a token for another nonce is refused")
	bob.account_sign_in(AccountTest.token(key, AccountTest.claims("whatever", int(Time.get_unix_time_from_system()), {"sub": "google-bob"})))
	check((await answer("bob")).get("error") == "no_nonce", "a token without a fresh nonce is refused")
	var again := await sign_in(bob, "bob", "google-bob")
	check(again.get("error") == "" and again.get("nickname") == "용사" and String(again.get("session")).length() == 64, "signing in again opens the same account")

	alice.account_rename("용사")
	check((await answer("alice")).get("error") == "nickname_taken", "renaming respects uniqueness")
	alice.account_rename("마왕군주")
	check((await answer("alice")).get("nickname") == "마왕군주", "renaming works")

	alice.disconnect_from_server()
	await create_timer(0.3).timeout
	check(not server.peer_accounts.has(alice.multiplayer.get_unique_id()), "the server forgets the binding when the connection closes")
	alice.connect_to_server("127.0.0.1", PORT)
	if not await wait_for(func(): return alice.client_connection_state == "lobby"):
		check(false, "alice reconnects"); quit(1); return
	alice.client_transport_verified = true
	alice.account_resume(alice_session)
	var resumed := await answer("alice")
	check(resumed.get("action") == "resume" and resumed.get("error") == "" and resumed.get("nickname") == "마왕군주", "a session token resumes the account after reconnecting")
	alice.account_resume("0".repeat(64))
	check((await answer("alice")).get("error") == "expired", "an unknown session is refused")

	alice.account_sign_out(alice_session)
	check((await answer("alice")).get("action") == "logout", "signing out answers")
	alice.account_resume(alice_session)
	check((await answer("alice")).get("error") == "expired", "a signed-out session no longer resumes")
	alice.account_rename("새이름")
	check((await answer("alice")).get("error") == "not_signed_in", "signing out unbinds the connection")

	bob.account_delete()
	check((await answer("bob")).get("action") == "delete" and server.accounts.find_by_subject("google-bob").is_empty() and not server.accounts.nickname_taken("용사"), "an account can delete itself")
	bob.account_resume(String(bob_created.session))
	check((await answer("bob")).get("error") == "expired", "a deleted account's sessions are gone")
	check(server.accounts.dirty == false and FileAccess.file_exists(directory.path_join("accounts.json")), "account changes are written immediately")

	for client in [alice, bob]: client.disconnect_from_server()
	await create_timer(0.2).timeout
	server.multiplayer.multiplayer_peer.close()
	for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	if failures == 0: print("PASS: %d account wire checks" % checks)
	quit(1 if failures else 0)
