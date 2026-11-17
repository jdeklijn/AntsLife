class_name LevelSidebar
extends CanvasLayer

# The permanent column on the left of the playfield. Three semi-transparent cards, in the
# same style as the ant card on the right but mirrored: the accent border and the rounded
# corners sit on the side that faces the level.
#
#   top     day / night pictures, a granite road with the ant walking on it, the day
#           counter, the pause button and the speed buttons
#   middle  the resources and how many of each there are (about 60% of the height)
#   bottom  save, main menu and quit (about 12% of the height)
#
# The ant on the road is the real 3D ant (the same model as in the level), walking on a
# granite slab in a little 3D scene. During the day it walks from the dawn picture to the
# dusk picture, during the night it walks back; at both ends it turns around, so you can
# see it is a 3D model. The pause and speed buttons drive Engine.time_scale, so they
# change the real speed of the game: speed 1 is one full cycle in 24 minutes.

# The day turned into night or back again. Hook gameplay up to this (ants that sleep,
# for example); the sky follows the smooth value of cycle_changed.
signal phase_changed(is_day: bool)
# How dark it is and where the sun is: night_amount 0 = full day, 1 = full night;
# sun_angle 0 = sunrise, PI/2 = noon, PI = sunset, 3PI/2 = midnight
signal cycle_changed(night_amount: float, sun_angle: float)
# A new day started, counted from starting_day
signal day_changed(day: int)
# The save button was pressed. The real save system is not there yet.
signal save_requested

const FONT = preload("res://assets/ui/fonts/Nunito/Nunito-VariableFont_wght.ttf")
const ANT_MODEL := preload("res://assets/characters/ants/player_ant/ant_v3_compleet.gltf")
const GRANITE := preload("res://assets/world/textures/granite.png")

# The little 3D scene in the day card: a granite footpath with the ant on top.
# The slab is longer than the card, so the road runs off both sides.
const ROAD_SIZE := Vector3(8.0, 0.34, 1.2)
# The same ant model as in the level, scaled so it fits on the road
const ANT_SCALE := 0.5
# How much of the little world is shown from top to bottom, in world units
const ROAD_VIEW_HEIGHT := 1.28
# The camera looks down on the road, so the top surface and the ant on it are visible
const ROAD_CAMERA_ELEVATION := 20.0

# The resources, in the order they are shown. Add or remove entries and the rows follow.
const RESOURCE_LIST: Array[Dictionary] = [
	{"id": "dirt", "name": "Dirt", "icon": "res://assets/ui/levels/resources/rsc_dirt_icoon.png"},
	{"id": "rock", "name": "Rock", "icon": "res://assets/ui/levels/resources/rsc_rock_icoon.png"},
	{"id": "wood", "name": "Wood", "icon": "res://assets/ui/levels/resources/rsc_wood_icoon.png"},
	{"id": "leaves", "name": "Leaves", "icon": "res://assets/ui/levels/resources/rsc_leaves_icoon.png"},
	{"id": "food", "name": "Food", "icon": "res://assets/ui/levels/resources/rsc_food_ico.png"},
	{"id": "water", "name": "Water", "icon": "res://assets/ui/levels/resources/rsc_water_icoon.png"},
	{"id": "iron", "name": "Iron", "icon": "res://assets/ui/levels/resources/rsc_iron_icoon.png"},
	{"id": "copper", "name": "Copper", "icon": "res://assets/ui/levels/resources/rsc_copper_icoon.png"},
	{"id": "gold", "name": "Gold", "icon": "res://assets/ui/levels/resources/rsc_gold_icoon.png"},
	{"id": "diamond", "name": "Diamond", "icon": "res://assets/ui/levels/resources/rsc_diamond_icoon.png"},
]

