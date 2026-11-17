extends CanvasLayer

# A semi-transparent card that slides in from the right edge while an ant is selected.
# It shows the ant's name and the action that ant is carrying out. The pencil next to
# the name turns the name into an editable field.

const FONT = preload("res://assets/ui/fonts/Nunito/Nunito-VariableFont_wght.ttf")
const PENCIL_PATH := "res://assets/ui/icons/pencil.svg"
const ANT_MODEL := preload("res://assets/characters/ants/player_ant/ant_v3_compleet.gltf")
const ANT_MODEL_ANIMATION := preload("res://scripts/ant/ant_model_animation.gd")

# Emitted when the card's size or resting place changes, so a panel stacked under it
# (the future "select room" panel) can follow along.
signal stack_changed(panel_rect: Rect2, stack_top: float)

@export var panel_width: float = 200.0
# Height of the card. Leave at 0 to make it exactly as tall as its content (preview,
# name and action); set a value above 0 to force that height.
@export var panel_height: float = 0.0
# Never make the card shorter than this, even when the content is smaller
@export var min_panel_height: float = 0.0
# Distance from the top of the screen to the card
@export var top_margin: float = 4.0
# Space kept free under the card for the "select room" panel that comes later
@export var stack_gap: float = 12.0
# Height of the live ant preview above the name
@export var preview_height: float = 50.0
@export var preview_model_scale: float = 0.17
# Zooms the preview camera in. The camera fits the whole ant automatically, so this is the
# knob for making the ant look bigger in the card. Above about 1.1 the tips may touch
# the edge of the preview.
@export var preview_zoom: float = 1.0
@export var margin: float = 0.0
@export var slide_time: float = 0.25
@export var background_color: Color = Color(0.06, 0.08, 0.05, 0.78)
@export var accent_color: Color = Color(0.55, 0.78, 0.35)
@export var title_color: Color = Color(0.94, 0.96, 0.88)
@export var text_color: Color = Color(0.80, 0.85, 0.74)

var _panel: PanelContainer
var _column: VBoxContainer
var _name_label: Label
var _name_edit: LineEdit
var _pencil: Button
var _action_label: Label
var _preview_rect: TextureRect
var _preview_viewport: SubViewport
var _preview_pivot: Node3D
var _preview_player: AnimationPlayer
var _preview_radius: float = 0.5
var _preview_time: float = 0.0
var _ant: Node = null
var _open: bool = false
var _editing: bool = false
var _tween: Tween
# Height we asked for last time, so the card is not resized every frame
var _fitted_height: float = -1.0

func _ready() -> void:
	_build()
	Events.ant_selected.connect(_on_ant_selected)
	Events.ant_deselected.connect(_on_ant_deselected)

func _process(delta: float) -> void:
	# Poll, so the action text also follows a choice made in the radial menu
	if _open and is_instance_valid(_ant):
		_refresh()
		_update_preview(delta)
		_fit_height()

func _build() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_left = 12
	style.corner_radius_bottom_left = 12
	style.border_width_left = 4
	style.border_color = accent_color
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.add_theme_stylebox_override("panel", style)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.clip_contents = true
	_panel.visible = false
	add_child(_panel)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 6)
	_panel.add_child(column)
	_column = column

	# Live preview of the ant, so you can see idle / dig / carry at a glance
	_preview_rect = TextureRect.new()
	_preview_rect.custom_minimum_size = Vector2(0.0, preview_height)
	_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_preview_rect)
	_build_preview()

	# Name + pencil (the pencil swaps the label for an editable field)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_constant_override("separation", 8)
	column.add_child(header)

	_name_label = _make_label(26, title_color)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_name_label)

	_name_edit = _make_name_edit()
	_name_edit.visible = false
	header.add_child(_name_edit)

	_pencil = _make_pencil_button()
	header.add_child(_pencil)

	var line := ColorRect.new()
	line.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.35)
	line.custom_minimum_size = Vector2(0.0, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	var caption := _make_label(13, text_color)
	caption.text = "Action"
	caption.modulate.a = 0.7
	column.add_child(caption)

	_action_label = _make_label(19, title_color)
	# One line, cut off with "...". An autowrap label reports the height of the whole text
	# wrapped at one pixel as its minimum, so a short action left a big empty strip below it.
	_action_label.clip_text = true
	_action_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_action_label)

