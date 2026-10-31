extends CanvasLayer

# Emitted whenever a layer is switched off or on. The dictionary holds, for every face
# of the block, how many layers are switched off, counted from that face inwards.
signal layers_changed(peeled: Dictionary)

# The camera is found automatically when this field is empty.
# Drag the four eye images into the other fields in the Inspector.
@export var camera: Camera3D
@export var green_eye: Texture2D          # this layer can be switched off
@export var grey_eye: Texture2D           # this layer cannot be switched off (passive)
@export var closed_green_eye: Texture2D   # switched off, and it can be switched on again
@export var closed_grey_eye: Texture2D    # switched off, and it cannot be switched on yet (passive)

# At most this many eyes are shown per set, so at most this many layers per face can be
# switched off. The eyes fade from full opacity to min_opacity.
@export var max_eyes: int = 9
@export var min_opacity: float = 0.1
@export var column_eye_size: Vector2 = Vector2(64, 32)
@export var diagonal_eye_size: Vector2 = Vector2(40, 20)
# Every eye further away is this much smaller (0 = all eyes the same size)
@export var size_falloff: float = 0.04
# Space between the edge of the block and the eyes, in pixels
@export var edge_margin: float = 8.0
# The depth layers lie close together on screen. This spreads them out along the same
# line, and min_diagonal_step is the smallest distance between two eyes in pixels.
@export var diagonal_spread: float = 1.5
@export var min_diagonal_step: float = 22.0
# Keep the eyes on the screen when the block is panned far away
@export var clamp_to_screen: bool = true

# The arrows that turn the view to the left side (key Q) and the right side (key E).
# Drag your own images into these fields. With only one image, the other arrow is
# the same image, mirrored. With no images at all there are no arrows.
@export var left_arrow: Texture2D
@export var right_arrow: Texture2D
@export var arrow_size: Vector2 = Vector2(64, 64)
# Distance between the arrows and the bottom edge of the screen
@export var arrow_bottom_margin: int = 24
# An arrow is a bit dimmed, and lights up while the mouse is over it
@export var arrow_dimmed_color: Color = Color(0.8, 0.8, 0.8)
# Shows the name of the side you are looking at between the arrows
@export var show_view_name: bool = true
@export var view_name_width: float = 120.0

const Face = LevelData.Face
enum LayerSet { COLUMN, DIAGONAL }
enum EyeAction { NONE, PEEL, RESTORE }

# Per quarter turn of the camera (0 = start view, 1 = left, 2 = back, 3 = right):
# the face you look at in the side views
const SIDE_FACES := [Face.FRONT, Face.LEFT, Face.BACK, Face.RIGHT]
# the face on the left of the screen
const LEFT_FACES := [Face.LEFT, Face.BACK, Face.RIGHT, Face.FRONT]
# the face at the top of the screen in the top view and in the bottom view
const TOP_VIEW_UP_FACES := [Face.BACK, Face.RIGHT, Face.FRONT, Face.LEFT]
const BOTTOM_VIEW_UP_FACES := [Face.FRONT, Face.LEFT, Face.BACK, Face.RIGHT]

var _peeled := {}                 # face -> number of switched-off layers
var _view_name := "front"
var _view_index := 0
var _near_face: int = Face.FRONT  # the face you look at: its layers are the diagonal eyes (V)
var _up_face: int = Face.TOP      # the face at the top of the screen: its layers are the column (F)
var _left_face: int = Face.LEFT   # the face on the left of the screen
var _root: Control
var _eyes: Array[Dictionary] = []
var _view_label: Label

func _ready() -> void:
	# The level view finds this HUD through the group and listens to layers_changed
	add_to_group("layer_hud")
	if camera == null:
		camera = get_viewport().get_camera_3d()
	if camera == null or not camera.has_signal("view_changed"):
		push_error("LayerHud: no camera with playfield_camera.gd found. Attach the script to the Camera3D.")
		return
	if green_eye == null or grey_eye == null:
		push_error("LayerHud: assign at least the green and the grey eye image in the Inspector.")
		return
	# A missing closed eye falls back on another eye, so the HUD still shows up
	if closed_grey_eye == null:
		push_warning("LayerHud: closed grey eye is not assigned, using the grey eye instead.")
		closed_grey_eye = grey_eye
	if closed_green_eye == null:
		push_warning("LayerHud: closed green eye is not assigned, using the closed grey eye instead.")
		closed_green_eye = closed_grey_eye
	for face in Face.values():
		_peeled[face] = 0
	# A full-screen container that lets mouse clicks through, so only the eyes catch them
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build_arrows()
	camera.connect("view_changed", _on_view_changed)
	_update_view_faces()
	_rebuild()

