extends SceneTree

const UISounds = preload("res://scripts/ui/UISounds.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	for kind in ["hover", "click", "confirm", "back", "toggle", "error", "start", "victory", "defeat"]:
		var wav: AudioStreamWAV = UISounds.stream(kind)
		check(wav != null and wav.data.size() > 400, "%s sound has audio data" % kind)
		var seconds := float(wav.data.size()) / 2.0 / float(UISounds.RATE)
		check(seconds > 0.02 and seconds < 1.5, "%s sound length is sensible (%.2fs)" % [kind, seconds])
		var peak := 0
		for i in range(0, wav.data.size() - 1, 2):
			peak = maxi(peak, absi(wav.data.decode_s16(i)))
		check(peak > 800 and peak < 32000, "%s is audible but does not clip (peak %d)" % [kind, peak])
		check(UISounds.stream(kind) == wav, "%s is cached" % kind)
	UISounds.enabled = false
	UISounds.play("click")
	UISounds.enabled = true
	print("ui_sounds_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
