extends "res://scripts/ui/SubMenuFrame.gd"
## Patch-note history. Static layout is in scenes/ui/PatchNotesScreen.tscn; entries come from PatchNotes.
## The newest releases are open; older ones fold under their version so the list stays short.

const PatchNotes = preload("res://scripts/PatchNotes.gd")

const VERSION_COLOR := Color("#86f7ad")
const CHANGE_COLOR := Color("#dce1ec")
const OPEN_COUNT := 3

func populate() -> void:
	var entries_box: VBoxContainer = $Column/PatchNotesScroll/Entries
	var index := 0
	for entry in PatchNotes.entries():
		var open := index < OPEN_COUNT
		index += 1
		var changes: Array = entry.changes
		var version := String(entry.version)
		var body := VBoxContainer.new()
		body.add_theme_constant_override("separation", 8)
		body.visible = open
		for change in changes:
			var label := Label.new()
			label.text = "• " + Localization.text(String(change))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.add_theme_font_size_override("font_size", 18)
			label.add_theme_color_override("font_color", CHANGE_COLOR)
			body.add_child(label)
		var heading := Button.new()
		heading.flat = true
		heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
		heading.focus_mode = Control.FOCUS_NONE
		for state in ["normal", "hover", "pressed", "focus"]:
			heading.add_theme_stylebox_override(state, StyleBoxEmpty.new()) # no button padding: the version lines up with its bullets
		heading.add_theme_font_size_override("font_size", 22)
		heading.add_theme_color_override("font_color", VERSION_COLOR)
		heading.add_theme_color_override("font_hover_color", VERSION_COLOR.lightened(0.2))
		heading.text = _heading_text(version, changes.size(), open)
		heading.tooltip_text = Localization.text("눌러서 접기·펼치기")
		heading.pressed.connect(func():
			body.visible = not body.visible
			heading.text = _heading_text(version, changes.size(), body.visible)
		)
		entries_box.add_child(heading)
		entries_box.add_child(body)

static func _heading_text(version: String, count: int, open: bool) -> String:
	var text := "%s  %s" % ["▾" if open else "▸", version]
	return text if open else text + "   (%d)" % count
