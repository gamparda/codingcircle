extends RefCounted
## Device-local recovery points, with an explicit preview before replacing progress.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MultiplayerUI = preload("res://scripts/MultiplayerUI.gd")
const Achievements = preload("res://scripts/Achievements.gd")
const Goals = preload("res://scripts/Goals.gd")
const NewFeatures = preload("res://scripts/NewFeatures.gd")
const BattleBindings = preload("res://scripts/BattleBindings.gd")
const CHALLENGE_PAGE_SIZE := 8
const RECORD_FIELDS := [
	["ai_matches", "AI 경기", "판"], ["ai_wins", "AI 승리", "승"], ["ai_losses", "AI 패배", "패"],
	["highest_campaign", "최고 캠페인", "단계"],
	["online_completed", "온라인 완료", "판"], ["online_wins", "온라인 승리", "승"],
	["online_losses", "온라인 패배", "패"], ["online_draws", "온라인 무승부", "판"],
	["online_interrupted", "온라인 중단", "판"],
	["win_streak", "현재 연승", "연승"], ["best_streak", "최고 연승", "연승"],
	["daily_completed", "일일 도전 누적 성공", "회"], ["weekly_completed", "주간 도전 누적 성공", "회"],
]

static func _label(text: String, color: Color = UIKit.TEXT_MUTED) -> Label:
	var label := MultiplayerUI.label(text, 15, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

static func _summary(data: Dictionary) -> String:
	return "%s · 캠페인 %d단계 개방 · 별 %d개\nAI %d판 · 온라인 %d판 · 업적 %d개 · 일일 기록 %d일 · 주간 기록 %d주" % [String(data.nickname), int(data.campaign_unlocked), int(data.stats.total_stars), int(data.stats.ai_matches), int(data.stats.online_completed), data.achievements.size(), data.daily.size(), data.weekly.size()]

static func _deck_names(kinds: Array, units: bool) -> String:
	var structures := {"wall": "방벽", "swamp": "늪", "turret": "포탑", "generator": "발전기"}
	var names: PackedStringArray = []
	for kind in kinds:
		names.append(String(BattleModel.UNIT_NAMES.get(kind, kind) if units else structures.get(kind, kind)))
	return " / ".join(names)

static func _deck_item(kind: String, units: bool) -> String:
	# IDs distinguish names that overlap, such as wizard and warlock.
	return "%s (%s)" % [_deck_names([kind], units), kind]

static func _deck_group_comparison(before: Array, after: Array, units: bool, keys: Array) -> Dictionary:
	var removed: Array = []
	var added: Array = []
	var moved: PackedStringArray = []
	var rows: Array = []
	for kind in before:
		if not after.has(kind): removed.append(kind)
	for kind in after:
		if not before.has(kind):
			added.append(kind)
		elif before.find(kind) != after.find(kind):
			moved.append("%s %d → %d번" % [_deck_item(String(kind), units), before.find(kind) + 1, after.find(kind) + 1])
	var title := "병력" if units else "구조물"
	var summary := title + " · 변경 없음"
	if before != after:
		summary = title + (" · 구성 동일, 순서만 변경" if removed.is_empty() and added.is_empty() else " · 구성 교체")
	var details: PackedStringArray = []
	if not removed.is_empty(): details.append("사본에서 빠짐: %s" % _deck_names(removed, units))
	if not added.is_empty(): details.append("사본에 들어옴: %s" % _deck_names(added, units))
	if not moved.is_empty(): details.append("유지되는 항목의 순서 이동: %s" % " / ".join(moved))
	# The save sanitizer guarantees three distinct, valid items in each group.
	# Bindings stay on the current device when a profile is restored.
	for index in before.size():
		var changed: bool = before[index] != after[index]
		var note := "동일"
		if changed:
			note = "순서 이동" if before.has(after[index]) else "새 항목"
		rows.append({"text": "%s %d [%s]: %s → %s · %s" % [title, index + 1, BattleBindings.key_name(int(keys[index + (0 if units else 3)])), _deck_item(String(before[index]), units), _deck_item(String(after[index]), units), note], "changed": changed})
	return {"summary": summary, "details": "\n".join(details), "rows": rows, "changed": before != after}

static func _decks_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var slots: Array = []
	var changed_text: PackedStringArray = []
	var first_changed := -1
	var keys: Array = live.settings.battle_keys
	for index in live.deck_presets.size():
		var before: Dictionary = live.deck_presets[index]
		var after: Dictionary = restored.deck_presets[index]
		var changes: PackedStringArray = []
		var kinds: PackedStringArray = []
		if String(before.name) != String(after.name):
			changes.append("이름: %s → %s" % [String(before.name), String(after.name)])
			kinds.append("이름")
		if before.units != after.units:
			changes.append("병력: %s → %s" % [_deck_names(before.units, true), _deck_names(after.units, true)])
			kinds.append("병력")
		if before.structures != after.structures:
			changes.append("구조물: %s → %s" % [_deck_names(before.structures, false), _deck_names(after.structures, false)])
			kinds.append("구조물")
		if not changes.is_empty():
			if first_changed < 0: first_changed = index
			changed_text.append("덱 슬롯 %d\n%s" % [index + 1, "\n".join(changes)])
		slots.append({"before_name": String(before.name), "after_name": String(after.name),
			"changed": not changes.is_empty(), "changes": "·".join(kinds) + " 변경" if not kinds.is_empty() else "변경 없음",
			"units": _deck_group_comparison(before.units, after.units, true, keys),
			"structures": _deck_group_comparison(before.structures, after.structures, false, keys)})
	return {"slots": slots, "changed": changed_text.size(), "text": "\n\n".join(changed_text) if not changed_text.is_empty() else "세 덱의 이름·병력·구조물·배치 순서 변경 없음",
		"default_slot": first_changed if first_changed >= 0 else int(restored.last_deck),
		"before_selected": int(live.last_deck), "after_selected": int(restored.last_deck)}

static func _challenge_versions(history: Dictionary, date: String) -> Dictionary:
	if not history.has(date): return {}
	var record: Dictionary = history[date]
	var versions: Dictionary = record.get("previous", {}).duplicate()
	# Main/previous placement is storage bookkeeping, not a change of the result.
	versions[String(record.ruleset)] = record
	return versions

static func _challenge_value(record: Dictionary) -> String:
	if record.is_empty(): return "기록 없음"
	return "%s · %d점 · %s초" % ["성공" if bool(record.won) else "실패", int(record.score), str(record.seconds)]

static func _challenge_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var rows: Array = []
	var summaries: PackedStringArray = []
	var lost := 0
	var lowered := 0
	for period in ["daily", "weekly"]:
		var before_history: Dictionary = live[period]
		var after_history: Dictionary = restored[period]
		var dates: Array = before_history.keys()
		for date in after_history:
			if not dates.has(date): dates.append(date)
		dates.sort()
		dates.reverse()
		var added := 0
		var removed := 0
		var changed := 0
		var unchanged := 0
		for date in dates:
			var before_versions := _challenge_versions(before_history, String(date))
			var after_versions := _challenge_versions(after_history, String(date))
			var rules: Array = before_versions.keys()
			for rule in after_versions:
				if not rules.has(rule): rules.append(rule)
			rules.sort()
			for rule in rules:
				var before: Dictionary = before_versions.get(rule, {})
				var after: Dictionary = after_versions.get(rule, {})
				# Ignore nested history and compare only the result restored for this date/version.
				if not before.is_empty() and not after.is_empty() and before.won == after.won and int(before.score) == int(after.score) and float(before.seconds) == float(after.seconds):
					unchanged += 1
					continue
				var risk := false
				var kind := "변경"
				if before.is_empty():
					kind = "추가"
					added += 1
				elif after.is_empty():
					kind = "사라짐"
					risk = true
					removed += 1
					lost += 1
				else:
					changed += 1
					# The best successful score uses time only to break a tied score.
					risk = bool(before.won) and (not bool(after.won) or int(after.score) < int(before.score) or (int(after.score) == int(before.score) and float(after.seconds) > float(before.seconds)))
					if risk:
						kind = "낮아짐"
						lowered += 1
				var day := String(date)
				var date_label := "%s-%s-%s" % [day.substr(0, 4), day.substr(4, 2), day.substr(6, 2)]
				var period_label := "일일" if period == "daily" else "주간 (주 시작일)"
				var version_label := "버전 미상" if rule == "0" else String(rule)
				var text := "%s · %s · %s · %s\n현재: %s\n사본: %s" % [period_label, date_label, version_label, kind, _challenge_value(before), _challenge_value(after)]
				rows.append({"text": text, "search": (text + " " + day + " " + String(rule)).to_lower(), "kind": kind, "risk": risk})
		var title := "일일" if period == "daily" else "주간"
		summaries.append("%s: 추가 %d개 · 변경 %d개 · 사라짐 %d개 · 동일 %d개" % [title, added, changed, removed, unchanged])
	var warning := ""
	if lost > 0 or lowered > 0:
		warning = "도전 기록 %d개가 사라지고 성공 기록 %d개가 실패·낮은 점수·동점의 느린 시간으로 바뀝니다. 다른 날짜·버전의 증가로 상쇄하지 않았습니다." % [lost, lowered]
	return {"rows": rows, "summary": "\n".join(summaries), "warning": warning}

static func _stats_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var rows: Array = []
	var decreased: PackedStringArray = []
	var increased := 0
	for field in RECORD_FIELDS:
		var before := int(live.stats[field[0]])
		var after := int(restored.stats[field[0]])
		if before == after: continue
		var risk := after < before
		var delta := before - after if risk else after - before
		var change := "%d%s %s" % [delta, field[2], "감소" if risk else "증가"]
		rows.append({"text": "%s: %d%s → %d%s · %s" % [field[1], before, field[2], after, field[2], change], "risk": risk})
		if risk:
			decreased.append("%s %d%s" % [field[1], delta, field[2]])
		else:
			increased += 1
	var warning := ""
	if not decreased.is_empty():
		warning = "줄어드는 전적: %s. 각 항목의 감소를 따로 표시하며 다른 기록의 증가로 상쇄하지 않습니다." % " / ".join(decreased)
	return {"rows": rows, "summary": "전적: 감소 %d항목 · 증가 %d항목 · 동일 %d항목" % [decreased.size(), increased, RECORD_FIELDS.size() - rows.size()], "warning": warning,
		"empty": "전적 항목 변경 없음"}

static func _achievement_time(stamp: int) -> String:
	return _stamp(stamp) if stamp > 0 else "달성 시각 미상"

static func _achievements_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var removed: Array = []
	var added: Array = []
	var changed: Array = []
	var missing_names: PackedStringArray = []
	var unchanged := 0
	for definition in Achievements.DEFS:
		var id := String(definition.id)
		# A zero timestamp still means unlocked; compare membership before timestamps.
		var before := live.achievements.has(id)
		var after := restored.achievements.has(id)
		var title := String(definition.name)
		if before and not after:
			missing_names.append(title)
			removed.append({"text": "%s · 사라짐\n현재: 달성 (%s)\n사본: 미달성\n조건: %s" % [title, _achievement_time(int(live.achievements[id])), String(definition.desc)], "risk": true})
		elif not before and after:
			added.append({"text": "%s · 추가\n현재: 미달성\n사본: 달성 (%s)" % [title, _achievement_time(int(restored.achievements[id]))], "risk": false})
		elif before and after:
			var before_stamp := int(live.achievements[id])
			var after_stamp := int(restored.achievements[id])
			if before_stamp != after_stamp:
				changed.append({"text": "%s · 달성 시각 변경 (달성 유지)\n현재: %s\n사본: %s" % [title, _achievement_time(before_stamp), _achievement_time(after_stamp)], "risk": false})
			else:
				unchanged += 1
	var rows: Array = []
	# Put losses first, even when the total unlocked count stays the same or grows.
	rows.append_array(removed)
	rows.append_array(added)
	rows.append_array(changed)
	var warning := ""
	if not removed.is_empty():
		warning = "현재 달성한 업적 %d개가 미달성으로 바뀝니다: %s. 사본에서 추가되는 업적과 별도로 확인하세요." % [removed.size(), " / ".join(missing_names)]
	return {"rows": rows, "summary": "달성 업적 %d → %d개 · 사라짐 %d개 · 추가 %d개\n달성 시각 변경 %d개 · 같은 달성 기록 %d개" % [live.achievements.size(), restored.achievements.size(), removed.size(), added.size(), changed.size(), unchanged], "warning": warning,
		"empty": "업적 달성 여부·달성 시각 변경 없음"}

static func _goals_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var removed: Array = []
	var added: Array = []
	var missing_names: PackedStringArray = []
	for definition in Goals.DEFS:
		var id := String(definition.id)
		# Use the menu's completion rules: some goals come from statistics, not flags.
		var before := Goals.is_done(live, id)
		var after := Goals.is_done(restored, id)
		if before == after: continue
		var title := String(definition.title)
		var row := {"text": "%s · %s\n현재: %s → 사본: %s\n목표 안내: %s" % [title, "다시 완료 필요" if before else "완료로 변경", "완료" if before else "미완료", "완료" if after else "미완료", String(definition.desc)], "risk": before}
		if before:
			missing_names.append(title)
			removed.append(row)
		else:
			added.append(row)
	var rows: Array = []
	rows.append_array(removed)
	rows.append_array(added)
	var before_next := Goals.next_goal(live)
	var after_next := Goals.next_goal(restored)
	var summary := "시작 목표 완료 %d / %d → %d / %d · 다시 미완료 %d개 · 새로 완료 %d개 · 상태 유지 %d개\n다음 추천: %s → %s" % [Goals.done_count(live), Goals.DEFS.size(), Goals.done_count(restored), Goals.DEFS.size(), removed.size(), added.size(), Goals.DEFS.size() - rows.size(), String(before_next.get("title", "모든 목표 완료")), String(after_next.get("title", "모든 목표 완료"))]
	if Goals.all_done(live) and not Goals.all_done(restored):
		summary += "\n복구 후 메인 메뉴에 시작 목표 버튼이 다시 표시됩니다."
	elif not Goals.all_done(live) and Goals.all_done(restored):
		summary += "\n복구 후 모든 목표가 완료되어 메인 메뉴의 시작 목표 버튼이 숨겨집니다."
	var warning := ""
	if not removed.is_empty():
		warning = "완료한 시작 목표 %d개가 다시 미완료로 바뀝니다: %s. 다른 목표의 완료 증가와 별도로 확인하세요." % [removed.size(), " / ".join(missing_names)]
	return {"rows": rows, "summary": summary, "warning": warning, "empty": "시작 목표별 완료 상태 변경 없음"}

static func _tutorial_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var before := bool(live.tutorial_completed)
	var after := bool(restored.tutorial_completed)
	var rows: Array = []
	var warning := ""
	if before != after:
		var effect := "복구 후 다음 캠페인·AI 연습 전투에서 소환·구조물 설치·자원 회복 안내가 다시 표시됩니다. 안내에서 건너뛰기를 선택할 수 있습니다." if before else "복구 후 캠페인·AI 연습 전투의 첫 전투 안내를 자동으로 표시하지 않습니다."
		rows.append({"text": effect, "risk": before})
		if before:
			warning = "첫 전투 안내의 완료 기록이 미완료로 바뀌어 다음 캠페인·AI 연습 전투에서 안내가 다시 표시됩니다."
	return {"rows": rows, "summary": "첫 전투 안내: %s → %s\n완료는 안내를 마치거나 건너뛴 상태를 뜻하며, 전투 승리 여부와는 별개입니다." % ["완료" if before else "미완료", "완료" if after else "미완료"], "warning": warning, "empty": "첫 전투 안내 완료 상태 변경 없음"}

static func _nickname_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var before := String(live.nickname)
	var after := String(restored.nickname)
	var rows: Array = []
	var warning := ""
	if before != after:
		warning = "닉네임이 「%s」에서 「%s」로 바뀝니다." % [before, after]
		rows.append({"text": "복구 후 멀티플레이의 닉네임 입력에 사본의 이름이 표시됩니다. 멀티플레이 화면에서 다시 수정할 수 있습니다. 서버에 이미 보관된 기록을 바꾸는 복구는 아닙니다.", "risk": true})
	return {"rows": rows, "summary": "닉네임: 「%s」 → 「%s」" % [before, after], "warning": warning, "empty": "닉네임 변경 없음"}

static func _features_comparison(live: Dictionary, restored: Dictionary) -> Dictionary:
	var reset: Array = []
	var seen: Array = []
	var reset_names: PackedStringArray = []
	var unchanged := 0
	for feature in NewFeatures.FEATURES:
		var id := String(feature.id)
		# Match the guide's membership check; order and retired IDs do not affect NEW tags.
		var before := NewFeatures.is_seen(live, id)
		var after := NewFeatures.is_seen(restored, id)
		if before == after:
			unchanged += 1
			continue
		var title := String(feature.title)
		var row := {"text": "%s · %s\n현재: %s → 사본: %s" % [title, "다시 미확인" if before else "확인함으로 변경", "확인함" if before else "미확인 (NEW)", "확인함" if after else "미확인 (NEW)"], "risk": before}
		if before:
			reset_names.append(title)
			reset.append(row)
		else:
			seen.append(row)
	var rows: Array = []
	rows.append_array(reset)
	rows.append_array(seen)
	var before_unseen := NewFeatures.unseen(live).size()
	var after_unseen := NewFeatures.unseen(restored).size()
	var summary := "현재 안내의 미확인 기능 %d → %d개 / %d개\n다시 미확인 %d개 · 확인함으로 변경 %d개 · 상태 유지 %d개" % [before_unseen, after_unseen, NewFeatures.FEATURES.size(), reset.size(), seen.size(), unchanged]
	if before_unseen == 0 and after_unseen > 0:
		summary += "\n복구 후 메인 메뉴에 새 기능 %d개 버튼이 다시 표시됩니다." % after_unseen
	elif before_unseen > 0 and after_unseen == 0:
		summary += "\n복구 후 현재 안내의 모든 기능이 확인 상태가 되어 메인 메뉴의 새 기능 버튼이 숨겨집니다."
	# A shared button keeps NEW until all of its features have been seen.
	var buttons: PackedStringArray = []
	for feature in NewFeatures.FEATURES:
		var button := String(feature.button)
		if buttons.has(button): continue
		buttons.append(button)
		var before_new := false
		var after_new := false
		var titles: PackedStringArray = []
		for item in NewFeatures.features_for(button):
			titles.append(String(item.title))
			before_new = before_new or not NewFeatures.is_seen(live, String(item.id))
			after_new = after_new or not NewFeatures.is_seen(restored, String(item.id))
		if before_new != after_new:
			rows.append({"text": "메뉴 NEW 표시 (%s): %s → %s" % [" / ".join(titles), "표시" if before_new else "숨김", "표시" if after_new else "숨김"], "risk": after_new})
	var warning := ""
	if not reset.is_empty():
		warning = "확인한 새 기능 %d개가 다시 미확인으로 바뀝니다: %s. 다른 기능의 확인 증가와 별도로 표시합니다." % [reset.size(), " / ".join(reset_names)]
	return {"rows": rows, "summary": summary, "warning": warning, "empty": "현재 안내의 기능별 확인 상태 변경 없음"}

static func _comparison(current: Dictionary, candidate: Dictionary) -> Dictionary:
	# Compare the normalized values restore_backup actually applies, without touching either profile.
	var live := SaveData.sanitize(current)
	var restored := SaveData.sanitize(candidate)
	var campaign: PackedStringArray = []
	var decks := _decks_comparison(live, restored)
	var warnings: PackedStringArray = []
	var lost_clears := 0
	var lost_stars := 0
	for index in live.campaign_records.size():
		var before: Dictionary = live.campaign_records[index]
		var after: Dictionary = restored.campaign_records[index]
		var changes: PackedStringArray = []
		if bool(before.cleared) != bool(after.cleared):
			changes.append("클리어 %s → %s" % ["완료" if before.cleared else "미완료", "완료" if after.cleared else "미완료"])
			if before.cleared: lost_clears += 1
		if int(before.best_stars) != int(after.best_stars):
			changes.append("별 %d → %d" % [int(before.best_stars), int(after.best_stars)])
			lost_stars += maxi(0, int(before.best_stars) - int(after.best_stars))
		if float(before.fastest_win) != float(after.fastest_win):
			changes.append("최단 승리 %s → %s" % [_win_time(before), _win_time(after)])
		if float(before.best_base_hp) != float(after.best_base_hp):
			changes.append("최고 기지 체력 %s → %s" % [str(before.best_base_hp), str(after.best_base_hp)])
		if int(before.attempts) != int(after.attempts) or int(before.wins) != int(after.wins):
			changes.append("시도 %d → %d · 승리 %d → %d" % [int(before.attempts), int(after.attempts), int(before.wins), int(after.wins)])
		if not changes.is_empty():
			campaign.append("%d단계 · %s\n%s" % [index + 1, ServerAI.stage_name(index + 1), "\n".join(changes)])
	var summary := "변경: 캠페인 기록 %d단계 · 덱 구성 %d개\n개방 단계 %d → %d · 총 별 %d → %d" % [campaign.size(), int(decks.changed), int(live.campaign_unlocked), int(restored.campaign_unlocked), int(live.stats.total_stars), int(restored.stats.total_stars)]
	if int(restored.campaign_unlocked) < int(live.campaign_unlocked):
		warnings.append("개방 단계가 줄어 일부 캠페인이 다시 잠깁니다.")
	if lost_clears > 0 or lost_stars > 0:
		warnings.append("현재 기록 중 클리어 %d단계·별 %d개가 사본의 낮은 기록으로 바뀝니다. 다른 단계의 증가와 별도로 계산했습니다." % [lost_clears, lost_stars])
	var before_growth := SaveData.campaign_growth_level(live)
	var after_growth := SaveData.campaign_growth_level(restored)
	if before_growth != after_growth:
		var before_bonus := BattleModel.campaign_bonuses(before_growth)
		var after_bonus := BattleModel.campaign_bonuses(after_growth)
		summary += "\n성장 보상 %d → %d단계 · 병력 강화 +%d%% → +%d%%\n자원 수입 %s → %s/초 · 보유 한도 %d → %d · 시작 자원 %d → %d" % [before_growth, after_growth, roundi((float(before_bonus.stat_scale) - 1.0) * 100), roundi((float(after_bonus.stat_scale) - 1.0) * 100), str(before_bonus.income), str(after_bonus.income), int(before_bonus.capacity), int(after_bonus.capacity), int(before_bonus.starting_resources), int(after_bonus.starting_resources)]
	if int(live.last_deck) != int(restored.last_deck):
		summary += "\n최근 선택 덱: 슬롯 %d → 슬롯 %d" % [int(live.last_deck) + 1, int(restored.last_deck) + 1]
	var challenges := _challenge_comparison(live, restored)
	if not String(challenges.warning).is_empty(): warnings.append(String(challenges.warning))
	var stats := _stats_comparison(live, restored)
	if not String(stats.warning).is_empty(): warnings.append(String(stats.warning))
	var achievements := _achievements_comparison(live, restored)
	if not String(achievements.warning).is_empty(): warnings.append(String(achievements.warning))
	var goals := _goals_comparison(live, restored)
	if not String(goals.warning).is_empty(): warnings.append(String(goals.warning))
	var tutorial := _tutorial_comparison(live, restored)
	if not String(tutorial.warning).is_empty(): warnings.append(String(tutorial.warning))
	var nickname := _nickname_comparison(live, restored)
	if not String(nickname.warning).is_empty(): warnings.append(String(nickname.warning))
	var features := _features_comparison(live, restored)
	if not String(features.warning).is_empty(): warnings.append(String(features.warning))
	return {"summary": summary, "warning": "\n".join(warnings),
		"campaign": "\n\n".join(campaign) if not campaign.is_empty() else "단계별 기록 변경 없음",
		"decks": String(decks.text), "deck_slots": decks,
		"challenges": challenges, "stats": stats, "achievements": achievements, "goals": goals, "tutorial": tutorial,
		"nickname": nickname, "features": features}

static func _win_time(record: Dictionary) -> String:
	return str(record.fastest_win) + "초" if float(record.fastest_win) > 0.0 else "미기록 또는 0초"

static func _fill_comparison(parent: VBoxContainer, current: Dictionary, candidate: Dictionary, view_state: Dictionary = {}) -> void:
	for child in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
	var comparison := _comparison(current, candidate)
	parent.add_child(_label("복구하면 바뀌는 내용 · 현재 → 사본", UIKit.GOLD))
	var summary := _label(String(comparison.summary), UIKit.TEXT)
	summary.name = "ProfileComparisonSummary"
	parent.add_child(summary)
	if not String(comparison.warning).is_empty():
		var warning := _label(String(comparison.warning), UIKit.DANGER)
		warning.name = "ProfileComparisonWarning"
		parent.add_child(warning)
	_add_record_comparison(parent, "프로필 · 닉네임", "ProfileNickname", comparison.nickname)
	_add_record_comparison(parent, "새 기능 · 확인 상태·메뉴 NEW 표시", "ProfileFeature", comparison.features)
	parent.add_child(_label("현재 새 기능 안내에 있는 기능만 비교합니다. 과거 기능의 확인 ID는 사본의 저장 내용대로 복구하지만 이 개수에 포함하지 않습니다. 같은 메뉴로 연결되는 기능이 하나라도 미확인이면 그 메뉴에 NEW가 표시됩니다. 확인 상태는 기능의 잠금이나 전투 진행도와 별개입니다."))
	_add_record_comparison(parent, "전적 · 항목별 변경", "ProfileStats", comparison.stats)
	parent.add_child(_label("감소는 기기에 저장된 횟수·최고 단계·연승 기록이 줄어든다는 뜻입니다. 패배·중단 횟수의 감소도 표시하며 실력이 낮아졌다는 뜻은 아닙니다. 총 별은 아래 캠페인 비교에 표시합니다."))
	_add_record_comparison(parent, "업적 · 사라짐·추가·달성 시각", "ProfileAchievement", comparison.achievements)
	_add_record_comparison(parent, "시작 목표 · 완료 상태·다음 추천", "ProfileGoal", comparison.goals)
	parent.add_child(_label("첫 승리·일일 도전·온라인 대전 목표는 누적 전적으로, 내 덱 만들기·드래프트·리플레이 보기 목표는 저장된 완료 기록으로 판정합니다. 오늘의 도전 기록이나 업적 개수로 완료 여부를 추정하지 않습니다."))
	_add_record_comparison(parent, "튜토리얼 · 첫 전투 안내", "ProfileTutorial", comparison.tutorial)
	parent.add_child(_label("캠페인 · 변경된 단계", UIKit.GOLD))
	var campaign := _label(String(comparison.campaign), UIKit.TEXT)
	campaign.name = "ProfileCampaignChanges"
	parent.add_child(campaign)
	_add_deck_comparison(parent, comparison.deck_slots, view_state)
	_add_challenge_comparison(parent, comparison.challenges)
	parent.add_child(_label("기록을 합치거나 더 높은 기록을 고르는 복구가 아닙니다. 닉네임·새 기능 확인 상태·전적·업적·시작 목표·튜토리얼·도전 기록을 포함한 진행도 전체가 사본으로 바뀝니다. 현재 설정·익명 ID·전송 대기 기록은 유지합니다."))

static func _add_deck_comparison(parent: VBoxContainer, comparison: Dictionary, view_state: Dictionary) -> void:
	parent.add_child(_label("덱 · 슬롯을 골라 구성·버튼 순서 비교", UIKit.GOLD))
	var summary := _label("세 덱 중 변경 %d개 · 최근 선택 덱: 슬롯 %d → 슬롯 %d" % [int(comparison.changed), int(comparison.before_selected) + 1, int(comparison.after_selected) + 1], UIKit.TEXT)
	summary.name = "ProfileDeckComparisonSummary"
	parent.add_child(summary)
	parent.add_child(_label("슬롯 버튼은 비교할 덱만 고릅니다. 복구는 세 덱을 모두 사본으로 되돌립니다.\n병력·구조물 번호는 전투 버튼 순서이며 [키]는 복구 후에도 유지되는 이 기기의 현재 단축키입니다."))
	var selectors := HFlowContainer.new()
	selectors.name = "ProfileDeckComparisonSlots"
	selectors.add_theme_constant_override("h_separation", 10)
	selectors.add_theme_constant_override("v_separation", 10)
	parent.add_child(selectors)
	var buttons: Array[Button] = []
	var panels: Array[Control] = []
	var details := VBoxContainer.new()
	details.name = "ProfileDeckChanges"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(details)
	for index in comparison.slots.size():
		var slot: Dictionary = comparison.slots[index]
		var button := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 15)
		button.name = "ProfileDeckSlot%d" % (index + 1)
		button.toggle_mode = true
		button.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		button.custom_minimum_size = Vector2(210, UIKit.TOUCH_MIN_HEIGHT)
		button.tooltip_text = "슬롯 %d · %s\n이름: %s → %s\n현재 최근 선택: %s · 사본 최근 선택: %s" % [index + 1, String(slot.changes), String(slot.before_name), String(slot.after_name), "예" if index == int(comparison.before_selected) else "아니오", "예" if index == int(comparison.after_selected) else "아니오"]
		selectors.add_child(button)
		buttons.append(button)
		var panel := VBoxContainer.new()
		panel.name = "ProfileDeckSlot%dDetails" % (index + 1)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.add_theme_constant_override("separation", 8)
		details.add_child(panel)
		panels.append(panel)
		panel.add_child(_label("슬롯 %d · %s\n이름: %s → %s" % [index + 1, String(slot.changes), String(slot.before_name), String(slot.after_name)], UIKit.GOLD if bool(slot.changed) else UIKit.TEXT))
		panel.add_child(_label("현재 최근 선택: %s · 사본 최근 선택: %s" % ["이 덱" if index == int(comparison.before_selected) else "다른 덱", "이 덱" if index == int(comparison.after_selected) else "다른 덱"]))
		for group in [slot.units, slot.structures]:
			panel.add_child(_label(String(group.summary), UIKit.GOLD if bool(group.changed) else UIKit.TEXT_MUTED))
			if not String(group.details).is_empty(): panel.add_child(_label(String(group.details), UIKit.TEXT))
			for row in group.rows:
				panel.add_child(_label(String(row.text), UIKit.GOLD if bool(row.changed) else UIKit.TEXT_MUTED))
	var select_slot := func(selected: int):
		if selected < 0 or selected >= buttons.size(): return
		view_state.deck_slot = selected
		for index in buttons.size():
			var slot: Dictionary = comparison.slots[index]
			var badges: PackedStringArray = []
			if index == int(comparison.before_selected): badges.append("현재 선택")
			if index == int(comparison.after_selected): badges.append("사본 선택")
			buttons[index].set_pressed_no_signal(index == selected)
			buttons[index].text = "%s슬롯 %d · %s\n%s" % ["✓ " if index == selected else "", index + 1, "변경" if bool(slot.changed) else "동일", " / ".join(badges) if not badges.is_empty() else "최근 선택 아님"]
			panels[index].visible = index == selected
	for index in buttons.size():
		buttons[index].pressed.connect(select_slot.bind(index))
	var selected := int(view_state.get("deck_slot", -1))
	select_slot.call(selected if selected >= 0 and selected < buttons.size() else int(comparison.default_slot))

