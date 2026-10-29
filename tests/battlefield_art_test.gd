extends SceneTree
# Battlefield artwork: every picture loads, fortress damage states follow base health, and every
# tactic card has an icon.
const BattlefieldArt = preload("res://scripts/ui/BattlefieldArt.gd")
const SpellArt = preload("res://scripts/ui/SpellArt.gd")

var failures := 0

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	var textures: Array = [BattlefieldArt.SKY, BattlefieldArt.RUINS, BattlefieldArt.GROUND, BattlefieldArt.GENERATOR, BattlefieldArt.SWAMP]
	for group in [BattlefieldArt.BASES[0], BattlefieldArt.BASES[1], BattlefieldArt.WALL, BattlefieldArt.WALL_BROKEN, BattlefieldArt.TURRET]:
		textures.append_array(group)
	check(textures.size() == 17 and textures.all(func(texture): return texture is Texture2D and texture.get_width() > 0), "all battlefield pictures load")
	check(BattlefieldArt.base_state(320.0, 320.0) == 0 and BattlefieldArt.base_state(150.0, 320.0) == 1 and BattlefieldArt.base_state(60.0, 320.0) == 2, "the fortress picture follows its health")
	check(BattlefieldArt.base_state(0.0, 0.0) == 2, "a fortress with no health shows the ruin")
	for kind in BattleModel.STRUCTURE_STATS:
		check(SpellArt.icon(String(kind)) != null, "the %s card has an icon" % kind)
	print("battlefield_art_test failures=%d" % failures)
	quit(1 if failures else 0)