func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_name_edit() -> LineEdit:
	var edit := LineEdit.new()
	edit.add_theme_font_override("font", FONT)
	edit.add_theme_font_size_override("font_size", 22)
	edit.add_theme_color_override("font_color", title_color)
	edit.add_theme_color_override("caret_color", accent_color)
	edit.add_theme_color_override("selection_color", Color(accent_color.r, accent_color.g, accent_color.b, 0.35))
	edit.placeholder_text = "Name"
	edit.max_length = 32
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	edit.add_theme_stylebox_override("normal", _edit_style(false))
	edit.add_theme_stylebox_override("focus", _edit_style(true))
	edit.text_submitted.connect(_on_name_submitted)
	edit.focus_exited.connect(_on_name_focus_exited)
	edit.gui_input.connect(_on_name_gui_input)
	return edit

func _edit_style(highlighted: bool) -> StyleBoxFlat:
	var edit_style := StyleBoxFlat.new()
	edit_style.bg_color = Color(1.0, 1.0, 1.0, 0.08)
	edit_style.corner_radius_top_left = 6
	edit_style.corner_radius_top_right = 6
	edit_style.corner_radius_bottom_left = 6
	edit_style.corner_radius_bottom_right = 6
	edit_style.content_margin_left = 8.0
	edit_style.content_margin_right = 8.0
	edit_style.content_margin_top = 2.0
	edit_style.content_margin_bottom = 2.0
	if highlighted:
		edit_style.border_width_bottom = 2
		edit_style.border_color = accent_color
	return edit_style

func _make_pencil_button() -> Button:
	var button := Button.new()
	button.name = "RenameButton"
	button.flat = true
	button.tooltip_text = "Rename"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(24.0, 24.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.expand_icon = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# The SVG needs an import step, so fall back to plain text on a fresh project
	var pencil := load(PENCIL_PATH) as Texture2D
	if pencil != null:
		button.icon = pencil
	else:
		button.text = "Edit"
		button.add_theme_font_override("font", FONT)
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_color_override("font_color", text_color)
	button.pressed.connect(_start_rename)
	return button

# ---- Live ant preview ----

func _build_preview() -> void:
	_preview_viewport = SubViewport.new()
	_preview_viewport.name = "AntPreview"
	_preview_viewport.size = _preview_size()
	_preview_viewport.transparent_bg = true
	_preview_viewport.own_world_3d = true
	_preview_viewport.msaa_3d = Viewport.MSAA_2X
	_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_preview_viewport)
	_preview_rect.texture = _preview_viewport.get_texture()

	# Ambient light, so the block model is readable from every side
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.80, 0.70)
	env.ambient_light_energy = 1.35
	world_env.environment = env
	_preview_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	sun.light_energy = 1.1
	_preview_viewport.add_child(sun)

	# The pivot is what we wobble; the model itself keeps its own animation
	_preview_pivot = Node3D.new()
	_preview_pivot.rotation = Vector3(0.0, PI, 0.0)
	_preview_pivot.scale = Vector3.ONE * preview_model_scale
	_preview_viewport.add_child(_preview_pivot)
	_preview_pivot.add_child(ANT_MODEL.instantiate())

	# The block ant has no clips, so the same procedural animator as in the level gives
	# the preview its breathing and looking around
	var animator := ANT_MODEL_ANIMATION.new()
	animator.name = "AntModelAnimation"
	_preview_pivot.add_child(animator)

	_preview_player = _preview_pivot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _preview_player != null and not _preview_player.get_animation_list().is_empty():
		var clip: String = _preview_player.get_animation_list()[0]
		var animation := _preview_player.get_animation(clip)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
		_preview_player.play(clip)

	_frame_preview()

func _preview_size() -> Vector2i:
	var width := maxf(panel_width - 40.0, 64.0)
	return Vector2i(int(width), int(preview_height))

