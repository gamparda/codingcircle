extends SceneTree

var failures := 0

func expect_true(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	var UpdateManager = load("res://scripts/UpdateManager.gd")
	expect_true(UpdateManager != null, "UpdateManager loads")
	if UpdateManager != null:
		var updater = UpdateManager.new()
		var has_policy: bool = updater.has_method("is_trusted_manifest_url") and updater.has_method("is_trusted_installer_url") and updater.has_method("validate_manifest") and updater.has_method("verify_manifest_signature") and updater.has_method("accept_signed_manifest") and updater.has_method("validated_port") and updater.has_method("random_update_basename") and updater.has_method("build_update_helper_batch")
		expect_true(has_policy, "origin policy methods exist")
		if has_policy:
			expect_true(UpdateManager.is_trusted_manifest_url("https://gamparda.github.io/codingcircle/update.json", false), "official HTTPS manifest is trusted")
			expect_true(not UpdateManager.is_trusted_manifest_url("http://gamparda.github.io/codingcircle/update.json", false), "HTTP manifest is rejected by default")
			expect_true(not UpdateManager.is_trusted_manifest_url("https://gamparda.github.io.evil.example/codingcircle/update.json", false), "lookalike manifest host is rejected")
			expect_true(not UpdateManager.is_trusted_manifest_url("https://evil.example/update.json", false), "arbitrary HTTPS manifest host is rejected")
			expect_true(UpdateManager.is_trusted_installer_url("https://gamparda.github.io/codingcircle/CatWarSetup.exe", false), "official HTTPS installer is trusted")
			expect_true(not UpdateManager.is_trusted_installer_url("https://evil.example/CatWarSetup.exe", false), "arbitrary HTTPS installer host is rejected")
			var valid_manifest := {
				"version": "0.3.9",
				"commit": "0123456789abcdef0123456789abcdef01234567",
				"installer_url": "https://gamparda.github.io/codingcircle/CatWarSetup.exe",
				"sha256": "a".repeat(64),
				"mandatory": true,
				"published_at": "2026-08-30T00:00:00Z",
			}
			expect_true(UpdateManager.validate_manifest(valid_manifest, false), "well-formed official manifest is accepted")
			var malformed := valid_manifest.duplicate()
			malformed.version = "0.3.x"
			expect_true(not UpdateManager.validate_manifest(malformed, false), "non-numeric version fails closed")
			malformed = valid_manifest.duplicate()
			malformed.sha256 = "abc"
			expect_true(not UpdateManager.validate_manifest(malformed, false), "short hash fails closed")
			malformed = valid_manifest.duplicate()
			malformed.mandatory = false
			expect_true(not UpdateManager.validate_manifest(malformed, false), "non-mandatory manifest fails closed")
			malformed = valid_manifest.duplicate()
			malformed.commit = 123
			expect_true(not UpdateManager.validate_manifest(malformed, false), "wrong field type fails closed")
			var production_key := CryptoKey.new()
			expect_true(not UpdateManager.MANIFEST_PUBLIC_KEY_PEM.is_empty(), "production manifest public key is provisioned")
			expect_true(production_key.load_from_string(UpdateManager.MANIFEST_PUBLIC_KEY_PEM, true) == OK and production_key.is_public_only(), "production manifest public key parses as public-only RSA")
			var crypto := Crypto.new()
			var signing_key := crypto.generate_rsa(2048)
			var manifest_bytes := JSON.stringify(valid_manifest).to_utf8_buffer()
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_SHA256)
			hashing.update(manifest_bytes)
			var digest := hashing.finish()
			var signature := crypto.sign(HashingContext.HASH_SHA256, digest, signing_key)
			var public_key_pem := signing_key.save_to_string(true)
			var signature_b64 := Marshalls.raw_to_base64(signature)
			expect_true(UpdateManager.verify_manifest_signature(manifest_bytes, signature_b64, public_key_pem), "valid manifest signature is accepted")
			expect_true(not UpdateManager.verify_manifest_signature("tampered".to_utf8_buffer(), signature_b64, public_key_pem), "tampered manifest is rejected")
			expect_true(not UpdateManager.verify_manifest_signature(manifest_bytes, signature_b64, ""), "missing production public key fails closed")
			updater.manifest_public_key_pem = public_key_pem
			updater.current_version = "0.3.8"
			expect_true(updater.accept_signed_manifest(manifest_bytes, signature_b64), "verified manifest enters update flow")
			expect_true(updater.state == "waiting_safe", "verified newer manifest waits for safe point")
			updater.state = "checking_signature"
			expect_true(not updater.accept_signed_manifest("tampered".to_utf8_buffer(), signature_b64), "unverified manifest is rejected by update flow")
			expect_true(updater.manifest.is_empty() and updater.state == "failed", "unverified manifest fails closed")
			expect_true(UpdateManager.validated_port("1") == 1, "lowest UDP port is accepted")
			expect_true(UpdateManager.validated_port("65535") == 65535, "highest UDP port is accepted")
			expect_true(UpdateManager.validated_port("0") == -1, "zero port is rejected")
			expect_true(UpdateManager.validated_port("65536") == -1, "out-of-range port is rejected")
			expect_true(UpdateManager.validated_port("7777&calc") == -1, "command syntax in port is rejected")
			expect_true(UpdateManager.validated_port("+7777") == -1, "signed port is rejected")
			var first_name: String = UpdateManager.random_update_basename("exe")
			var second_name: String = UpdateManager.random_update_basename("exe")
			var update_name_pattern := RegEx.create_from_string("^catwar-update-[0-9a-f]{32}\\.exe$")
			expect_true(first_name != second_name, "per-update filenames are unpredictable")
			expect_true(update_name_pattern.search(first_name) != null, "random installer name is batch-safe")
			var helper_batch: String = UpdateManager.build_update_helper_batch(
				first_name,
				"catwar-update-0123456789abcdef0123456789abcdef.bak",
				"C:\\Games\\Cat War\\CatWar.exe",
				"C:\\Games\\Cat War",
				"b".repeat(64),
				"7777&calc"
			)
			var hash_check_at := helper_batch.find("certutil.exe -hashfile")
			var installer_launch_at := helper_batch.find(" /VERYSILENT")
			expect_true(hash_check_at >= 0 and installer_launch_at > hash_check_at, "helper re-checks hash before installer launch")
			expect_true(helper_batch.contains("if errorlevel 1 goto rollback"), "hash mismatch aborts installation")
			expect_true(helper_batch.contains(":rollback") and helper_batch.count("robocopy.exe") >= 2 and helper_batch.contains("/MIR"), "failed installation restores the complete previous install")
			expect_true(helper_batch.contains("if errorlevel 8 goto restore_failed"), "failed restore preserves backup for manual recovery")
			expect_true(not helper_batch.contains("7777&calc") and helper_batch.contains("--port=7777"), "invalid restart port never reaches batch interpolation")
		updater.free()
	finish()

func finish() -> void:
	if failures == 0:
		print("PASS: Windows updater origin policy")
		quit(0)
	else:
		printerr("FAILED: %d Windows updater origin checks" % failures)
		quit(1)