@export_group("Placement")
# The same width as the ant card, so the two sides look like a pair
@export var panel_width: float = 200.0
@export var margin: float = 0.0
@export var top_margin: float = 4.0
@export var bottom_margin: float = 4.0
# Space between the three cards
@export var gap: float = 12.0
# The middle card takes this part of the screen height
@export_range(0.1, 0.9) var resources_fraction: float = 0.60
# The bottom card takes this part of the screen height
@export_range(0.05, 0.3) var controls_fraction: float = 0.12

@export_group("Day and night")
@export var day_icon: Texture2D = preload("res://assets/ui/icons/day_icoon.png")
@export var night_icon: Texture2D = preload("res://assets/ui/icons/night_icoon.png")
# Size of the dawn and dusk pictures at the top of the card
@export var phase_icon_size: float = 34.0
# Height of the granite footpath the ant walks on
@export var path_height: float = 62.0
# How quickly the ant turns around at the ends of the road
@export var ant_turn_speed: float = 7.0
# Seconds for one full day and one full night together at speed 1 (24 minutes)
@export var day_length: float = 1440.0
# Part of the cycle that is day (0.5 = half day, half night)
@export_range(0.1, 0.9) var day_share: float = 0.5
# How far the sun must be above or below the horizon before it is fully day or night.
# 0.25 is about 14 degrees of sun height, which gives a real twilight.
@export_range(0.02, 0.8) var twilight_height: float = 0.25
@export var start_at_day: bool = true
# The first day of the level, shown in the card and counted up at every new morning
@export var starting_day: int = 1
# Where "Main menu" and "Quit" go: the screen with the sandbox entrance
@export_file("*.tscn") var start_scene: String = "res://scenes/main/main_scene.tscn"

@export_group("Colours")
@export var background_color: Color = Color(0.06, 0.08, 0.05, 0.78)
@export var accent_color: Color = Color(0.55, 0.78, 0.35)
@export var title_color: Color = Color(0.94, 0.96, 0.88)
@export var text_color: Color = Color(0.80, 0.85, 0.74)

var _day_panel: PanelContainer
var _resources_panel: PanelContainer
var _controls_panel: PanelContainer
var _day_icon_rect: TextureRect
var _night_icon_rect: TextureRect
var _day_label: Label
var _ant_road: Control
var _ant_rect: TextureRect
var _ant_viewport: SubViewport
var _ant_root: Node3D
var _ant_pivot: Node3D
var _road_aspect: float = 1.0
var _speed_buttons: Array[Button] = []
var _pause_button: Button
var _amount_labels: Dictionary = {}
var _amounts: Dictionary = {}

var _time: float = 0.0
var _is_day: bool = true
var _night_amount: float = 0.0
var _day: int = 1
var _speed: int = 1
var _paused: bool = false
# Side view at the start: the ant looks to the right, the way the day runs
var _ant_yaw: float = -PI * 0.5

func _ready() -> void:
	layer = 2
	_build()
	# The game starts at normal speed and running, whatever the previous scene left behind
	_speed = 1
	_paused = false
	Engine.time_scale = 1.0
	_update_speed_buttons()
	_update_pause_button()
	_set_day(starting_day, false)
	# A day starts at dawn, a night in the middle of the night
	_time = 0.0 if start_at_day else day_length * (day_share + (1.0 - day_share) * 0.5)
	var angle := _sun_angle_for(_time / day_length) if day_length > 0.0 else 0.0
	_night_amount = _night_amount_for(angle)
	_is_day = _night_amount <= 0.5
	_set_phase(_is_day, false)
	get_viewport().size_changed.connect(_layout)
	_layout()
	# The sky may already have to start dark, if the level starts at night
	cycle_changed.emit(_night_amount, angle)

func _process(delta: float) -> void:
	# While paused the clock stands still; delta is already 0 through Engine.time_scale,
	# but this also keeps the tab out of the cycle when paused another way.
	if day_length > 0.0 and not _paused:
		var previous := _time
		_time = fmod(_time + delta, day_length)
		# The clock wrapped around: a new day starts
		if _time < previous:
			_set_day(_day + 1, true)
		var angle := _sun_angle_for(_time / day_length)
		var night := _night_amount_for(angle)
		_night_amount = night
		# Every frame, because the sun has to move along its arc
		cycle_changed.emit(night, angle)
		var day := night <= 0.5
		if day != _is_day:
			_is_day = day
			_set_phase(day, true)
	_update_day_preview(delta)

