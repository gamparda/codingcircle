extends Node
## Works around a Godot 4.7.2 + Windows (Korean IME) bug: while typing Hangul, the engine reports the changing
## preedit text but never delivers the syllable the IME just committed when the next syllable starts, so a
## LineEdit keeps only the last syllable (every new one replaces the previous). Diagnosed with tools/ime_probe.gd:
## the log showed IME updates "한" -> "" -> "ㄱ" with no text change in between.
##
## The commit can be reconstructed: when the preedit empties and a new one starts at once, the committed text is the
## old preedit minus whatever final consonant moved into the new syllable ("텟" then "스" commits "테"). If the engine
## does deliver the commit itself (a Hangul key event arrives), nothing is inserted, so a fixed engine is not doubled.
##
## The last syllable has a second problem: clicking another field commits it, but the engine hands it to the field
## that was just clicked. It is sent back to the field it was typed in.

const SETTLE_MS := 30 # how long to wait for the engine's own commit before supplying it
const PAIR_MS := 12 # an emptied preedit followed by a new one within this time is a syllable boundary
const HANGUL_START := 0x1100
const REDIRECT_MS := 300 # a stray commit this soon after the preedit ended belongs to the field it was typed in

const INITIALS := "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
## Final consonants by index 1..27 (index 0 = none), each as [what stays as the final, the initial that moves on].
const FINAL_PARTS := [
	[], ["", "ㄱ"], ["", "ㄲ"], ["ㄱ", "ㅅ"], ["", "ㄴ"], ["ㄴ", "ㅈ"], ["ㄴ", "ㅎ"], ["", "ㄷ"], ["", "ㄹ"],
	["ㄹ", "ㄱ"], ["ㄹ", "ㅁ"], ["ㄹ", "ㅂ"], ["ㄹ", "ㅅ"], ["ㄹ", "ㅌ"], ["ㄹ", "ㅍ"], ["ㄹ", "ㅎ"], ["", "ㅁ"],
	["", "ㅂ"], ["ㅂ", "ㅅ"], ["", "ㅅ"], ["", "ㅆ"], ["", "ㅇ"], ["", "ㅈ"], ["", "ㅊ"], ["", "ㅋ"], ["", "ㅌ"],
	["", "ㅍ"], ["", "ㅎ"],
]
## Single consonants that can stand as a final, to find the final index of a "stays" component.
const FINALS := "ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ"

var previous := ""
var cleared := ""
var cleared_at := -1000
var pending: Array = []
var last_hangul_key := -1000
var engine_commits := false
var typing_owner: Node = null

static func is_syllable(character: String) -> bool:
	if character.length() != 1:
		return false
	var code := character.unicode_at(0)
	return code >= 0xAC00 and code <= 0xD7A3

## The text the IME committed when `before` was replaced by a new preedit `after`.
static func commit_for(before: String, after: String) -> String:
	if before.is_empty() or not is_syllable(before) or not is_syllable(after):
		return before # a lone jamo, or a brand-new syllable starting from a fresh consonant
	var code := before.unicode_at(0) - 0xAC00
	var initial := code / 588
	var vowel := (code % 588) / 28
	var final_index := code % 28
	if final_index == 0:
		return before
	var parts: Array = FINAL_PARTS[final_index]
	var moved: String = parts[1]
	var next_initial := INITIALS[(after.unicode_at(0) - 0xAC00) / 588]
	if moved != next_initial:
		return before # the new syllable does not start with the consonant that would have moved
	var stays: String = parts[0]
	var stays_index := 0 if stays.is_empty() else FINALS.find(stays) + 1
	return String.chr(0xAC00 + initial * 588 + vowel * 28 + stays_index)

func on_ime_text(text: String, now: int, owner: Node = null) -> void:
	if not text.is_empty() and owner != null:
		typing_owner = owner
	if text.is_empty():
		if not previous.is_empty():
			cleared = previous
			cleared_at = now
		previous = ""
		return
	if not cleared.is_empty() and now - cleared_at <= PAIR_MS and not engine_commits:
		pending.append({"text": commit_for(cleared, text), "due": now + SETTLE_MS, "since": cleared_at})
	cleared = ""
	previous = text

func on_key(unicode: int, now: int) -> void:
	if unicode >= HANGUL_START:
		last_hangul_key = now

## A Hangul character the engine delivered to `current_owner`. When it is exactly the syllable whose preedit just ended in
## another field, it is inserted there and true is returned (the caller then swallows the event).
func redirect_commit(unicode: int, now: int, current_owner: Node) -> bool:
	if unicode < HANGUL_START or cleared.is_empty() or now - cleared_at > REDIRECT_MS:
		return false
	if not is_instance_valid(typing_owner) or typing_owner == current_owner or String.chr(unicode) != cleared:
		return false
	if not ((typing_owner is LineEdit or typing_owner is TextEdit) and typing_owner.editable):
		return false
	typing_owner.insert_text_at_caret(cleared)
	cleared = ""
	return true

## Inserts the reconstructed commits that stayed undelivered after the settle time.
func flush(now: int, target: Node) -> void:
	var remaining: Array = []
	for entry in pending:
		if now < int(entry.due):
			remaining.append(entry)
		elif last_hangul_key >= int(entry.since) - SETTLE_MS:
			engine_commits = true # the engine committed it by itself: this machine does not need the workaround
		elif (target is LineEdit and target.editable) or (target is TextEdit and target.editable):
			target.insert_text_at_caret(String(entry.text))
	pending = remaining

func _notification(what: int) -> void:
	if what == NOTIFICATION_OS_IME_UPDATE:
		on_ime_text(DisplayServer.ime_get_text(), Time.get_ticks_msec(), get_viewport().gui_get_focus_owner())

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var now := Time.get_ticks_msec()
		if redirect_commit(event.unicode, now, get_viewport().gui_get_focus_owner()):
			get_viewport().set_input_as_handled()
			return
		on_key(event.unicode, now)

func _process(_delta: float) -> void:
	if not pending.is_empty():
		flush(Time.get_ticks_msec(), get_viewport().gui_get_focus_owner())