static func _add_record_comparison(parent: VBoxContainer, title: String, prefix: String, comparison: Dictionary) -> void:
	parent.add_child(_label(title, UIKit.GOLD))
	var summary := _label(String(comparison.summary), UIKit.TEXT)
	summary.name = prefix + "ComparisonSummary"
	parent.add_child(summary)
	var details := VBoxContainer.new()
	details.name = prefix + "Changes"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 10)
	parent.add_child(details)
	if comparison.rows.is_empty():
		details.add_child(_label(String(comparison.empty), UIKit.TEXT))
	else:
		for row in comparison.rows:
			details.add_child(_label(String(row.text), UIKit.DANGER if bool(row.risk) else UIKit.TEXT))

static func _add_challenge_comparison(parent: VBoxContainer, comparison: Dictionary) -> void:
	parent.add_child(_label("도전 · 날짜·버전별 변경", UIKit.GOLD))
	var summary := _label(String(comparison.summary), UIKit.TEXT)
	summary.name = "ProfileChallengeComparisonSummary"
	parent.add_child(summary)
	parent.add_child(_label("기기에 보관된 날짜·버전별 최고 기록을 비교합니다. 주간은 월요일 날짜이며 버전 미상은 동일한 규칙의 기록이라고 확정할 수 없습니다. 실패 전투의 시간 변화는 성공 기록 하락으로 세지 않습니다."))
	var rows: Array = comparison.rows
	if rows.is_empty():
		parent.add_child(_label("일일·주간 도전 기록 변경 없음", UIKit.TEXT))
		return
	var filters := HFlowContainer.new()
	filters.name = "ProfileChallengeComparisonFilters"
	filters.add_theme_constant_override("h_separation", 10)
	filters.add_theme_constant_override("v_separation", 10)
	parent.add_child(filters)
	var search := LineEdit.new()
	search.name = "ProfileChallengeComparisonSearch"
	search.placeholder_text = "도전 날짜 · 버전 검색"
	search.tooltip_text = "2026-10 또는 20261013, 버전, 일일·주간, 성공·실패로 변경된 기록을 검색합니다. 공백으로 나눈 검색어를 모두 포함한 기록을 표시합니다."
	search.max_length = 120
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(280, UIKit.TOUCH_MIN_HEIGHT)
	filters.add_child(search)
	var filter := OptionButton.new()
	filter.name = "ProfileChallengeComparisonFilter"
	filter.custom_minimum_size = Vector2(190, UIKit.TOUCH_MIN_HEIGHT)
	for title in ["전체 변경", "사라짐·낮아짐", "추가만", "변경만"]: filter.add_item(title)
	filters.add_child(filter)
	var count := _label("")
	count.name = "ProfileChallengeComparisonCount"
	parent.add_child(count)
	var details := _label("", UIKit.TEXT)
	details.name = "ProfileChallengeChanges"
	parent.add_child(details)
	var pages := HFlowContainer.new()
	pages.add_theme_constant_override("h_separation", 10)
	pages.add_theme_constant_override("v_separation", 10)
	parent.add_child(pages)
	var previous := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 15)
	previous.name = "ProfileChallengePreviousPage"
	previous.text = "이전 기록"
	previous.custom_minimum_size = Vector2(140, UIKit.TOUCH_MIN_HEIGHT)
	pages.add_child(previous)
	var next := UIKit.style_button(Button.new(), UIKit.ACCENT, false, 15)
	next.name = "ProfileChallengeNextPage"
	next.text = "다음 기록"
	next.custom_minimum_size = Vector2(140, UIKit.TOUCH_MIN_HEIGHT)
	pages.add_child(next)
	var state := {"page": 0}
	var refresh := func():
		var terms := search.text.strip_edges().to_lower().split(" ", false)
		var selected: Array = []
		for row in rows:
			if filter.selected == 1 and not bool(row.risk): continue
			if filter.selected == 2 and row.kind != "추가": continue
			if filter.selected == 3 and row.kind not in ["변경", "낮아짐"]: continue
			var matches := true
			for term in terms:
				if not String(row.search).contains(term):
					matches = false
					break
			if matches: selected.append(row)
		var total_pages := maxi(1, ceili(float(selected.size()) / CHALLENGE_PAGE_SIZE))
		state.page = clampi(int(state.page), 0, total_pages - 1)
		var lines: PackedStringArray = []
		for row in selected.slice(int(state.page) * CHALLENGE_PAGE_SIZE, (int(state.page) + 1) * CHALLENGE_PAGE_SIZE):
			lines.append(String(row.text))
		details.text = "\n\n".join(lines) if not lines.is_empty() else "조건에 맞는 변경 기록이 없습니다. 검색어를 지우거나 전체 변경을 선택하세요."
		count.text = "표시 조건 %d개 / 전체 변경 %d개 · %d / %d페이지" % [selected.size(), rows.size(), int(state.page) + 1, total_pages]
		previous.disabled = int(state.page) == 0
		next.disabled = int(state.page) >= total_pages - 1
	search.text_changed.connect(func(_value: String): state.page = 0; refresh.call())
	filter.item_selected.connect(func(_index: int): state.page = 0; refresh.call())
	previous.pressed.connect(func(): state.page = int(state.page) - 1; refresh.call())
	next.pressed.connect(func(): state.page = int(state.page) + 1; refresh.call())
	refresh.call()

