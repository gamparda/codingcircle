extends RefCounted
## Spell artwork (assets/spells): animation frames for each spell and the tactic card icons.
## Frames share one cell size per animation, ground line at the bottom, centered horizontally.

const LIGHTNING := [preload("res://assets/spells/lightning_0.png"), preload("res://assets/spells/lightning_1.png"), preload("res://assets/spells/lightning_2.png"), preload("res://assets/spells/lightning_3.png"), preload("res://assets/spells/lightning_4.png"), preload("res://assets/spells/lightning_5.png")]
const FIREBALL := [preload("res://assets/spells/fireball_0.png"), preload("res://assets/spells/fireball_1.png"), preload("res://assets/spells/fireball_2.png"), preload("res://assets/spells/fireball_3.png")]
const FIREBALL_BURST := [preload("res://assets/spells/fireball_burst_0.png"), preload("res://assets/spells/fireball_burst_1.png"), preload("res://assets/spells/fireball_burst_2.png"), preload("res://assets/spells/fireball_burst_3.png"), preload("res://assets/spells/fireball_burst_4.png"), preload("res://assets/spells/fireball_burst_5.png")]
const FROST := [preload("res://assets/spells/frost_0.png"), preload("res://assets/spells/frost_1.png"), preload("res://assets/spells/frost_2.png"), preload("res://assets/spells/frost_3.png"), preload("res://assets/spells/frost_4.png"), preload("res://assets/spells/frost_5.png")]
const BLESSING := [preload("res://assets/spells/blessing_0.png"), preload("res://assets/spells/blessing_1.png"), preload("res://assets/spells/blessing_2.png"), preload("res://assets/spells/blessing_3.png"), preload("res://assets/spells/blessing_4.png"), preload("res://assets/spells/blessing_5.png")]
const BLESSING_AURA := [preload("res://assets/spells/blessing_aura_0.png"), preload("res://assets/spells/blessing_aura_1.png"), preload("res://assets/spells/blessing_aura_2.png"), preload("res://assets/spells/blessing_aura_3.png")]
const SERAPH_DESCEND := [preload("res://assets/spells/seraph_descend_0.png"), preload("res://assets/spells/seraph_descend_1.png"), preload("res://assets/spells/seraph_descend_2.png"), preload("res://assets/spells/seraph_descend_3.png"), preload("res://assets/spells/seraph_descend_4.png"), preload("res://assets/spells/seraph_descend_5.png")]
const SERAPH_CAST := [preload("res://assets/spells/seraph_cast_0.png"), preload("res://assets/spells/seraph_cast_1.png"), preload("res://assets/spells/seraph_cast_2.png"), preload("res://assets/spells/seraph_cast_3.png"), preload("res://assets/spells/seraph_cast_4.png"), preload("res://assets/spells/seraph_cast_5.png"), preload("res://assets/spells/seraph_cast_6.png")]
const SERAPH_REVIVE := [preload("res://assets/spells/seraph_revive_0.png"), preload("res://assets/spells/seraph_revive_1.png"), preload("res://assets/spells/seraph_revive_2.png"), preload("res://assets/spells/seraph_revive_3.png"), preload("res://assets/spells/seraph_revive_4.png")]

const ICONS := {
	"lightning": preload("res://assets/spells/icon_lightning.png"),
	"fireball": preload("res://assets/spells/icon_fireball.png"),
	"frost": preload("res://assets/spells/icon_frost.png"),
	"blessing": preload("res://assets/spells/icon_blessing.png"),
	"seraph": preload("res://assets/spells/icon_seraph.png"),
	"swamp": preload("res://assets/spells/icon_swamp.png"),
	"wall": preload("res://assets/spells/icon_wall.png"),
	"turret": preload("res://assets/spells/icon_turret.png"),
	"generator": preload("res://assets/spells/icon_generator.png"),
}

## The card icon for a tactic card, or null when it has none (the card then shows an emblem).
static func icon(kind: String) -> Texture2D:
	return ICONS.get(kind)

## The frame of `frames` at `progress` (0..1) through the animation.
static func frame(frames: Array, progress: float) -> Texture2D:
	return frames[clampi(int(progress * frames.size()), 0, frames.size() - 1)]

## A looping frame at `fps`.
static func loop(frames: Array, time: float, fps: float = 10.0) -> Texture2D:
	return frames[int(time * fps) % frames.size()]
