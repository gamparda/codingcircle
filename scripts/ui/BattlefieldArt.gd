extends RefCounted
## Battlefield artwork (assets/battlefield): the backdrop layers, both fortresses in three states of damage
## and the built structures. Blue art is the player's side; red variants are recoloured copies.

const SKY := preload("res://assets/battlefield/sky.jpg")
## Where the sky art's far scenery meets its empty dark band, as a fraction of its height.
const SKY_HORIZON := 0.68
const RUINS := preload("res://assets/battlefield/ruins.png")
const GROUND := preload("res://assets/battlefield/ground.png")
## Where units walk on the ground strip, as a fraction of its height: the upper part of the dirt road.
const GROUND_LANE := 0.40
## Intact, burning, ruined.
const BASES := [
	[preload("res://assets/battlefield/base_blue_0.png"), preload("res://assets/battlefield/base_blue_1.png"), preload("res://assets/battlefield/base_blue_2.png")],
	[preload("res://assets/battlefield/base_red_0.png"), preload("res://assets/battlefield/base_red_1.png"), preload("res://assets/battlefield/base_red_2.png")],
]
const WALL := [preload("res://assets/battlefield/wall.png"), preload("res://assets/battlefield/wall_red.png")]
const WALL_BROKEN := [preload("res://assets/battlefield/wall_broken.png"), preload("res://assets/battlefield/wall_broken_red.png")]
const TURRET := [preload("res://assets/battlefield/turret.png"), preload("res://assets/battlefield/turret_red.png")]
const GENERATOR := preload("res://assets/battlefield/generator.png")
const SWAMP := preload("res://assets/battlefield/swamp.png")

## Which fortress picture fits the remaining health.
static func base_state(hp: float, max_hp: float) -> int:
	var ratio := hp / maxf(1.0, max_hp)
	return 0 if ratio > 0.6 else (1 if ratio > 0.25 else 2)