# Where the sun is in its arc: 0 = sunrise, PI/2 = noon, PI = sunset, 3PI/2 = midnight.
# The day and the night each take their own part of the cycle, so day_share still works.
func _sun_angle_for(t: float) -> float:
	if day_share <= 0.0:
		return 0.0
	if t < day_share:
		return PI * (t / day_share)
	return PI + PI * ((t - day_share) / maxf(1.0 - day_share, 0.001))

# 0 = full day, 1 = full night. It fades around the horizon, so the sky darkens exactly
# while the sun goes under and brightens again while it comes up.
func _night_amount_for(angle: float) -> float:
	var edge := maxf(twilight_height, 0.001)
	return 1.0 - smoothstep(-edge, edge, sin(angle))

# ---- Building ----

func _build() -> void:
	_build_day_panel()
	_build_resources_panel()
	_build_controls_panel()

func _build_day_panel() -> void:
	_day_panel = _make_panel("DayNightPanel")
	var column := _make_column(_day_panel)
	column.add_theme_constant_override("separation", 8)

	# Dawn on the left, dusk on the right; the day counter sits under them
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)

	_day_icon_rect = _make_phase_icon(day_icon)
	header.add_child(_day_icon_rect)
	header.add_child(_make_spacer())
	_night_icon_rect = _make_phase_icon(night_icon)
	header.add_child(_night_icon_rect)

	_day_label = _make_label(16, title_color)
	_day_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_day_label)

	# The granite footpath with the real 3D ant walking over it
	_build_ant_road(column)

	# Pause and the three speeds in one row, leaving the height for the road above
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	column.add_child(controls)

	_pause_button = _make_button("")
	_pause_button.custom_minimum_size = Vector2(36.0, 30.0)
	_pause_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pause_button.pressed.connect(toggle_pause)
	controls.add_child(_pause_button)

	var group := ButtonGroup.new()
	_speed_buttons.clear()
	for i in 3:
		var button := _make_button("%dx" % (i + 1))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, 30.0)
		button.button_pressed = i == 0
		button.tooltip_text = "%dx: a whole day and night take %d minutes" % [i + 1, 24 / (i + 1)]
		button.pressed.connect(set_speed.bind(i + 1))
		controls.add_child(button)
		_speed_buttons.append(button)

func _make_phase_icon(texture: Texture2D) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(phase_icon_size, phase_icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _make_spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

# Left and right padding of a card, so the road knows how wide it is
func _panel_side_margins() -> float:
	var style := _day_panel.get_theme_stylebox("panel")
	if style == null:
		return 0.0
	return style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT)

# ---- The ant on the road ----

# A real little 3D scene: a granite slab with the same ant model as in the level
# walking over the top of it. The card only shows the picture that scene renders.
func _build_ant_road(column: VBoxContainer) -> void:
	_ant_road = Control.new()
	_ant_road.name = "AntRoad"
	_ant_road.custom_minimum_size = Vector2(0.0, path_height)
	_ant_road.clip_contents = true
	_ant_road.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_ant_road)

	var content_width := maxf(panel_width - _panel_side_margins(), 1.0)
	_road_aspect = content_width / maxf(path_height, 1.0)

	_ant_rect = TextureRect.new()
	_ant_rect.name = "RoadView"
	_ant_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ant_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_ant_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_ant_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_ant_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ant_road.add_child(_ant_rect)

	_build_road_view(Vector2i(
		maxi(int(round(content_width)) * 4, 64),
		maxi(int(round(path_height)) * 4, 64)))