static func _add_comparison(parent: Node, current: Dictionary, candidate: Dictionary, view_state: Dictionary = {}) -> void:
	var comparison := VBoxContainer.new()
	comparison.name = "ProfileRecoveryComparison"
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_theme_constant_override("separation", 10)
	parent.add_child(comparison)
	_fill_comparison(comparison, current, candidate, view_state)

static func _stamp(seconds: int) -> String:
	return Time.get_datetime_string_from_unix_time(seconds).replace("T", " ") + " UTC"

static func _button(main, parent: Node, text: String, name: String, callback: Callable, primary: bool = false) -> Button:
	var button := MultiplayerUI.button(main, parent, text, name, callback, primary)
	button.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	return button

static func _copy_text(status: Label, scroll: ScrollContainer, text: String) -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	elif text.to_utf8_buffer().size() > SaveData.MAX_BACKUP_TRANSFER_BYTES:
		status.text = "사본이 너무 커서 클립보드로 옮길 수 없습니다. 보관 폴더의 JSON 사본을 다른 위치로 복사하세요."
	else:
		DisplayServer.clipboard_set(text)
		if DisplayServer.clipboard_get().replace("\r\n", "\n") == text.replace("\r\n", "\n"):
			status.text = "진행도 JSON을 복사했습니다. 메모장 등에 붙여넣어 .json 파일로 저장하세요. 게임 삭제·전체 초기화 전에 게임 밖에 보관해야 합니다."
		else:
			status.text = "클립보드 복사를 확인하지 못했습니다. 다시 시도하거나 보관 폴더에서 사본을 복사하세요."
	scroll.ensure_control_visible.call_deferred(status)

