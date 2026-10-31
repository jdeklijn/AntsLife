class_name RadialMenu
extends Control

# Drag the AntAction resources into this array in the Inspector
@export var actions: Array[AntAction] = []
@export var radius: float = 85.0
@export var button_size: Vector2 = Vector2(84, 84)

var _ant: Ant = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.ant_selected.connect(_on_ant_selected)
	Events.ant_deselected.connect(_on_ant_deselected)

func _unhandled_input(event: InputEvent) -> void:
	# Escape: release the ant, which also closes the menu
	if _ant != null and event.is_action_pressed("ui_cancel"):
		_ant.deselect()
		get_viewport().set_input_as_handled()

func _on_ant_selected(ant: Node2D) -> void:
	_open(ant as Ant)

func _on_ant_deselected(_ant_node: Node2D) -> void:
	_close()

func _open(ant: Ant) -> void:
	_close()
	_ant = ant
	if actions.is_empty():
		push_warning("RadialMenu: no actions assigned in the Inspector.")
		return
	var center := _clamped_center(ant.get_global_transform_with_canvas().origin)
	print("RadialMenu: opening with %d actions at %s" % [actions.size(), center])  # temporary debug
	var n := actions.size()
	for i in n:
		var action := actions[i]
		var angle := -PI / 2.0 + i * TAU / n
		var button := Button.new()
		button.text = action.label
		button.custom_minimum_size = button_size
		button.size = button_size
		button.position = center + Vector2.from_angle(angle) * radius - button_size / 2.0
		var reason := ant.check_action(action)
		if reason != "":
			button.disabled = true
			button.tooltip_text = reason
		else:
			button.pressed.connect(_on_action_pressed.bind(action))
		add_child(button)

func _close() -> void:
	for child in get_children():
		child.queue_free()
	_ant = null

func _on_action_pressed(action: AntAction) -> void:
	var ant := _ant
	_close()
	print("Action chosen: ", action.label)  # temporary debug
	Events.action_requested.emit(ant, action)

# Keeps the whole menu inside the screen
func _clamped_center(p: Vector2) -> Vector2:
	var margin := radius + button_size.x / 2.0
	var view := get_viewport_rect().size
	return Vector2(
		clampf(p.x, margin, view.x - margin),
		clampf(p.y, margin, view.y - margin)
	)
