extends SceneTree
## Driven by tests/resumable_download_test.py: downloads --url into --out with ResumableDownload, optionally
## stopping after --stop-after bytes (to simulate the app closing), and prints the outcome.
const ResumableDownload = preload("res://scripts/ResumableDownload.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var options := {"url": "", "out": "", "key": "test", "stop-after": "0", "timeout": "60"}
	for arg in OS.get_cmdline_user_args():
		var pair := arg.trim_prefix("--").split("=", true, 1)
		if pair.size() == 2: options[pair[0]] = pair[1]
	var download := ResumableDownload.new()
	root.add_child(download)
	var outcome := {"done": false, "ok": false, "retries": 0}
	download.retrying.connect(func(_attempt, _max): outcome.retries = int(outcome.retries) + 1)
	download.finished.connect(func(ok): outcome.done = true; outcome.ok = ok)
	var resumed_from := 0
	download.start(String(options.url), String(options.out), String(options.key))
	resumed_from = download.offset
	var deadline := Time.get_ticks_msec() + int(float(options.timeout) * 1000.0)
	var stop_after := int(options["stop-after"])
	while not outcome.done and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
		if stop_after > 0 and download.offset >= stop_after:
			download.cancel()
			print("RESULT stopped offset=%d" % download.offset)
			quit(0)
			return
	print("RESULT ok=%s resumed_from=%d offset=%d total=%d retries=%d" % [outcome.ok, resumed_from, download.offset, download.total, int(outcome.retries)])
	quit(0 if outcome.ok else 1)
