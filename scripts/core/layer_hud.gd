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
# shown. The eyes fade from full opacity to min_opacity.
@export var max_eyes: int = 10
@export var min_opacity: float = 0.35
# The size of one eye, in pixels. Its board scales along with it.
@export var column_eye_size: Vector2 = Vector2(44, 44)
@export var diagonal_eye_size: Vector2 = Vector2(34, 34)
# Every eye further away is this much smaller (0 = all eyes the same size)
@export var size_falloff: float = 0.04
# An eye is centred on the point where its own layer touches the block. These offsets
# move the eye and its board from there, in screen pixels: +X to the right, +Y down.
# Tune them until the signs sit exactly where you want them.
@export var column_eye_offset: Vector2 = Vector2.ZERO
@export var diagonal_eye_offset: Vector2 = Vector2.ZERO
# In the top and bottom views the depth layers lie on one spot on screen. There they are
# spread out along the same line; diagonal_spread scales the step and min_diagonal_step
# is the smallest distance between two eyes in pixels. In the side views every eye sits
# exactly on its own layer instead.
@export var diagonal_spread: float = 1.5
@export var min_diagonal_step: float = 22.0
# Eyes that fall outside the screen are hidden, instead of piling up on the screen edge
@export var hide_offscreen: bool = true
# Keep the field clean: the eyes and their boards are hidden while you play. Hold Shift
# to show them for as long as you hold it, or switch them on and off with Caps Lock.
@export var hidden_by_default: bool = true
@export var show_with_shift: bool = true
@export var toggle_with_capslock: bool = true

# Every eye gets its own wooden sign behind it, so the eyes stay where they belong
# instead of being gathered on one board. The depth eyes take the sign with the post,
# the column eyes the post-less board. Drag the two images into these fields.
@export var sign_post_texture: Texture2D
@export var sign_board_texture: Texture2D
@export var sign_tint: Color = Color.WHITE
# The board behind each eye is this many times as tall as that eye
@export var column_sign_scale: float = 1.15
@export var diagonal_sign_scale: float = 1.15
# Moves every board relative to its own eye, in screen pixels: +X right, +Y down
@export var sign_offset: Vector2 = Vector2.ZERO
# The board part of the posted sign image, as fractions of its height from the top.
# The eye is centred on that board, so the post stays below it.
@export var horizontal_sign_board_top: float = 0.13
@export var horizontal_sign_board_ratio: float = 0.68

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

# Picked up automatically when the images are dropped in, unless the Inspector says otherwise
const SIGN_POST_PATH := "res://assests/ui/levels/eyes/woodensignwith pole.png"
const SIGN_BOARD_PATH := "res://assests/ui/levels/eyes/woodensign.png"

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
var _sign_root: Control
var _post_sign_texture: Texture2D
var _board_sign_texture: Texture2D
var _eyes: Array[Dictionary] = []
var _view_label: Label
# True when Caps Lock switched the eyes on; Shift only shows them while it is held
var _toggled_on: bool = false

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
	# The eye images have transparent space around them too. Cropping it makes the stone
	# fill the whole spot instead of shrinking inside its own margin.
	green_eye = _cropped(green_eye)
	grey_eye = _cropped(grey_eye)
	closed_green_eye = _cropped(closed_green_eye)
	closed_grey_eye = _cropped(closed_grey_eye)
	for face in Face.values():
		_peeled[face] = 0
	# The signs sit in their own layer under the eyes. The eyes are rebuilt on every view
	# change, the signs are not, so they keep their place.
	_sign_root = Control.new()
	_sign_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sign_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_sign_root)
	# A full-screen container that lets mouse clicks through, so only the eyes catch them
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_load_signs()
	_build_arrows()
	camera.connect("view_changed", _on_view_changed)
	_update_view_faces()
	_toggled_on = not hidden_by_default
	_rebuild()

func _process(_delta: float) -> void:
	var showing := _eyes_showing()
	if _root != null and _root.visible != showing:
		_root.visible = showing
		_sign_root.visible = showing
	# The eyes follow the layers they belong to while the camera pans, zooms and turns
	if _root != null and showing:
		_place_eyes()

# Caps Lock switches the eyes on and off; Shift shows them while it is held. While a name
# is being typed, Shift is just Shift and the field stays clean.
func _eyes_showing() -> bool:
	return _toggled_on or (
		show_with_shift and Input.is_key_pressed(KEY_SHIFT)
		and not _typing_in_a_field())

func _typing_in_a_field() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit

func _unhandled_input(event: InputEvent) -> void:
	if _root == null:
		return
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_CAPSLOCK and toggle_with_capslock:
		_toggled_on = not _toggled_on
		get_viewport().set_input_as_handled()
		return
	# F and V only work while the eyes are on screen, so a hidden layer cannot change
	if not _eyes_showing():
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
	for child in _sign_root.get_children():
		child.queue_free()
	for child in _root.get_children():
		child.queue_free()
	_eyes.clear()
	_build_set(LayerSet.COLUMN, _up_face, "F")
	_build_set(LayerSet.DIAGONAL, _near_face, "V")
	_place_eyes()
	print("LayerHud: %d eyes, view %s" % [_eyes.size(), _view_name])  # temporary debug

