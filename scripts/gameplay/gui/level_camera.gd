class_name PlayfieldCamera
extends Camera3D

# Emitted after the view changes: the name is "front", "left", "back", "right", "top" or
# "bottom", and the index counts the quarter turns (0 = start view, 1 = left, 2 = back, 3 = right)
signal view_changed(view_name: String, view_index: int)

# Pan speed in world units per second, measured at a field of view of 20 degrees.
# It scales with the zoom, so the movement on screen feels the same at any zoom level.
@export var pan_speed: float = 8.0

# Zoom limits, as field of view in degrees (smaller = zoomed in)
@export var min_fov: float = 5.0
@export var max_fov: float = 40.0
# The field of view is multiplied by this for every notch of the mouse wheel
@export var wheel_zoom_step: float = 0.9
# The field of view is halved this many times per second while + or - is held
@export var key_zoom_rate: float = 0.5

# The camera turns around the level. This is roughly the middle of the 10 x 12 x 10 test level.
@export var level_center: Vector3 = Vector3(5.0, 6.0, -5.0)
# The point the camera looks at can never leave this box (the size of the level)
@export var bounds_min: Vector3 = Vector3(0.0, 0.0, -10.0)
@export var bounds_max: Vector3 = Vector3(10.0, 12.0, 0.0)
# How quickly the camera moves to another view
@export var turn_speed: float = 10.0

const SIDE_NAMES := ["front", "left", "back", "right"]
# Camera pitch when looking straight down (top view) or straight up (bottom view)
const TOP_PITCH := -PI / 2.0
const BOTTOM_PITCH := PI / 2.0

enum Mode { SIDE, TOP, BOTTOM }

var _target: Vector3       # the point the camera looks at
var _distance: float       # distance from the camera to that point
var _yaw: float
var _pitch: float
var _yaw_goal: float
var _pitch_goal: float
var _side_pitch: float     # pitch used for the four side views
var _mode: Mode = Mode.SIDE
var _view_index: int = 0   # counts the quarter turns, 0 = the view the game started with

# The view the game started with, which C returns to
var _home_target: Vector3
var _home_yaw: float
var _home_pitch: float
var _home_fov: float
var _going_home: bool = false

func _ready() -> void:
	# Work out what the camera looks at from where the scene placed it, so the
	# starting view stays exactly as you set it up in the editor
	var forward := -global_basis.z
	var along := (level_center - global_position).dot(forward)
	_target = global_position + forward * along
	_distance = global_position.distance_to(_target)
	_yaw = rotation.y
	_pitch = rotation.x
	_yaw_goal = _yaw
	_pitch_goal = _pitch
	_side_pitch = _pitch
	_home_target = _target
	_home_yaw = _yaw
	_home_pitch = _pitch
	_home_fov = fov

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(wheel_zoom_step)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0 / wheel_zoom_step)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_Q: _turn_to_side(1)           # the side on the left of the current view
			KEY_E: _turn_to_side(-1)          # the side on the right of the current view
			KEY_Z: _toggle_mode(Mode.TOP)     # look from above, press again to go back
			KEY_X: _toggle_mode(Mode.BOTTOM)  # look from below, press again to go back
			KEY_C: _go_home()                 # back to the starting view

func _process(delta: float) -> void:
	_pan(delta)
	_zoom_with_keys(delta)

	var t := 1.0 - exp(-turn_speed * delta)
	_yaw = lerpf(_yaw, _yaw_goal, t)
	_pitch = lerpf(_pitch, _pitch_goal, t)

	if _going_home:
		_target = _target.lerp(_home_target, t)
		fov = lerpf(fov, _home_fov, t)
		if _target.distance_to(_home_target) < 0.01 and absf(fov - _home_fov) < 0.01:
			_target = _home_target
			fov = _home_fov
			_going_home = false

	_update_transform()

func _update_transform() -> void:
	var look_basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	global_position = _target + look_basis.z * _distance
	rotation = Vector3(_pitch, _yaw, 0.0)

# step = 1 turns the camera to the left side, step = -1 to the right side
func _turn_to_side(step: int) -> void:
	_going_home = false
	_view_index += step
	_yaw_goal -= step * PI / 2.0
	_announce()

# Switches to the top or bottom view, or back to the side views when already there
func _toggle_mode(mode: Mode) -> void:
	_going_home = false
	if _mode == mode:
		_mode = Mode.SIDE
		_pitch_goal = _side_pitch
	else:
		_mode = mode
		_pitch_goal = TOP_PITCH if mode == Mode.TOP else BOTTOM_PITCH
	_announce()

# Returns to the view the game started with: front side, original position and zoom
func _go_home() -> void:
	_mode = Mode.SIDE
	_view_index = 0
	_pitch_goal = _home_pitch
	# Take the nearest equivalent angle, so the camera does not spin all the way back
	_yaw_goal = _home_yaw + roundf((_yaw_goal - _home_yaw) / TAU) * TAU
	_going_home = true
	_announce()

# Public, so buttons on screen can do the same as the keys Q and E
func turn_left() -> void:
	_turn_to_side(1)

func turn_right() -> void:
	_turn_to_side(-1)

func _announce() -> void:
	var view_name: String = SIDE_NAMES[posmod(_view_index, 4)]
	if _mode == Mode.TOP:
		view_name = "top"
	elif _mode == Mode.BOTTOM:
		view_name = "bottom"
	print("View: ", view_name)  # temporary debug
	view_changed.emit(view_name, posmod(_view_index, 4))

# W = up, S = down, A = left, D = right, all in the plane of the screen
func _pan(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input.y += 1.0
	if Input.is_key_pressed(KEY_S): input.y -= 1.0
	if Input.is_key_pressed(KEY_A): input.x -= 1.0
	if Input.is_key_pressed(KEY_D): input.x += 1.0
	if input == Vector2.ZERO:
		return
	_going_home = false

	# "Right" follows the camera but stays flat. In the side views "up" is world up,
	# so the distance to the level does not change; in the top and bottom views it is
	# the up direction of the screen.
	var right := Vector3(global_basis.x.x, 0.0, global_basis.x.z).normalized()
	var up := global_basis.y if absf(_pitch) > PI / 4.0 else Vector3.UP
	var move := (right * input.x + up * input.y).normalized()
	var speed := pan_speed * (fov / 20.0)

	_target += move * speed * delta
	_target = _target.clamp(bounds_min, bounds_max)

# + zooms in, - zooms out (both the main keys and the numeric keypad)
func _zoom_with_keys(delta: float) -> void:
	var direction := 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_PLUS) or Input.is_key_pressed(KEY_KP_ADD):
		direction += 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT):
		direction -= 1.0
	if direction != 0.0:
		_zoom(pow(key_zoom_rate, direction * delta))

# Zooming changes the field of view and not the camera position, so the
# flat, 2D look stays the same at every zoom level
func _zoom(factor: float) -> void:
	_going_home = false
	fov = clampf(fov * factor, min_fov, max_fov)
