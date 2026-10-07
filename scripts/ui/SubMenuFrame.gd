extends PanelContainer
## Shared frame of the full-screen sub menus (records, patch notes, deck, settings).
## Layout and styling live in scenes/ui/SubMenuFrame.tscn; this script only fills in text.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")

@onready var column: VBoxContainer = $Column

func setup(title_text: String, subtitle_text: String) -> VBoxContainer:
	UIKit.display($Column/Title, 34)
	$Column/Title.text = Localization.text(title_text)
	$Column/Subtitle.text = Localization.text(subtitle_text)
	return column
