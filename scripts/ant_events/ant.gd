class_name Ant
extends Node2D

# Click area and selection marker
@export var hit_size: Vector2 = Vector2(48, 56)
@export var ring_radius: float = 30.0
@export var ring_color: Color = Color(0.55, 0.78, 0.35)

# Ant data (decides which actions are available)
@export var category: String = "excavator"
@export var level: int = 1
@export var tools: Array[String] = []

var selected: bool = false

func _ready() -> void:
	Events.ant_selected.connect(_on_ant_selected)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_under_mouse():
			select()
			get_viewport().set_input_as_handled()
		elif selected:
			deselect()

func _is_under_mouse() -> bool:
	var local_pos := to_local(get_global_mouse_position())
	return Rect2(-hit_size / 2.0, hit_size).has_point(local_pos)

func select() -> void:
	if selected:
		return
	selected = true
	queue_redraw()
	Events.ant_selected.emit(self)

func deselect() -> void:
	if not selected:
		return
	selected = false
	queue_redraw()
	Events.ant_deselected.emit(self)

# Returns "" if this ant may do the action, otherwise the reason why not
func check_action(action: AntAction) -> String:
	if not action.allowed_categories.is_empty() and not (category in action.allowed_categories):
		return "Only for: " + ", ".join(PackedStringArray(action.allowed_categories))
	if level < action.min_level:
		return "Requires level %d" % action.min_level
	if action.required_tool != "" and not (action.required_tool in tools):
		return "Requires tool: " + action.required_tool
	return ""

# Another ant was selected: release this ant's marker
func _on_ant_selected(ant: Node2D) -> void:
	if ant != self and selected:
		selected = false
		queue_redraw()

func _draw() -> void:
	if selected:
		draw_arc(Vector2.ZERO, ring_radius, 0.0, TAU, 48, ring_color, 2.0)
