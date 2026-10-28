extends RefCounted
## Read-only counts captured from a replay checkpoint; never keeps live unit references.

const UIKit = preload("res://scripts/ui/UIKit.gd")

# Shared with the live army panel so a kind has the same role in both views.
const ROLES := {
	"front": {"title": "근접 전열", "kinds": ["shield", "swordsman", "berserker", "zombie", "paladin", "demon_lord", "skeleton"], "description": "근거리에서 공격하고 전열을 구성합니다. 좀비와 해골도 이 역할에 포함합니다."},
	"ranged": {"title": "원거리 공격", "kinds": ["archer", "warlock", "sniper"], "description": "원거리에서 공격합니다. 흑마법사는 공격 대상에 적 공격 속도를 늦추는 장판도 만들고, 저격수는 가장 뒤의 적을 노립니다."},
	"support": {"title": "공속 지원", "kinds": ["healer"], "description": "마법사는 아군의 공격속도를 높입니다. 직접 피해를 주거나 체력을 회복하지 않습니다."},
	"summoner": {"title": "소환 지휘", "kinds": ["necromancer"], "description": "네크로맨서는 공격하면서 해골을 소환합니다. 소환된 해골은 근접 전열에 따로 집계합니다."},
}

static func capture(units: Array) -> Dictionary:
	var counts := {"living": [0, 0], "summons": [0, 0], "kinds": [{}, {}]}
	for unit in units:
		if float(unit.hp) <= 0.0: continue
		var side := int(unit.side)
		var kind := String(unit.kind)
		counts.living[side] += 1
		counts.kinds[side][kind] = int(counts.kinds[side].get(kind, 0)) + 1
		if BattleModel.SUMMON_STATS.has(kind): counts.summons[side] += 1
	return counts

static func populate(parent: VBoxContainer, counts: Dictionary, baseline: Dictionary = {}) -> void:
	if counts.is_empty():
		parent.add_child(_label("이 시점의 병력 정보가 없습니다. 시작·끝 지점을 다시 지정하세요.", 16, UIKit.TEXT_MUTED))
		return
	parent.add_child(_label("구간 끝의 생존 병력" if not baseline.is_empty() else "현재 시점의 생존 병력", 20, UIKit.GOLD))
	var hint := "양쪽 생존 인원과 자기 진영 전체에서의 비율입니다. 해골은 근접 전열에 포함하며 사망 후 정리 대기 병력·구조물은 제외합니다. 병력 수는 전투력이나 승률을 뜻하지 않습니다."
	if not baseline.is_empty():
		hint += "\n시작→끝과 괄호의 순증감을 표시합니다. 생산·소환·사망이 함께 반영되므로 감소를 처치 수로 해석할 수 없습니다."
	parent.add_child(_label(hint, 13, UIKit.TEXT_MUTED))
	_add_row(parent, "생존 병력", counts.living, baseline.get("living", []))
	_add_row(parent, "그중 소환 병력", counts.summons, baseline.get("summons", []))
	parent.add_child(HSeparator.new())
	for role in ROLES:
		var values := [0, 0]
		var before := [0, 0] if not baseline.is_empty() else []
		for side in 2:
			for kind in ROLES[role].kinds:
				values[side] += int(counts.kinds[side].get(kind, 0))
				if not before.is_empty(): before[side] += int(baseline.kinds[side].get(kind, 0))
		var card := VBoxContainer.new()
		card.name = "ReplayArmyRole_" + String(role)
		card.add_theme_constant_override("separation", 4)
		parent.add_child(card)
		_add_row(card, String(ROLES[role].title), values, before, counts.living)
		var bars := HBoxContainer.new()
		bars.add_theme_constant_override("separation", 24)
		card.add_child(bars)
		for side in 2:
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 10
			bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bar.show_percentage = false
			bar.step = 0.0
			bar.value = 100.0 * float(values[side]) / float(counts.living[side]) if int(counts.living[side]) > 0 else 0.0
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var track := StyleBoxFlat.new()
			track.bg_color = UIKit.BG_DEEP
			bar.add_theme_stylebox_override("background", track)
			var fill := StyleBoxFlat.new()
			fill.bg_color = UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED
			bar.add_theme_stylebox_override("fill", fill)
			bars.add_child(bar)
	parent.add_child(HSeparator.new())
	parent.add_child(_label("종류별 생존 수 · 소환된 해골은 별도 집계", 18, UIKit.GOLD))
	for kind in BattleModel.UNIT_NAMES:
		var values := [int(counts.kinds[0].get(kind, 0)), int(counts.kinds[1].get(kind, 0))]
		var before := [int(baseline.kinds[0].get(kind, 0)), int(baseline.kinds[1].get(kind, 0))] if not baseline.is_empty() else []
		_add_row(parent, String(BattleModel.UNIT_NAMES[kind]), values, before)

static func _add_row(parent: VBoxContainer, title: String, values: Array, baseline: Array = [], totals: Array = []) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	row.add_child(_label(title, 16, UIKit.TEXT))
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	row.add_child(columns)
	for side in 2:
		var amount := int(values[side])
		var text := "%s · %d명" % ["블루" if side == 0 else "레드", amount]
		if not totals.is_empty():
			text += " · %.1f%%" % (100.0 * float(amount) / float(totals[side])) if int(totals[side]) > 0 else " · 비율 —"
		if not baseline.is_empty():
			var delta := amount - int(baseline[side])
			text += " · %d→%d (%s%d)" % [int(baseline[side]), amount, "+" if delta > 0 else "", delta]
		var label := _label(text, 14, UIKit.TEAM_BLUE if side == 0 else UIKit.TEAM_RED)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(label)

static func _label(text: String, font_size: int, tone: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tone)
	return label
