extends RefCounted
## Battle cosmetics on the HUD: both sides' looks on the battlefield, the player's card frame, and emotes — a 💬
## button opens the four worn emotes; online the server relays the choice to both players, solo it just shows.
## Emotes are a fixed set of phrases (no free text).

const Localization = preload("res://scripts/Localization.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Progression = preload("res://scripts/accounts/Progression.gd")

const BUBBLE_SECONDS := 2.6
const LOCAL_GAP_MSEC := 1500

## The looks of world sides 0 and 1: online what the server sent, solo the player's own on their side.
static func looks(main) -> Array:
	if not main.local_ai_mode:
		return main.match_looks if main.match_looks is Array and main.match_looks.size() == 2 else [{}, {}]
	var mine: Dictionary = main.account.meta.get("equipped", {}) if main.account.is_signed_in() else {}
	var result: Array = [{}, {}]
	result[main.own_side] = mine
	return result

static func apply_looks(main) -> void:
	if is_instance_valid(main.battle_view):
		main.battle_view.set_looks(looks(main))

## The own card frame's colour, or a transparent colour for the plain frame.
static func frame_color(main) -> Color:
	var own: Dictionary = looks(main)[main.own_side] if main.own_side == 0 or main.own_side == 1 else {}
	var entry: Dictionary = Progression.cosmetic(String(own.get("frame", "")))
	return entry.color if entry.get("color") is Color else Color(0, 0, 0, 0)

static func frame_card(main, button: Button) -> void:
	var color := frame_color(main)
	if color.a <= 0.0 or button.has_node("CardFrame"):
		return
	var frame := Panel.new()
	frame.name = "CardFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color(color.r, color.g, color.b, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", style)
	button.add_child(frame)

static func emotes_worn(main) -> Array:
	var own: Dictionary = looks(main)[main.own_side] if main.own_side == 0 or main.own_side == 1 else {}
	var worn = own.get("emotes", [])
	return worn if worn is Array and worn.size() == Progression.EMOTE_SLOTS else Progression.DEFAULT_EQUIPPED.emotes

static func add_button(main) -> void:
	if main.network.client_is_spectator:
		return
	var button := UIKit.icon_button("💬", Localization.text("감정 표현"), UIKit.EDGE, 52.0)
	button.name = "EmoteButton"
	button.position = Vector2(1214, 158)
	button.z_index = 10
	button.pressed.connect(func(): _toggle_menu(main, button))
	main.root_background.add_child(button)

static func _toggle_menu(main, anchor: Control) -> void:
	var existing = main.root_background.get_node_or_null("EmoteMenu")
	if existing != null:
		existing.queue_free()
		return
	var menu := VBoxContainer.new()
	menu.name = "EmoteMenu"
	menu.z_index = 11
	menu.position = anchor.position + Vector2(-190, 58)
	menu.add_theme_constant_override("separation", 6)
	for id in emotes_worn(main):
		var emote := String(id)
		var choice = main._styled_button(String(Progression.cosmetic(emote).get("name", emote)), UIKit.EDGE.lightened(0.2), false)
		choice.name = "Emote_" + emote.replace(":", "_")
		choice.custom_minimum_size = Vector2(240, 44)
		choice.add_theme_font_size_override("font_size", 15)
		choice.pressed.connect(func():
			menu.queue_free()
			send(main, emote))
		menu.add_child(choice)
	main.root_background.add_child(menu)

static func send(main, emote: String) -> void:
	if main.local_ai_mode:
		var now := Time.get_ticks_msec()
		if now - int(main.get_meta("last_emote", -LOCAL_GAP_MSEC)) < LOCAL_GAP_MSEC:
			return
		main.set_meta("last_emote", now)
		show_bubble(main, main.own_side, emote)
	else:
		main.network.send_emote(emote)

## A speech bubble over `side`'s castle for a moment.
static func show_bubble(main, side: int, emote: String) -> void:
	if not main.battle_active or not is_instance_valid(main.battle_view):
		return
	var view = main.battle_view
	var name := "EmoteBubble%d" % side
	var old = main.root_background.get_node_or_null(name)
	if old != null:
		old.free()
	var bubble := PanelContainer.new()
	bubble.name = name
	bubble.z_index = 12
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.98, 0.95, 0.88, 0.95)
	style.border_color = UIKit.TEAM_BLUE if view.display_side(side) == 0 else UIKit.TEAM_RED
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 6; style.content_margin_bottom = 6
	bubble.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = String(Progression.cosmetic(emote).get("name", emote))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color("#2a1f16"))
	bubble.add_child(label)
	main.root_background.add_child(bubble)
	var x: float = view.world_to_screen_x(BattleModel.FIELD_LEFT if side == 0 else BattleModel.FIELD_RIGHT)
	var left: bool = view.display_side(side) == 0
	bubble.position = view.position + Vector2(clampf(x + (30.0 if left else -230.0), 10.0, view.size.x - 240.0), view.size.y * 0.72 - 250.0)
	bubble.pivot_offset = Vector2(20, 20)
	bubble.scale = Vector2(0.6, 0.6)
	var tween := bubble.create_tween()
	tween.tween_property(bubble, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(BUBBLE_SECONDS)
	tween.tween_property(bubble, "modulate:a", 0.0, 0.4)
	tween.tween_callback(bubble.queue_free)