# Points the camera at the model and fits it in the view, whatever its size
func _frame_preview() -> void:
	var box := AABB()
	var found := false
	for node in _preview_pivot.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var node_box: AABB = mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		box = node_box if not found else box.merge(node_box)
		found = true
	if not found:
		return

	var center := box.get_center()
	_preview_radius = maxf(box.size.length() * 0.5, 0.001)
	var eye := center + Vector3(0.55, 0.32, 1.0).normalized() * _preview_radius * 4.0

	# Fit the box to the view, taking the wide panel shape and the camera angle into account
	var forward := (center - eye).normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var up := right.cross(forward)
	var half_width := 0.0
	var half_height := 0.0
	for i in 8:
		var corner := box.get_endpoint(i) - center
		half_width = maxf(half_width, absf(corner.dot(right)))
		half_height = maxf(half_height, absf(corner.dot(up)))
	var aspect := float(_preview_viewport.size.x) / maxf(float(_preview_viewport.size.y), 1.0)
	var fit := maxf(half_height, half_width / aspect) * 2.0 * 1.12

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(fit / maxf(preview_zoom, 0.1), 0.01)
	camera.near = 0.01
	camera.far = _preview_radius * 20.0
	camera.position = eye
	_preview_viewport.add_child(camera)
	camera.look_at(center, Vector3.UP)
	camera.current = true

# Every action gets its own motion: the clip speeds up and the whole ant leans into it
func _update_preview(delta: float) -> void:
	if _preview_pivot == null:
		return
	_preview_time += delta

	var action := ""
	if is_instance_valid(_ant):
		action = str(_ant.call("get_current_action")).to_lower()

	var clip_speed := 1.0
	var beat := 2.2
	var tilt := 0.0
	var bob := 0.035
	var shake := 0.0
	match action:
		"dig":
			clip_speed = 2.6
			beat = 7.0
			tilt = -0.30
			bob = 0.075
		"carry":
			clip_speed = 1.5
			beat = 3.4
			tilt = 0.14
			bob = 0.050
		"defend":
			clip_speed = 2.0
			beat = 5.0
			bob = 0.040
			shake = 0.16

	# The preview follows the idle speed set on the ant, so card and level feel the same
	var ant := _ant as Ant3D
	if ant != null and action == "":
		clip_speed *= ant.idle_speed

	if _preview_player != null:
		# If the model ever gets a real clip per action ("dig", "carry", ...), use it
		var clip := ""
		if action != "" and _preview_player.has_animation(action):
			clip = action
		elif _preview_player.has_animation("idle"):
			clip = "idle"
		if clip != "" and _preview_player.current_animation != clip:
			_preview_player.play(clip)
		_preview_player.speed_scale = clip_speed

	var wave := sin(_preview_time * beat)
	var sway := sin(_preview_time * beat * 2.2) * shake
	_preview_pivot.position = Vector3(0.0, wave * bob * _preview_radius, 0.0)
	_preview_pivot.rotation = Vector3(tilt + wave * 0.04, PI + sway * _preview_radius, sway * 0.4)

func _set_preview_active(active: bool) -> void:
	if _preview_viewport == null:
		return
	_preview_viewport.size = _preview_size()
	if active:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	else:
		_preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

# ---- Renaming ----

func _start_rename() -> void:
	if _editing or not is_instance_valid(_ant):
		return
	if not _ant.has_method("set_ant_name"):
		return
	_editing = true
	_name_edit.text = str(_ant.call("get_ant_name"))
	_name_label.visible = false
	_pencil.visible = false
	_name_edit.visible = true
	_name_edit.grab_focus()
	_name_edit.select_all()

# commit = true saves the typed name, false throws it away
func _finish_rename(commit: bool) -> void:
	if not _editing:
		return
	_editing = false
	var new_name := _name_edit.text.strip_edges()
	_name_edit.visible = false
	_name_label.visible = true
	_pencil.visible = true
	if commit and new_name != "" and is_instance_valid(_ant) and _ant.has_method("set_ant_name"):
		_ant.call("set_ant_name", new_name)
	_refresh()

