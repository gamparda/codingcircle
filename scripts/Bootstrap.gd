extends Control
## The launcher, the one game script that only ever changes with a new APK or executable. It loads the newest
## installed game-data pack that is known to work, then hands over to that pack's updater
## (scripts/ContentUpdater.gd), so update logic itself arrives with pack updates. Its only other job is
## recovery: a pack that has not yet proven it starts (pending_boot) is rolled back to the previous one, and a
## pack whose updater or game cannot load is dropped so the next start falls back.
##
## It deliberately preloads nothing: every script loaded before the pack would stay the APK's copy for the
## whole session. The layout under CONTENT_DIR is shared with ContentUpdater.gd.

const MAIN_SCENE := "res://scenes/Main.tscn"
const UPDATER_SCRIPT := "res://scripts/ContentUpdater.gd"
const BUILD_INFO_PATH := "res://build_info.json"
const CONTENT_DIR := "user://content"
const ACTIVE_PACK := CONTENT_DIR + "/active.pck"
const PREVIOUS_PACK := CONTENT_DIR + "/previous.pck"
const ACTIVE_METADATA := CONTENT_DIR + "/active.json"
const PREVIOUS_METADATA := CONTENT_DIR + "/previous.json"
const PACK_BOOT_STABILITY_SECONDS := 5.0

var bundled_version := "0.0.0"
var bundled_binary_version := "0.0.0"
var bundled_windows_version := "0.0.0"
var bundled_commit := "unknown"
var active_version := "0.0.0"
var active_commit := "unknown"
var active_pack_loaded := false
var launched := false
var message_label: Label

func _ready() -> void:
	# The project name (which also names the save folder) stays as it was; only the window title changes.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title("Keepfall")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var build_info := _read_json(BUILD_INFO_PATH)
	bundled_version = String(build_info.get("version", "0.0.0"))
	bundled_binary_version = String(build_info.get("binary_version", bundled_version))
	bundled_commit = String(build_info.get("commit", bundled_commit))
	bundled_windows_version = String(build_info.get("windows_version", bundled_version))
	Engine.set_meta("bundled_windows_version", bundled_windows_version) # the installer version this executable shipped with
	active_version = bundled_version
	active_commit = bundled_commit
	if not _updates_wanted():
		launch_game()
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CONTENT_DIR))
	if _read_json(ACTIVE_METADATA).get("pending_boot", false) == true:
		rollback_pack() # the last new pack never confirmed a good start
	_load_installed_pack()
	var updater_script = load(UPDATER_SCRIPT)
	var updater = updater_script.new() if updater_script is GDScript and updater_script.can_instantiate() else null
	if updater == null or not updater.has_method("begin"):
		# A pack whose updater cannot run must not stay: drop it for the next start, and play this one as it is.
		push_warning("content updater unavailable")
		if active_pack_loaded:
			rollback_pack()
		launch_game()
		return
	updater.name = "ContentUpdater"
	add_child(updater)
	updater.begin(self)

## Android always updates its content pack; Windows only in release builds (or when asked), never for the
## headless dedicated server, which is updated by the Linux updater or by the installer.
func _updates_wanted() -> bool:
	var args := OS.get_cmdline_user_args()
	if args.has("--server") or args.has("--disable-content-updates") or DisplayServer.get_name() == "headless":
		return false
	if OS.get_name() == "Android":
		return true
	return OS.get_name() == "Windows" and (OS.has_feature("release") or args.has("--force-content-updates"))

func _load_installed_pack() -> void:
	var metadata := _read_json(ACTIVE_METADATA)
	var active_path := ProjectSettings.globalize_path(ACTIVE_PACK)
	if not metadata.get("version") is String or not metadata.get("commit") is String or not metadata.get("sha256") is String:
		return
	if not FileAccess.file_exists(active_path) or FileAccess.get_sha256(active_path).to_lower() != String(metadata.sha256).to_lower():
		rollback_pack()
		return
	if _is_newer(bundled_version, String(metadata.version)):
		# A freshly installed APK already carries newer game data than the downloaded pack.
		rollback_pack()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS_PACK))
		return
	if ProjectSettings.load_resource_pack(ACTIVE_PACK, true):
		active_pack_loaded = true
		active_version = String(metadata.version)
		active_commit = String(metadata.commit)
	else:
		rollback_pack()

## Starts the game; with `confirm_new_pack` (a pack installed this run) it is kept only once the game runs.
func launch_game(confirm_new_pack: bool = false) -> void:
	if launched:
		return
	launched = true
	var packed_scene := load(MAIN_SCENE) as PackedScene
	var game: Node = packed_scene.instantiate() if packed_scene != null else null
	if game == null:
		if active_pack_loaded:
			rollback_pack()
		_give_up("게임을 불러오지 못했습니다. 앱을 다시 실행해 주세요.")
		return
	for child in get_children():
		if child is CanvasItem:
			child.visible = false
	add_child(game)
	if confirm_new_pack:
		await get_tree().create_timer(PACK_BOOT_STABILITY_SECONDS).timeout
		if is_instance_valid(game) and game.is_inside_tree() and game.is_node_ready():
			_confirm_pack_boot()

func _confirm_pack_boot() -> void:
	var metadata := _read_json(ACTIVE_METADATA)
	if metadata.is_empty() or metadata.get("pending_boot", false) != true:
		return
	metadata.pending_boot = false
	if _write_json_atomic(ACTIVE_METADATA, metadata):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS_PACK))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREVIOUS_METADATA))

## Puts the previous pack back (or none, which leaves the APK's own game data).
func rollback_pack() -> void:
	var active_path := ProjectSettings.globalize_path(ACTIVE_PACK)
	var previous_path := ProjectSettings.globalize_path(PREVIOUS_PACK)
	var metadata_path := ProjectSettings.globalize_path(ACTIVE_METADATA)
	var previous_metadata_path := ProjectSettings.globalize_path(PREVIOUS_METADATA)
	DirAccess.remove_absolute(active_path)
	DirAccess.remove_absolute(metadata_path)
	if FileAccess.file_exists(previous_path):
		DirAccess.rename_absolute(previous_path, active_path)
	if FileAccess.file_exists(previous_metadata_path):
		DirAccess.rename_absolute(previous_metadata_path, metadata_path)

## Last resort, in plain text (no localization or theme is loaded here).
func _give_up(text: String) -> void:
	if active_pack_loaded:
		rollback_pack()
	if not is_instance_valid(message_label):
		var background := ColorRect.new()
		background.color = Color("#0c0907")
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(background)
		message_label = Label.new()
		message_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(message_label)
	message_label.text = text

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temporary_path := absolute_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data) + "\n")
	file.close()
	DirAccess.remove_absolute(absolute_path)
	return DirAccess.rename_absolute(temporary_path, absolute_path) == OK

static func _is_newer(remote: String, current: String) -> bool:
	var remote_parts := remote.trim_prefix("v").split(".")
	var current_parts := current.trim_prefix("v").split(".")
	for index in maxi(remote_parts.size(), current_parts.size()):
		var remote_value := int(remote_parts[index]) if index < remote_parts.size() else 0
		var current_value := int(current_parts[index]) if index < current_parts.size() else 0
		if remote_value != current_value:
			return remote_value > current_value
	return false
