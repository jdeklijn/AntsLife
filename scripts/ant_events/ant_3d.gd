class_name Ant3D
extends Node3D

# ---- Position ----
# The cell the ant stands on. It is placed at the bottom centre of that cell. With
# place_on_grass on, only x and z are used and the ant starts on the grass surface.
@export var cell: Vector3i = Vector3i(3, 10, 0)
# Turn this off to place the ant by hand with the Position in the Inspector
@export var place_on_cell: bool = true
# Stand on the grass of whatever level is loaded, so a bigger or taller level does not
# bury the ant. Only the x and z of the cell are used then; turn it off to start the ant
# underground at the exact cell y.
@export var place_on_grass: bool = true

# ---- Animation ----
# The animation that plays as soon as the ant is in the scene
@export var idle_animation: StringName = &"idle_loop"
# Playback speed of the idle clip. Lower is slower: 0.5 is half speed, 1.0 the clip's
# own speed.
@export_range(0.1, 3.0, 0.05) var idle_speed: float = 1.0

# ---- Ant data (decides which actions are available) ----
@export var ant_name: String = "Ant"
@export var category: String = "excavator"
@export var level: int = 1
@export var tools: Array[String] = []

# What the ant is doing now. Shown in the info panel; empty means idle.
var current_action: String = ""

# ---- Selecting the ant with the mouse ----
# An invisible box around the ant that catches the mouse click. With auto_hit_box on it
# is measured from the model on start; these values are the fallback for the first frames
# and for when auto_hit_box is off.
@export var hit_size: Vector3 = Vector3(1.0, 0.9, 1.0)
@export var hit_offset: Vector3 = Vector3(0.0, 0.45, 0.0)
# Show the box, to tune hit_size and hit_offset
@export var show_hit_box: bool = false
# The ring on the ground around a selected ant
@export var ring_radius: float = 0.45
@export var ring_color: Color = Color(0.55, 0.78, 0.35)
# Shift the model so the lowest point of its current pose stands on the cell. This keeps
# the feet on the grass whatever pose (or animation) the model is in.
@export var snap_model_to_ground: bool = true
# Fit the click box to the model on start (plus hit_margin), so a scaled ant stays easy
# to click without editing hit_size by hand. Turn off to use hit_size/hit_offset as-is.
@export var auto_hit_box: bool = true
@export var hit_margin: float = 0.15

var selected: bool = false
var _ring: MeshInstance3D

func _ready() -> void:
	# This script moves the node it hangs on, so it belongs on the root of ant_3d.tscn only.
	# On a node that contains the level, it would move the whole level.
	for node in find_children("*", "MeshInstance3D", true, false):
		if node.has_method("rebuild"):
			push_error("Ant3D: this script is attached to a node that contains the level view. Attach ant_3d.gd to the root of ant_3d.tscn instead.")
			return
	if place_on_cell:
		var start := cell
		if place_on_grass:
			start.y = _grass_row() + 1
		position = cell_to_world(start)
	_make_ring()
	if show_hit_box:
		_make_hit_box_debug()
	Events.ant_selected.connect(_on_ant_selected)
	Events.action_requested.connect(_on_action_requested)
	_play_idle()
	if snap_model_to_ground:
		_snap_model_to_ground.call_deferred()
	Ants.register(self)

func _exit_tree() -> void:
	# The autoload may already be gone while the game shuts down
	if is_instance_valid(Ants):
		Ants.unregister(self)

# World z is the negative of the level z, the same way the level view builds the blocks

func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, c.y, -c.z - 0.5)

# The grass row of the level in this scene, so the ant stands on top of whatever level
# is loaded instead of on a row that was tuned for one level size
func _grass_row() -> int:
	var level := LevelData.find_sibling(self)
	return level.surface_y if level != null else Level01.surface_y()

# ---- Ring creation ----

func _make_ring() -> void:
	var torus := TorusMesh.new()
	torus.outer_radius = ring_radius
	torus.inner_radius = ring_radius - 0.03
	torus.rings = 32
	torus.ring_segments = 16
	
	_ring = MeshInstance3D.new()
	_ring.name = "ring"
	_ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = ring_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring.material_override = material
	_ring.visible = selected
	add_child(_ring)

# Debug hit box (larger than ant, invisible)

