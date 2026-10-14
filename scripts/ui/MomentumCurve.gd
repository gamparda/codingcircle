extends Control
## Static background and curve. The parent redraws its playhead independently.
## Reduce presentation only: original observations still drive analysis and seeking.

const UIKit = preload("res://scripts/ui/UIKit.gd")
const MAX_COLUMNS := 2048
const BATCH_ITEMS := 512
const BUDGET_USEC := 4000
const LINE_COLOR := Color(1, 1, 1, 0.8)

var _samples: Array = []
var _total_ticks := 1
var _panel := StyleBoxFlat.new()
var _mesh: ArrayMesh
var _segments: Array[PackedVector2Array] = []
var _cached_size := Vector2(-1.0, -1.0)
var _dirty := true
var _paused := false
var _stage := 0 # 0: idle, 1: observations, 2: fill triangles, 3: publish
var _build_size := Vector2.ZERO
var _columns := 1
var _sample_index := 0
var _column := -1
var _bucket: Array[int] = []
var _line := PackedVector2Array()
var _pending_segments: Array[PackedVector2Array] = []
var _mesh_segment := 0
var _mesh_index := 1
var _mesh_items := 0
var _mesh_done := 0
var _vertices := PackedVector3Array()
var _colors := PackedColorArray()
var _percent := 0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_panel.bg_color = Color("#0a101c")
	_panel.border_color = UIKit.EDGE_SOFT
	_panel.set_border_width_all(1)
	_panel.set_corner_radius_all(8)
	_panel.anti_aliasing = true
	resized.connect(_invalidate)
	visibility_changed.connect(_on_visibility_changed)
	set_process(false)

func _enter_tree() -> void:
	_update_processing()

func _ready() -> void:
	_update_processing()

func _exit_tree() -> void:
	_discard_pending()
	_dirty = true
	set_process(false)

func setup(samples: Array, ticks: int) -> void:
	_samples = samples
	_total_ticks = maxi(1, ticks)
	_invalidate()

func set_preparation_paused(paused: bool) -> void:
	_paused = paused
	_update_processing()

func _update_processing() -> void:
	set_process(is_inside_tree() and is_visible_in_tree() and not _paused and (_dirty or _stage != 0))

func _discard_pending() -> void:
	_stage = 0
	_sample_index = 0
	_column = -1
	_bucket = []
	_line = PackedVector2Array()
	_pending_segments = []
	_mesh_segment = 0
	_mesh_index = 1
	_mesh_items = 0
	_mesh_done = 0
	_vertices = PackedVector3Array()
	_colors = PackedColorArray()
	_percent = 0

func _invalidate() -> void:
	_discard_pending()
	_mesh = null
	_segments = []
	_dirty = true
	queue_redraw()
	_update_processing()

func _on_visibility_changed() -> void:
	if not is_visible_in_tree() and _stage != 0:
		_discard_pending()
		_dirty = true
	_update_processing()

func _alive() -> bool:
	if not is_inside_tree(): return false
	var node: Node = self
	while node != null:
		if node.is_queued_for_deletion(): return false
		node = node.get_parent()
	return true

func _point(index: int) -> Vector2:
	var sample: Dictionary = _samples[index]
	var mid := _build_size.y * 0.5
	return Vector2(_build_size.x * float(sample.t) / float(_total_ticks), mid - float(sample.momentum) * maxf(0.0, mid - 3.0))

## First, minimum, maximum, last in each display column, in time order.
## Keeping extrema avoids averaging away a brief lead or reversal.
func _flush_bucket() -> void:
	var ordered: Array[int] = _bucket.duplicate()
	ordered.sort()
	var previous := -1
	for index in ordered:
		if index != previous:
			_line.append(_point(index))
			previous = index
	_bucket = []

func _finish_line() -> void:
	if not _line.is_empty():
		_pending_segments.append(_line)
		_mesh_items += _line.size() # Edges plus one advance to the next segment.
	_line = PackedVector2Array()

func _take_sample() -> void:
	var index := _sample_index
	var sample: Dictionary = _samples[index]
	# Never bridge a period with no received battle state, even within a pixel
	# or across the boundary between processing frames.
	if bool(sample.get("break_before", false)) and not _bucket.is_empty():
		_flush_bucket()
		_finish_line()
		_column = -1
	var next_column := clampi(floori(float(sample.t) / float(_total_ticks) * _columns), 0, _columns - 1)
	if next_column != _column:
		_flush_bucket()
		_bucket = [index, index, index, index]
		_column = next_column
	else:
		_bucket[3] = index
		if float(sample.momentum) < float(_samples[_bucket[1]].momentum): _bucket[1] = index
		if float(sample.momentum) > float(_samples[_bucket[2]].momentum): _bucket[2] = index
	_sample_index += 1

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

