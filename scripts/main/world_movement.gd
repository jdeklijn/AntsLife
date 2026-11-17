extends Camera3D

@export var move_speed: float = 3.0
@export var mouse_sensitivity: float = 0.002

# Start position of the game
@export var start_position: Vector3 = Vector3(0, 1.5, 5)
@export var start_pitch_deg: float = -10.0  # negative to watch a bit down

var yaw: float = 0.0    # left/right turning
var pitch: float = 0.0  # look up/down

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	global_position = start_position
	yaw = 0.0  # 0 = watch in the direction of the z-axel
	pitch = deg_to_rad(start_pitch_deg)
	_apply_rotation()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, deg_to_rad(-80), deg_to_rad(80))
		_apply_rotation()
		
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:		
		var from := project_ray_origin(event.position)
		var to := from + project_ray_normal(event.position) * 1000.0
		var space := get_world_3d().direct_space_state
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.collide_with_areas = true
		var result := space.intersect_ray(query)		
		if result and result.collider is Area3D:			
			result.collider.input_event.emit(self, event, result.position, result.normal, 0)	

func _apply_rotation() -> void:
	rotation = Vector3(pitch, yaw, 0.0)

func _physics_process(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): input.z -= 1  
	if Input.is_key_pressed(KEY_S): input.z += 1  
	if Input.is_key_pressed(KEY_A): input.x -= 1  
	if Input.is_key_pressed(KEY_D): input.x += 1  
	if Input.is_key_pressed(KEY_SPACE): input.y += 1  
	if Input.is_key_pressed(KEY_SHIFT): input.y -= 1  

	if input == Vector3.ZERO:
		return

	# Horizontale beweging volgt de kijkrichting (alleen yaw), omhoog/omlaag blijft wereld-omhoog
	var flat_basis := Basis(Vector3.UP, yaw)
	var move := flat_basis * Vector3(input.x, 0.0, input.z) + Vector3.UP * input.y
	global_position += move.normalized() * move_speed * delta