func _build_road_view(view_size: Vector2i) -> void:
	# Rendered bigger than it is shown, so the ant and the stones stay sharp
	_ant_viewport = SubViewport.new()
	_ant_viewport.name = "RoadView3D"
	_ant_viewport.size = view_size
	_ant_viewport.transparent_bg = true
	_ant_viewport.own_world_3d = true
	_ant_viewport.msaa_3d = Viewport.MSAA_4X
	_ant_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_ant_viewport)
	_ant_rect.texture = _ant_viewport.get_texture()

	# The same light as the preview in the ant card, so the block colours match
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0.0, 0.0, 0.0, 0.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.74, 0.80, 0.70)
	env.ambient_light_energy = 1.35
	world_env.environment = env
	_ant_viewport.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	sun.light_energy = 1.15
	# The ant casts a shadow on the slab, so it clearly stands on it instead of in front
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 12.0
	_ant_viewport.add_child(sun)

	# The granite slab. Its top sits exactly on y = 0, where the ant walks.
	var slab := MeshInstance3D.new()
	slab.name = "Footpath"
	var box := BoxMesh.new()
	box.size = ROAD_SIZE
	slab.mesh = box
	slab.material_override = _make_stone_material(0.74)
	slab.position = Vector3(0.0, -ROAD_SIZE.y * 0.5, 0.0)
	_ant_viewport.add_child(slab)

	# A lighter walking surface on top of the slab, so the top edge catches the eye and
	# the path clearly reads as a thick stone slab instead of a flat strip.
	var surface := MeshInstance3D.new()
	surface.name = "FootpathTop"
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_SIZE.x, ROAD_SIZE.z)
	surface.mesh = plane
	surface.material_override = _make_stone_material(1.08)
	surface.position = Vector3(0.0, 0.004, 0.0)
	_ant_viewport.add_child(surface)

	# The ant itself, in side view with its own walking animation
	_ant_root = Node3D.new()
	_ant_root.name = "Ant"
	_ant_viewport.add_child(_ant_root)

	# The pivot turns the ant around at the ends of the road. The plain glTF has its
	# head along -Z, so a quarter turn puts the head to the right, in side view.
	_ant_pivot = Node3D.new()
	_ant_pivot.name = "AntPivot"
	_ant_pivot.rotation.y = _ant_yaw
	_ant_pivot.scale = Vector3.ONE * ANT_SCALE
	_ant_root.add_child(_ant_pivot)
	_ant_pivot.add_child(ANT_MODEL.instantiate())

	# The model brings two clips: idle and walking. The road always uses walking.
	var player := _ant_pivot.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		if player.has_animation("walking"):
			player.play("walking")
		elif not player.get_animation_list().is_empty():
			player.play(player.get_animation_list()[0])

	_build_road_camera()

func _make_stone_material(brightness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = GRANITE
	# A slightly warm stone, so it sits in the green card instead of looking blue
	material.albedo_color = Color(1.08, 1.03, 0.95) * brightness
	material.roughness = 1.0
	material.metallic = 0.0
	# Triplanar keeps the stones the same size on the top and the sides of the slab
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.85, 0.85, 0.85)
	return material

# An orthogonal camera from the front, a little above the road, so the slab reads as
# a 3D path and the ant visibly stands on its top surface.
func _build_road_camera() -> void:
	# Centred on the ant plus the slab, so there is no empty strip above or below
	var target := Vector3(0.0, 0.05, 0.0)
	var elevation := deg_to_rad(ROAD_CAMERA_ELEVATION)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = ROAD_VIEW_HEIGHT
	camera.near = 0.05
	camera.far = 40.0
	camera.position = target + Vector3(0.0, sin(elevation), cos(elevation)) * 6.0
	_ant_viewport.add_child(camera)
	camera.look_at(target, Vector3.UP)
	camera.current = true

