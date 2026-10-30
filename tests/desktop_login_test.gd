extends SceneTree
# PC sign-in: the browser URL (PKCE, state, nonce), the loopback redirect, the server-side code exchange
# over real ENet RPCs, and the whole ClientAccount flow from the button to the nickname step.
const AccountTest = preload("res://tests/account_test.gd")
const DesktopLogin = preload("res://scripts/accounts/DesktopLogin.gd")
const ClientAccount = preload("res://scripts/accounts/ClientAccount.gd")
const AccountFlow = preload("res://scripts/net/AccountFlow.gd")
const PORT := 27996
const DESKTOP_ID := "111-desktop.apps.googleusercontent.com"

var checks := 0
var failures := 0
var key: CryptoKey

func _initialize() -> void:
	Engine.max_fps = 30
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

func wait_for(predicate: Callable, seconds: float = 5.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while not predicate.call() and Time.get_ticks_msec() < deadline:
		await create_timer(0.03).timeout
	return predicate.call()

func query_of(url: String) -> Dictionary:
	return DesktopLogin.parse_request("GET /?%s HTTP/1.1\r\n\r\n" % url.get_slice("?", 1))

## Plays the browser: requests `path` on the loopback redirect and returns the response text.
func browse(redirect: String, path: String) -> String:
	var peer := StreamPeerTCP.new()
	peer.connect_to_host("127.0.0.1", int(redirect.get_slice(":", 2)))
	if not await wait_for(func(): peer.poll(); return peer.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		return ""
	peer.put_data(("GET %s HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n" % path).to_ascii_buffer())
	var response := PackedByteArray()
	await wait_for(func():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED: return true
		var available := peer.get_available_bytes()
		if available > 0: response.append_array(peer.get_partial_data(available)[1])
		return peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or response.size() > 0 and response.get_string_from_utf8().contains("</body>") or response.get_string_from_ascii().begins_with("HTTP/1.1 404"))
	return response.get_string_from_utf8()

func make_controller(label: String):
	var holder := Node.new(); holder.name = label; root.add_child(holder)
	set_multiplayer(SceneMultiplayer.new(), holder.get_path())
	var bootstrap := Node.new(); bootstrap.name = "Bootstrap"; holder.add_child(bootstrap)
	var main := Node.new(); main.name = "Main"; bootstrap.add_child(main)
	var controller := NetworkController.new(); controller.name = "NetworkController"; main.add_child(controller)
	controller.set_room_request("session"); controller.client_nickname = label
	return controller

func run() -> void:
	create_timer(60.0).timeout.connect(func(): printerr("desktop login watchdog"); quit(1))
	key = Crypto.new().generate_rsa(2048)

	# --- the browser half on its own ---
	var opened := []
	var login := DesktopLogin.new()
	login.open_url = func(url): opened.append(url)
	root.add_child(login)
	var done := []
	var failed := []
	login.completed.connect(func(code, verifier, redirect): done.append([code, verifier, redirect]))
	login.failed.connect(func(reason): failed.append(reason))
	check(login.start(DESKTOP_ID, "n".repeat(32)) and opened.size() == 1, "sign-in opens one browser page")
	var query := query_of(String(opened[0]))
	check(String(opened[0]).begins_with(DesktopLogin.AUTH_URL), "the page is Google's")
	check(query.client_id == DESKTOP_ID and query.scope == "openid" and query.nonce == "n".repeat(32) and query.code_challenge_method == "S256", "client, scope, nonce and PKCE method")
	check(String(query.redirect_uri).begins_with("http://127.0.0.1:") and int(String(query.redirect_uri).get_slice(":", 2)) > 0, "the redirect is a loopback port")
	check(query.code_challenge == DesktopLogin.challenge(login.verifier) and login.verifier.length() >= 43, "the challenge is the verifier's SHA-256")
	var redirect := String(query.redirect_uri)
	var forged := await browse(redirect, "/?state=wrong&code=stolen")
	check(forged.begins_with("HTTP/1.1 404") and login.active() and done.is_empty(), "a request with the wrong state is ignored")
	var page := await browse(redirect, "/?state=%s&code=4%%2F0Abc-xyz&scope=openid" % query.state)
	check(page.contains("로그인 완료"), "the browser is told to go back to the game")
	check(done.size() == 1 and done[0][0] == "4/0Abc-xyz" and done[0][1] == login.verifier and done[0][2] == redirect, "the code, verifier and redirect come out decoded")
	check(not login.active(), "the listener closes after the redirect")
	opened.clear()
	login.start(DESKTOP_ID, "m".repeat(32))
	var second := query_of(String(opened[0]))
	await browse(String(second.redirect_uri), "/?state=%s&error=access_denied" % second.state)
	check(failed == ["cancelled"] and not login.active(), "declining in the browser cancels")
	check(second.state != query.state, "every sign-in has a new state")
	login.start(DESKTOP_ID, "m".repeat(32))
	login.elapsed = DesktopLogin.WAIT_SECONDS + 1.0
	await wait_for(func(): return not login.active())
	check(failed.back() == "timeout" and not login.active(), "an abandoned sign-in times out")
	check(AccountFlow.valid_desktop_request("4/0Abc", "a".repeat(43), "http://127.0.0.1:5000"), "a well-formed request")
	check(not AccountFlow.valid_desktop_request("4/0Abc", "a".repeat(43), "http://evil.example:5000"), "only loopback redirects")
	check(not AccountFlow.valid_desktop_request("4/0Abc", "a".repeat(43), "http://127.0.0.1:5000/x"), "no paths on the redirect")
	check(not AccountFlow.valid_desktop_request("a&b=c", "a".repeat(43), "http://127.0.0.1:5000"), "codes cannot smuggle form fields")
	check(not AccountFlow.valid_desktop_request("4/0Abc", "short", "http://127.0.0.1:5000"), "PKCE verifiers have their length")

	# --- the server exchange over real RPCs ---
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_ID", DESKTOP_ID)
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_SECRET", "test-secret")
	var directory := "user://desktop_login_%d" % Time.get_ticks_usec()
	var server = make_controller("Server")
	if not server.start_dedicated_server(PORT): quit(1); return
	server.configure_accounts(directory, false)
	server.google.keys = {"test-key": key}
	check(server.google.client_ids.has(DESKTOP_ID), "the server accepts the desktop client's tokens")
	var exchanged := []
	var issued := {"nonce": ""}
	server.desktop_exchange_override = func(code, verifier, redirect_uri):
		exchanged.append([code, verifier, redirect_uri])
		return AccountTest.token(key, AccountTest.claims(issued.nonce, int(Time.get_unix_time_from_system()), {"sub": "google-pc", "aud": DESKTOP_ID}))
	var client = make_controller("pc")
	client.connect_to_server("127.0.0.1", PORT)
	if not await wait_for(func(): return client.client_connection_state == "lobby"):
		check(false, "the client reaches the lobby"); quit(1); return
	client.client_transport_verified = true

	ClientAccount.desktop_override = 1
	ClientAccount.required_override = 0
	ClientAccount.save_path = directory + "/client_account.json"
	var account = ClientAccount.new()
	root.add_child(account)
	account.setup(client)
	check(account.desktop != null and account.can_sign_in(), "PC offers Google sign-in")
	var browser_urls := []
	account.desktop.open_url = func(url): browser_urls.append(url)
	client.account_nonce_received.connect(func(nonce): issued.nonce = nonce)
	check(account.sign_in(), "the sign-in starts")
	check(await wait_for(func(): return account.waiting_for_browser()), "the game waits for the browser")
	check(account.desktop_client_id == DESKTOP_ID and browser_urls.size() == 1, "the server named the desktop client and the browser opened")
	var trip := query_of(String(browser_urls[0]))
	check(trip.nonce == issued.nonce, "the server's nonce goes into the Google request")
	await browse(String(trip.redirect_uri), "/?state=%s&code=pc-code" % trip.state)
	check(await wait_for(func(): return account.state == "needs_nickname"), "the code becomes a verified sign-in: %s / %s" % [account.state, account.message])
	check(exchanged.size() == 1 and exchanged[0][0] == "pc-code" and exchanged[0][2] == String(trip.redirect_uri), "the server exchanged the code with the verifier and redirect")
	account.create("피씨유저", true)
	check(await wait_for(func(): return account.state == "signed_in"), "a PC account is created")

	# Without the secret the server says PC sign-in is unavailable.
	account.sign_out()
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_SECRET", "")
	account.sign_in()
	check(await wait_for(func(): return account.state == "guest" and account.message.contains("PC 로그인")), "an unconfigured server is reported: %s" % account.message)
	check(not account.desktop.active(), "no browser is opened then")

	# A code sent with a nonce that is gone is refused.
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_SECRET", "test-secret")
	await create_timer(1.2).timeout # the server's per-connection request pacing
	var results := []
	client.account_result_received.connect(func(result): results.append(result))
	# The nonce from the unconfigured attempt is still unused: the first code spends it, a second has none.
	client.account_desktop_login("pc-code", "a".repeat(43), "http://127.0.0.1:5000")
	await wait_for(func(): return not results.is_empty())
	results.clear()
	await create_timer(1.2).timeout
	client.account_desktop_login("pc-code", "a".repeat(43), "http://127.0.0.1:5000")
	check(await wait_for(func(): return not results.is_empty()) and results[0].error == "no_nonce", "a code without a fresh nonce is refused: %s" % [results])

	account.queue_free()
	client.disconnect_from_server()
	server.multiplayer.multiplayer_peer.close()
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_ID", "")
	OS.set_environment("CATWAR_GOOGLE_DESKTOP_CLIENT_SECRET", "")
	ClientAccount.desktop_override = -1
	ClientAccount.required_override = -1
	print("desktop login test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
