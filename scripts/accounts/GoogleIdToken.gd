extends RefCounted
## Verifies Google ID tokens (RS256 JWTs) offline against Google's published signing keys (JWKS).
## Only the token's subject ("sub", Google's stable account ID) is used; e-mail and profile claims
## are never read or kept.

## Public OAuth client IDs whose tokens are accepted (the Android app requests tokens for the web
## client). CATWAR_GOOGLE_CLIENT_IDS (comma-separated) replaces the list. The PC sign-in's desktop client
## (CATWAR_GOOGLE_DESKTOP_CLIENT_ID, see AccountFlow) is accepted as well.
const DEFAULT_CLIENT_IDS := ["36479821399-4n3unj8u7isrvjke1aopjp380hlt7jln.apps.googleusercontent.com"]
const CLIENT_IDS_ENV := "CATWAR_GOOGLE_CLIENT_IDS"
const DESKTOP_CLIENT_ID_ENV := "CATWAR_GOOGLE_DESKTOP_CLIENT_ID"
const JWKS_URL := "https://www.googleapis.com/oauth2/v3/certs"
const ISSUERS := ["accounts.google.com", "https://accounts.google.com"]
const CLOCK_SKEW := 300
const MAX_TOKEN_LENGTH := 4096

var client_ids: Array = []
## kid -> CryptoKey (public)
var keys: Dictionary = {}

func _init() -> void:
	var configured := OS.get_environment(CLIENT_IDS_ENV).strip_edges()
	client_ids = DEFAULT_CLIENT_IDS.duplicate() if configured.is_empty() else Array(configured.split(",", false)).map(func(id): return String(id).strip_edges())
	var desktop := OS.get_environment(DESKTOP_CLIENT_ID_ENV).strip_edges()
	if not desktop.is_empty() and not client_ids.has(desktop):
		client_ids.append(desktop)

## Replaces the signing keys with a JWKS document ({"keys": [{kid, kty, alg, n, e}, ...]}).
## Returns how many RSA keys were loaded.
func load_jwks(document: Variant) -> int:
	if not document is Dictionary or not document.get("keys") is Array:
		return 0
	var loaded := {}
	for entry in document.keys:
		if not entry is Dictionary or entry.get("kty") != "RSA" or not entry.get("kid") is String or not entry.get("n") is String or not entry.get("e") is String:
			continue
		var key := rsa_public_key(base64url_decode(entry.n), base64url_decode(entry.e))
		if key != null:
			loaded[String(entry.kid)] = key
	if not loaded.is_empty():
		keys = loaded
	return loaded.size()

func has_key(kid: String) -> bool:
	return keys.has(kid)

## Returns {"ok": true, "subject": sub} or {"ok": false, "error": reason, "kid": kid}.
## `nonce` must match the one the server handed this client, so a token cannot be replayed elsewhere.
func verify(token: String, nonce: String, now: int = -1) -> Dictionary:
	if now < 0:
		now = int(Time.get_unix_time_from_system())
	if token.length() > MAX_TOKEN_LENGTH:
		return _fail("malformed")
	var parts := token.split(".")
	if parts.size() != 3:
		return _fail("malformed")
	var header = JSON.parse_string(base64url_decode(parts[0]).get_string_from_utf8())
	var claims = JSON.parse_string(base64url_decode(parts[1]).get_string_from_utf8())
	if not header is Dictionary or not claims is Dictionary or header.get("alg") != "RS256" or not header.get("kid") is String:
		return _fail("malformed")
	var kid := String(header.kid)
	if not keys.has(kid):
		return _fail("unknown_key", kid)
	var signed := HashingContext.new()
	signed.start(HashingContext.HASH_SHA256)
	signed.update((parts[0] + "." + parts[1]).to_utf8_buffer())
	if not Crypto.new().verify(HashingContext.HASH_SHA256, signed.finish(), base64url_decode(parts[2]), keys[kid]):
		return _fail("bad_signature")
	if not String(claims.get("iss", "")) in ISSUERS:
		return _fail("wrong_issuer")
	if not String(claims.get("aud", "")) in client_ids:
		return _fail("wrong_audience")
	if not _is_number(claims.get("exp")) or not _is_number(claims.get("iat")) or float(claims.exp) + CLOCK_SKEW < now or float(claims.iat) - CLOCK_SKEW > now:
		return _fail("expired")
	if nonce.is_empty() or String(claims.get("nonce", "")) != nonce:
		return _fail("wrong_nonce")
	var subject := String(claims.get("sub", ""))
	if subject.is_empty() or subject.length() > 255:
		return _fail("malformed")
	return {"ok": true, "subject": subject}

static func _fail(error: String, kid: String = "") -> Dictionary:
	return {"ok": false, "error": error, "kid": kid}

static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func base64url_decode(text: String) -> PackedByteArray:
	var normal := text.replace("-", "+").replace("_", "/")
	while normal.length() % 4 != 0:
		normal += "="
	return Marshalls.base64_to_raw(normal)

static func base64url_encode(bytes: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(bytes).replace("+", "-").replace("/", "_").replace("=", "")

## Builds an RSA public key from its modulus and exponent (as found in a JWKS entry).
static func rsa_public_key(modulus: PackedByteArray, exponent: PackedByteArray) -> CryptoKey:
	if modulus.size() < 128 or exponent.is_empty():
		return null
	var rsa_key := _der(0x30, _der_integer(modulus) + _der_integer(exponent))
	var bit_string := PackedByteArray([0]) + rsa_key
	# AlgorithmIdentifier: rsaEncryption (1.2.840.113549.1.1.1) with NULL parameters.
	var algorithm := PackedByteArray([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
	var info := _der(0x30, algorithm + _der(0x03, bit_string))
	var pem := "-----BEGIN PUBLIC KEY-----\n%s\n-----END PUBLIC KEY-----\n" % Marshalls.raw_to_base64(info)
	var key := CryptoKey.new()
	return key if key.load_from_string(pem, true) == OK else null

static func _der_integer(value: PackedByteArray) -> PackedByteArray:
	var start := 0
	while start < value.size() - 1 and value[start] == 0:
		start += 1
	var body := value.slice(start)
	if body[0] & 0x80:
		body = PackedByteArray([0]) + body
	return _der(0x02, body)

static func _der(tag: int, body: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray([tag])
	var length := body.size()
	if length < 0x80:
		out.append(length)
	else:
		var length_bytes := PackedByteArray()
		while length > 0:
			length_bytes.insert(0, length & 0xff)
			length >>= 8
		out.append(0x80 | length_bytes.size())
		out.append_array(length_bytes)
	out.append_array(body)
	return out