func _process(_delta: float) -> void:
	# The eyes follow the layers they belong to while the camera pans, zooms and turns
	if _root != null:
		_place_eyes()

func _unhandled_input(event: InputEvent) -> void:
	if _root == null:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var face := -1
	match key_event.keycode:
		KEY_F: face = _up_face    # the column of eyes
		KEY_V: face = _near_face  # the diagonal of eyes
	if face == -1:
		return
	# F / V switches the next layer off, Alt+F / Alt+V switches the last one on again
	_apply(face, EyeAction.RESTORE if key_event.alt_pressed else EyeAction.PEEL)

func _on_view_changed(view_name: String, view_index: int = 0) -> void:
	_view_name = view_name
	if _view_label != null:
		_view_label.text = view_name.capitalize()
	_view_index = view_index
	_update_view_faces()
	_rebuild()

# Works out which faces of the block are near, at the top and on the left of the screen
func _update_view_faces() -> void:
	var i := posmod(_view_index, 4)
	_left_face = LEFT_FACES[i]
	match _view_name:
		"top":
			_near_face = Face.TOP
			_up_face = TOP_VIEW_UP_FACES[i]
		"bottom":
			_near_face = Face.BOTTOM
			_up_face = BOTTOM_VIEW_UP_FACES[i]
		_:
			_near_face = SIDE_FACES[i]
			_up_face = Face.TOP

func _apply(face: int, action: int) -> void:
	var before: int = _peeled[face]
	if action == EyeAction.PEEL:
		_peeled[face] = mini(before + 1, _max_peel(face))
	elif action == EyeAction.RESTORE:
		_peeled[face] = maxi(before - 1, 0)
	if _peeled[face] != before:
		_rebuild()
		layers_changed.emit(_peeled.duplicate())

# One layer always stays, counting the layers switched off from the opposite face too
func _max_peel(face: int) -> int:
	var opposite_peeled: int = _peeled[_opposite(face)]
	return mini(_layer_count(face) - 1 - opposite_peeled, max_eyes)

# ---- The geometry of the block (the 10 x 12 x 10 test level) ----

func _size() -> Vector3:
	return Vector3(Level01.SIZE)

# The number of layers between a face and its opposite face. Above the grass is air.
func _layer_count(face: int) -> int:
	match face:
		Face.FRONT, Face.BACK:
			return Level01.SIZE.z
		Face.LEFT, Face.RIGHT:
			return Level01.SIZE.x
	return Level01.SURFACE_Y + 1

func _opposite(face: int) -> int:
	match face:
		Face.FRONT: return Face.BACK
		Face.BACK: return Face.FRONT
		Face.LEFT: return Face.RIGHT
		Face.RIGHT: return Face.LEFT
		Face.TOP: return Face.BOTTOM
	return Face.TOP

func _face_axis(face: int) -> int:
	match face:
		Face.FRONT, Face.BACK:
			return Vector3.AXIS_Z
		Face.LEFT, Face.RIGHT:
			return Vector3.AXIS_X
	return Vector3.AXIS_Y

# The coordinate of the face along its axis (world z is the negative of the level z)
func _face_plane(face: int) -> float:
	match face:
		Face.BACK: return -_size().z
		Face.RIGHT: return _size().x
		Face.TOP: return float(Level01.SURFACE_Y + 1)
	return 0.0

# The direction from the face into the block
func _face_inward(face: int) -> Vector3:
	match face:
		Face.FRONT: return Vector3(0, 0, -1)
		Face.BACK: return Vector3(0, 0, 1)
		Face.LEFT: return Vector3(1, 0, 0)
		Face.RIGHT: return Vector3(-1, 0, 0)
		Face.TOP: return Vector3(0, -1, 0)
	return Vector3(0, 1, 0)

# The corner where the near, the top and the left face of the current view meet
func _corner() -> Vector3:
	var corner := Vector3.ZERO
	for face in [_up_face, _near_face, _left_face]:
		corner[_face_axis(face)] = _face_plane(face)
	return corner

# ---- Building and placing the eyes ----

func _rebuild() -> void:
	for child in _root.get_children():
		child.queue_free()
	_eyes.clear()
	_build_set(LayerSet.COLUMN, _up_face, "F")
	_build_set(LayerSet.DIAGONAL, _near_face, "V")
	_place_eyes()	

