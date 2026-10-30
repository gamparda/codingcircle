extends SceneTree
## Patched content updates: from the installed files and a few Range requests PackPatcher rebuilds the new pack
## byte for byte, fetching only the changed files; too big a change, a wrong checksum or a broken pack fails so
## the launcher downloads the whole pack instead. The packs are built with PCKPacker like the exported ones.
const PackPatcher = preload("res://scripts/PackPatcher.gd")

var failures := 0
var directory := ""

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func bytes_of(seed_value: int, size: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedByteArray()
	out.resize(size)
	for i in size:
		out[i] = rng.randi() & 255
	return out

## Writes `files` (path -> bytes) into a pack at `name` and returns its path.
func pack(name: String, files: Dictionary) -> String:
	var packer := PCKPacker.new()
	var path := directory + "/" + name
	packer.pck_start(path)
	for file_path in files:
		var source := directory + "/src_" + String(file_path).replace("/", "_")
		var out := FileAccess.open(source, FileAccess.WRITE)
		out.store_buffer(files[file_path])
		out.close()
		packer.add_file("res://" + String(file_path), source)
	packer.flush()
	return path

## Runs a patch of the pack at `new_path` against `installed` files; returns the patcher after it finished.
func patch(new_path: String, installed: Dictionary, sha: String = "") -> PackPatcher:
	var served := FileAccess.get_file_as_bytes(new_path)
	var patcher := PackPatcher.new()
	patcher.fetch_override = func(from: int, to: int) -> Dictionary:
		return {"bytes": served.slice(from, mini(to + 1, served.size())), "total": served.size()}
	patcher.local_bytes = func(path: String) -> PackedByteArray:
		return installed.get(path, PackedByteArray())
	root.add_child(patcher)
	var done := []
	patcher.finished.connect(func(ok): done.append(ok))
	patcher.start("https://example.invalid/new.pck", directory + "/pending.pck", sha if not sha.is_empty() else FileAccess.get_sha256(new_path))
	for frame in 600:
		if not done.is_empty():
			break
		await process_frame
	patcher.set_meta("ok", not done.is_empty() and bool(done[0]))
	return patcher

func run() -> void:
	directory = ProjectSettings.globalize_path("user://pack_patcher_test_%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(directory)
	var old_files := {}
	for i in 40:
		old_files["data/file_%02d.bin" % i] = bytes_of(i, 20000 + i * 1500)
	old_files["scripts/main.gdc"] = bytes_of(900, 8000)
	var new_files := old_files.duplicate()
	new_files["scripts/main.gdc"] = bytes_of(901, 8300) # changed code
	new_files["data/file_07.bin"] = bytes_of(907, 31000) # changed art
	new_files["data/added.bin"] = bytes_of(999, 12000) # a new file
	new_files.erase("data/file_30.bin") # a removed file
	var new_path := pack("new.pck", new_files)
	var new_sha := FileAccess.get_sha256(new_path)
	var total := FileAccess.get_file_as_bytes(new_path).size()

	var patcher := await patch(new_path, old_files)
	check(bool(patcher.get_meta("ok")), "a patch from the installed files succeeds: %s" % patcher.reason)
	check(FileAccess.get_sha256(directory + "/pending.pck") == new_sha, "the rebuilt pack is the new pack byte for byte")
	check(patcher.remote_bytes < 80000 and patcher.remote_bytes < total / 5, "only the changed files are downloaded (%d of %d bytes)" % [patcher.remote_bytes, total])
	# A big installed file straddling the first request's 64 KB is copied, not downloaded again.
	var big_old := {"data/a_big.bin": bytes_of(77, 150000), "data/b.bin": bytes_of(78, 30000)}
	var big_new := big_old.duplicate()
	big_new["data/b.bin"] = bytes_of(79, 30000)
	var big := await patch(pack("big.pck", big_new), big_old)
	check(bool(big.get_meta("ok")) and big.remote_bytes <= 30000 + 64, "a file across the first 64 KB is copied (%d bytes fetched)" % big.remote_bytes)
	await patch(new_path, old_files)
	var info = JSON.parse_string(FileAccess.get_file_as_string(directory + "/pending.pck.json"))
	check(info is Dictionary and String(info.key) == new_sha and int(info.total) == total, "it is left as a finished download for the launcher")

	# From an older install with more differences it still lands on the same pack.
	var older := old_files.duplicate()
	for i in range(0, 8):
		older["data/file_%02d.bin" % i] = bytes_of(500 + i, 9000)
	var from_older := await patch(new_path, older)
	check(bool(from_older.get_meta("ok")) and FileAccess.get_sha256(directory + "/pending.pck") == new_sha, "an install several versions behind patches straight to the newest")
	check(from_older.remote_bytes > patcher.remote_bytes, "and downloads more of it")

	# Nothing installed in common: a full download is better.
	var nothing := await patch(new_path, {})
	check(not bool(nothing.get_meta("ok")) and nothing.reason == "not_worth", "with little in common it leaves it to the full download (%s)" % nothing.reason)
	check(not FileAccess.file_exists(directory + "/pending.pck") and not FileAccess.file_exists(directory + "/pending.pck.json"), "and leaves nothing half-built behind")

	# A pack that does not match the published checksum is refused.
	var wrong := await patch(new_path, old_files, "0".repeat(64))
	check(not bool(wrong.get_meta("ok")) and wrong.reason == "checksum" and not FileAccess.file_exists(directory + "/pending.pck"), "a result with the wrong SHA-256 is thrown away")

	# Not a pack at all.
	var junk_path := directory + "/junk.pck"
	var junk := FileAccess.open(junk_path, FileAccess.WRITE)
	junk.store_buffer(bytes_of(5, 70000))
	junk.close()
	var broken := await patch(junk_path, old_files)
	check(not bool(broken.get_meta("ok")) and broken.reason == "header", "a file that is not a pack fails cleanly")

	print("pack patcher test: %d failures" % failures)
	quit(1 if failures > 0 else 0)
