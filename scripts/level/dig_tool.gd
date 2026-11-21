extends CanvasLayer

# The player's dig tool.
#
# While the tool is on, the left mouse button digs: a click takes one block away, holding
# the button and dragging selects a straight row of blocks (only horizontal or vertical)
# and digs them all on release. While the tool is off, the left button keeps its normal
# job: sliding the view around, the same directions WASD uses.
#
# The tool is switched on with the Dig button in the bottom right corner, with G, or by
# picking "Dig" from an ant's radial menu. The digging itself lives in the level view, so
# a later "ants dig for you" version can use exactly the same cell code.

const FONT = preload("res://assets/ui/fonts/Nunito/Nunito-VariableFont_wght.ttf")
const BUTTON_SIZE := Vector2(96.0, 44.0)
const MARGIN := 24.0
const ACCENT := Color(0.55, 0.78, 0.35)
const TEXT_COLOR := Color(0.94, 0.96, 0.88)
const BACKGROUND := Color(0.06, 0.08, 0.05, 0.78)

var _view: Node = null
var _camera: Camera3D = null
var _button: Button
var _active: bool = false

# The drag: the block it started on, the face it is being selected on, and the row of
# blocks under the mouse right now
var _dragging: bool = false
var _start_cell := Vector3i.ZERO
var _normal := Vector3.UP
var _plane := Plane()
var _cells: Array[Vector3i] = []

func _ready() -> void:
	layer = 2
	_build_button()
	_view = get_tree().get_first_node_in_group("level_view")
	_camera = get_viewport().get_camera_3d()
	Events.action_requested.connect(_on_action_requested)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _build_button() -> void:
	_button = Button.new()
	_button.name = "DigButton"
	_button.text = "Dig"
	_button.toggle_mode = true
	_button.focus_mode = Control.FOCUS_NONE
	_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_button.tooltip_text = "Dig (G): click a block, or hold the left button and drag a row"
	_button.add_theme_font_override("font", FONT)
	_button.add_theme_font_size_override("font_size", 16)
	_button.add_theme_color_override("font_color", TEXT_COLOR)
	_button.add_theme_color_override("font_hover_color", TEXT_COLOR)
	_button.add_theme_color_override("font_pressed_color", BACKGROUND)
	_button.add_theme_color_override("font_hover_pressed_color", BACKGROUND)
	_button.add_theme_stylebox_override("normal", _button_style(
		Color(BACKGROUND.r, BACKGROUND.g, BACKGROUND.b, 0.78), 2, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.45)))
	_button.add_theme_stylebox_override("hover", _button_style(
		Color(0.16, 0.21, 0.12, 0.9), 2, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.7)))
	_button.add_theme_stylebox_override("pressed", _button_style(
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.9), 2, ACCENT))
	_button.add_theme_stylebox_override("hover_pressed", _button_style(
		Color(ACCENT.r, ACCENT.g, ACCENT.b, 1.0), 2, TEXT_COLOR))
	_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_button.toggled.connect(_on_button_toggled)
	add_child(_button)

func _button_style(color: Color, border: int, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_left = border
	style.border_width_right = border
	style.border_width_top = border
	style.border_width_bottom = border
	style.border_color = border_color
	return style

func _layout() -> void:
	if _button == null:
		return
	var screen := get_viewport().get_visible_rect().size
	_button.size = BUTTON_SIZE
	_button.position = Vector2(
		screen.x - MARGIN - BUTTON_SIZE.x, screen.y - MARGIN - BUTTON_SIZE.y)

func _on_button_toggled(toggled_on: bool) -> void:
	set_active(toggled_on)

func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	if _button != null:
		_button.set_pressed_no_signal(active)
	if _active:
		Input.set_default_cursor_shape(Input.CURSOR_CROSS)
	else:
		_cancel()
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)

func is_active() -> bool:
	return _active

func toggle() -> void:
	set_active(not _active)

