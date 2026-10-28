extends RefCounted
## Presentation only: coordinates follow display interpolation, while combat
## values and timers always use the last authoritative snapshot.

const FONT = preload("res://assets/fonts/BlackHanSans-Regular.ttf")

static func body_rect(view, unit: Dictionary) -> Rect2:
	var x: float = view.world_to_screen_x(view.motion.position(int(unit.id), float(unit.x)))
	return Rect2(x - 28.0, view.size.y * 0.72 - 94.0, 56.0, 94.0)

static func hit_rect(view, unit: Dictionary) -> Rect2:
	# Include the staggered health bars as well as the sprite body.
	return body_rect(view, unit).grow_individual(0.0, 32.0, 0.0, 0.0)

static func units_at(view, position: Vector2) -> Array:
	var hits: Array = []
	var order := 0
	for unit in view.snapshot.get("units", []):
		order += 1
		if float(unit.get("hp", 0.0)) <= 0.0 or not BattleModel.UNIT_NAMES.has(String(unit.get("kind", ""))): continue
		var rect := body_rect(view, unit)
		if not hit_rect(view, unit).has_point(position): continue
		var distance := position.distance_squared_to(rect.get_center())
		# Equal-distance units are drawn in snapshot order; prefer the top one.
		hits.append({"unit": unit, "distance": distance, "order": order})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a.distance) != float(b.distance): return float(a.distance) < float(b.distance)
		return int(a.order) > int(b.order)
	)
	var result: Array = []
	for hit in hits: result.append(hit.unit)
	return result

static func unit_at(view, position: Vector2) -> Dictionary:
	var units := units_at(view, position)
	return {} if units.is_empty() else units[0]

static func curse_remaining(view, unit: Dictionary) -> float:
	var remaining := 0.0
	var elapsed := float(view.snapshot.get("elapsed", 0.0))
	for curse in view.snapshot.get("curses", []):
		if int(curse.get("side", -1)) == int(unit.side): continue
		if absf(float(curse.get("x", 0.0)) - float(unit.x)) > BattleModel.CURSE_RADIUS: continue
		remaining = maxf(remaining, float(curse.get("expires_at", elapsed)) - elapsed)
	return remaining

