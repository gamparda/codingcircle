extends SceneTree
# Google ID token verification and the server account store, offline with a locally generated key.
const GoogleIdToken = preload("res://scripts/accounts/GoogleIdToken.gd")
const AccountStore = preload("res://scripts/accounts/AccountStore.gd")

var checks := 0
var failures := 0
var crypto := Crypto.new()
var signing_key: CryptoKey

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", message)

static func token(key: CryptoKey, claims: Dictionary, kid: String = "test-key") -> String:
	var header := GoogleIdToken.base64url_encode(JSON.stringify({"alg": "RS256", "kid": kid, "typ": "JWT"}).to_utf8_buffer())
	var body := GoogleIdToken.base64url_encode(JSON.stringify(claims).to_utf8_buffer())
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update((header + "." + body).to_utf8_buffer())
	return header + "." + body + "." + GoogleIdToken.base64url_encode(Crypto.new().sign(HashingContext.HASH_SHA256, hashing.finish(), key))

static func claims(nonce: String, now: int, overrides: Dictionary = {}) -> Dictionary:
	var value := {"iss": "https://accounts.google.com", "aud": GoogleIdToken.DEFAULT_CLIENT_IDS[0], "sub": "1234567890", "iat": now, "exp": now + 3600, "nonce": nonce, "email": "someone@example.com"}
	value.merge(overrides, true)
	return value

## Reads n and e out of a SubjectPublicKeyInfo DER, as a JWKS publisher would expose them.
static func modulus_and_exponent(public_pem: String) -> Array:
	var body := PackedStringArray()
	for line in public_pem.split("\n"):
		if not line.begins_with("-----"): body.append(line)
	var der := Marshalls.base64_to_raw("".join(body))
	var integers: Array = []
	var index := 0
	while index < der.size() and integers.size() < 2:
		var tag := der[index]
		var length := der[index + 1]
		var offset := index + 2
		if length & 0x80:
			var count := length & 0x7f
			length = 0
			for i in count: length = (length << 8) | der[offset + i]
			offset += count
		if tag == 0x02:
			integers.append(der.slice(offset, offset + length))
			index = offset + length
		elif tag == 0x03:
			index = offset + 1 # skip the unused-bits byte and step into the bit string
		elif tag == 0x30:
			index = offset # step into sequences
		else:
			index = offset + length
	return integers