func _take_edge() -> void:
	var line := _pending_segments[_mesh_segment]
	# Count advancing past a single point as work too: many gaps must be bounded.
	if _mesh_index >= line.size():
		_mesh_segment += 1
		_mesh_index = 1
		return
	var mid := _build_size.y * 0.5
	var a := line[_mesh_index - 1]
	var b := line[_mesh_index]
	# Split at the baseline so each team's area ends exactly at the curve.
	if (a.y < mid and b.y > mid) or (a.y > mid and b.y < mid):
		var crossing := Vector2(lerpf(a.x, b.x, (mid - a.y) / (b.y - a.y)), mid)
		_append_strip(a, crossing, mid, _vertices, _colors)
		_append_strip(crossing, b, mid, _vertices, _colors)
	else:
		_append_strip(a, b, mid, _vertices, _colors)
	_mesh_index += 1

func _process(_delta: float) -> void:
	if not _alive():
		_discard_pending()
		_dirty = true
		set_process(false)
		return
	if not is_visible_in_tree() or _paused:
		_update_processing()
		return
	if _dirty:
		_discard_pending()
		if size.x <= 0.0 or size.y <= 0.0:
			set_process(false)
			return # A later resize wakes preparation again.
		_build_size = size
		_columns = clampi(ceili(size.x), 1, MAX_COLUMNS)
		_stage = 1
		_dirty = false
		queue_redraw()
	if size != _build_size:
		_invalidate()
		return
	var deadline := Time.get_ticks_usec() + BUDGET_USEC
	var items := 0
	if _stage == 1:
		while _sample_index < _samples.size() and items < BATCH_ITEMS:
			_take_sample()
			items += 1
			if Time.get_ticks_usec() >= deadline: break
		var percent := mini(89, int(90.0 * float(_sample_index) / float(maxi(1, _samples.size()))))
		if percent != _percent:
			_percent = percent
			queue_redraw()
		if _sample_index == _samples.size():
			_flush_bucket()
			_finish_line()
			_stage = 2
		return # Start triangle preparation on a separate frame.
	if _stage == 2:
		while _mesh_segment < _pending_segments.size() and items < BATCH_ITEMS:
			_take_edge()
			_mesh_done += 1
			items += 1
			if Time.get_ticks_usec() >= deadline: break
		var percent := mini(99, 90 + int(9.0 * float(_mesh_done) / float(maxi(1, _mesh_items))))
		if _percent != percent:
			_percent = percent
			queue_redraw()
		if _mesh_segment == _pending_segments.size(): _stage = 3
		return # Upload only after all CPU work has yielded.
	if _stage == 3:
		_publish()

func _publish() -> void:
	# The engine upload itself is indivisible and can exceed the CPU budget.
	var mesh: ArrayMesh
	if not _vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_COLOR] = _colors
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_mesh = mesh
	_segments = _pending_segments
	_cached_size = _build_size
	_discard_pending()
	set_process(false)
	queue_redraw()

func _draw() -> void:
	draw_style_box(_panel, Rect2(Vector2.ZERO, size))
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var mid := size.y * 0.5
	draw_line(Vector2(0, mid), Vector2(size.x, mid), Color(1, 1, 1, 0.14), 1.0)
	# Drawing never scans observations or constructs geometry. Until a complete
	# cache is ready the parent still draws interactive markers and the playhead.
	if _dirty or _stage != 0 or size != _cached_size:
		if not _samples.is_empty():
			draw_string(get_theme_default_font(), Vector2(8, 18), "전세 곡선 준비 중 · %d%%" % _percent, HORIZONTAL_ALIGNMENT_LEFT, maxf(0.0, size.x - 16.0), 13, UIKit.TEXT_MUTED)
		return
	if _mesh != null: draw_mesh(_mesh, null)
	for line in _segments:
		if line.size() >= 2:
			draw_polyline(line, LINE_COLOR, 1.5, true)
		else:
			draw_circle(line[0], 2.0, LINE_COLOR)
