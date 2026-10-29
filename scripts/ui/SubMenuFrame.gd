extends PanelContainer
## Shared frame of the full-screen sub menus (records, patch notes, deck, settings, modes). A header row holds
## a round back button, the title and subtitle, and a right-aligned slot for screen actions (`actions`).
## Layout lives in scenes/ui/SubMenuFrame.tscn; the header is assembled here so inheriting scenes keep their
## children's places in Column.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")

@onready var column: VBoxContainer = $Column
var header: HBoxContainer
var back_button: Button
var actions: HBoxContainer

func setup(title_text: String, subtitle_text: String) -> VBoxContainer:
	var title: Label = $Column/Title
	var subtitle: Label = $Column/Subtitle
	add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.panel_box(UIKit.EDGE, 18, 1.0), 30, 22))
	UIKit.display(title, 32, UIKit.TEXT)
	title.text = Localization.text(title_text)
	subtitle.text = Localization.text(subtitle_text)
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	subtitle.visible = not subtitle_text.is_empty()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header = HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 16)
	column.add_child(header)
	column.move_child(header, 0)
	back_button = UIKit.icon_button("←", Localization.text("뒤로"))
	back_button.name = "SubMenuBack"
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.visible = false
	header.add_child(back_button)
	var titles := VBoxContainer.new()
	titles.name = "Titles"
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	header.add_child(titles)
	title.reparent(titles)
	subtitle.reparent(titles)
	actions = HBoxContainer.new()
	actions.name = "HeaderActions"
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_theme_constant_override("separation", 8)
	header.add_child(actions)
	var rule := HSeparator.new()
	rule.name = "HeaderRule"
	column.add_child(rule)
	column.move_child(rule, 1)
	column.add_theme_constant_override("separation", 12)
	return column

var _back_action := Callable()

## Shows the header's back button; `node_name` keeps a screen's established button name.
func set_back(action: Callable, node_name: String = "SubMenuBack") -> Button:
	if _back_action.is_valid() and back_button.pressed.is_connected(_back_action):
		back_button.pressed.disconnect(_back_action)
	_back_action = action
	back_button.name = node_name
	back_button.visible = true
	back_button.pressed.connect(action)
	return back_button

## Makes the header's back button do what a screen's own back/cancel `button` does, and hides that button
## (it stays in the tree under its name). An emptied button row is hidden with it.
func adopt_back(button: Button) -> void:
	set_back(func():
		if is_instance_valid(button) and not button.disabled:
			button.pressed.emit(), back_button.name)
	back_button.tooltip_text = button.text
	button.visible = false
	var row := button.get_parent() as Control
	if row is BoxContainer and row.get_children().all(func(child): return not (child as Control).visible):
		row.visible = false

## The frame around a sub-menu column (from Main._submenu).
static func of(column: Control) -> Node:
	var node: Node = column
	while node != null and not node.has_method("adopt_back"):
		node = node.get_parent()
	return node
