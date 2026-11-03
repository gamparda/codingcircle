extends SceneTree
## Snapshots and combat events travel compressed: the round trip is exact, a big battle (over a thousand units)
## fits and passes validation, and broken or forged packets decode to nothing.

const Protocol = preload("res://scripts/NetworkProtocol.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _init() -> void:
	var model := BattleModel.new()
	var deck := ["shield", "archer", "swordsman", "healer"]
	model.configure_deck(0, deck, ["wall", "turret", "generator", "swamp"])
	model.configure_deck(1, deck, ["wall", "turret", "generator", "swamp"])
	for side in 2:
		model.cheats[side]["army_cap"] = true
		model.cheats[side]["no_cap"] = true
	# Beyond today's field limits, as a future battle without them would be.
	for side in 2:
		for i in 600:
			var kind := String(deck[i % 4])
			model._create_unit(side, kind, BattleModel.UNIT_STATS[kind], 1.0, 1.0, (300.0 + (i % 90) * 7.0) if side == 0 else (1000.0 - (i % 90) * 7.0))
	for i in 20: model.tick(1.0 / 30.0)
	var snapshot := Protocol.snapshot_for(model.snapshot(), 0)
	check(model.units.size() > 1000, "a big battle (%d units)" % model.units.size())
	var packed := Protocol.pack(snapshot)
	var back = Protocol.unpack(packed)
	check(back is Dictionary and var_to_bytes(back) == var_to_bytes(snapshot), "the round trip is exact")
	check(NetworkController.is_valid_snapshot(back), "a thousand-unit snapshot passes validation")
	check(packed.size() < var_to_bytes(snapshot).size() / 8, "compression pays (%d -> %d bytes)" % [var_to_bytes(snapshot).size(), packed.size()])
	var events := model.drain_combat_events()
	check(Protocol.unpack(Protocol.pack(events)) == events, "combat events round trip")
	check(Protocol.unpack(PackedByteArray()) == null and Protocol.unpack(PackedByteArray([1, 2, 3])) == null, "short packets decode to nothing")
	var truncated := packed.slice(0, packed.size() / 2)
	check(Protocol.unpack(truncated) == null, "a truncated packet decodes to nothing")
	var forged := packed.duplicate()
	forged.encode_u32(0, Protocol.MAX_UNPACKED_BYTES + 1)
	check(Protocol.unpack(forged) == null, "a claimed size over the limit is refused")
	var lying := packed.duplicate()
	lying.encode_u32(0, 100)
	check(Protocol.unpack(lying) == null, "a size that does not match the data is refused")
	var junk := PackedByteArray([16, 0, 0, 0])
	junk.append_array(PackedByteArray([0xde, 0xad, 0xbe, 0xef, 1, 2, 3, 4]))
	check(Protocol.unpack(junk) == null, "garbage is refused")
	print("snapshot_pack_test failures=%d" % failures)
	quit(1 if failures > 0 else 0)
