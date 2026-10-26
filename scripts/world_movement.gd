extends Camera3D

@export var move_speed: float = 1.0
@export var mouse_sensitivity: float = 0.001
@export var key_direction_distance: float = 0.5

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE	

func _input(event):
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			rotate_y(-event.relative.x * mouse_sensitivity)

			var new_rotation_x = rotation.x - event.relative.y * mouse_sensitivity
			new_rotation_x = clamp(
				new_rotation_x,
				deg_to_rad(-80),
				deg_to_rad(80)
			)
			rotation.x = new_rotation_x

func _physics_process(delta):
	var direction := Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W): direction.z = -key_direction_distance
	if Input.is_key_pressed(KEY_S): direction.z = key_direction_distance
	if Input.is_key_pressed(KEY_A): direction.x = -key_direction_distance
	if Input.is_key_pressed(KEY_D): direction.x = key_direction_distance
	if Input.is_key_pressed(KEY_SPACE): direction.y = 1
	if Input.is_key_pressed(KEY_SHIFT): direction.y = -1

	if direction.length() > 0:
		direction = direction.normalized()
		global_position -= direction * move_speed * delta
