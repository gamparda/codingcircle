extends RefCounted
## The assist window's log: kept in memory for the screen (newest last, bounded) and appended to a file for later.

signal line_added(entry: Dictionary)

const MAX_LINES := 1000
const LEVELS := ["info", "warn", "error"]

var lines: Array = []
var path := ""

func _init(file_path: String = "") -> void:
	path = file_path

func add(level: String, text: String) -> Dictionary:
	var stamp := Time.get_time_dict_from_system()
	var entry := {"time": "%02d:%02d:%02d" % [int(stamp.hour), int(stamp.minute), int(stamp.second)], "level": level if LEVELS.has(level) else "info", "text": text}
	lines.append(entry)
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.READ_WRITE) if FileAccess.file_exists(path) else FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.seek_end()
			file.store_line("%s [%s] %s" % [entry.time, String(entry.level).to_upper(), text])
			file.close()
	line_added.emit(entry)
	return entry

func text_of(entry: Dictionary) -> String:
	return "%s  %s" % [entry.time, entry.text]

## The whole log as one block of text (for "copy").
func as_text(minimum_level: String = "info") -> String:
	var rank := LEVELS.find(minimum_level)
	var out := PackedStringArray()
	for entry in lines:
		if LEVELS.find(String(entry.level)) >= rank:
			out.append("%s [%s] %s" % [entry.time, String(entry.level).to_upper(), entry.text])
	return "\n".join(out)
