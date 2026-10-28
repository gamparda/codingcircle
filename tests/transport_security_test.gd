extends SceneTree
# DTLS on every ENet link: development servers are encrypted, official clients verify the server.
const TransportSecurity = preload("res://scripts/net/TransportSecurity.gd")
const PORT := 27993

var checks := 0
var failures := 0
var server

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

## Raw ENet client with the given DTLS setup (or none); returns the final connection status.
func raw_connect(hostname: String, options: TLSOptions) -> int:
	var mp := SceneMultiplayer.new()
	var peer := ENetMultiplayerPeer.new()
	peer.create_client("127.0.0.1", PORT)
	if options != null: peer.host.dtls_client_setup(hostname, options)
	mp.multiplayer_peer = peer
	var deadline := Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		mp.poll()
		await create_timer(0.02).timeout
	var status := peer.get_connection_status()
	peer.close()
	return status

func run() -> void:
	check(TransportSecurity.is_official_address("ruellyya.kr") and TransportSecurity.is_official_address(" 211.176.222.145 ") and TransportSecurity.is_official_address("192.168.0.4"), "every official address is recognised")
	check(not TransportSecurity.is_official_address("127.0.0.1") and not TransportSecurity.is_official_address("ruellyya.kr.example.com"), "other addresses are not official")
	check(TransportSecurity.client_hostname("211.176.222.145") == "ruellyya.kr", "the bare official IP is verified as the official hostname")

	OS.set_environment(TransportSecurity.CERT_ENV, "/nonexistent/fullchain.pem")
	OS.set_environment(TransportSecurity.KEY_ENV, "/nonexistent/privkey.pem")
	check(TransportSecurity.server_options() == null, "an unreadable configured certificate refuses to start rather than downgrade")
	var broken = make_controller("BrokenServer")
	check(not broken.start_dedicated_server(PORT), "the server does not start without its configured certificate")
	OS.unset_environment(TransportSecurity.CERT_ENV)
	OS.unset_environment(TransportSecurity.KEY_ENV)

	server = make_controller("Server")
	check(server.start_dedicated_server(PORT), "a development server starts with the public development identity")
	var client = make_controller("Client")
	client.connect_to_server("127.0.0.1", PORT)
	var deadline := Time.get_ticks_msec() + 5000
	while client.client_connection_state != "lobby" and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	check(client.client_connection_state == "lobby", "a client reaches the lobby over DTLS")
	check(not client.client_transport_verified, "a development server is never marked verified")
	client.disconnect_from_server()

	check(await raw_connect("", null) != MultiplayerPeer.CONNECTION_CONNECTED, "an unencrypted client cannot connect")
	check(await raw_connect("ruellyya.kr", TLSOptions.client()) != MultiplayerPeer.CONNECTION_CONNECTED, "an official client refuses a server without the official certificate")
	var dev := X509Certificate.new(); dev.load_from_string(TransportSecurity.DEV_CERT)
	check(await raw_connect("keepfall-dev", TLSOptions.client(dev, "keepfall-dev")) == MultiplayerPeer.CONNECTION_CONNECTED, "the development identity itself completes a verified handshake")

	server.multiplayer.multiplayer_peer.close()
	if failures == 0: print("PASS: %d DTLS transport checks" % checks)
	quit(1 if failures else 0)
