extends Node
## Downloads one file in Range chunks, so a slow or throttled connection (a phone over its data cap) never runs into
## a whole-file timeout, and a dropped connection costs one chunk instead of the whole file. Failed chunks are
## retried with growing pauses; the partial file and a small info file survive app restarts, so the next start()
## for the same file continues where it stopped. The caller verifies the finished file (SHA-256).

const CHUNK_BYTES := 1024 * 1024
const CHUNK_TIMEOUT_SECONDS := 60.0
## Consecutive failed chunks before giving up; a later start() still resumes.
const MAX_ATTEMPTS := 6
const MAX_PAUSE_SECONDS := 20.0

signal progressed(done: int, total: int)
signal retrying(attempt: int, max_attempts: int)
signal finished(ok: bool)

var url := ""
var path := ""
var info_path := ""
var key := ""
var offset := 0
var total := -1
var failures := 0
var active := false
var headers: PackedStringArray = []
var http: HTTPRequest

## Starts or resumes downloading `source` into `target`. `identity` names the exact file (its SHA-256): a partial
## file left by the same identity is continued, anything else starts over.
func start(source: String, target: String, identity: String, extra_headers: PackedStringArray = []) -> void:
	url = source
	path = target
	info_path = target + ".json"
	key = identity
	headers = extra_headers
	failures = 0
	total = -1
	offset = 0
	var info := _read_info()
	if String(info.get("key", "")) == key and FileAccess.file_exists(path):
		offset = _size(path)
		total = int(info.get("total", -1))
	else:
		DirAccess.remove_absolute(path)
		_write_info()
	if not is_instance_valid(http):
		http = HTTPRequest.new()
		http.use_threads = true
		http.max_redirects = 0
		# Ranges must be of the file itself: offered gzip, GitHub Pages answers with ranges of a compressed copy.
		http.accept_gzip = false
		http.request_completed.connect(_on_chunk)
		add_child(http)
	http.timeout = CHUNK_TIMEOUT_SECONDS
	http.download_file = ""
	active = true
	_request_chunk()

func cancel() -> void:
	active = false
	if is_instance_valid(http):
		http.cancel_request()

## Bytes received so far, including the chunk in flight.
func received() -> int:
	return offset + (http.get_downloaded_bytes() if is_instance_valid(http) and active else 0)

## Forgets the partial file (after it was used, or when it turned out wrong).
func discard() -> void:
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(info_path)

func _request_chunk() -> void:
	if not active:
		return
	if total >= 0 and offset >= total:
		active = false
		finished.emit(true)
		return
	var request_headers := PackedStringArray(headers)
	request_headers.append("Range: bytes=%d-%d" % [offset, offset + CHUNK_BYTES - 1])
	if http.request(url, request_headers) != OK:
		_chunk_failed()

func _on_chunk(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray) -> void:
	if not active:
		return
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 416 and offset > 0:
		# Asked past the end: the partial file is already complete (the caller's hash check confirms it).
		total = offset
		_write_info()
		active = false
		finished.emit(true)
		return
	if result != HTTPRequest.RESULT_SUCCESS or not response_code in [200, 206]:
		_chunk_failed()
		return
	if response_code == 200:
		# The server ignored the range and sent the whole file.
		if not _write(body, true):
			_chunk_failed()
			return
		offset = body.size()
		total = body.size()
	else:
		var range := parse_content_range(response_headers)
		if range.is_empty() or int(range.start) != offset or body.is_empty():
			_chunk_failed()
			return
		if not _write(body, false):
			_chunk_failed()
			return
		offset += body.size()
		total = int(range.total)
	_write_info()
	failures = 0
	progressed.emit(offset, total)
	_request_chunk()

func _chunk_failed() -> void:
	failures += 1
	if failures >= MAX_ATTEMPTS:
		active = false
		finished.emit(false)
		return
	retrying.emit(failures, MAX_ATTEMPTS)
	var pause := minf(pow(2.0, float(failures)), MAX_PAUSE_SECONDS)
	get_tree().create_timer(pause).timeout.connect(func():
		if active:
			_request_chunk())

## {"start", "end", "total"} from a `Content-Range: bytes start-end/total` header, or {} when absent or invalid.
static func parse_content_range(response_headers: PackedStringArray) -> Dictionary:
	for header in response_headers:
		var text := String(header).strip_edges()
		if not text.to_lower().begins_with("content-range:"):
			continue
		var value := text.substr(text.find(":") + 1).strip_edges()
		if not value.to_lower().begins_with("bytes "):
			return {}
		var parts := value.substr(6).split("/")
		var span := parts[0].split("-") if parts.size() == 2 else PackedStringArray()
		if span.size() != 2 or not span[0].is_valid_int() or not span[1].is_valid_int() or not parts[1].is_valid_int():
			return {}
		var start := int(span[0])
		var end := int(span[1])
		var size := int(parts[1])
		if start < 0 or end < start or size <= end:
			return {}
		return {"start": start, "end": end, "total": size}
	return {}

func _write(body: PackedByteArray, truncate: bool) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE if truncate or not FileAccess.file_exists(path) else FileAccess.READ_WRITE)
	if file == null:
		return false
	file.seek_end()
	file.store_buffer(body)
	file.flush()
	var ok := file.get_error() == OK
	file.close()
	return ok

func _size(file_path: String) -> int:
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return 0
	var length := file.get_length()
	file.close()
	return length

func _read_info() -> Dictionary:
	if not FileAccess.file_exists(info_path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(info_path))
	return parsed if parsed is Dictionary else {}

func _write_info() -> void:
	var file := FileAccess.open(info_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"key": key, "total": total}))
		file.close()