func _make_hit_box_debug() -> void:
	var hit_shape := SphereShape3D.new()
	hit_shape.radius = 0.6
	var collision := CollisionShape3D.new()
	collision.shape = hit_shape
	add_child(collision)

# ---- Standing on the ground ----

# The rest pose of the model does not have to have its feet on y = 0. Wait until the first
# animation frame has been applied, then move the model so its lowest point sits on the
# ant's cell. With a real idle clip this is what puts the feet exactly on the grass.
func _snap_model_to_ground() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var model := _model_root()
	if model == null:
		return
	var box := _model_bounds(model)
	if box.size == Vector3.ZERO:
		return
	var shift := global_position.y - box.position.y
	model.position.y += shift
	box.position.y += shift
	# The same box is the click target, with a little extra around the ant
	if auto_hit_box:
		hit_offset = box.get_center() - global_position
		hit_size = box.size + Vector3.ONE * hit_margin * 2.0

# World-space box around every mesh of the model, in its current pose
func _model_bounds(model: Node3D) -> AABB:
	var box := AABB()
	var found := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		var part := mesh_instance.global_transform * mesh_instance.mesh.get_aabb()
		box = part if not found else box.merge(part)
		found = true
	return box

# The first child that holds meshes is the ant model (the selection ring is skipped)
func _model_root() -> Node3D:
	for child in get_children():
		if child == _ring or not (child is Node3D):
			continue
		if not child.find_children("*", "MeshInstance3D", true, false).is_empty():
			return child as Node3D
	return null

# ---- Selecting ----

func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or button.pressed:
		return
	# Selecting happens when the button is released, so holding it down to slide the
	# level does not select the ant as well
	var camera := get_viewport().get_camera_3d()
	if camera is PlayfieldCamera and camera.view_dragged():
		return
	if _is_under_mouse():
		select()
		get_viewport().set_input_as_handled()
	elif selected:
		deselect()

func _is_under_mouse() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var mouse := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_dir := camera.project_ray_normal(mouse)
	var box := AABB(global_position + hit_offset - hit_size * 0.5, hit_size)
	return box.intersects_ray(ray_origin, ray_dir) != null

func select() -> void:
	if selected:
		return
	selected = true
	if _ring != null:
		_ring.visible = true
	Events.ant_selected.emit(self)

func deselect() -> void:
	if not selected:
		return
	selected = false
	if _ring != null:
		_ring.visible = false
	Events.ant_deselected.emit(self)

func _on_ant_selected(ant: Node) -> void:
	if ant != self and selected:
		selected = false
		if _ring != null:
			_ring.visible = false

# Animation control

func _play_idle() -> void:
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		# ant_v3_compleet has no skeleton or clips; AntModelAnimation moves its parts instead
		if find_child("AntModelAnimation", true, false) != null:
			return
		push_warning("Ant3D: no AnimationPlayer found in the model. Is the model a child of this node?")
		return
	var chosen = idle_animation
	if not player.has_animation(chosen):
		for animation_name in player.get_animation_list():
			chosen = animation_name
			break
	var animation := player.get_animation(chosen)
	if animation == null:
		return
	animation.loop_mode = Animation.LOOP_LINEAR
	player.speed_scale = idle_speed
	player.play(chosen)

func check_action(_action: AntAction) -> String:
	# Placeholder - implement based on ant category/tools
	return ""

# ---- Info for the selection panel ----

func get_ant_name() -> String:
	return ant_name

func get_current_action() -> String:
	return current_action

# Called by the info panel. An empty name is refused, so an ant is never nameless.
func set_ant_name(new_name: String) -> void:
	var trimmed := new_name.strip_edges()
	if trimmed == "":
		return
	ant_name = trimmed
	Ants.set_ant_name(self, ant_name)

func _on_action_requested(ant: Node, action: Resource) -> void:
	if ant != self:
		return
	current_action = str(action.get("label"))
	Ants.set_action(self, current_action)
	# Picking an action ends the interaction: drop the selection, the ring and the panel
	deselect()

# Where the radial menu should appear (2D screen position above the ant)
func get_menu_position() -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return get_viewport().get_visible_rect().size / 2.0
	return camera.unproject_position(global_position + Vector3(0.0, hit_offset.y, 0.0))