static func _comparison_controls(parent: Node, controls: Array[Control]) -> void:
	for child in parent.get_children():
		if child is Control and child.focus_mode != Control.FOCUS_NONE:
			controls.append(child)
		_comparison_controls(child, controls)

static func _dialog_navigation(scroll: ScrollContainer, confirm: Button, cancel: Button, close: Callable) -> void:
	scroll.focus_mode = Control.FOCUS_ALL
	var controls: Array[Control] = [scroll]
	_comparison_controls(scroll, controls)
	controls.append(confirm)
	controls.append(cancel)
	for index in controls.size():
		var control := controls[index]
		var previous := control.get_path_to(controls[(index + controls.size() - 1) % controls.size()])
		var next := control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = previous
		control.focus_next = next
		# Preserve editing keys and the OptionButton's own arrow-key behavior.
		if control == scroll or (control is Button and not control is OptionButton):
			control.focus_neighbor_top = previous
			control.focus_neighbor_left = previous
			control.focus_neighbor_bottom = next
			control.focus_neighbor_right = next
		control.gui_input.connect(func(event: InputEvent):
			if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
				control.accept_event()
				close.call())
	scroll.gui_input.connect(func(event: InputEvent):
		if not event is InputEventKey or not event.pressed:
			return
		match event.keycode:
			KEY_UP: scroll.scroll_vertical -= 40
			KEY_DOWN: scroll.scroll_vertical += 40
			KEY_PAGEUP: scroll.scroll_vertical -= maxi(80, roundi(scroll.size.y * 0.85))
			KEY_PAGEDOWN: scroll.scroll_vertical += maxi(80, roundi(scroll.size.y * 0.85))
			KEY_HOME: scroll.scroll_vertical = 0
			KEY_END: scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
			_: return
		scroll.accept_event())
	scroll.grab_focus.call_deferred()

