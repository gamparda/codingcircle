extends Node
## PC Google sign-in: opens Google's sign-in page in the browser and waits on a loopback address
## (127.0.0.1, a free port) for the redirect that carries the authorization code (OAuth 2.0 for installed
## apps, with PKCE and a random state). The code, the PKCE verifier and the redirect go to the official
## server, which trades them for an ID token with the desktop client's secret: the game never holds it.

signal completed(code: String, verifier: String, redirect_uri: String)
signal failed(reason: String)

const AUTH_URL := "https://accounts.google.com/o/oauth2/v2/auth"
## The whole browser round trip; the server's nonce lasts a little longer (AccountFlow.NONCE_SECONDS).
const WAIT_SECONDS := 240.0
const MAX_REQUEST_BYTES := 8192
const CONNECTION_SECONDS := 5.0

const PAGE_DONE := "<!doctype html><meta charset=utf-8><title>Keepfall</title><body style=\"font-family:sans-serif;background:#0c1220;color:#eef2fb;text-align:center;padding-top:15vh\"><h1>로그인 완료</h1><p>게임으로 돌아가세요. 이 창은 닫아도 됩니다.</p></body>"
const PAGE_FAILED := "<!doctype html><meta charset=utf-8><title>Keepfall</title><body style=\"font-family:sans-serif;background:#0c1220;color:#eef2fb;text-align:center;padding-top:15vh\"><h1>로그인하지 않았습니다</h1><p>게임으로 돌아가 다시 시도하세요.</p></body>"

## Tests replace the browser: receives the sign-in URL instead of opening it.
var open_url := func(url: String): OS.shell_open(url)

var server: TCPServer = null
var connections: Array = [] # {"peer": StreamPeerTCP, "data": PackedByteArray, "age": float}
var state := ""
var verifier := ""
var redirect_uri := ""
var elapsed := 0.0

func active() -> bool:
	return server != null

## Starts a sign-in for OAuth client `client_id`; `nonce` is the server's, bound into the ID token.
func start(client_id: String, nonce: String) -> bool:
	cancel()
	server = TCPServer.new()
	if server.listen(0, "127.0.0.1") != OK:
		server = null
		return false
	var crypto := Crypto.new()
	verifier = base64url(crypto.generate_random_bytes(32))
	state = crypto.generate_random_bytes(16).hex_encode()
	redirect_uri = "http://127.0.0.1:%d" % server.get_local_port()
	elapsed = 0.0
	open_url.call(auth_url(client_id, redirect_uri, challenge(verifier), state, nonce))
	return true

func cancel() -> void:
	for connection in connections:
		connection.peer.disconnect_from_host()
	connections.clear()
	if server != null:
		server.stop()
	server = null

static func auth_url(client_id: String, redirect: String, code_challenge: String, request_state: String, nonce: String) -> String:
	var query := {"response_type": "code", "client_id": client_id, "redirect_uri": redirect, "scope": "openid",
		"code_challenge": code_challenge, "code_challenge_method": "S256", "state": request_state, "nonce": nonce, "prompt": "select_account"}
	var parts := PackedStringArray()
	for key in query:
		parts.append("%s=%s" % [key, String(query[key]).uri_encode()])
	return AUTH_URL + "?" + "&".join(parts)

static func base64url(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

static func challenge(code_verifier: String) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(code_verifier.to_ascii_buffer())
	return base64url(hashing.finish())

## The query parameters of an HTTP request line ("GET /?a=1&b=2 HTTP/1.1"), or {} when it is not a GET.
static func parse_request(text: String) -> Dictionary:
	var line := text.get_slice("\r\n", 0)
	var words := line.split(" ")
	if words.size() < 2 or words[0] != "GET":
		return {}
	var target := words[1]
	var query := target.get_slice("?", 1) if target.contains("?") else ""
	var values := {"_path": target.get_slice("?", 0)}
	for pair in query.split("&", false):
		var key := pair.get_slice("=", 0).uri_decode()
		values[key] = pair.substr(pair.find("=") + 1).uri_decode() if pair.contains("=") else ""
	return values

func _process(delta: float) -> void:
	if server == null:
		return
	elapsed += delta
	if elapsed > WAIT_SECONDS:
		cancel()
		failed.emit("timeout")
		return
	while server != null and server.is_connection_available():
		connections.append({"peer": server.take_connection(), "data": PackedByteArray(), "age": 0.0})
	for connection in connections.duplicate():
		if server == null:
			return
		_serve(connection, delta)

func _serve(connection: Dictionary, delta: float) -> void:
	var peer: StreamPeerTCP = connection.peer
	peer.poll()
	connection.age += delta
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or connection.age > CONNECTION_SECONDS:
		_drop(connection)
		return
	var available := peer.get_available_bytes()
	if available > 0:
		var chunk: Array = peer.get_partial_data(mini(available, MAX_REQUEST_BYTES))
		if int(chunk[0]) == OK:
			connection.data.append_array(chunk[1])
	if connection.data.size() > MAX_REQUEST_BYTES:
		_drop(connection)
		return
	var text: String = connection.data.get_string_from_ascii()
	if not text.contains("\r\n\r\n"):
		return
	var query := parse_request(text)
	if query.is_empty() or String(query.get("state", "")) != state:
		# Not our redirect (a favicon, another page, a forged request): answer and keep waiting.
		_reply(peer, 404, "")
		_drop(connection)
		return
	var code := String(query.get("code", ""))
	_reply(peer, 200, PAGE_DONE if not code.is_empty() else PAGE_FAILED)
	_drop(connection)
	var result := {"code": code, "verifier": verifier, "redirect": redirect_uri, "error": String(query.get("error", ""))}
	cancel()
	if code.is_empty():
		failed.emit("cancelled" if result.error == "access_denied" else "denied")
	else:
		completed.emit(result.code, result.verifier, result.redirect)

func _reply(peer: StreamPeerTCP, status: int, html: String) -> void:
	var body := html.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n" % [status, "OK" if status == 200 else "Not Found", body.size()]
	peer.put_data(head.to_ascii_buffer())
	if not body.is_empty():
		peer.put_data(body)

func _drop(connection: Dictionary) -> void:
	connection.peer.disconnect_from_host()
	connections.erase(connection)