# Day: left to right. Night: right to left. The ant turns around at both ends.
func _update_day_preview(delta: float) -> void:
	if _ant_root == null:
		return
	var day_part := clampf(day_share, 0.001, 0.999)
	var t := get_cycle_position()
	var progress: float
	if t < day_part:
		progress = t / day_part
	else:
		progress = 1.0 - (t - day_part) / maxf(1.0 - day_part, 0.001)
	progress = clampf(progress, 0.0, 1.0)

	# Keep the whole ant in view: half the visible width, minus its own half length
	var half_view := ROAD_VIEW_HEIGHT * _road_aspect * 0.5
	var limit := maxf(half_view - 0.52, 0.0)
	_ant_root.position.x = lerp(-limit, limit, progress)

	if _ant_pivot == null:
		return
	var target_yaw := -PI * 0.5 if t < day_part else PI * 0.5
	_ant_pivot.rotation.y = lerp_angle(
		_ant_pivot.rotation.y, target_yaw, 1.0 - exp(-ant_turn_speed * delta))

func _build_resources_panel() -> void:
	_resources_panel = _make_panel("ResourcesPanel")
	var column := _make_column(_resources_panel)
	column.add_theme_constant_override("separation", 6)

	var title := _make_label(14, accent_color)
	title.text = "RESOURCES"
	column.add_child(title)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(rows)

	for resource in RESOURCE_LIST:
		rows.add_child(_make_resource_row(resource))