static func _filtered_entries(source: Array, query: String, order: int) -> Array:
	var entries: Array = []
	var terms := query.to_lower().replace("\t", " ").replace("\n", " ").split(" ", false)
	for entry in source:
		var searchable := (_stamp(int(entry.modified)) + " " + String(entry.path).get_file() + " " + _summary(entry.data)).to_lower()
		var matches := true
		for term in terms:
			if not searchable.contains(term):
				matches = false
				break
		if matches:
			entries.append(entry)
	entries.sort_custom(func(a: Dictionary, b: Dictionary):
		if order == 1 and int(a.modified) != int(b.modified):
			return int(a.modified) < int(b.modified)
		if order == 2 and int(a.data.stats.total_stars) != int(b.data.stats.total_stars):
			return int(a.data.stats.total_stars) > int(b.data.stats.total_stars)
		if order == 3 and int(a.data.campaign_unlocked) != int(b.data.campaign_unlocked):
			return int(a.data.campaign_unlocked) > int(b.data.campaign_unlocked)
		return int(a.modified) > int(b.modified) if int(a.modified) != int(b.modified) else String(a.path) < String(b.path))
	return entries

static func show(main, message: String = "", selected_path: String = "", browser_state: Dictionary = {}) -> void:
	# Screen-local state survives refresh/import/cleanup, without changing the save.
	var state := {"query": String(browser_state.get("query", "")), "order": clampi(int(browser_state.get("order", 0)), 0, 3), "selected_path": selected_path if not selected_path.is_empty() else String(browser_state.get("selected_path", "")), "deck_slot": clampi(int(browser_state.get("deck_slot", -1)), -1, 2)}
	var outer: VBoxContainer = main._submenu("진행도 보관·복구", "현재 진행도를 보관하거나, 읽을 수 있는 사본을 골라 복구합니다.")
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRecoveryScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 12)
	scroll.add_child(column)
	column.add_child(_label("현재 진행도", UIKit.GOLD))
	column.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	column.add_child(_label("현재 진행도 사본은 전적·덱·저장된 설정을 보관합니다. 설정 화면에서 저장하지 않은 편집은 포함되지 않습니다."))
	var backup: Button = _button(main, column, "현재 진행도 사본 보관", "CreateProfileBackup", func():
		var path := SaveData.create_backup(main.save_data)
		if not path.is_empty(): state.query = ""
		show(main, "현재 진행도 사본을 보관했습니다." if not path.is_empty() else "사본을 보관하지 못했습니다. 저장 공간과 파일 권한을 확인하고 다시 시도하세요.", path, state))
	backup.tooltip_text = ProjectSettings.globalize_path(SaveData.recovery_dir())
	column.add_child(HSeparator.new())
	var candidates := SaveData.recovery_candidates()
	var entries: Array = []
	column.add_child(_label("복구할 사본 · 검색·정렬", UIKit.GOLD))
	var filters := HBoxContainer.new()
	filters.name = "ProfileRecoveryFilters"
	filters.add_theme_constant_override("separation", 10)
	column.add_child(filters)
	var search := LineEdit.new()
	search.name = "ProfileRecoverySearch"
	search.placeholder_text = "닉네임 · 보관 날짜 · 파일명 검색"
	search.tooltip_text = "UTC 보관 날짜(예: 2026-10)·닉네임·파일명·진행도 요약을 검색합니다. 공백으로 나눈 검색어를 모두 포함한 사본을 표시합니다."
	search.max_length = 120
	search.text = String(state.query)
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(search)
	var order := OptionButton.new()
	order.name = "ProfileRecoveryOrder"
	order.custom_minimum_size = Vector2(180, UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44)
	for title in ["최근 보관순", "오래된 보관순", "별 많은 순", "캠페인 진행순"]:
		order.add_item(title)
	order.select(int(state.order))
	filters.add_child(order)
	var reset: Button = main._styled_button("초기화", UIKit.ACCENT, false)
	reset.name = "ResetProfileRecoveryFilters"
	reset.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	filters.add_child(reset)
	var count := _label("")
	count.name = "ProfileRecoveryCount"
	column.add_child(count)
	var choice := OptionButton.new()
	choice.name = "ProfileRecoveryChoice"
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.custom_minimum_size.y = UIKit.TOUCH_MIN_HEIGHT if UIKit.is_touch() else 44
	choice.fit_to_longest_item = false
	column.add_child(choice)
	var preview := _label("", UIKit.TEXT)
	preview.name = "ProfileRecoveryPreview"
	column.add_child(preview)
	var comparison := VBoxContainer.new()
	comparison.name = "ProfileRecoveryComparison"
	comparison.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	comparison.add_theme_constant_override("separation", 10)
	column.add_child(comparison)
	column.add_child(_label("복구는 전적·진행도·덱·닉네임을 사본으로 되돌립니다. 현재 진행도와 디스크 원본을 먼저 별도 보관합니다.\n현재 설정, 익명 ID, 전송 대기 기록은 유지하며 과거 결과를 다시 보내지 않습니다. 리플레이와 서버 기록은 그대로 남습니다."))
	if int(candidates.excluded) > 0:
		column.add_child(_label("손상되었거나 지원하지 않는 사본 %d개는 목록에서 제외했습니다. 원본 파일은 복구 폴더에 남아 있습니다." % int(candidates.excluded)))
	var status := _label(message, UIKit.GOLD)
	status.name = "ProfileRecoveryStatus"
	if not String(candidates.error).is_empty():
		status.text = (message + "\n" if not message.is_empty() else "") + String(candidates.error)
	column.add_child(status)
	column.add_child(HSeparator.new())
	column.add_child(_label("게임 밖에 사본 보관·다른 기기에서 가져오기", UIKit.GOLD))
	column.add_child(_label("내보내기는 진행도를 JSON으로 복사합니다. 익명 ID와 전송 대기 기록은 제외합니다.\n가져오기는 내용을 확인해 사본만 보관합니다. 현재 진행도를 바꾸려면 아래의 복구 확인을 별도로 눌러야 합니다."))
	var transfer := HFlowContainer.new()
	transfer.name = "ProfileBackupTransfer"
	transfer.add_theme_constant_override("h_separation", 10)
	transfer.add_theme_constant_override("v_separation", 10)
	column.add_child(transfer)
	_button(main, transfer, "현재 진행도 내보내기", "ExportCurrentProfile", func():
		_copy_text(status, scroll, SaveData.to_backup_text(main.save_data)))
	var export_selected := _button(main, transfer, "선택한 사본 내보내기", "ExportSelectedProfile", func():
		if choice.selected < 0 or choice.selected >= entries.size():
			return
		var entry: Dictionary = entries[choice.selected]
		var result := SaveData.backup_export(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		_copy_text(status, scroll, String(result.text)))
	_button(main, transfer, "클립보드 사본 가져오기", "ImportProfileBackup", func():
		if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
			status.text = "이 환경에서는 클립보드를 사용할 수 없습니다. JSON 사본을 보관 폴더에 복사한 뒤 새로고침하세요."
			scroll.ensure_control_visible.call_deferred(status)
			return
		_preview_import(main, DisplayServer.clipboard_get(), status, scroll, state))
	var delete_selected := _button(main, transfer, "선택한 사본 삭제 확인", "PreviewProfileBackupDelete", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm_delete(main, entries[choice.selected], state))
	delete_selected.tooltip_text = "내용과 파일명을 확인한 뒤 선택한 사본 하나만 삭제합니다. 마지막으로 읽을 수 있는 사본은 남깁니다."
	var folder := _label("보관 위치: " + ProjectSettings.globalize_path(SaveData.recovery_dir()))
	folder.add_theme_font_size_override("font_size", 13)
	column.add_child(folder)
	if not OS.has_feature("mobile") and not OS.has_feature("web"):
		_button(main, column, "보관 폴더 열기", "OpenProfileRecoveryFolder", func():
			var directory := SaveData.recovery_dir()
			if DirAccess.make_dir_recursive_absolute(directory) != OK or OS.shell_open(ProjectSettings.globalize_path(directory)) != OK:
				status.text = "보관 폴더를 열지 못했습니다. 표시된 보관 위치와 파일 권한을 확인하세요."
				scroll.ensure_control_visible.call_deferred(status))
	var footer := HBoxContainer.new()
	footer.name = "ProfileRecoveryFooter"
	footer.add_theme_constant_override("separation", 10)
	outer.add_child(footer)
	var restore: Button = _button(main, footer, "선택한 사본 복구 확인", "PreviewProfileRestore", func():
		if choice.selected >= 0 and choice.selected < entries.size():
			_confirm(main, entries[choice.selected], state), true)
	restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(main, footer, "새로고침", "RefreshProfileRecovery", func():
		show(main, "", "", state))
	_button(main, footer, "설정으로", "ProfileRecoveryBack", main._build_settings_screen)
	var update_preview := func(index: int):
		var valid := index >= 0 and index < entries.size()
		restore.disabled = not valid
		export_selected.disabled = not valid
		delete_selected.disabled = not valid or candidates.entries.size() < 2
		comparison.visible = valid
		preview.tooltip_text = ""
		if not valid:
			preview.text = "검색 조건에 맞는 사본이 없습니다. 검색어를 바꾸거나 초기화하세요." if not candidates.entries.is_empty() else "현재 진행도를 사본으로 보관하거나, 아래에서 외부 사본을 가져오세요. 손상된 원본은 수정하지 않고 보관합니다."
			if not entries.is_empty():
				preview.text = "선택했던 사본이 검색 결과에 없거나 더 이상 존재하지 않습니다. 복구·내보내기·삭제할 사본을 목록에서 직접 선택하세요."
			return
		state.selected_path = String(entries[index].path)
		preview.text = _stamp(int(entries[index].modified)) + "\n" + _summary(entries[index].data) + "\n파일: " + String(entries[index].path).get_file()
		if int(entries[index].get("excluded", 0)) > 0:
			preview.text += "\n잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entries[index].excluded)
		preview.tooltip_text = ProjectSettings.globalize_path(String(entries[index].path))
		_fill_comparison(comparison, main.save_data, entries[index].data, state)
	var rebuild := func():
		entries.clear()
		entries.append_array(_filtered_entries(candidates.entries, String(state.query), int(state.order)))
		choice.clear()
		var selected := -1
		for index in entries.size():
			var entry: Dictionary = entries[index]
			choice.add_item("%s · %s · 별 %d개 · 캠페인 %d단계" % [_stamp(int(entry.modified)), String(entry.data.nickname), int(entry.data.stats.total_stars), int(entry.data.campaign_unlocked)])
			choice.set_item_tooltip(index, ProjectSettings.globalize_path(String(entry.path)))
			if String(entry.path) == String(state.selected_path): selected = index
		if selected < 0 and String(state.selected_path).is_empty() and not entries.is_empty(): selected = 0
		choice.select(selected)
		choice.disabled = entries.is_empty()
		if selected < 0:
			choice.text = "복구할 사본을 선택하세요" if not entries.is_empty() else "검색 결과가 없습니다" if not candidates.entries.is_empty() else "복구할 수 있는 사본이 없습니다"
		count.text = "표시 %d개 / 읽을 수 있는 사본 %d개 · 마지막 사본은 삭제하지 않습니다." % [entries.size(), candidates.entries.size()]
		reset.disabled = String(state.query).is_empty() and int(state.order) == 0
		update_preview.call(selected)
	choice.item_selected.connect(update_preview)
	search.text_changed.connect(func(value: String): state.query = value; rebuild.call())
	order.item_selected.connect(func(index: int): state.order = index; rebuild.call())
	reset.pressed.connect(func():
		state.query = ""; state.order = 0
		search.set_text(""); order.select(0)
		rebuild.call(); search.grab_focus())
	rebuild.call()
	if not message.is_empty():
		scroll.ensure_control_visible.call_deferred(status)

static func _preview_import(main, text: String, screen_status: Label, screen_scroll: ScrollContainer, browser_state: Dictionary = {}) -> void:
	var preview := SaveData.preview_backup_text(text)
	if not preview.ok:
		screen_status.text = String(preview.error)
		screen_scroll.ensure_control_visible.call_deferred(screen_status)
		return
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 가져오기 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileImportConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("가져올 사본", UIKit.GOLD))
	details.add_child(_label(_summary(preview.data), UIKit.TEXT))
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	_add_comparison(details, main.save_data, preview.data, browser_state)
	details.add_child(_label("이 단계에서는 사본만 보관합니다. 보관 후 선택한 사본 복구 확인을 눌러야 진행도를 되돌립니다.\n복구할 때도 현재 설정·익명 ID·전송 대기 기록을 유지합니다. 가져온 사본의 결과는 다시 보내지 않습니다."))
	if int(preview.excluded) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 가져온 JSON 원본은 그대로 보관합니다." % int(preview.excluded), UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileImportStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "사본만 보관", "ConfirmProfileImport", func():
		# Use the text that was previewed, even if the clipboard changed meanwhile.
		var result := SaveData.import_backup_text(text)
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		browser_state.query = ""
		show(main, "가져온 사본을 보관하고 선택했습니다. 현재 진행도는 그대로입니다. 되돌리려면 선택한 사본 복구 확인을 누르세요.", String(result.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileImport", close)
	_dialog_navigation(scroll, confirm, cancel, close)

static func _confirm_delete(main, entry: Dictionary, browser_state: Dictionary) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 사본 삭제 확인", Rect2(230, 100, 820, 520))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileBackupDeleteScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	details.add_child(_label("삭제할 파일: " + ProjectSettings.globalize_path(String(entry.path))))
	details.add_child(_label("선택한 사본 파일 하나를 영구 삭제합니다. 이 파일로는 더 이상 복구할 수 없습니다. 필요하면 취소하고 먼저 내보내세요.\n현재 진행도·다른 사본·리플레이·서버 기록은 유지합니다. 마지막으로 읽을 수 있는 사본은 삭제할 수 없습니다.", UIKit.DANGER))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileBackupDeleteStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "이 사본만 영구 삭제", "ConfirmProfileBackupDelete", func():
		var result := SaveData.delete_backup(String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		# Keep the missing path so another file is never silently selected after deletion.
		show(main, "선택한 사본 하나를 삭제했습니다. 현재 진행도는 그대로입니다. 다른 사본을 사용하려면 목록에서 직접 선택하세요.", "", browser_state))
	var cancel := _button(main, dialog, "취소", "CancelProfileBackupDelete", close)
	_dialog_navigation(scroll, confirm, cancel, close)
	# Destructive confirmation starts on cancel, including keyboard users.
	cancel.grab_focus.call_deferred()

static func _confirm(main, entry: Dictionary, browser_state: Dictionary = {}) -> void:
	var previous_focus: Control = main.get_viewport().gui_get_focus_owner()
	var close := func():
		main._dismiss_action_overlay()
		if is_instance_valid(previous_focus): previous_focus.grab_focus.call_deferred()
	var dialog: VBoxContainer = main._action_panel("진행도 복구 확인", Rect2(230, 120, 820, 470))
	var scroll := ScrollContainer.new()
	scroll.name = "ProfileRestoreConfirmScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.scroll_deadzone = 16
	dialog.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("현재 진행도", UIKit.GOLD))
	details.add_child(_label(_summary(SaveData.sanitize(main.save_data)), UIKit.TEXT))
	details.add_child(_label("이 사본으로 진행도를 되돌립니다.", UIKit.GOLD))
	details.add_child(_label(_stamp(int(entry.modified)) + "\n" + _summary(entry.data), UIKit.TEXT))
	_add_comparison(details, main.save_data, entry.data, browser_state)
	if int(entry.get("excluded", 0)) > 0:
		details.add_child(_label("잘못된 도전 기록 %d개는 복구에서 제외합니다. 사본 원본은 그대로 보관합니다." % int(entry.excluded), UIKit.DANGER))
	details.add_child(_label("현재 진행도와 원본을 보관한 뒤 복구합니다. 보관이나 저장에 실패하면 현재 진행도를 유지합니다.\n현재 설정과 전송 대기 기록을 유지하며, 이미 전송한 과거 결과는 다시 보내지 않습니다."))
	var status := _label("", UIKit.DANGER)
	status.name = "ProfileRestoreStatus"
	details.add_child(status)
	var confirm := _button(main, dialog, "보관 후 복구", "ConfirmProfileRestore", func():
		var result := SaveData.restore_backup(main.save_data, String(entry.path), String(entry.fingerprint))
		if not result.ok:
			status.text = String(result.error)
			scroll.ensure_control_visible.call_deferred(status)
			return
		main.save_data = result.data
		main.profile_load_warning = ""
		main.profile_load_details = ""
		main.battle_preset = {}
		main.network.client_nickname = String(main.save_data.nickname)
		main._profile_saved()
		show(main, "진행도를 복구했습니다. 복구 전 진행도도 사본 목록에 보관했습니다.", String(entry.path), browser_state), true)
	var cancel := _button(main, dialog, "취소", "CancelProfileRestore", close)
	_dialog_navigation(scroll, confirm, cancel, close)