static func draw(view, unit: Dictionary, spectator: bool, navigation_hint: String = "") -> void:
	var body := body_rect(view, unit)
	var side := int(unit.side)
	var kind := String(unit.kind)
	var team: Color = view.BLUE if view.display_side(side) == 0 else view.RED
	var hp := float(unit.hp)
	var maximum := maxf(1.0, float(unit.get("max_hp", hp)))
	var fraction := clampf(hp / maximum, 0.0, 1.0)
	var health_tone: Color = view.RED_LIGHT if fraction <= 0.25 else Color("#e8edf5")
	view.draw_rect(body, view.GOLD, false, 2.0)
	view.draw_circle(Vector2(body.get_center().x, body.end.y + 3.0), 4.0, view.GOLD)
	var width := minf(380.0, maxf(1.0, view.size.x - 24.0))
	var left := clampf(body.get_center().x - width * 0.5, 12.0, maxf(12.0, view.size.x - width - 12.0))
	var card := Rect2(left, 28.0, width, 224.0 if navigation_hint.is_empty() else 244.0)
	view.draw_line(Vector2(card.get_center().x, card.end.y), Vector2(body.get_center().x, body.position.y), Color(team.r, team.g, team.b, 0.65), 1.5)
	view.draw_rect(card, Color(0.02, 0.03, 0.06, 0.96))
	view.draw_rect(card, team, false, 2.0)
	var side_name := ("블루" if side == 0 else "레드") if spectator else ("아군" if side == view.own_side else "적군")
	var summon := " · 소환 병력" if BattleModel.SUMMON_STATS.has(kind) else ""
	_line(view, left, width, 56.0, "%s · %s%s" % [side_name, String(BattleModel.UNIT_NAMES.get(kind, kind)), summon], 20, team)
	_line(view, left, width, 82.0, "체력 %d / %d · %d%%%s" % [ceili(hp), ceili(maximum), roundi(fraction * 100.0), " · 사망 주의" if fraction <= 0.25 else ""], 16, health_tone)
	view.draw_rect(Rect2(left + 12.0, 90.0, width - 24.0, 6.0), Color("#313a4a"))
	view.draw_rect(Rect2(left + 12.0, 90.0, (width - 24.0) * fraction, 6.0), health_tone)
	var cursed_for := curse_remaining(view, unit)
	var curse_scale: float = BattleModel.CURSE_SPEED_SCALE if cursed_for > 0.0 else 1.0
	var stacks := clampi(int(unit.get("support_stacks", 0)), 0, BattleModel.SUPPORT_MAX_STACKS) if kind != "healer" else 0
	var enraged := BattleModel.is_enraged(unit)
	var speed := (1.0 + stacks * BattleModel.SUPPORT_INCREMENT) * (BattleModel.RAGE_SPEED_MULTIPLIER if enraged else 1.0) * curse_scale
	var attack := "공속 지원 병력 · 직접 공격 없음" if kind == "healer" else "현재 공격력 %.1f · 공속 ×%.2f" % [float(unit.get("damage", 0.0)) * (1.0 + int(unit.get("souls", 0)) * float(BattleModel.trait_value(kind, "soul_damage_step", 0.0))), speed]
	_line(view, left, width, 120.0, attack, 15, Color("#e8edf5"))
	_line(view, left, width, 144.0, "공속 지원 %d / %d중첩 · +%d%%" % [stacks, BattleModel.SUPPORT_MAX_STACKS, roundi(stacks * BattleModel.SUPPORT_INCREMENT * 100.0)] if kind != "healer" else "마법사는 공속 지원을 받지 않습니다", 14, Color("#86f7ad"))
	var curse_text := "저주 없음"
	if cursed_for > 0.0:
		curse_text = "저주 · 공속 -%d%% · 장판 %.1f초" % [roundi((1.0 - BattleModel.CURSE_SPEED_SCALE) * 100.0), maxf(0.1, cursed_for)]
	_line(view, left, width, 168.0, curse_text, 14, Color("#c592ff") if cursed_for > 0.0 else Color("#b0bbcf"))
	var ability := "현재 수치 · 성장과 전장 효과 반영"
	var ability_tone := Color("#b0bbcf")
	if kind == "berserker":
		ability = "분노 발동 · 공속 ×%.1f" % BattleModel.RAGE_SPEED_MULTIPLIER if enraged else "분노 대기 · 체력 %d%% 이하에서 발동" % roundi(BattleModel.RAGE_HP_FRACTION * 100.0)
		if enraged: ability_tone = Color("#ff9a61")
	elif kind == "necromancer":
		ability = "소환 시간 정보 없음"
		if unit.has("summon_remaining"):
			var remaining := float(unit.summon_remaining)
			ability = "다음 해골 소환 %.1f초" % maxf(0.1, remaining) if remaining > 0.0 else "해골 소환 준비됨"
	elif unit.has("souls"):
		var ready_in := float(unit.get("skill_remaining", 0.0))
		ability = "영혼 %d / %d · %s %s" % [int(unit.souls), int(BattleModel.trait_value(kind, "soul_max", 0)), BattleModel.skill_name(kind), ("%.1f초 뒤" % maxf(0.1, ready_in)) if ready_in > 0.0 else "준비됨"]
		ability_tone = Color("#ff6b5a")
	elif unit.has("skill_remaining"):
		var ready_in := float(unit.skill_remaining)
		ability = "%s %.1f초 뒤" % [BattleModel.skill_name(kind), maxf(0.1, ready_in)] if ready_in > 0.0 else "%s 준비됨" % BattleModel.skill_name(kind)
		ability_tone = Color("#ffd36a")
	elif BattleModel.trait_value(kind, "target_rearmost", false):
		ability = "사거리 안 가장 뒤의 적을 저격"
	elif unit.has("revive_remaining"):
		ability = "쓰러짐 · %.1f초 뒤 부활" % maxf(0.1, float(unit.revive_remaining))
		ability_tone = Color("#9fd18b")
	elif BattleModel.can_revive(kind):
		ability = "첫 사망 시 1회 부활 · 언데드"
	elif cursed_for > 0.0:
		ability = "저주는 장판을 벗어나면 해제됩니다"
	_line(view, left, width, 192.0, ability, 14, ability_tone)
	_line(view, left, width, 212.0, "마지막 전투 상태 기준 · 전투는 계속 진행", 12, Color("#8995ad"))
	if navigation_hint.is_empty():
		_line(view, left, width, 238.0, "같은 병력 · 빈 전장 · Esc로 닫기", 12, Color("#8995ad"))
	else:
		_line(view, left, width, 238.0, navigation_hint, 12, view.GOLD)
		_line(view, left, width, 258.0, "Shift+Tab: 이전 · 빈 전장/Esc: 닫기", 12, Color("#8995ad"))

static func _line(view, left: float, width: float, y: float, text: String, font_size: int, tone: Color) -> void:
	view.draw_string(FONT, Vector2(left + 12.0, y), text, HORIZONTAL_ALIGNMENT_LEFT, width - 24.0, font_size, tone)
