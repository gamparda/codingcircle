extends SceneTree

# Generate import settings before committing art, so read-only server releases
# only need to write their private .godot cache, never adjacent source metadata.
func _initialize() -> void:
	var template := "res://assets/units/tanker.png.import"
	var expected := "139cf57ddac20fc02e11bbee54a119b7"
	if "res://assets/units/tanker.png".md5_text() != expected:
		printerr("Import cache-path convention mismatch")
		quit(1)
		return
	var count := prepare("res://assets/units", template)
	count += prepare("res://assets/source/role_sheets", template)
	print("PREPARED_PNG_IMPORT_SETTINGS ", count)
	quit(0)

func prepare(folder: String, template: String) -> int:
	var directory := DirAccess.open(folder)
	var count := 0
	for child in directory.get_directories():
		count += prepare(folder.path_join(child), template)
	for name in directory.get_files():
		if not name.ends_with(".png"): continue
		var source := folder.path_join(name)
		if FileAccess.file_exists(source + ".import"): continue
		var config := ConfigFile.new()
		if config.load(template) != OK:
			printerr("Cannot read PNG import template")
			quit(1)
			return count
		var cache := "res://.godot/imported/" + name + "-" + source.md5_text() + ".ctex"
		config.set_value("remap", "uid", ResourceUID.id_to_text(ResourceUID.create_id()))
		config.set_value("remap", "path", cache)
		config.set_value("deps", "source_file", source)
		config.set_value("deps", "dest_files", [cache])
		if config.save(source + ".import") != OK:
			printerr("Cannot save import settings: ", source)
			quit(1)
			return count
		count += 1
	return count
