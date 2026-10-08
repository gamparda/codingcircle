extends SceneTree
## Korean typing workaround: reconstructing the syllable the IME committed when the engine does not deliver it.

const ImeFix = preload("res://scripts/ImeFix.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# What the IME committed, from the old preedit and the one that replaced it.
	for case in [["한", "ㄱ", "한"], ["력", "ㅌ", "력"], ["텟", "스", "테"], ["닭", "가", "달"], ["값", "사", "갑"], ["있", "써", "이"], ["앉", "자", "안"], ["읽", "기", "일"], ["가", "ㅏ", "가"], ["ㅎ", "ㅏ", "ㅎ"], ["한", "나", "하"], ["한", "가", "한"], ["핫", "사", "하"], ["", "ㄱ", ""]]:
		check(ImeFix.commit_for(case[0], case[1]) == case[2], "'%s' then '%s' commits '%s' (got '%s')" % [case[0], case[1], case[2], ImeFix.commit_for(case[0], case[1])])

	# The real log from tools/ime_probe.gd: syllables are never delivered by the engine, only the last one at focus loss.
	var sequence := [["ㅎ", 0], ["하", 100], ["한", 200], ["", 300], ["ㄱ", 301], ["그", 400], ["글", 500], ["", 600], ["ㅇ", 601], ["이", 700], ["입", 800],
		["", 900], ["ㄹ", 901], ["려", 1000], ["력", 1100], ["", 1200], ["ㅌ", 1201], ["테", 1300], ["텟", 1400], ["", 1500], ["스", 1501], ["슽", 1600], ["", 1700], ["트", 1701]]
	var fix := ImeFix.new()
	var field := LineEdit.new()
	for step in sequence:
		fix.on_ime_text(String(step[0]), int(step[1]))
		fix.flush(int(step[1]) + 40, field)
	check(field.text == "한글입력테스", "committed syllables are supplied while typing (got '%s')" % field.text)
	fix.on_ime_text("", 1800)
	field.insert_text_at_caret("트") # the engine does commit the last syllable when typing stops
	check(field.text == "한글입력테스트" and not fix.engine_commits, "the whole word ends up in the field")

	# Slow typing: a deleted preedit followed much later by a new one is not a syllable boundary.
	var slow := ImeFix.new()
	var slow_field := LineEdit.new()
	slow.on_ime_text("ㅎ", 0)
	slow.on_ime_text("", 100)
	slow.on_ime_text("ㄱ", 600)
	slow.flush(700, slow_field)
	check(slow_field.text == "", "deleting a lone jamo does not commit it")

	# An engine that delivers the commit itself must not get it twice.
	var healthy := ImeFix.new()
	var healthy_field := LineEdit.new()
	healthy.on_ime_text("한", 0)
	healthy.on_ime_text("", 100)
	healthy.on_key(0xD55C, 100)
	healthy_field.insert_text_at_caret("한")
	healthy.on_ime_text("ㄱ", 101)
	healthy.flush(200, healthy_field)
	check(healthy_field.text == "한" and healthy.engine_commits, "no duplicate when the engine delivered the syllable")
	healthy.on_ime_text("그", 300)
	healthy.on_ime_text("", 400)
	healthy.on_ime_text("ㅇ", 401)
	healthy.flush(500, healthy_field)
	check(healthy_field.text == "한", "once the engine is seen delivering, the workaround stays off")

	# Clicking another field commits the last syllable, which the engine hands to the newly clicked field.
	var first := LineEdit.new()
	var second := LineEdit.new()
	var jump := ImeFix.new()
	first.text = "한글입력테스"
	first.caret_column = first.text.length()
	jump.on_ime_text("트", 100, first)
	jump.on_ime_text("", 200)
	check(jump.redirect_commit(0xD2B8, 204, second) and first.text == "한글입력테스트" and second.text == "", "the stray last syllable goes back to the field it was typed in")
	check(not jump.redirect_commit(0xD2B8, 205, second), "and only once")
	jump.on_ime_text("글", 300, first)
	jump.on_ime_text("", 400)
	check(not jump.redirect_commit(0xD2B8, 404, second), "a different character is left alone")
	check(not jump.redirect_commit(0xAE00, 404, first), "so is a commit that already reached its own field")
	check(not jump.redirect_commit(0xAE00, 400 + ImeFix.REDIRECT_MS + 50, second), "and one that arrives long after the preedit ended")
	var gone := LineEdit.new()
	jump.on_ime_text("가", 1000, gone)
	jump.on_ime_text("", 1100)
	gone.free()
	check(not jump.redirect_commit(0xAC00, 1104, second), "a field that no longer exists is skipped")
	var locked_owner := LineEdit.new()
	locked_owner.editable = false
	jump.on_ime_text("나", 2000, locked_owner)
	jump.on_ime_text("", 2100)
	check(not jump.redirect_commit(0xB098, 2104, second), "read-only fields do not receive it")
	check(not jump.redirect_commit(0x41, 2104, second), "ASCII is never redirected")

	# Read-only fields and non-text focus are left alone.
	var locked := LineEdit.new()
	locked.editable = false
	var other := ImeFix.new()
	other.on_ime_text("한", 0)
	other.on_ime_text("", 100)
	other.on_ime_text("ㄱ", 101)
	other.flush(200, locked)
	check(locked.text == "", "read-only fields stay untouched")
	var button := Button.new()
	other.on_ime_text("글", 300)
	other.on_ime_text("", 400)
	other.on_ime_text("ㅇ", 401)
	other.flush(500, button)
	check(other.pending.is_empty(), "other controls just drop the pending commit")
	print("ime_fix_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
