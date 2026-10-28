extends RefCounted
## Screens are laid out for a 1280x720 canvas. The window stretches with aspect "expand", so a wider
## (phone) or taller (tablet) screen gives a larger canvas. This keeps hand-placed controls where they
## belong on it: a control placed under a responsive parent is anchored by where it sits in the design
## canvas, per axis —
##   spans the whole axis          -> stretches with the screen,
##   equal margins on both sides   -> stretches (wide controls) or stays centered (dialogs),
##   nearer the far edge           -> keeps its distance from that edge,
##   otherwise                     -> stays where it is.
## Containers whose size moves while their content settles can carry their intended Rect2 as meta
## "design_rect".
## At exactly 1280x720 nothing moves. Controls under containers are left to their container.

const DESIGN := Vector2(1280.0, 720.0)
const META := "responsive_root"
## Margins this close count as equal (the hand layouts are not pixel-perfect).
const MARGIN_TOLERANCE := 24.0
## Centered controls at least this wide stretch instead (panels, bars); narrower ones stay centered.
const STRETCH_MIN := {0: 600.0, 1: 420.0}

## Marks `control` as a parent whose hand-placed children follow it on the stretching axes.
## `design` is its size in the 1280x720 layout.
static func mark(control: Control, design: Vector2 = DESIGN, axes: Array = [true, true]) -> void:
	control.set_meta(META, {"design": design, "axes": axes})

## Call when `node` enters the tree; it is adapted after the code that created it has placed it.
static func on_node_added(node: Node) -> void:
	if node is Control:
		var parent := node.get_parent()
		# The parent may be marked by its own (earlier queued) adaptation, so decide when this runs.
		if parent is Control and not parent is Container:
			adapt.call_deferred(node)

static func adapt(control: Control) -> void:
	if not is_instance_valid(control) or control.has_meta("responsive_done") or not control.is_inside_tree():
		return
	var parent := control.get_parent()
	if not parent is Control or not parent.has_meta(META):
		return
	control.set_meta("responsive_done", true)
	if control.anchor_left != 0.0 or control.anchor_right != 0.0 or control.anchor_top != 0.0 or control.anchor_bottom != 0.0:
		return # placed with anchors on purpose
	var parent_meta: Dictionary = parent.get_meta(META)
	var rect: Rect2 = control.get_meta("design_rect", Rect2(control.get_meta("reveal_rest", control.position), control.size))
	var stretched := [false, false]
	for axis in 2:
		# A container's height follows its content and may still be settling: leave it alone
		# unless the intended rectangle was given.
		if axis == 1 and control is Container and not control.has_meta("design_rect"):
			continue
		if parent_meta.axes[axis]:
			stretched[axis] = _adapt_axis(control, axis, float(parent_meta.design[axis]), rect.position[axis], rect.size[axis])
	if (stretched[0] or stretched[1]) and not control is Container:
		mark(control, rect.size, stretched)

## Returns true when the control now stretches along the axis (its own children may then follow it).
static func _adapt_axis(control: Control, axis: int, design: float, start: float, length: float) -> bool:
	# A control sliding in (UIKit.reveal) is measured where it will rest, and keeps sliding from there.
	var shift := control.position[axis] - start
	var before := start
	var after := design - (start + length)
	var low_side := SIDE_LEFT if axis == 0 else SIDE_TOP
	var high_side := SIDE_RIGHT if axis == 0 else SIDE_BOTTOM
	var stretched := false
	if before <= 0.5 and after <= 0.5:
		_anchor(control, low_side, high_side, 0.0, 1.0, start + shift, start + shift + length - design)
		stretched = true
	elif absf(before - after) <= MARGIN_TOLERANCE:
		if length >= float(STRETCH_MIN[axis]):
			_anchor(control, low_side, high_side, 0.0, 1.0, start + shift, start + shift + length - design)
			stretched = true
		else:
			_anchor(control, low_side, high_side, 0.5, 0.5, start + shift - design * 0.5, start + shift + length - design * 0.5)
	elif after < before:
		_anchor(control, low_side, high_side, 1.0, 1.0, start + shift - design, start + shift + length - design)
	return stretched

static func _anchor(control: Control, low_side: int, high_side: int, low: float, high: float, low_offset: float, high_offset: float) -> void:
	# Far anchor first: an anchor may not pass its opposite one.
	control.set_anchor(high_side, high)
	control.set_anchor(low_side, low)
	control.set_offset(low_side, low_offset)
	control.set_offset(high_side, high_offset)
