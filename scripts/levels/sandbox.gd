extends Area3D

@export var level_scene: String = "res://scenes/playfield.tscn"

func _ready() -> void:
	input_event.connect(_on_input_event)

func _on_input_event(_camera: Node, event: InputEvent, _position: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		get_tree().change_scene_to_file(level_scene)