# One eye for every layer of the face, nearest layer first
func _build_set(layer_set: int, face: int, key: String) -> void:
	var peeled: int = _peeled[face]
	var layers := _layer_count(face)
	var can_peel := peeled < _max_peel(face)
	# One eye and one board per layer of the face, so the innermost layer gets one too
	var eye_count := mini(layers, max_eyes)
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
		elif layer == layers - 1:
			texture = grey_eye
			tip = "The deepest layer always stays"
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
	# Every eye gets its own board, in the layer under the eyes
	var sign: TextureRect = null
	if layer_set == LayerSet.COLUMN:
		sign = _make_sign(_board_sign_texture)
	else:
		sign = _make_sign(_post_sign_texture)
	_eyes.append({ "node": eye, "set": layer_set, "layer": layer, "sign": sign })

# Keeps every eye on its own layer and puts its own wooden sign right behind it
func _place_eyes() -> void:
	if camera == null or _eyes.is_empty():
		return
	var corner := _corner()
	var screen := get_viewport().get_visible_rect()
	for entry in _eyes:
		var node: TextureRect = entry["node"]
		var layer: int = entry["layer"]
		var eye := _layer_slot(entry["set"], layer, corner)
		node.position = eye.position
		node.size = eye.size
		var sign: TextureRect = entry.get("sign")
		var posted: bool = entry["set"] == LayerSet.DIAGONAL
		if sign != null:
			_place_eye_sign(sign, eye, posted,
				diagonal_sign_scale if posted else column_sign_scale)
		# Hide a layer that is off screen instead of clamping it against the edge, so
		# the layers that are out of view do not pile up in a stack
		var shown := not hide_offscreen or screen.grow(
			eye.size.x * 0.5).has_point(eye.get_center())
		node.visible = shown
		if sign != null:
			sign.visible = shown

# ---- The sign behind each eye ----

# Loads and crops the two sign images once, so every eye can get its own copy
func _load_signs() -> void:
	# Also picked up by path, so it works without touching the Inspector
	if sign_post_texture == null and ResourceLoader.exists(SIGN_POST_PATH):
		sign_post_texture = load(SIGN_POST_PATH)
	if sign_board_texture == null and ResourceLoader.exists(SIGN_BOARD_PATH):
		sign_board_texture = load(SIGN_BOARD_PATH)
	_post_sign_texture = _cropped(sign_post_texture)
	_board_sign_texture = _cropped(sign_board_texture)

func _make_sign(texture: Texture2D) -> TextureRect:
	if texture == null:
		return null
	var sign := TextureRect.new()
	sign.texture = texture
	sign.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sign.stretch_mode = TextureRect.STRETCH_SCALE
	sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sign.modulate = sign_tint
	_sign_root.add_child(sign)
	return sign

# The sign images carry a lot of transparent space around them. Cropping to the visible
# part keeps the board at its own aspect; stretching the full square image would make the
# planks drift apart and give every eye a fragment of a board.
func _cropped(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null:
		return texture
	if image.is_compressed():
		image.decompress()
	var used := image.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return texture
	if used.position == Vector2i.ZERO and used.size == image.get_size():
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = used
	return atlas

# Width divided by height of the visible part of the sign
func _sign_aspect(texture: Texture2D) -> float:
	if texture == null:
		return 1.0
	var size := texture.get_size()
	if size.y <= 0.0:
		return 1.0
	return size.x / size.y

# Puts the board behind the eye, scaled to that eye. The eye sits in the middle of the
# board; the posted sign keeps its post hanging below it.
func _place_eye_sign(sign: TextureRect, eye: Rect2, posted: bool, scale: float) -> void:
	var board_height := maxf(eye.size.y, 6.0) * clampf(scale, 0.5, 4.0)
	var aspect := _sign_aspect(sign.texture)
	var center := eye.get_center()
	var sign_width: float
	if posted:
		var board_fraction := maxf(
			horizontal_sign_board_ratio - horizontal_sign_board_top, 0.01)
		var sign_height := board_height / board_fraction
		sign_width = sign_height * aspect
		var board_center := (
			horizontal_sign_board_top + board_fraction * 0.5) * sign_height
		sign.position = Vector2(center.x - sign_width * 0.5, center.y - board_center)
		sign.size = Vector2(sign_width, sign_height)
	else:
		# The post-less board is the whole image
		sign_width = board_height * aspect
		sign.position = Vector2(
			center.x - sign_width * 0.5, center.y - board_height * 0.5)
		sign.size = Vector2(sign_width, board_height)
	sign.position += sign_offset

# Where the eye sits: centred on its own layer, moved by the offset for that set
func _layer_slot(layer_set: int, layer: int, corner: Vector3) -> Rect2:
	var size: Vector2
	var center: Vector2
	var offset: Vector2
	if layer_set == LayerSet.COLUMN:
		size = column_eye_size
		offset = column_eye_offset
		center = camera.unproject_position(corner + _face_inward(_up_face) * (layer + 0.5))
	else:
		size = diagonal_eye_size
		offset = diagonal_eye_offset
		var near_inward := _face_inward(_near_face)
		if _view_name == "top" or _view_name == "bottom":
			var first := camera.unproject_position(corner + near_inward * 0.5)
			var second := camera.unproject_position(corner + near_inward * 1.5)
			var step := (second - first) * diagonal_spread
			if step.length() < min_diagonal_step:
				var direction := step.normalized() if step.length() > 0.01 else Vector2(0.7, -0.7)
				step = direction * min_diagonal_step
			center = first + step * layer
		else:
			center = camera.unproject_position(corner + near_inward * (layer + 0.5))
	size *= 1.0 - size_falloff * layer
	center += offset
	return Rect2(center - size / 2.0, size)

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
