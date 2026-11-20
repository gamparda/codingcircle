extends SceneTree
## The engine download accepts only this game data's rules and this platform's library from the official channel.
const NF = preload("res://scripts/NativeFetch.gd")
const RulesHash = preload("res://scripts/BattleRulesHash.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)
func _init() -> void:
	var sha := "a".repeat(64)
	var manifest := {"native_rules_hash": RulesHash.HASH,
		"native_android_arm64_url": "https://gamparda.github.io/codingcircle/libbattle_native.android.arm64.so", "native_android_arm64_sha256": sha,
		"native_windows_x86_64_url": "https://gamparda.github.io/codingcircle/libbattle_native.windows.x86_64.dll", "native_windows_x86_64_sha256": sha}
	check(NF.manifest_entry(manifest, "android.arm64").get("url", "").ends_with(".android.arm64.so"), "the official arm64 engine is accepted")
	check(not NF.manifest_entry(manifest, "windows.x86_64").is_empty(), "the official Windows engine is accepted")
	check(NF.manifest_entry(manifest, "android.arm32").is_empty(), "a platform without an entry gets nothing")
	var other := manifest.duplicate()
	other.native_rules_hash = "0".repeat(64)
	check(NF.manifest_entry(other, "android.arm64").is_empty(), "an engine for other rules is refused")
	var foreign := manifest.duplicate()
	foreign.native_android_arm64_url = "https://example.com/libbattle_native.android.arm64.so"
	check(NF.manifest_entry(foreign, "android.arm64").is_empty(), "a library from elsewhere is refused")
	var wrong := manifest.duplicate()
	wrong.native_android_arm64_url = "https://gamparda.github.io/codingcircle/CatWar.apk"
	check(NF.manifest_entry(wrong, "android.arm64").is_empty(), "a file that is not this platform's library is refused")
	var bad_sha := manifest.duplicate()
	bad_sha.native_android_arm64_sha256 = "xyz"
	check(NF.manifest_entry(bad_sha, "android.arm64").is_empty(), "a malformed checksum is refused")
	print("PASS: native fetch checks" if failures == 0 else "FAILED: %d" % failures)
	quit(0 if failures == 0 else 1)
