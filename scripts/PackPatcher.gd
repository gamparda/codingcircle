extends Node
## Updates a content pack by downloading only what changed. A Godot pack lists every file with its offset, size
## and MD5; this reads the new pack's header and file list with two Range requests, compares each file with the
## game data already installed (res://, the running pack), copies the files that match and fetches only the
## rest of the new pack (changed files, padding) by Range. The result is the new pack byte for byte: the caller
## checks its SHA-256, and any failure (or a patch that would save little) means a normal full download.
## It works from any older version straight to the newest, with nothing stored on the server but the pack.
##
## The finished file is left where ResumableDownload would leave a complete download (with its info file), so a
## launcher that only knows full downloads takes it as already downloaded.

signal progressed(done: int, total: int)
signal finished(ok: bool)

const ResumableDownload = preload("res://scripts/ResumableDownload.gd")

## The first request: the header and the start of the data.
const HEAD_BYTES := 65536
## Remote spans with at most this much installed data between them are fetched as one request.
const MERGE_GAP := 4096
const MAX_REQUEST_BYTES := 1024 * 1024
## Not worth patching: a full download is simpler when most of the pack changed or it would take too many requests.
const MAX_REMOTE_SHARE := 0.7
const MAX_REQUESTS := 300
## Hashing installed files is spread over frames.
const HASH_BYTES_PER_FRAME := 4 * 1024 * 1024
const REQUEST_TIMEOUT_SECONDS := 60.0
const MAX_ATTEMPTS := 4
const PACK_DIR_ENCRYPTED := 1
const PACK_REL_FILEBASE := 2

## Tests replace the network and the installed data: fetch_override(from, to_inclusive) -> {"bytes", "total"}
## (synchronous) and local_bytes(path) -> PackedByteArray (empty when absent).
var fetch_override := Callable()
var local_bytes := Callable()

var url := ""
var target := ""
var expected_sha := ""
var reason := "" # why it gave up, for logs and tests
var total := 0
var remote_bytes := 0
var request_count := 0
var _head := PackedByteArray()
var _directory := PackedByteArray()
var _file_base := 0
var _dir_offset := 0
var _entries: Array = [] # {"path", "start", "size", "md5"} sorted by start
var _hash_index := 0
var _spans: Array = [] # {"start", "end", "kind": "head"/"dir"/"local"/"remote", "path"}
var _span_index := 0
var _file: FileAccess
var _done := 0
var _stage := "idle"
var _attempts := 0
var _pending_range := Vector2i(-1, -1)
var http: HTTPRequest

func _ready() -> void:
	set_process(false)

## Starts building `destination` (the new pack at `source`, whose SHA-256 is `sha256`).
func start(source: String, destination: String, sha256: String) -> void:
	url = source
	target = destination
	expected_sha = sha256.to_lower()
	reason = ""
	remote_bytes = 0
	request_count = 0
	_done = 0
	_entries.clear()
	_spans.clear()
	_stage = "head"
	_fetch(0, HEAD_BYTES - 1)

func cancel() -> void:
	_stage = "idle"
	set_process(false)
	if is_instance_valid(http):
		http.cancel_request()
	if _file != null:
		_file.close()
		_file = null

func _fail(why: String) -> void:
	reason = why
	cancel()
	DirAccess.remove_absolute(target)
	DirAccess.remove_absolute(target + ".json")
	finished.emit(false)

## --- network -------------------------------------------------------------------------------------------------

func _fetch(from: int, to: int) -> void:
	_pending_range = Vector2i(from, to)
	request_count += 1
	if fetch_override.is_valid():
		var answer: Dictionary = fetch_override.call(from, to)
		_on_bytes(answer.get("bytes", PackedByteArray()), int(answer.get("total", -1)))
		return
	if not is_instance_valid(http):
		http = HTTPRequest.new()
		http.use_threads = true
		http.max_redirects = 0
		http.accept_gzip = false # ranges must be of the file itself
		http.timeout = REQUEST_TIMEOUT_SECONDS
		http.request_completed.connect(_on_http)
		add_child(http)
	if http.request(url, ["Cache-Control: no-cache", "Range: bytes=%d-%d" % [from, to]]) != OK:
		_retry()

