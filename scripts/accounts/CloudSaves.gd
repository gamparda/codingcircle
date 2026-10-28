extends RefCounted
## Each account's game progress on the server: one file per account under <state>/saves/<id[0:2]>/<id>.json,
## written atomically, holding {"revision", "updated", "data"} where `data` is the portable save text the
## client sent (SaveData.cloud_text). Writes are compare-and-swap on the revision, so two devices cannot
## silently overwrite each other.

const ServerStats = preload("res://scripts/ServerStats.gd")

const DIR_NAME := "saves"
const MAX_BYTES := 512 * 1024

var root := ""

func configure(directory: String) -> void:
	root = "" if directory.is_empty() else directory.path_join(DIR_NAME)

func _path(id: String) -> String:
	return root.path_join(id.substr(0, 2)).path_join(id + ".json")

## {"revision": int, "updated": int, "data": String}; revision 0 and empty data when nothing is stored.
func read(id: String) -> Dictionary:
	var empty := {"revision": 0, "updated": 0, "data": ""}
	if root.is_empty() or id.is_empty():
		return empty
	var stored = ServerStats.read_json(_path(id))
	if not stored is Dictionary or not stored.get("data") is String or not (stored.get("revision") is int or stored.get("revision") is float):
		return empty
	return {"revision": int(stored.revision), "updated": int(stored.get("updated", 0)), "data": String(stored.data)}

## Stores `text` when the stored revision is still `expected`. Returns {"ok", "revision", "error"}; the error
## is "conflict" (someone stored first), "too_large", "invalid" or "storage".
func write(id: String, expected: int, text: String, now: int) -> Dictionary:
	if root.is_empty() or id.is_empty():
		return {"ok": false, "revision": 0, "error": "storage"}
	if text.to_utf8_buffer().size() > MAX_BYTES:
		return {"ok": false, "revision": 0, "error": "too_large"}
	if not JSON.parse_string(text) is Dictionary:
		return {"ok": false, "revision": 0, "error": "invalid"}
	var current := read(id)
	if int(current.revision) != expected:
		return {"ok": false, "revision": int(current.revision), "error": "conflict"}
	var revision := expected + 1
	if not ServerStats.write_json(_path(id), {"revision": revision, "updated": now, "data": text}):
		return {"ok": false, "revision": expected, "error": "storage"}
	return {"ok": true, "revision": revision, "error": ""}

func delete(id: String) -> void:
	if not root.is_empty() and not id.is_empty():
		DirAccess.remove_absolute(_path(id))