# Picking "Dig" in an ant's menu also puts the dig tool in the player's hand
func _on_action_requested(_ant: Node, action: Resource) -> void:
	if action == null:
		return
	if String(action.get("id")) == "dig":
		set_active(true)

func _typing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _input(event: InputEvent) -> void:
	# The keys work even while the tool is off, so G can always pick it up
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and not _typing():
		if key.keycode == KEY_G:
			toggle()
			get_viewport().set_input_as_handled()
			return
		if key.keycode == KEY_ESCAPE and _active:
			set_active(false)
			get_viewport().set_input_as_handled()
			return
	if not _active or _typing():
		return
	if _view == null:
		_view = get_tree().get_first_node_in_group("level_view")
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
	if _view == null or _camera == null:
		return
	# Node._input runs before the camera and the ants see the mouse, so handling it here
	# is what keeps the left button from sliding the view while the tool is on.
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			# A press on a HUD card belongs to the HUD, not to the field
			if get_viewport().gui_get_hovered_control() != null:
				return
			_begin(button.position)
		elif _dragging:
			_finish()
		get_viewport().set_input_as_handled()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		_update_selection(motion.position)
		get_viewport().set_input_as_handled()

# Starts a selection on the block and face under the mouse
func _begin(screen_position: Vector2) -> void:
	var hit: Dictionary = _view.ray_hit(_camera, screen_position)
	if hit.is_empty():
		return
	_start_cell = hit["cell"]
	_normal = hit["normal"]
	_plane = _view.face_plane(_start_cell, _normal)
	_dragging = true
	_cells = [_start_cell]
	_view.show_dig_preview(_cells)

# Turns the mouse position into a row of blocks on the same face. Only one axis changes:
# the drag picks the direction it has moved furthest in, so a selection is always a
# straight horizontal or vertical line.
func _update_selection(screen_position: Vector2) -> void:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	var point = _plane.intersects_ray(origin, direction)
	if point == null:
		return
	var target: Vector3i = _view.point_to_cell_on_face(point, _start_cell, _normal)
	_cells = _line_to(target)
	var level: LevelData = _view.get("level")
	if level != null:
		_view.show_dig_preview(_cells)

func _line_to(target: Vector3i) -> Array[Vector3i]:
	var level: LevelData = _view.get("level")
	if level == null:
		return [_start_cell]
	# The two in-plane axes of the face under the mouse
	var axes: Array[int] = [0, 1]
	if absf(_normal.x) > 0.5:
		axes = [2, 1]
	elif absf(_normal.y) > 0.5:
		axes = [0, 2]
	var delta := target - _start_cell
	var axis: int = axes[0]
	if absi(_axis_value(delta, axes[1])) > absi(_axis_value(delta, axes[0])):
		axis = axes[1]
	var end := clampi(_axis_value(target, axis), 0, _axis_value(level.size, axis) - 1)
	var start := _axis_value(_start_cell, axis)
	var step := signi(end - start)
	var cells: Array[Vector3i] = []
	for i in range(0, absi(end - start) + 1):
		var cell := _set_axis_value(_start_cell, axis, start + step * i)
		if level.can_dig(cell):
			cells.append(cell)
	return cells

func _finish() -> void:
	_dragging = false
	_view.clear_dig_preview()
	if not _cells.is_empty():
		_view.dig_cells(_cells)
	_cells.clear()

func _cancel() -> void:
	_dragging = false
	_cells.clear()
	if _view != null:
		_view.clear_dig_preview()

func _axis_value(v: Vector3i, axis: int) -> int:
	match axis:
		0: return v.x
		1: return v.y
	return v.z

func _set_axis_value(v: Vector3i, axis: int, value: int) -> Vector3i:
	match axis:
		0: return Vector3i(value, v.y, v.z)
		1: return Vector3i(v.x, value, v.z)
	return Vector3i(v.x, v.y, value)