# One eye for every layer of the face, nearest layer first
func _build_set(layer_set: int, face: int, key: String) -> void:
	var peeled: int = _peeled[face]
	var can_peel := peeled < _max_peel(face)
	var eye_count := mini(_layer_count(face) - 1, max_eyes)
	for layer in eye_count:
		var texture: Texture2D
		var action := EyeAction.NONE
		var tip := ""
		if layer < peeled:
			if layer == peeled - 1:
				texture = closed_green_eye
				action = EyeAction.RESTORE
				tip = "Switch this layer on again (Alt+%s)" % key
			else:
				texture = closed_grey_eye
				tip = "Switched off. The layer before it has to be switched on first."
		elif layer == peeled and can_peel:
			texture = green_eye
			action = EyeAction.PEEL
			tip = "Switch this layer off (%s)" % key
		else:
			texture = grey_eye
			tip = "This layer cannot be switched off yet"
		var opacity := lerpf(1.0, min_opacity, float(layer) / float(maxi(max_eyes - 1, 1)))
		_add_eye(texture, opacity, layer_set, layer, face, action, tip)

func _add_eye(texture: Texture2D, opacity: float, layer_set: int, layer: int,
		face: int, action: int, tip: String) -> void:
	var eye := TextureRect.new()
	eye.texture = texture
	eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	eye.mouse_filter = Control.MOUSE_FILTER_STOP
	eye.modulate.a = opacity
	eye.tooltip_text = tip
	eye.gui_input.connect(_on_eye_input.bind(face, action))
	_root.add_child(eye)
	_eyes.append({ "node": eye, "set": layer_set, "layer": layer })

# Puts every eye next to the layer it belongs to, as seen by the camera
func _place_eyes() -> void:
	if camera == null or _eyes.is_empty():
		return
	var corner := _corner()
	var screen_size := get_viewport().get_visible_rect().size

	# The column follows the layers along the top-left edge of the block, one by one
	var up_inward := _face_inward(_up_face)

	# The diagonal follows the receding edge. In a view from the front it is short on
	# screen, so it is spread out (and in the top view it would shrink to a point).
	var near_inward := _face_inward(_near_face)
	var first := camera.unproject_position(corner + near_inward * 0.5)
	var second := camera.unproject_position(corner + near_inward * 1.5)
	var step := (second - first) * diagonal_spread
	if step.length() < min_diagonal_step:
		var direction := step.normalized() if step.length() > 0.01 else Vector2(0.7, -0.7)
		step = direction * min_diagonal_step

	for entry in _eyes:
		var node: TextureRect = entry["node"]
		var layer: int = entry["layer"]
		var center: Vector2
		var base_size: Vector2
		if entry["set"] == LayerSet.COLUMN:
			base_size = column_eye_size
			center = camera.unproject_position(corner + up_inward * (layer + 0.5))
		else:
			base_size = diagonal_eye_size
			center = first + step * layer
		# Beside the block, not on top of it
		center.x -= base_size.x / 2.0 + edge_margin
		var eye_px := base_size * (1.0 - size_falloff * layer)
		var pos := center - eye_px / 2.0
		if clamp_to_screen:
			pos = pos.clamp(Vector2.ZERO, screen_size - eye_px)
		node.size = eye_px
		node.position = pos

func _on_eye_input(event: InputEvent, face: int, action: int) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		_apply(face, action)

# ---- The arrows that turn the view ----

# One row at the bottom of the screen: left arrow, name of the side, right arrow.
# It is added to the layer itself, not to the root container, because that one is
# emptied every time the eyes are rebuilt.
func _build_arrows() -> void:
	if left_arrow == null and right_arrow == null:
		return
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	row.add_child(_make_arrow(true))
	if show_view_name:
		_view_label = Label.new()
		_view_label.text = _view_name.capitalize()
		_view_label.custom_minimum_size = Vector2(view_name_width, arrow_size.y)
		_view_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_view_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_view_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_view_label)
	row.add_child(_make_arrow(false))
	add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, arrow_bottom_margin)

func _make_arrow(left: bool) -> TextureButton:
	var button := TextureButton.new()
	var texture := left_arrow if left else right_arrow
	# Without an image of its own, an arrow is the other image, mirrored
	button.flip_h = texture == null
	if texture == null:
		texture = right_arrow if left else left_arrow
	button.texture_normal = texture
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.custom_minimum_size = arrow_size

	button.modulate = arrow_dimmed_color
	button.mouse_entered.connect(func() -> void: button.modulate = Color.WHITE)
	button.mouse_exited.connect(func() -> void: button.modulate = arrow_dimmed_color)

	if left:
		button.tooltip_text = "Turn to the left side (Q)"
		button.pressed.connect(Callable(camera, "turn_left"))
	else:
		button.tooltip_text = "Turn to the right side (E)"
		button.pressed.connect(Callable(camera, "turn_right"))
	return button
