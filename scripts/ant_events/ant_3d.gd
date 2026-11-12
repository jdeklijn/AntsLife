class_name Ant3D
extends Node3D

# ---- Position ----
# The cell the ant stands on. It is placed at the bottom centre of that cell, so a cell
# on top of the grass puts the ant on the grass. (3, 10, 0) is the third block of the
# front layer, in the first row above the grass.
@export var cell: Vector3i = Vector3i(3, 10, 0)
# Turn this off to place the ant by hand with the Position in the Inspector
@export var place_on_cell: bool = true

# ---- Animation ----
# The animation that plays as soon as the ant is in the scene
@export var idle_animation: StringName = &"idle_loop"

# ---- Ant data (decides which actions are available) ----
@export var ant_name: String = "Ant"
@export var category: String = "excavator"
@export var level: int = 1
@export var tools: Array[String] = []

# What the ant is doing now. Shown in the info panel; empty means idle.
var current_action: String = ""

# ---- Selecting the ant with the mouse ----
# An invisible box around the ant that catches the mouse click. It is larger than the
# ant itself, because a flat ant seen from the front is a small target.
@export var hit_size: Vector3 = Vector3(1.0, 0.9, 1.0)
@export var hit_offset: Vector3 = Vector3(0.0, 0.45, 0.0)
# Show the box, to tune hit_size and hit_offset
@export var show_hit_box: bool = false
# The ring on the ground around a selected ant
@export var ring_radius: float = 0.45
@export var ring_color: Color = Color(0.55, 0.78, 0.35)

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
		position = cell_to_world(cell)
	_make_ring()
	if show_hit_box:
		_make_hit_box_debug()
	Events.ant_selected.connect(_on_ant_selected)
	Events.action_requested.connect(_on_action_requested)
	_play_idle()
	Ants.register(self)

func _exit_tree() -> void:
	# The autoload may already be gone while the game shuts down
	if is_instance_valid(Ants):
		Ants.unregister(self)

# World z is the negative of the level z, the same way the level view builds the blocks

func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, c.y, -c.z - 0.5)

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

# ---- Selecting ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