func _on_http(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if _stage == "idle":
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 206:
		_retry()
		return
	var range := ResumableDownload.parse_content_range(headers)
	if range.is_empty() or int(range.start) != _pending_range.x:
		_retry()
		return
	_attempts = 0
	_on_bytes(body, int(range.total))

func _retry() -> void:
	_attempts += 1
	if _attempts >= MAX_ATTEMPTS:
		_fail("network")
		return
	get_tree().create_timer(pow(2.0, float(_attempts))).timeout.connect(func():
		if _stage != "idle":
			_fetch(_pending_range.x, _pending_range.y))

func _on_bytes(bytes: PackedByteArray, size_total: int) -> void:
	match _stage:
		"head":
			_head = bytes
			total = size_total
			if not _parse_header():
				return
			_stage = "directory"
			_fetch(_dir_offset, total - 1)
		"directory":
			_directory = bytes
			if _directory.size() != total - _dir_offset or not _parse_directory():
				if reason.is_empty():
					_fail("directory")
				return
			_stage = "hashing"
			_hash_index = 0
			set_process(true)
		"writing":
			var expected := _pending_range.y - _pending_range.x + 1
			if bytes.size() != expected:
				_retry()
				return
			_file.store_buffer(bytes)
			_done += bytes.size()
			progressed.emit(_done, remote_bytes)
			_span_index += 1
			_write_spans()

## --- the pack's layout ---------------------------------------------------------------------------------------

func _parse_header() -> bool:
	if total <= 0 or _head.size() < 128 or _head.slice(0, 4).get_string_from_ascii() != "GDPC":
		_fail("header")
		return false
	var format := _head.decode_u32(4)
	var flags := _head.decode_u32(20)
	if format < 3 or (flags & PACK_DIR_ENCRYPTED) != 0:
		_fail("format")
		return false
	_file_base = int(_head.decode_u64(24))
	_dir_offset = int(_head.decode_u64(32))
	if (flags & PACK_REL_FILEBASE) == 0 or _file_base <= 0 or _dir_offset <= _file_base or _dir_offset >= total:
		_fail("format")
		return false
	return true

func _parse_directory() -> bool:
	var at := 0
	var count := _directory.decode_u32(at)
	at += 4
	for index in count:
		if at + 4 > _directory.size():
			return false
		var length := _directory.decode_u32(at)
		at += 4
		if at + length + 36 > _directory.size():
			return false
		var path := _directory.slice(at, at + length).get_string_from_utf8()
		at += length
		var offset := int(_directory.decode_u64(at))
		var size := int(_directory.decode_u64(at + 8))
		var md5 := _directory.slice(at + 16, at + 32).hex_encode()
		var entry_flags := _directory.decode_u32(at + 32)
		at += 36
		if entry_flags != 0:
			_fail("encrypted")
			return false
		var start := _file_base + offset
		if start < _file_base or start + size > _dir_offset:
			return false
		_entries.append({"path": path.trim_prefix("res://"), "start": start, "size": size, "md5": md5, "local": false})
	_entries.sort_custom(func(a, b): return int(a.start) < int(b.start))
	return true

## --- comparing with what is installed ------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _stage != "hashing":
		set_process(false)
		return
	var budget := HASH_BYTES_PER_FRAME
	while _hash_index < _entries.size() and budget > 0:
		var entry: Dictionary = _entries[_hash_index]
		entry.local = _installed_md5(String(entry.path), int(entry.size)) == String(entry.md5)
		budget -= int(entry.size)
		_hash_index += 1
	if _hash_index < _entries.size():
		return
	set_process(false)
	if not _plan():
		return
	_file = FileAccess.open(target, FileAccess.WRITE)
	if _file == null:
		_fail("write")
		return
	DirAccess.remove_absolute(target + ".json")
	_stage = "writing"
	_span_index = 0
	_write_spans()

func _installed_md5(path: String, size: int) -> String:
	if local_bytes.is_valid():
		var bytes: PackedByteArray = local_bytes.call(path)
		if bytes.size() != size:
			return ""
		var context := HashingContext.new()
		context.start(HashingContext.HASH_MD5)
		context.update(bytes)
		return context.finish().hex_encode()
	var resource := "res://" + path
	if not FileAccess.file_exists(resource):
		return ""
	var file := FileAccess.open(resource, FileAccess.READ)
	if file == null or file.get_length() != size:
		return ""
	file.close()
	return FileAccess.get_md5(resource)

func _read_installed(path: String) -> PackedByteArray:
	if local_bytes.is_valid():
		return local_bytes.call(path)
	return FileAccess.get_file_as_bytes("res://" + path)

## Splits the new pack into spans: the header and file list already fetched, files copied from the installed
## data, and remote ranges for everything else (merged when close, cut at MAX_REQUEST_BYTES).
func _plan() -> bool:
	var spans: Array = []
	var cursor := 0
	for entry in _entries:
		var start := int(entry.start)
		var end := start + int(entry.size)
		if start < cursor:
			_fail("overlap")
			return false
		if start > cursor:
			spans.append({"start": cursor, "end": start, "kind": "zero"}) # alignment padding (the checksum confirms it)
		spans.append({"start": start, "end": end, "kind": "local" if bool(entry.local) else "remote", "path": entry.path})
		cursor = end
	if cursor < _dir_offset:
		spans.append({"start": cursor, "end": _dir_offset, "kind": "zero"})
	# What the first request already brought in needs no second trip.
	var head_end := mini(_head.size(), _dir_offset)
	var trimmed: Array = [{"start": 0, "end": head_end, "kind": "head"}]
	for span in spans:
		if int(span.end) <= head_end:
			continue
		if int(span.start) < head_end:
			if span.kind != "remote":
				# A copied file or padding straddling the head: take its tail from the remote side instead.
				span = {"start": head_end, "end": span.end, "kind": "remote"}
			else:
				span = {"start": head_end, "end": span.end, "kind": span.kind}
		trimmed.append(span)
	# Merge remote spans separated by little local data.
	var merged: Array = []
	for span in trimmed:
		if not merged.is_empty() and span.kind == "remote":
			var last: Dictionary = merged.back()
			if last.kind == "remote":
				last.end = span.end
				continue
			if last.kind != "remote" and merged.size() >= 2 and merged[merged.size() - 2].kind == "remote" and int(last.end) - int(last.start) <= MERGE_GAP:
				merged.pop_back()
				merged.back().end = span.end
				continue
		merged.append(span)
	_spans.clear()
	remote_bytes = 0
	var requests := 0
	for span in merged:
		if span.kind != "remote":
			_spans.append(span)
			continue
		var start := int(span.start)
		while start < int(span.end):
			var end := mini(start + MAX_REQUEST_BYTES, int(span.end))
			_spans.append({"start": start, "end": end, "kind": "remote"})
			remote_bytes += end - start
			requests += 1
			start = end
	_spans.append({"start": _dir_offset, "end": total, "kind": "dir"})
	if requests > MAX_REQUESTS or float(remote_bytes) > float(total) * MAX_REMOTE_SHARE:
		_fail("not_worth")
		return false
	return true

## --- writing the new pack ------------------------------------------------------------------------------------

func _write_spans() -> void:
	while _span_index < _spans.size():
		var span: Dictionary = _spans[_span_index]
		match String(span.kind):
			"head":
				_file.store_buffer(_head.slice(0, int(span.end)))
			"zero":
				var padding := PackedByteArray()
				padding.resize(int(span.end) - int(span.start))
				_file.store_buffer(padding)
			"dir":
				_file.store_buffer(_directory)
			"local":
				var bytes := _read_installed(String(span.path))
				if bytes.size() != int(span.end) - int(span.start):
					_fail("local_changed")
					return
				_file.store_buffer(bytes)
			"remote":
				_fetch(int(span.start), int(span.end) - 1)
				return # continues in _on_bytes
		_span_index += 1
	_file.close()
	_file = null
	_stage = "idle"
	if FileAccess.get_sha256(target).to_lower() != expected_sha:
		_fail("checksum")
		return
	# Where a finished ResumableDownload leaves its file: the launcher takes it as downloaded.
	var info := FileAccess.open(target + ".json", FileAccess.WRITE)
	if info != null:
		info.store_string(JSON.stringify({"key": expected_sha, "total": total}))
		info.close()
	finished.emit(true)
