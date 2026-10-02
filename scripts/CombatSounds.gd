extends RefCounted

static var cache: Dictionary = {}
const RATE := 16000
const DURATIONS := {"melee":0.08,"arrow":0.11,"death":0.15,"destroy":0.20,"warning":0.28}

static func event_sound(event: Dictionary) -> String:
	match String(event.get("type","")):
		"ATTACK": return "arrow" if event.get("attack_kind","") in ["archer","turret","warlock"] else "melee"
		"DEATH": return "death"
		"STRUCTURE_DESTROYED": return "destroy"
	return ""

static func stream(kind: String) -> AudioStreamWAV:
	if cache.has(kind): return cache[kind]
	if not DURATIONS.has(kind): return null
	var samples := int(RATE*float(DURATIONS[kind]))
	var bytes := PackedByteArray(); bytes.resize(samples*2)
	var seed_value := 9173
	for index in samples:
		var t := float(index)/RATE
		var envelope := pow(1.0-float(index)/samples,2.0)*minf(1.0,float(index)/32.0)
		seed_value = (seed_value*1664525+1013904223)&0x7fffffff
		var noise := float(seed_value%65536)/32768.0-1.0
		var sample := 0.0
		match kind:
			"melee": sample = (noise*0.65+sin(TAU*110.0*t)*0.35)*envelope
			"arrow": sample = (noise*0.25+sin(TAU*(1450.0*t-2900.0*t*t))*0.45)*envelope
			"death": sample = sin(TAU*(230.0*t-450.0*t*t))*envelope*0.6
			"destroy": sample = (noise*0.5+sin(TAU*65.0*t)*0.5)*envelope
			"warning": sample = sin(TAU*620.0*t)*envelope*0.55*(1.0 if fmod(t,0.12)<0.075 else 0.0)
		bytes.encode_s16(index*2,clampi(roundi(sample*12000.0),-32768,32767))
	var output := AudioStreamWAV.new(); output.format = AudioStreamWAV.FORMAT_16_BITS; output.mix_rate = RATE; output.stereo = false; output.data = bytes
	cache[kind] = output
	return output
