extends RefCounted

static var cached: AudioStreamWAV

static func stream() -> AudioStreamWAV:
	if cached != null: return cached
	var pcm := PackedByteArray()
	var rate := 16000
	var count := 2560
	for index in count:
		var t := float(index) / float(rate)
		var envelope := minf(1.0, t / 0.012) * pow(1.0 - float(index) / float(count), 2.0)
		var phase := TAU * (180.0 * t - 240.0 * t * t)
		var value := int((sin(phase) * 0.7 + sin(phase * 2.0) * 0.2) * envelope * 24000.0)
		pcm.append(value & 255)
		pcm.append((value >> 8) & 255)
	cached = AudioStreamWAV.new()
	cached.format = AudioStreamWAV.FORMAT_16_BITS
	cached.mix_rate = rate
	cached.stereo = false
	cached.data = pcm
	return cached
