extends Control
## Static background and curve. The parent redraws its playhead independently.
## Reduce presentation only: original observations still drive analysis and seeking.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MAX_COLUMNS := 2048
const LINE_COLOR := Color(1, 1, 1, 0.8)

var _samples: Array = []
var _total_ticks := 1
var _panel := StyleBoxFlat.new()
var _mesh: ArrayMesh
var _segments: Array[PackedVector2Array] = []
var _cached_size := Vector2(-1.0, -1.0)
var _dirty := true

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_panel.bg_color = Color("#0a101c")
	_panel.border_color = UIKit.EDGE_SOFT
	_panel.set_border_width_all(1)
	_panel.set_corner_radius_all(8)
	_panel.anti_aliasing = true
	resized.connect(queue_redraw)

func setup(samples: Array, ticks: int) -> void:
	_samples = samples
	_total_ticks = maxi(1, ticks)
	_dirty = true
	queue_redraw()

func _point(index: int) -> Vector2:
	var sample: Dictionary = _samples[index]
	var mid := size.y * 0.5
	return Vector2(size.x * float(sample.t) / float(_total_ticks), mid - float(sample.momentum) * maxf(0.0, mid - 3.0))

## First, minimum, maximum, last in each display column, in time order.
## Keeping extrema avoids averaging away a brief lead or reversal.
func _append_bucket(line: PackedVector2Array, bucket: Array[int]) -> PackedVector2Array:
	var ordered: Array[int] = bucket.duplicate()
	ordered.sort()
	var previous := -1
	for index in ordered:
		if index != previous:
			line.append(_point(index))
			previous = index
	return line

func _display_segments() -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	var line := PackedVector2Array()
	var bucket: Array[int] = []
	var column := -1
	var columns := clampi(ceili(size.x), 1, MAX_COLUMNS)
	for index in _samples.size():
		var sample: Dictionary = _samples[index]
		# Never bridge a period with no received battle state, even within a pixel.
		if bool(sample.get("break_before", false)) and not bucket.is_empty():
			line = _append_bucket(line, bucket)
			segments.append(line)
			line = PackedVector2Array()
			bucket = []
			column = -1
		var next_column := clampi(floori(float(sample.t) / float(_total_ticks) * columns), 0, columns - 1)
		if next_column != column:
			if not bucket.is_empty(): line = _append_bucket(line, bucket)
			bucket = [index, index, index, index]
			column = next_column
		else:
			bucket[3] = index
			if float(sample.momentum) < float(_samples[bucket[1]].momentum): bucket[1] = index
			if float(sample.momentum) > float(_samples[bucket[2]].momentum): bucket[2] = index
	if not bucket.is_empty(): line = _append_bucket(line, bucket)
	if not line.is_empty(): segments.append(line)
	return segments

func _append_triangle(a: Vector2, b: Vector2, c: Vector2, color: Color, vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	vertices.append(Vector3(a.x, a.y, 0.0))
	vertices.append(Vector3(b.x, b.y, 0.0))
	vertices.append(Vector3(c.x, c.y, 0.0))
	for _vertex in 3: colors.append(color)

func _append_strip(a: Vector2, b: Vector2, mid: float, vertices: PackedVector3Array, colors: PackedColorArray) -> void:
	if b.x <= a.x: return
	var team_color: Color = UIKit.TEAM_BLUE if a.y + b.y < mid * 2.0 else UIKit.TEAM_RED
	var color := Color(team_color.r, team_color.g, team_color.b, 0.55)
	var base_a := Vector2(a.x, mid)
	var base_b := Vector2(b.x, mid)
	if a.y != mid: _append_triangle(a, base_a, b, color, vertices, colors)
	if b.y != mid: _append_triangle(b, base_a, base_b, color, vertices, colors)

func _build_mesh(segments: Array[PackedVector2Array], mid: float) -> void:
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	for line in segments:
		for index in range(1, line.size()):
			var a := line[index - 1]
			var b := line[index]
			# Split at the baseline so each team's area ends exactly at the curve.
			if (a.y < mid and b.y > mid) or (a.y > mid and b.y < mid):
				var crossing := Vector2(lerpf(a.x, b.x, (mid - a.y) / (b.y - a.y)), mid)
				_append_strip(a, crossing, mid, vertices, colors)
				_append_strip(crossing, b, mid, vertices, colors)
			else:
				_append_strip(a, b, mid, vertices, colors)
	_mesh = null
	if vertices.is_empty(): return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	_mesh = ArrayMesh.new()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

func _draw() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	if size.x <= 0.0 or size.y <= 0.0:
		_mesh = null
		_segments = []
		_dirty = true
		return
	var mid := size.y * 0.5
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.14), 1.0)
	if _dirty or size != _cached_size:
		_segments = _display_segments()
		_build_mesh(_segments, mid)
		_cached_size = size
		_dirty = false
	if _mesh != null: draw_mesh(_mesh, null)
	for line in _segments:
		if line.size() >= 2:
			draw_polyline(line, LINE_COLOR, 1.5, true)
		else:
			draw_circle(line[0], 2.0, LINE_COLOR)
