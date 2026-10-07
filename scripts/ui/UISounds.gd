extends RefCounted
## Interface sound effects, synthesised at runtime (no audio files to ship or license).
## UISounds.play("click") from anywhere; a small voice pool lives under the scene-tree root.

const RATE := 22050
const VOICES := 6
const MIN_GAP_MSEC := {"hover": 70, "toggle": 40}

static var _streams: Dictionary = {}
static var _pool: Node = null
static var _last: Dictionary = {}
static var enabled := true

static func play(kind: String, volume_db: float = -10.0) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(kind, -10000)) < int(MIN_GAP_MSEC.get(kind, 20)):
		return
	var voice := _free_voice()
	if voice == null:
		return
	_last[kind] = now
	voice.stream = stream(kind)
	voice.volume_db = volume_db
	voice.play()

static func _free_voice() -> AudioStreamPlayer:
	var loop := Engine.get_main_loop()
	if not loop is SceneTree:
		return null
	var tree: SceneTree = loop
	if _pool == null or not is_instance_valid(_pool):
		_pool = Node.new()
		_pool.name = "UISoundPool"
		tree.root.add_child(_pool)
		for i in VOICES:
			var player := AudioStreamPlayer.new()
			player.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
			_pool.add_child(player)
	for player in _pool.get_children():
		if not player.playing:
			return player
	return null

static func stream(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var samples: PackedFloat32Array
	match kind:
		"hover": samples = _tone(1900.0, 2100.0, 0.035, 0.22, 0.0)
		"click": samples = _mix([_tone(820.0, 520.0, 0.07, 0.55, 0.0), _tone(2400.0, 1800.0, 0.02, 0.18, 0.0)])
		"confirm": samples = _sequence([[660.0, 0.08], [990.0, 0.14]], 0.5)
		"back": samples = _tone(560.0, 380.0, 0.12, 0.5, 0.0)
		"toggle": samples = _sequence([[880.0, 0.04], [1250.0, 0.07]], 0.4)
		"error": samples = _tone(190.0, 160.0, 0.16, 0.5, 0.55)
		"start": samples = _mix([_sweep_noise(0.45, 0.35), _sequence([[196.0, 0.15], [294.0, 0.15], [392.0, 0.3]], 0.35)])
		"victory": samples = _sequence([[523.0, 0.11], [659.0, 0.11], [784.0, 0.11], [1047.0, 0.38]], 0.5)
		"defeat": samples = _sequence([[392.0, 0.18], [330.0, 0.18], [262.0, 0.42]], 0.45)
		_: samples = _tone(600.0, 600.0, 0.05, 0.3, 0.0)
	var wav := _to_stream(samples)
	_streams[kind] = wav
	return wav

# --- synthesis helpers -------------------------------------------------------
static func _tone(from_hz: float, to_hz: float, seconds: float, volume: float, square: float) -> PackedFloat32Array:
	var count := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(count)
		phase += TAU * lerpf(from_hz, to_hz, t) / float(RATE)
		var envelope := pow(1.0 - t, 2.0) * minf(1.0, float(i) / 40.0)
		var wave := sin(phase) * (1.0 - square) + (1.0 if sin(phase) >= 0.0 else -1.0) * square
		out[i] = (wave + sin(phase * 2.0) * 0.25) * envelope * volume
	return out

static func _sequence(notes: Array, volume: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		out.append_array(_tone(float(note[0]), float(note[0]), float(note[1]), volume, 0.0))
	return out

static func _sweep_noise(seconds: float, volume: float) -> PackedFloat32Array:
	var count := int(RATE * seconds)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_value := 4242
	var smooth := 0.0
	for i in count:
		var t := float(i) / float(count)
		seed_value = (seed_value * 1664525 + 1013904223) & 0x7fffffff
		var noise := float(seed_value % 65536) / 32768.0 - 1.0
		smooth += (noise - smooth) * lerpf(0.04, 0.6, t)
		out[i] = smooth * sin(t * PI) * volume
	return out

static func _mix(parts: Array) -> PackedFloat32Array:
	var length := 0
	for part in parts:
		length = maxi(length, part.size())
	var out := PackedFloat32Array()
	out.resize(length)
	for part in parts:
		for i in part.size():
			out[i] += part[i]
	return out

static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, clampi(roundi(samples[i] * 16000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