func _initialize() -> void:
	signing_key = crypto.generate_rsa(2048)
	var verifier := GoogleIdToken.new()
	var public_pem := signing_key.save_to_string(true)
	var parts := modulus_and_exponent(public_pem)
	check(parts.size() == 2, "the test key exposes a modulus and exponent")
	var rebuilt := GoogleIdToken.rsa_public_key(parts[0], parts[1])
	check(rebuilt != null and rebuilt.save_to_string(true) == public_pem, "a JWKS modulus/exponent rebuilds the same public key")
	var jwks := {"keys": [{"kid": "test-key", "kty": "RSA", "alg": "RS256", "use": "sig", "n": GoogleIdToken.base64url_encode(parts[0]), "e": GoogleIdToken.base64url_encode(parts[1])}, {"kid": "ec", "kty": "EC"}]}
	check(verifier.load_jwks(jwks) == 1 and verifier.has_key("test-key"), "RSA keys load from a JWKS document; others are skipped")
	check(verifier.load_jwks({"keys": []}) == 0 and verifier.has_key("test-key"), "an empty key document keeps the previous keys")

	var now := 1_800_000_000
	var nonce := "0123456789abcdef0123456789abcdef"
	var ok := verifier.verify(token(signing_key, claims(nonce, now)), nonce, now)
	check(ok.ok and ok.subject == "1234567890" and ok.size() == 2, "a valid token yields only the Google subject")
	check(verifier.verify(token(signing_key, claims(nonce, now)), "ffffffffffffffffffffffffffffffff", now).error == "wrong_nonce", "a token issued for another nonce is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now)), "", now).error == "wrong_nonce", "a missing nonce is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now, {"aud": "someone-else.apps.googleusercontent.com"})), nonce, now).error == "wrong_audience", "a token for another app is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now, {"iss": "https://evil.example"})), nonce, now).error == "wrong_issuer", "a token from another issuer is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now, {"exp": now - 1000})), nonce, now).error == "expired", "an expired token is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now, {"iat": now + 1000})), nonce, now).error == "expired", "a token from the future is refused")
	check(verifier.verify(token(signing_key, claims(nonce, now), "rotated"), nonce, now).error == "unknown_key", "an unknown key ID asks for a key refresh")
	var forged := crypto.generate_rsa(2048)
	check(verifier.verify(token(forged, claims(nonce, now)), nonce, now).error == "bad_signature", "a token signed by anyone else is refused")
	var good := token(signing_key, claims(nonce, now)).split(".")
	var tampered := GoogleIdToken.base64url_encode(JSON.stringify(claims(nonce, now, {"sub": "999"})).to_utf8_buffer())
	check(verifier.verify(good[0] + "." + tampered + "." + good[2], nonce, now).error == "bad_signature", "changing the subject breaks the signature")
	check(verifier.verify("not.a.token", nonce, now).error == "malformed" and verifier.verify("x".repeat(5000), nonce, now).error == "malformed", "malformed and oversized tokens are refused")
	var none_header := GoogleIdToken.base64url_encode(JSON.stringify({"alg": "none", "kid": "test-key"}).to_utf8_buffer())
	check(verifier.verify(none_header + "." + good[1] + ".", nonce, now).error == "malformed", "unsigned tokens are refused")

	var directory := "user://account_test_%d" % Time.get_ticks_usec()
	var store := AccountStore.new()
	store.configure(directory)
	check(store.salt.length() == 64 and FileAccess.file_exists(directory.path_join(AccountStore.FILE_NAME)), "a new store gets a random salt on disk")
	var created := store.create("google-sub-1", "마왕군주", now)
	check(created.has("id") and store.find_by_subject("google-sub-1") == created.id, "an account is found by its Google subject")
	check(not FileAccess.get_file_as_string(directory.path_join(AccountStore.FILE_NAME)).contains("google-sub-1"), "the raw Google subject is never written")
	check(store.create("google-sub-1", "다른이름", now).error == "exists", "one account per Google subject")
	check(store.create("google-sub-2", "마왕군주", now).error == "nickname_taken" and store.create("google-sub-2", " 마왕군주 ", now).error == "invalid_nickname", "nicknames are unique and trimmed")
	check(store.create("google-sub-3", "ABC", now).has("id") and store.create("google-sub-4", "abc", now).error == "nickname_taken", "nickname uniqueness ignores case")
	check(store.create("google-sub-5", "", now).error == "invalid_nickname" and store.create("google-sub-5", "a".repeat(17), now).error == "invalid_nickname" and store.create("google-sub-5", "줄\n바꿈", now).error == "invalid_nickname", "empty, long and control-character nicknames are refused")
	var id: String = created.id
	var session := store.issue_session(id, now)
	store.flush()
	check(session.length() == 64 and not FileAccess.get_file_as_string(directory.path_join(AccountStore.FILE_NAME)).contains(session), "session tokens are stored only as hashes")
	check(store.resume(session, now + 10) == id, "a session token resumes its account")
	check(store.resume(session, now + AccountStore.SESSION_SECONDS + 1).is_empty() and store.resume(session, now + 20).is_empty(), "an expired session stops working for good")
	session = store.issue_session(id, now)
	var sessions: Array = []
	for i in AccountStore.MAX_SESSIONS + 2: sessions.append(store.issue_session(id, now + i))
	check(store.accounts[id].sessions.size() == AccountStore.MAX_SESSIONS and store.resume(session, now + 100).is_empty() and store.resume(sessions.back(), now + 100) == id, "only the newest sessions are kept")
	store.revoke(sessions.back())
	check(store.resume(sessions.back(), now + 100).is_empty(), "a revoked session no longer works")
	check(store.rename(id, "abc") == "nickname_taken" and store.rename(id, "새이름") == "" and not store.nickname_taken("마왕군주") and store.nickname_taken("새이름"), "renaming frees the old nickname")
	store.flush()
	var reloaded := AccountStore.new()
	reloaded.configure(directory)
	check(reloaded.salt == store.salt and reloaded.find_by_subject("google-sub-1") == id and reloaded.profile(id).nickname == "새이름" and reloaded.resume(sessions[sessions.size() - 2], now + 100) == id, "accounts and sessions survive a restart")
	check(reloaded.delete(id) and reloaded.find_by_subject("google-sub-1").is_empty() and not reloaded.nickname_taken("새이름") and reloaded.resume(sessions[sessions.size() - 2], now + 100).is_empty(), "deleting an account frees its subject, nickname and sessions")
	reloaded.flush()
	var after := AccountStore.new()
	after.configure(directory)
	check(after.profile(id).is_empty() and after.create("google-sub-1", "새이름", now).has("id"), "a deleted account stays deleted and the person can sign up again")
	for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)

	if failures == 0: print("PASS: %d Google token and account store checks" % checks)
	quit(1 if failures else 0)
