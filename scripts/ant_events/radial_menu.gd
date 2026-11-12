class_name RadialMenu
extends Control

# Drag the AntAction resources into this array in the Inspector
@export var actions: Array[AntAction] = []
@export var radius: float = 85.0
@export var button_size: Vector2 = Vector2(84, 84)

# Works with any ant that has the methods get_menu_position(), check_action() and
# deselect(), so it does not depend on the class name of the ant script
var _ant: Node = null
var _buttons: Array[Button] = []
var _angles: Array[float] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Events.ant_selected.connect(_on_ant_selected)
	Events.ant_deselected.connect(_on_ant_deselected)

func _process(_delta: float) -> void:
	# The menu stays around the ant while the camera pans, zooms or turns
	if _ant != null:
		_place_buttons()

func _unhandled_input(event: InputEvent) -> void:
	# Escape: release the ant, which also closes the menu
	if _ant != null and event.is_action_pressed("ui_cancel"):
		_ant.call("deselect")
		get_viewport().set_input_as_handled()

func _on_ant_selected(ant: Node) -> void:
	if ant.has_method("get_menu_position") and ant.has_method("check_action"):
		_open(ant)

func _on_ant_deselected(_ant_node: Node) -> void:
	_close()

func _open(ant: Node) -> void:
	_close()
	_ant = ant
	if actions.is_empty():
		push_warning("RadialMenu: no actions assigned in the Inspector.")
		return
	var n := actions.size()
	for i in n:
		var action := actions[i]
		var button := Button.new()
		button.text = action.label
		button.custom_minimum_size = button_size
		button.size = button_size
		var reason: String = ant.call("check_action", action)
		if reason != "":
			button.disabled = true
			button.tooltip_text = reason
		else:
			button.pressed.connect(_on_action_pressed.bind(action))
		add_child(button)
		_buttons.append(button)
		_angles.append(-PI / 2.0 + i * TAU / n)
	_place_buttons()
	print("RadialMenu: opened with %d actions" % n)  # temporary debug

func _close() -> void:
	for child in get_children():
		child.queue_free()
	_buttons.clear()
	_angles.clear()
	_ant = null

func _place_buttons() -> void:
	var anchor: Vector2 = _ant.call("get_menu_position")
	var center := _clamped_center(anchor)
	for i in _buttons.size():
		_buttons[i].position = center + Vector2.from_angle(_angles[i]) * radius - button_size / 2.0

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