func _on_name_submitted(_text: String) -> void:
	_finish_rename(true)

func _on_name_focus_exited() -> void:
	# Clicking elsewhere saves the name, like a normal text field
	_finish_rename(true)

func _on_name_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		_finish_rename(false)
		_name_edit.accept_event()

# ---- Panel content ----

func _on_ant_selected(ant: Node) -> void:
	# Only ants that can tell us who they are (the 3D ant does)
	if not (ant.has_method("get_ant_name") and ant.has_method("get_current_action")):
		return
	if _editing:
		_finish_rename(false)
	_ant = ant
	_refresh()
	_show_panel()

func _on_ant_deselected(_ant_node: Node) -> void:
	_hide_panel()

func _refresh() -> void:
	if not is_instance_valid(_ant):
		return
	if not _editing:
		_name_label.text = str(_ant.call("get_ant_name"))
	var action := str(_ant.call("get_current_action"))
	_action_label.text = action if action != "" else "Idle"

# ---- Sliding in and out ----

func _screen_width() -> float:
	return get_viewport().get_visible_rect().size.x

# X position where the card comes to rest, glued to the right edge
func _rest_x() -> float:
	return _screen_width() - panel_width - margin

# The area this card covers on screen
func get_panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size)

# First free Y position under this card, for a panel that has to sit below it
# (the "select room" panel). It already includes stack_gap.
func get_stack_top() -> float:
	return _panel.position.y + _panel.size.y + stack_gap

# How tall the card wants to be: the forced panel_height, or exactly as tall as the
# content, so no empty strip is left under the action
func _wanted_height() -> float:
	var height := panel_height
	if height <= 0.0:
		height = _content_height()
	height = maxf(height, min_panel_height)
	# A Control can never be smaller than its own minimum size, so ask for at least that
	return maxf(height, _panel.get_combined_minimum_size().y)

# Adds up the visible rows plus the style margins. This is measured per row instead of
# asking the panel, because a container's own minimum size also counts hidden rows.
func _content_height() -> float:
	var height := 0.0
	var shown := 0
	for child in _column.get_children():
		var control := child as Control
		if control == null or not control.visible:
			continue
		height += control.get_combined_minimum_size().y
		shown += 1
	height += _column.get_theme_constant("separation") * float(maxi(shown - 1, 0))
	var style := _panel.get_theme_stylebox("panel")
	if style != null:
		height += style.get_minimum_size().y
	return height

# Shrinks or grows the card while the action text changes
func _fit_height() -> void:
	if panel_height > 0.0:
		return
	var height := _wanted_height()
	# Compare against the request, not against the panel: a forced minimum would make the
	# card taller than asked and then it would be resized on every frame
	if is_equal_approx(height, _fitted_height):
		return
	_fitted_height = height
	_panel.size = Vector2(panel_width, height)
	stack_changed.emit(
		Rect2(_rest_x(), _panel.position.y, panel_width, height),
		_panel.position.y + height + stack_gap)

func _show_panel() -> void:
	var screen := get_viewport().get_visible_rect().size
	var height := _wanted_height()
	_fitted_height = height
	_panel.size = Vector2(panel_width, height)
	# Pinned to the top right, so the space under it stays free
	var y := top_margin
	if not _open:
		# Start outside the screen, or continue from where a closing panel left off
		var start_x := screen.x if not _panel.visible else _panel.position.x
		_panel.position = Vector2(start_x, y)
		_panel.visible = true
	else:
		_panel.position = Vector2(_panel.position.x, y)
	_open = true
	_slide_to(_rest_x())
	_set_preview_active(true)
	stack_changed.emit(Rect2(_rest_x(), y, panel_width, height), y + height + stack_gap)

func _hide_panel() -> void:
	if _editing:
		_finish_rename(false)
	if not _open:
		return
	_open = false
	_fitted_height = -1.0
	_set_preview_active(false)
	_slide_to(_screen_width())

func _slide_to(target_x: float) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_panel, "position:x", target_x, slide_time)
	_tween.finished.connect(_on_slide_finished)

func _on_slide_finished() -> void:
	if not _open:
		_panel.visible = false
