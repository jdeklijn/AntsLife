class_name LevelSidebar
extends CanvasLayer

# The permanent column on the left of the playfield. Three semi-transparent cards, in the
# same style as the ant card on the right but mirrored: the accent border and the rounded
# corners sit on the side that faces the level.
#
#   top     day / night picture, the phase, the pause button and the speed buttons
#   middle  the resources and how many of each there are (about 60% of the height)
#   bottom  save, main menu and quit (about 12% of the height)
#
# The pause and speed buttons are only there for now: the actions come once we know how
# long a day lasts. The day / night cycle itself does run, so the icon swaps and other
# systems can follow it through phase_changed.

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

const FONT = preload("res://assests/ui/fonts/Nunito/Nunito-VariableFont_wght.ttf")

# The resources, in the order they are shown. Add or remove entries and the rows follow.
const RESOURCE_LIST: Array[Dictionary] = [
	{"id": "dirt", "name": "Dirt", "icon": "res://assests/ui/levels/resources/rsc_dirt_icoon.png"},
	{"id": "rock", "name": "Rock", "icon": "res://assests/ui/levels/resources/rsc_rock_icoon.png"},
	{"id": "wood", "name": "Wood", "icon": "res://assests/ui/levels/resources/rsc_wood_icoon.png"},
	{"id": "leaves", "name": "Leaves", "icon": "res://assests/ui/levels/resources/rsc_leaves_icoon.png"},
	{"id": "food", "name": "Food", "icon": "res://assests/ui/levels/resources/rsc_food_ico.png"},
	{"id": "water", "name": "Water", "icon": "res://assests/ui/levels/resources/rsc_water_icoon.png"},
	{"id": "iron", "name": "Iron", "icon": "res://assests/ui/levels/resources/rsc_iron_icoon.png"},
	{"id": "copper", "name": "Copper", "icon": "res://assests/ui/levels/resources/rsc_copper_icoon.png"},
	{"id": "gold", "name": "Gold", "icon": "res://assests/ui/levels/resources/rsc_gold_icoon.png"},
	{"id": "diamond", "name": "Diamond", "icon": "res://assests/ui/levels/resources/rsc_diamond_icoon.png"},
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
@export var day_icon: Texture2D = preload("res://assests/ui/levels/day_icoon.png")
@export var night_icon: Texture2D = preload("res://assests/ui/levels/night_icoon.png")
# Height of the picture at the top, like the ant preview on the right
@export var preview_height: float = 64.0
# Seconds for one full day and one full night together
@export var day_length: float = 240.0
# Part of the cycle that is day (0.5 = half day, half night)
@export_range(0.1, 0.9) var day_share: float = 0.5
# How far the sun must be above or below the horizon before it is fully day or night.
# 0.25 is about 14 degrees of sun height, which gives a real twilight.
@export_range(0.02, 0.8) var twilight_height: float = 0.25
@export var start_at_day: bool = true
# The first day of the level, shown in the card and counted up at every new morning
@export var starting_day: int = 1
# Where "Main menu" and "Quit" go: the screen with the sandbox entrance
@export_file("*.tscn") var start_scene: String = "res://scenes/main_scene.tscn"

@export_group("Colours")
@export var background_color: Color = Color(0.06, 0.08, 0.05, 0.78)
@export var accent_color: Color = Color(0.55, 0.78, 0.35)
@export var title_color: Color = Color(0.94, 0.96, 0.88)
@export var text_color: Color = Color(0.80, 0.85, 0.74)

var _day_panel: PanelContainer
var _resources_panel: PanelContainer
var _controls_panel: PanelContainer
var _phase_picture: TextureRect
var _phase_label: Label
var _day_label: Label
var _amount_labels: Dictionary = {}
var _amounts: Dictionary = {}

var _time: float = 0.0
var _is_day: bool = true
var _night_amount: float = 0.0
var _day: int = 1

func _ready() -> void:
	layer = 2
	_build()
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
	if day_length <= 0.0:
		return
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
	column.add_theme_constant_override("separation", 6)

	_phase_picture = TextureRect.new()
	_phase_picture.custom_minimum_size = Vector2(0.0, preview_height)
	_phase_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_phase_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_phase_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_phase_picture)

	# Day counter on the left, phase on the right
	var phase_row := HBoxContainer.new()
	phase_row.add_theme_constant_override("separation", 8)
	column.add_child(phase_row)

	_day_label = _make_label(15, text_color)
	_day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_day_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phase_row.add_child(_day_label)

	_phase_label = _make_label(17, title_color)
	_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_phase_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	phase_row.add_child(_phase_label)

	var line := ColorRect.new()
	line.color = Color(accent_color.r, accent_color.g, accent_color.b, 0.35)
	line.custom_minimum_size = Vector2(0.0, 2.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)

	# Speed: one of the three stays pressed, so you can see the current speed
	var speeds := HBoxContainer.new()
	speeds.add_theme_constant_override("separation", 4)
	column.add_child(speeds)
	var group := ButtonGroup.new()
	for speed in ["1x", "2x", "3x"]:
		var button := _make_button(str(speed))
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(0.0, 30.0)
		button.tooltip_text = "Speed is not wired up yet"
		button.button_pressed = speed == "1x"
		speeds.add_child(button)

	var pause := _make_button("Pause")
	pause.custom_minimum_size = Vector2(0.0, 32.0)
	pause.tooltip_text = "Pause is not wired up yet"
	column.add_child(pause)

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

# Swap the picture and the label. A sky or lighting system can listen to phase_changed.
func _set_phase(is_day: bool, announce: bool) -> void:
	_is_day = is_day
	if _phase_picture != null:
		_phase_picture.texture = day_icon if is_day else night_icon
	if _phase_label != null:
		_phase_label.text = "Day" if is_day else "Night"
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