func _make_resource_row(resource: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var icon := TextureRect.new()
	icon.texture = load(str(resource["icon"])) as Texture2D
	icon.custom_minimum_size = Vector2(36.0, 36.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var name_label := _make_label(13, text_color)
	name_label.text = str(resource["name"])
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_label)

	var amount := _make_label(16, title_color)
	amount.text = "0"
	amount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(amount)

	var id := str(resource["id"])
	_amounts[id] = 0
	_amount_labels[id] = amount
	return row

func _build_controls_panel() -> void:
	_controls_panel = _make_panel("ControlsPanel")
	var column := _make_column(_controls_panel)
	column.add_theme_constant_override("separation", 6)

	var save := _make_button("Save")
	save.size_flags_vertical = Control.SIZE_EXPAND_FILL
	save.pressed.connect(func() -> void: save_requested.emit())
	column.add_child(save)

	var menu := _make_button("Main menu")
	menu.size_flags_vertical = Control.SIZE_EXPAND_FILL
	menu.pressed.connect(_on_main_menu)
	column.add_child(menu)

	var quit := _make_button("Quit")
	quit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	quit.pressed.connect(_on_quit)
	column.add_child(quit)

# ---- Shared look ----

# A card in the same style as the ant card, mirrored so the open side faces the level
func _make_panel(node_name: String) -> PanelContainer:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.border_width_right = 4
	style.border_color = accent_color
	style.content_margin_left = 16.0
	style.content_margin_right = 20.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0

	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", style)
	panel.clip_contents = true
	add_child(panel)
	return panel

func _make_column(panel: PanelContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	return column

func _make_label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", title_color)
	button.add_theme_color_override("font_hover_color", title_color)
	button.add_theme_color_override("font_pressed_color", background_color)
	button.add_theme_color_override("font_hover_pressed_color", background_color)
	button.add_theme_stylebox_override("normal", _button_style(Color(1.0, 1.0, 1.0, 0.07)))
	button.add_theme_stylebox_override("hover", _button_style(Color(1.0, 1.0, 1.0, 0.15)))
	button.add_theme_stylebox_override("pressed", _button_style(
		Color(accent_color.r, accent_color.g, accent_color.b, 0.75)))
	button.add_theme_stylebox_override("hover_pressed", _button_style(
		Color(accent_color.r, accent_color.g, accent_color.b, 0.9)))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return button

func _button_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style

# ---- Placement ----

func _layout() -> void:
	if _day_panel == null:
		return
	var screen := get_viewport().get_visible_rect().size
	var x := margin

	# Top card: as tall as its own content
	var day_height := _day_panel.get_combined_minimum_size().y
	_day_panel.position = Vector2(x, top_margin)
	_day_panel.size = Vector2(panel_width, day_height)

	# Bottom card: pinned to the bottom edge
	var controls_height := maxf(
		screen.y * controls_fraction, _controls_panel.get_combined_minimum_size().y)
	var controls_y := screen.y - bottom_margin - controls_height
	_controls_panel.position = Vector2(x, controls_y)
	_controls_panel.size = Vector2(panel_width, controls_height)

	# Middle card: under the top card, about 60% of the height, never over the bottom card
	var resources_top := top_margin + day_height + gap
	var resources_height := maxf(
		screen.y * resources_fraction, _resources_panel.get_combined_minimum_size().y)
	resources_height = minf(resources_height, controls_y - gap - resources_top)
	_resources_panel.position = Vector2(x, resources_top)
	_resources_panel.size = Vector2(panel_width, maxf(resources_height, 0.0))

# ---- Day and night ----

# The active picture is bright, the other one fades into the card. A sky or lighting
# system can listen to phase_changed.
func _set_phase(is_day: bool, announce: bool) -> void:
	_is_day = is_day
	if _day_icon_rect != null:
		_day_icon_rect.modulate = Color(1.0, 1.0, 1.0, 1.0) if is_day else Color(1.0, 1.0, 1.0, 0.35)
	if _night_icon_rect != null:
		_night_icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.35) if is_day else Color(1.0, 1.0, 1.0, 1.0)
	if announce:
		phase_changed.emit(is_day)

func _set_day(day: int, announce: bool) -> void:
	_day = day
	if _day_label != null:
		_day_label.text = "Day %d" % day
	if announce:
		day_changed.emit(day)

func get_day() -> int:
	return _day

func is_day() -> bool:
	return _is_day

# 0.0 = the start of the day, 0.5 = the start of the night, 1.0 = the next day
func get_cycle_position() -> float:
	if day_length <= 0.0:
		return 0.0
	return _time / day_length

# ---- Speed and pause ----

# 1, 2 or 3 times the normal speed. It drives Engine.time_scale, so the whole game
# (ants, clock, animations) really runs faster. Speed 1 is 24 minutes per cycle.
func set_speed(speed: int) -> void:
	_speed = clampi(speed, 1, 3)
	_update_speed_buttons()
	if not _paused:
		Engine.time_scale = float(_speed)

func get_speed() -> int:
	return _speed

func toggle_pause() -> void:
	set_paused(not _paused)

# Pause stops everything: the clock, the ants and the animations. Resuming keeps the
# speed that was selected before.
func set_paused(paused: bool) -> void:
	_paused = paused
	Engine.time_scale = 0.0 if _paused else float(_speed)
	_update_pause_button()

func is_game_paused() -> bool:
	return _paused

func _update_speed_buttons() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == _speed - 1)

func _update_pause_button() -> void:
	if _pause_button != null:
		# Two bars while running, a triangle while paused
		_pause_button.text = "\u25b6" if _paused else "\u275a\u275a"
		_pause_button.tooltip_text = "Continue the game" if _paused else "Stop the whole game"

# ---- Resources ----

func set_resource_amount(id: String, amount: int) -> void:
	if not _amounts.has(id):
		return
	_amounts[id] = amount
	var label := _amount_labels[id] as Label
	if label != null:
		label.text = str(amount)

func get_resource_amount(id: String) -> int:
	return int(_amounts.get(id, 0))

# ---- Bottom card ----

# Both buttons leave the level for the start screen. When there is a real in-game menu,
# "Main menu" can open that instead.
func _on_main_menu() -> void:
	_go_to_start()

func _on_quit() -> void:
	_go_to_start()

func _go_to_start() -> void:
	Engine.time_scale = 1.0
	get_tree().paused = false
	get_tree().change_scene_to_file(start_scene)

# Never leave the engine frozen or running fast when this level goes away
func _exit_tree() -> void:
	Engine.time_scale = 1.0
