extends "res://scripts/ui/SubMenuFrame.gd"
## Patch-note history. Static layout is in scenes/ui/PatchNotesScreen.tscn; entries come from PatchNotes.

const PatchNotes = preload("res://scripts/PatchNotes.gd")

const VERSION_COLOR := Color("#86f7ad")
const CHANGE_COLOR := Color("#dce1ec")

func populate() -> void:
	var entries_box: VBoxContainer = $Column/PatchNotesScroll/Entries
	for entry in PatchNotes.entries():
		var heading := Label.new()
		heading.text = String(entry.version)
		heading.add_theme_font_size_override("font_size", 24)
		heading.add_theme_color_override("font_color", VERSION_COLOR)
		entries_box.add_child(heading)
		for change in entry.changes:
			var label := Label.new()
			label.text = "• " + Localization.text(String(change))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_color", CHANGE_COLOR)
			entries_box.add_child(label)
