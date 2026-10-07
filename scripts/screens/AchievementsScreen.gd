extends RefCounted
## Achievement gallery: unlocked cards glow gold, locked ones stay dim until earned.

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Achievements = preload("res://scripts/Achievements.gd")

static func _build_achievements_screen(main) -> void:
	var done := Achievements.unlocked_count(main.save_data)
	var column = main._submenu("업적", "달성 %d / %d" % [done, Achievements.DEFS.size()])
	var scroll := ScrollContainer.new()
	scroll.name = "AchievementScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "AchievementGrid"
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for entry in Achievements.DEFS:
		grid.add_child(_card(entry, main.save_data.get("achievements", {}).get(String(entry.id), -1)))
	var back = main._styled_button(Localization.text("전적으로 돌아가기"), Color("#697386"), false)
	back.name = "AchievementsBack"
	back.pressed.connect(main._build_records_screen)
	column.add_child(back)

static func _card(entry: Dictionary, unlocked_at: int) -> Control:
	var got := unlocked_at >= 0
	var tone := UIKit.GOLD if got else UIKit.TEXT_DIM
	var card := PanelContainer.new()
	card.name = "AchievementCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 84
	card.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(UIKit.SURFACE_HI.lerp(tone, 0.10 if got else 0.0), UIKit.SURFACE.darkened(0.12), Color(tone.r, tone.g, tone.b, 0.7 if got else 0.25), 12, 1.0, 0.35 if got else 0.0, Color(1.0, 0.85, 0.4, 0.3) if got else Color(0, 0, 0, 0), 0.08), 16, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(56, 56)
	var ring := StyleBoxFlat.new()
	ring.bg_color = Color(tone.r, tone.g, tone.b, 0.2 if got else 0.06)
	ring.border_color = tone
	ring.set_border_width_all(2)
	ring.set_corner_radius_all(28)
	ring.anti_aliasing = true
	badge.add_theme_stylebox_override("panel", ring)
	row.add_child(badge)
	var icon := Label.new()
	icon.text = String(entry.icon) if got else "?"
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 26)
	icon.add_theme_color_override("font_color", tone.lightened(0.3) if got else UIKit.TEXT_DIM)
	badge.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 3)
	row.add_child(text)
	var title := Label.new()
	title.name = "AchievementName"
	title.text = Localization.text(String(entry.name))
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", UIKit.TEXT if got else UIKit.TEXT_MUTED)
	text.add_child(title)
	var desc := Label.new()
	desc.text = Localization.text(String(entry.desc))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", UIKit.TEXT_MUTED)
	text.add_child(desc)
	if got:
		var when := Label.new()
		when.text = Time.get_datetime_string_from_unix_time(unlocked_at, true).substr(0, 10)
		when.add_theme_font_size_override("font_size", 11)
		when.add_theme_color_override("font_color", UIKit.GOLD)
		text.add_child(when)
	return card
