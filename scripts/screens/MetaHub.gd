extends RefCounted
## 성장: gold, today's quests, the season pass, the daily shop, the wardrobe, the codex and profile cards, in one
## screen off the main menu. Everything but the codex needs a signed-in account; the server owns the numbers and
## this screen redraws whenever its state arrives (Watcher). Also the reward line on the result screen.

const Localization = preload("res://scripts/Localization.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const UIKit = preload("res://scripts/ui/UIKit.gd")
const Progression = preload("res://scripts/accounts/Progression.gd")
const Titles = preload("res://scripts/accounts/Titles.gd")
const MenuScreens = preload("res://scripts/screens/MenuScreens.gd")

const GOLD_ICON := "💰"
const TABS := [["quests", "📜 임무·패스"], ["shop", "🛒 상점"], ["wardrobe", "👘 옷장"], ["codex", "📖 도감"], ["profile", "🪪 프로필"]]
const SLOT_NAMES := {"palette": "유닛 색", "frame": "카드 테두리", "banner": "프로필 깃발", "castle": "성 색", "emote": "감정 표현"}
const EMBLEMS := {"shield": "🏰", "moon": "🌙", "sword": "⚔", "crown": "👑", "star": "⭐"}

## The signed-in player's own card is asked for once per visit.
static var _asked_own := false

## Redraws a screen when the account's progression changes (and drops itself with the screen).
class Watcher extends Node:
	var account: Node
	var redraw: Callable
	func _ready() -> void:
		account.meta_changed.connect(_changed)
	func _exit_tree() -> void:
		if is_instance_valid(account) and account.meta_changed.is_connected(_changed):
			account.meta_changed.disconnect(_changed)
	func _changed() -> void:
		if redraw.is_valid():
			redraw.call()

static func hours_text(seconds: int) -> String:
	if seconds >= 3600:
		return Localization.text("%d시간 %d분") % [seconds / 3600, (seconds % 3600) / 60]
	return Localization.text("%d분") % (seconds / 60)

static func show(main, tab: String = "quests") -> void:
	var column: VBoxContainer = MenuScreens._submenu(main, Localization.text("성장"), Localization.text("임무 · 시즌 패스 · 상점 · 옷장 · 도감"), Callable(), "MetaHubBack")
	column.name = "MetaHub"
	var account = main.account
	account.refresh_meta()
	_asked_own = false
	var header := HBoxContainer.new()
	header.name = "MetaHeader"
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var tabs := HBoxContainer.new()
	tabs.name = "MetaTabs"
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	var scroll := ScrollContainer.new()
	scroll.name = "MetaScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "MetaBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	# The redraw callable lives in `state`: a lambda captures locals by value, so a tab button holding `redraw`
	# itself would keep the placeholder it saw when it was made.
	var state := {"tab": tab, "redraw": Callable()}
	var redraw := func():
		if not is_instance_valid(body):
			return
		_fill_header(main, header)
		_clear(tabs)
		for entry in TABS:
			var id := String(entry[0])
			var button = main._styled_button(Localization.text(String(entry[1])), UIKit.GOLD_DEEP if id == String(state.tab) else UIKit.EDGE.lightened(0.2), id == String(state.tab))
			button.name = "MetaTab_" + id
			button.custom_minimum_size = Vector2(0, 46)
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.add_theme_font_size_override("font_size", 14)
			button.pressed.connect(func():
				state.tab = id
				scroll.scroll_vertical = 0
				state.redraw.call())
			tabs.add_child(button)
		_clear(body)
		match String(state.tab):
			"quests": _quests(main, body)
			"shop": _shop(main, body)
			"wardrobe": _wardrobe(main, body)
			"codex": _codex(main, body)
			"profile": _profile(main, body)
	state.redraw = redraw
	var watcher := Watcher.new()
	watcher.name = "MetaWatcher"
	watcher.account = account
	watcher.redraw = redraw
	column.add_child(watcher)
	redraw.call()

## Detaches and frees a container's children at once, so rebuilt nodes keep their names.
static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

static func _fill_header(main, header: HBoxContainer) -> void:
	_clear(header)
	var account = main.account
	var meta: Dictionary = account.meta
	if not account.is_signed_in():
		header.add_child(MultiplayerUI.label(Localization.text("로그인하면 금화·임무·시즌 패스·상점을 쓸 수 있습니다. 도감은 누구나 볼 수 있습니다."), 15, UIKit.TEXT_MUTED))
		return
	if meta.is_empty():
		header.add_child(MultiplayerUI.label(Localization.text("서버에서 성장 정보를 받는 중…") if account.online else Localization.text("서버에 연결되면 성장 정보를 볼 수 있습니다."), 15, UIKit.TEXT_MUTED))
		return
	var gold := MultiplayerUI.label("%s %d" % [GOLD_ICON, int(meta.gold)], 22, UIKit.GOLD)
	gold.name = "MetaGold"
	header.add_child(gold)
	var time := MultiplayerUI.label(Localization.text("확인된 전투 시간 %s") % hours_text(int(meta.seconds)), 15, UIKit.TEXT)
	time.name = "MetaVerifiedTime"
	header.add_child(time)
	header.add_child(MultiplayerUI.label(Localization.text("오늘 전투 금화 %d / %d") % [int(meta.day_gold), Progression.DAILY_BATTLE_GOLD], 13, UIKit.TEXT_MUTED))
	if not String(account.meta_message).is_empty():
		header.add_child(MultiplayerUI.label(String(account.meta_message), 14, UIKit.DANGER))

static func _needs_meta(main, body: VBoxContainer) -> bool:
	if main.account.is_signed_in() and not main.account.meta.is_empty():
		return false
	var hint := MultiplayerUI.label(Localization.text("계정으로 로그인하고 서버에 연결되면 열립니다. 온라인 대전과 서버가 확인한 캠페인·도전·무한 방어 전투로 금화와 패스 경험치를 얻습니다."), 15, UIKit.TEXT_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(hint)
	return true

static func _row_panel(tint: Color = UIKit.EDGE_SOFT) -> Array:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = UIKit.SURFACE
	style.border_color = tint
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 14; style.content_margin_right = 14
	style.content_margin_top = 8; style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	return [panel, row]

static func _bar(value: float, maximum: float, width: float = 220.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, maximum)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(width, 14)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar

# ---------- quests and pass ----------

static func _quests(main, body: VBoxContainer) -> void:
	if _needs_meta(main, body):
		return
	var meta: Dictionary = main.account.meta
	body.add_child(MultiplayerUI.label(Localization.text("오늘의 임무 (매일 오전 9시 새로 고침)"), 17, UIKit.ACCENT))
	for quest in meta.quests:
		var parts := _row_panel(UIKit.SUCCESS if bool(quest.done) else UIKit.EDGE_SOFT)
		var row: HBoxContainer = parts[1]
		parts[0].name = "Quest_" + String(quest.id)
		var text := MultiplayerUI.label(("✓ " if bool(quest.done) else "") + ("[주간] " if bool(quest.get("weekly", false)) else "") + String(quest.text), 15, UIKit.TEXT if not bool(quest.done) else UIKit.SUCCESS)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(text)
		var shown_goal := int(quest.goal)
		var shown_progress := int(quest.progress)
		if String(quest.id).begins_with("time") or String(quest.id).begins_with("w_time"):
			shown_goal /= 60; shown_progress /= 60
		# Fixed-width columns so every quest's bar, count and reward line up.
		row.add_child(_bar(float(shown_progress), float(shown_goal), 200.0))
		var count := MultiplayerUI.label("%d / %d" % [shown_progress, shown_goal], 14, UIKit.TEXT_MUTED)
		count.custom_minimum_size = Vector2(80, 0)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(count)
		var reward := MultiplayerUI.label("%s %d" % [GOLD_ICON, int(quest.reward)], 14, UIKit.GOLD)
		reward.custom_minimum_size = Vector2(70, 0)
		reward.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(reward)
		body.add_child(parts[0])
	var pass_data: Dictionary = meta.pass
	var tier := int(pass_data.tier)
	var xp := int(pass_data.xp)
	body.add_child(MultiplayerUI.label(Localization.text("무료 시즌 패스 · %s") % String(pass_data.season), 17, UIKit.ACCENT))
	var parts := _row_panel(UIKit.GOLD_DEEP)
	parts[0].name = "SeasonPass"
	var row: HBoxContainer = parts[1]
	row.add_child(MultiplayerUI.label(Localization.text("%d / %d단계") % [tier, Progression.PASS_TIERS], 20, UIKit.GOLD))
	var into := xp - tier * Progression.PASS_XP_PER_TIER
	var bar := _bar(float(into) if tier < Progression.PASS_TIERS else 1.0, float(Progression.PASS_XP_PER_TIER) if tier < Progression.PASS_TIERS else 1.0, 260.0)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bar)
	row.add_child(MultiplayerUI.label(Localization.text("다음 단계까지 %d") % (Progression.PASS_XP_PER_TIER - into) if tier < Progression.PASS_TIERS else Localization.text("완주!"), 14, UIKit.TEXT_MUTED))
	body.add_child(parts[0])
	var how := MultiplayerUI.label(Localization.text("전투 10초마다 1, 승리 %d, 임무 %d 경험치. 단계마다 금화 %d, 5단계마다 이번 시즌 한정 꾸미기를 받습니다. 매달 새 시즌이 시작됩니다.") % [Progression.PASS_WIN_XP, Progression.PASS_QUEST_XP, Progression.PASS_TIER_GOLD], 13, UIKit.TEXT_MUTED)
	how.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(how)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	body.add_child(grid)
	var steps: Array = Progression.PASS_ITEMS.keys()
	steps.sort()
	for step in steps:
		var slot := String(Progression.PASS_ITEMS[step])
		var reached := tier >= int(step)
		var name := Titles.badge("season_pass") if slot == "title" else String(Progression.cosmetic("season:%s:%s" % [String(pass_data.season), slot]).get("name", slot))
		var cell := _row_panel(UIKit.GOLD if reached else UIKit.EDGE_SOFT)
		cell[1].add_child(MultiplayerUI.label(("✓ " if reached else "") + Localization.text("%d단계") % int(step), 14, UIKit.GOLD if reached else UIKit.TEXT_MUTED))
		var reward_label := MultiplayerUI.label(name, 14, UIKit.TEXT if reached else UIKit.TEXT_DIM)
		reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reward_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell[1].add_child(reward_label)
		cell[0].custom_minimum_size = Vector2(300, 0)
		grid.add_child(cell[0])

# ---------- shop ----------

static func swatch(id: String, size: float = 34.0) -> Control:
	var entry: Dictionary = Progression.cosmetic(id)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(size, size)
	var style := StyleBoxFlat.new()
	style.bg_color = entry.get("color", UIKit.SURFACE_HI) if entry.get("color") is Color else UIKit.SURFACE_HI
	if entry.get("color2") is Color:
		style.border_color = entry.color2
		style.set_border_width_all(4)
	style.set_corner_radius_all(int(size / 4.0))
	box.add_theme_stylebox_override("panel", style)
	var glyph := ""
	match String(entry.get("slot", "")):
		"banner": glyph = String(EMBLEMS.get(String(entry.get("emblem", "shield")), "★"))
		"emote": glyph = "💬"
		"castle": glyph = "🏰"
		"frame": glyph = "▢"
	if not glyph.is_empty():
		var label := MultiplayerUI.label(glyph, int(size * 0.45), Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(label)
	return box

static func _shop(main, body: VBoxContainer) -> void:
	if _needs_meta(main, body):
		return
	var meta: Dictionary = main.account.meta
	body.add_child(MultiplayerUI.label(Localization.text("오늘의 상점 · 매일 오전 9시에 바뀝니다. 꾸미기만 팔며 전투에는 영향이 없습니다."), 15, UIKit.TEXT_MUTED))
	for id in meta.shop:
		var item := String(id)
		var entry: Dictionary = Progression.cosmetic(item)
		var owned: bool = meta.owned.has(item)
		var parts := _row_panel()
		parts[0].name = "ShopItem_" + item
		var row: HBoxContainer = parts[1]
		row.add_child(swatch(item))
		var text := MultiplayerUI.label("%s\n%s" % [String(entry.name), Localization.text(String(SLOT_NAMES.get(String(entry.slot), "")))], 15, UIKit.TEXT)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var price := Progression.price(item)
		var button = main._styled_button(Localization.text("보유 중") if owned else "%s %d" % [GOLD_ICON, price], UIKit.EDGE if owned else UIKit.GOLD_DEEP, not owned and int(meta.gold) >= price)
		button.name = "Buy_" + item
		button.custom_minimum_size = Vector2(140, 44)
		button.disabled = owned or int(meta.gold) < price
		button.pressed.connect(func(): main.account.buy(item))
		row.add_child(button)
		body.add_child(parts[0])

# ---------- wardrobe ----------

static func _wardrobe(main, body: VBoxContainer) -> void:
	if _needs_meta(main, body):
		return
	var meta: Dictionary = main.account.meta
	var equipped: Dictionary = meta.equipped
	for slot in ["palette", "frame", "castle", "banner", "emote"]:
		body.add_child(MultiplayerUI.label(Localization.text(String(SLOT_NAMES[slot])), 17, UIKit.ACCENT))
		if slot == "emote":
			body.add_child(MultiplayerUI.label(Localization.text("전투 중 💬 버튼으로 쓸 4개: ") + " · ".join(equipped.emotes.map(func(id): return String(Progression.cosmetic(String(id)).get("name", id)))), 14, UIKit.TEXT_MUTED))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 6)
		body.add_child(grid)
		for id in _owned_in(meta, slot):
			var item := String(id)
			var parts := _row_panel(UIKit.GOLD if _wearing(equipped, slot, item) else UIKit.EDGE_SOFT)
			parts[0].name = "Wear_" + item.replace(":", "_")
			parts[0].custom_minimum_size = Vector2(440, 0)
			var row: HBoxContainer = parts[1]
			row.add_child(swatch(item, 30.0))
			var name := MultiplayerUI.label(String(Progression.cosmetic(item).name), 15, UIKit.TEXT)
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.add_child(name)
			if slot == "emote":
				for index in Progression.EMOTE_SLOTS:
					var at: int = index
					var on: bool = String(equipped.emotes[at]) == item
					var put = main._styled_button(str(at + 1), UIKit.GOLD_DEEP if on else UIKit.EDGE, on)
					put.custom_minimum_size = Vector2(40, 40)
					put.tooltip_text = Localization.text("%d번 자리에 두기") % (at + 1)
					put.pressed.connect(func(): main.account.equip(item, at))
					row.add_child(put)
			else:
				var wearing := _wearing(equipped, slot, item)
				var wear = main._styled_button(Localization.text("착용 중") if wearing else Localization.text("착용"), UIKit.EDGE if wearing else UIKit.GOLD_DEEP, not wearing)
				wear.custom_minimum_size = Vector2(100, 40)
				wear.disabled = wearing
				wear.pressed.connect(func(): main.account.equip(item, 0))
				row.add_child(wear)
			grid.add_child(parts[0])

static func _owned_in(meta: Dictionary, slot: String) -> Array:
	var items: Array = []
	for id in Progression.CATALOG:
		if String(Progression.CATALOG[id].slot) == slot and (bool(Progression.CATALOG[id].get("default", false)) or meta.owned.has(id)):
			items.append(String(id))
	for id in meta.owned:
		if String(id).begins_with("season:") and String(Progression.cosmetic(String(id)).slot) == slot:
			items.append(String(id))
	return items

static func _wearing(equipped: Dictionary, slot: String, item: String) -> bool:
	return equipped.emotes.has(item) if slot == "emote" else String(equipped.get(slot, "")) == item

# ---------- codex ----------

static func _codex(main, body: VBoxContainer) -> void:
	var mastery: Dictionary = main.account.meta.get("mastery", {}) if main.account.is_signed_in() else {}
	body.add_child(MultiplayerUI.label(Localization.text("숙련도: 유닛을 %d기 · %d기 · %d기 내보내면 동 · 은 · 금 등급이 됩니다 (서버가 확인한 전투만).") % [int(Progression.MASTERY_LEVELS[0][0]), int(Progression.MASTERY_LEVELS[1][0]), int(Progression.MASTERY_LEVELS[2][0])], 14, UIKit.TEXT_MUTED))
	for kind in BattleModel.UNIT_STATS:
		var parts := _row_panel()
		parts[0].name = "Codex_" + String(kind)
		var row: HBoxContainer = parts[1]
		var portrait := TextureRect.new()
		portrait.custom_minimum_size = Vector2(56, 56)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.texture = load("res://scripts/BattleView.gd").UNIT_TEXTURES.get(kind)
		row.add_child(portrait)
		var stats: Dictionary = BattleModel.UNIT_STATS[kind]
		var own: Dictionary = mastery.get(kind, {"spawned": 0, "kills": 0})
		var level := Progression.mastery_level(int(own.spawned))
		var text := MultiplayerUI.label("%s%s  ·  %s %d\n%s\n%s" % [String(BattleModel.UNIT_NAMES.get(kind, kind)), (" [%s]" % level) if not level.is_empty() else "", Localization.text("비용"), int(stats.get("cost", 0)),
			Localization.text(String(Progression.LORE.get(kind, ""))), Localization.text("출전 %d기 · 처치 %d") % [int(own.spawned), int(own.kills)]], 14, UIKit.TEXT)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		body.add_child(parts[0])

# ---------- profile cards ----------

static func _profile(main, body: VBoxContainer) -> void:
	var account = main.account
	var find := HBoxContainer.new()
	find.add_theme_constant_override("separation", 8)
	body.add_child(find)
	var field := LineEdit.new()
	field.name = "ProfileLookup"
	field.placeholder_text = Localization.text("닉네임으로 프로필 카드 보기")
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(0, 44)
	find.add_child(field)
	var look = main._styled_button(Localization.text("보기"), UIKit.GOLD_DEEP, true)
	look.name = "ProfileLookupButton"
	look.custom_minimum_size = Vector2(110, 44)
	look.pressed.connect(func():
		if not field.text.strip_edges().is_empty():
			account.look_up(field.text))
	find.add_child(look)
	if account.is_signed_in() and account.online and not _asked_own:
		_asked_own = true
		account.look_up(account.nickname)
	if not account.profile_card.is_empty():
		body.add_child(card(account.profile_card))
	elif not account.online:
		body.add_child(MultiplayerUI.label(Localization.text("서버에 연결되면 프로필 카드를 볼 수 있습니다."), 15, UIKit.TEXT_MUTED))

## A profile card: banner, title and name, rating, battle time, most fielded units.
static func card(data: Dictionary) -> Control:
	var banner: Dictionary = Progression.cosmetic(String(data.banner))
	var top: Color = banner.get("color", UIKit.ACCENT) if banner.get("color") is Color else UIKit.ACCENT
	var bottom: Color = banner.get("color2", UIKit.SURFACE) if banner.get("color2") is Color else UIKit.SURFACE
	var frame: Dictionary = Progression.cosmetic(String(data.frame))
	var edge: Color = frame.get("color", UIKit.GOLD_DEEP) if frame.get("color") is Color else UIKit.GOLD_DEEP
	var panel := PanelContainer.new()
	panel.name = "ProfileCard"
	panel.custom_minimum_size = Vector2(620, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", UIKit.with_margins(UIKit.box(top.darkened(0.25), bottom, edge, 16, 3.0), 22, 16))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var emblem := Label.new() # not the display font: it has no emoji
	emblem.text = String(EMBLEMS.get(String(banner.get("emblem", "shield")), "★"))
	emblem.add_theme_font_size_override("font_size", 40)
	head.add_child(emblem)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(names)
	if not String(data.title).is_empty():
		names.add_child(MultiplayerUI.label(Titles.badge(String(data.title)), 16, UIKit.GOLD))
	var nick := MultiplayerUI.label(String(data.nickname), 28, Color.WHITE)
	nick.name = "ProfileCardName"
	names.add_child(nick)
	var since := Time.get_date_dict_from_unix_time(int(data.since))
	names.add_child(MultiplayerUI.label(Localization.text("%d년 %d월부터 성을 지킴") % [int(since.year), int(since.month)], 13, UIKit.TEXT_MUTED))
	var rating := VBoxContainer.new()
	head.add_child(rating)
	rating.add_child(MultiplayerUI.label(Localization.text("랭크 %d") % int(data.rating), 22, UIKit.GOLD))
	rating.add_child(MultiplayerUI.label(Localization.text("최고 %d · %d판") % [int(data.best), int(data.ranked_games)], 13, UIKit.TEXT_MUTED))
	var facts := HBoxContainer.new()
	facts.add_theme_constant_override("separation", 22)
	box.add_child(facts)
	for fact in [[hours_text(int(data.seconds)), "전투 시간"], ["%d / %d" % [int(data.wins), int(data.battles)], "승 / 전투"], [str(int(data.titles)), "칭호"], [str(int(data.pass_tier)), "시즌 패스"]]:
		var cell := VBoxContainer.new()
		cell.add_child(MultiplayerUI.label(String(fact[0]), 18, Color.WHITE))
		cell.add_child(MultiplayerUI.label(Localization.text(String(fact[1])), 12, UIKit.TEXT_MUTED))
		facts.add_child(cell)
	if not data.units.is_empty():
		var units := PackedStringArray()
		for row in data.units:
			var level := Progression.mastery_level(int(row.spawned))
			units.append("%s%s %d" % [String(BattleModel.UNIT_NAMES.get(String(row.kind), row.kind)), ("[%s]" % level) if not level.is_empty() else "", int(row.spawned)])
		box.add_child(MultiplayerUI.label(Localization.text("주력 유닛 · ") + "  ·  ".join(units), 14, UIKit.TEXT))
	return panel

# ---------- result screen ----------

## A line on the result screen with what this battle earned, filled in when the server's answer arrives.
static func attach_reward(main, screen: Control, at: Vector2) -> void:
	var account = main.account
	if not account.is_signed_in() or main.cheats_used or main.network.client_is_spectator:
		return
	var label := Label.new()
	label.name = "RewardLine"
	label.position = at
	label.size = Vector2(580, 30)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", UIKit.GOLD)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(label)
	var fill := func():
		if not is_instance_valid(label) or account.last_reward.is_empty():
			return
		label.text = reward_text(account.last_reward)
		account.last_reward = {}
		UIKit.reveal(label, 0.3, 8.0)
	var watcher := Watcher.new()
	watcher.account = account
	watcher.redraw = fill
	label.add_child(watcher)
	fill.call()

static func reward_text(reward: Dictionary) -> String:
	var parts := PackedStringArray()
	parts.append("%s +%d" % [GOLD_ICON, int(reward.gold)])
	parts.append(Localization.text("패스 +%d") % int(reward.xp))
	if not reward.tiers.is_empty():
		parts.append(Localization.text("%d단계 달성!") % int(reward.tiers.back()))
	if not reward.quests.is_empty():
		parts.append(Localization.text("임무 완료 %d") % reward.quests.size())
	for id in reward.titles:
		parts.append(Titles.badge(String(id)))
	return "  ·  ".join(parts)
