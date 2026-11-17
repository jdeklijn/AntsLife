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
# The animation that plays as soon as the ant is in the scene. Godot's glTF import strips
# the "_loop" suffix and marks the clip looping, so "idle_loop" in Blockbench arrives here
# as "idle".
@export var idle_animation: StringName = &"idle"
# Playback speed of the idle clip. Lower is slower: 0.5 is half speed, 1.0 the clip's
# own speed.
@export_range(0.1, 3.0, 0.05) var idle_speed: float = 1.0
# The clip that plays while the ant walks to a clicked spot
@export var walking_animation: StringName = &"walking"
@export_range(0.1, 3.0, 0.05) var walking_speed: float = 1.0

# ---- Walking (click to point) ----
# How fast the ant walks, in blocks per second
@export var move_speed: float = 1.5
# How quickly the ant turns towards the direction it walks
@export var turn_speed: float = 10.0
# How close the ant has to get before it stops
@export var arrive_distance: float = 0.05
# Added to the walking direction, in degrees. The model in ant_3d.tscn is turned 180
# degrees, so this is what makes its head point the way it walks. Set it to 0 if the
# model itself already faces -Z.
@export var facing_offset_degrees: float = 180.0

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
var _walk_target: Vector3
var _has_walk_target: bool = false
var _walking: bool = false

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

# ---- Walking over the grass (click to point) ----

# Sends the ant to the spot under the mouse when it is on the grass. Returns false when
# the click missed the level, so the caller can clear the selection instead.
func walk_to_mouse() -> bool:
	var point := _mouse_ground_point()
	if point == Vector3.INF:
		return false
	walk_to(point)
	return true

# Where the mouse points on the grass surface, or Vector3.INF when it misses the level
func _mouse_ground_point() -> Vector3:
	var camera := get_viewport().get_camera_3d()
	var level := LevelData.find_sibling(self)
	if camera == null or level == null:
		return Vector3.INF
	var height := float(level.surface_y + 1)
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var hit = Plane(Vector3.UP, height).intersects_ray(origin, direction)
	if hit == null:
		return Vector3.INF
	var point: Vector3 = hit
	var cell := world_to_cell(point)
	var surface := Vector3i(cell.x, level.surface_y, cell.z)
	if not level.in_bounds(surface) or level.get_cell(surface) == LevelData.Cell.EMPTY:
		return Vector3.INF
	return Vector3(point.x, height, point.z)

# World position to the cell it lies in (world z is the negative of the level z)
func world_to_cell(p: Vector3) -> Vector3i:
	return Vector3i(floori(p.x), floori(p.y), floori(-p.z))

# Turns towards the point and walks there in a straight line, over the grass
func walk_to(point: Vector3) -> void:
	_walk_target = Vector3(point.x, global_position.y, point.z)
	if _walk_target.distance_to(global_position) <= arrive_distance:
		return
	_has_walk_target = true
	current_action = ""
	if is_instance_valid(Ants):
		Ants.set_action(self, current_action)
	_set_walking(true)

func stop_walking() -> void:
	if not _has_walk_target:
		return
	_has_walk_target = false
	_set_walking(false)

func is_walking() -> bool:
	return _has_walk_target

func _process(delta: float) -> void:
	if not _has_walk_target:
		return
	var to := _walk_target - global_position
	to.y = 0.0
	var distance := to.length()
	if distance <= arrive_distance:
		global_position = Vector3(_walk_target.x, global_position.y, _walk_target.z)
		stop_walking()
		return
	var direction := to / distance
	global_position += direction * minf(move_speed * delta, distance)
	# Face the way we walk. Godot's forward is -Z, so the yaw comes from the direction.
	var wanted := atan2(-direction.x, -direction.z) + deg_to_rad(facing_offset_degrees)
	rotation.y = lerp_angle(rotation.y, wanted, 1.0 - exp(-turn_speed * delta))

# Switches between the walk clip and the idle clip. A model without clips is animated by
# AntModelAnimation instead, which fades into its own walking motion.
func _set_walking(walking: bool) -> void:
	if _walking == walking:
		return
	_walking = walking
	var blocks := find_child("AntModelAnimation", true, false) as AntModelAnimation
	if blocks != null:
		blocks.set_walking(walking)
	if walking and _play_clip(walking_animation, walking_speed):
		return
	_play_idle()

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
		return
	if not selected:
		return
	# A click on the grass sends the selected ant there. Anywhere else lets it go.
	if walk_to_mouse():
		get_viewport().set_input_as_handled()
	else:
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

# The model's AnimationPlayer. glTF imports usually name it "AnimationPlayer", but fall
# back to the first one found so a renamed node still animates.
func _animation_player() -> AnimationPlayer:
	var player := find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player != null:
		return player
	for node in find_children("*", "AnimationPlayer", true, false):
		player = node as AnimationPlayer
		if player != null:
			return player
	return null

# The keys to try for a clip. Godot's glTF import turns a clip named "idle_loop" into a
# clip named "idle" that loops, so also try the name without that suffix. That keeps both
# naming styles working without editing the exported scene.
func _clip_candidates(clip: StringName) -> Array[StringName]:
	var names: Array[StringName] = [clip]
	var plain := String(clip)
	for suffix in ["_loop", "-loop"]:
		if plain.ends_with(suffix) and plain.length() > suffix.length():
			names.append(StringName(plain.substr(0, plain.length() - suffix.length())))
			break
	return names

# The key the AnimationPlayer needs to play a clip. A glTF import can also store every clip
# in a library named after the animation group ("idle/idle_loop"), so check the libraries
# too. A clip in the default library is played by its plain name.
func _resolve_clip(player: AnimationPlayer, clip: StringName) -> StringName:
	if clip == &"":
		return &""
	var candidates := _clip_candidates(clip)
	for candidate in candidates:
		if player.has_animation(candidate):
			return candidate
	for candidate in candidates:
		var plain := String(candidate)
		var fallback := &""
		for library_name in player.get_animation_library_list():
			var library := player.get_animation_library(library_name)
			if library == null or not library.has_animation(plain):
				continue
			var key := StringName("%s/%s" % [library_name, plain])
			# Prefer the library that is named after the clip ("idle" for "idle_loop")
			if plain.begins_with(String(library_name)):
				return key
			if fallback == &"":
				fallback = key
		if fallback != &"":
			return fallback
	return &""

# Plays one clip of the model's own AnimationPlayer. Returns false when it has no such clip.
func _play_clip(clip: StringName, speed: float) -> bool:
	var player := _animation_player()
	if player == null:
		return false
	var key := _resolve_clip(player, clip)
	if key == &"":
		push_warning("Ant3D: no clip '%s' in the model. Available: %s" % [clip, player.get_animation_list()])
		return false
	if player.current_animation != key or not player.is_playing():
		var animation := player.get_animation(key)
		if animation == null:
			return false
		animation.loop_mode = Animation.LOOP_LINEAR
		player.speed_scale = speed
		player.play(key)
		if OS.is_debug_build():
			print("Ant3D '%s': playing %s" % [ant_name, key])
	else:
		player.speed_scale = speed
	return true

func _play_idle() -> void:
	var player := _animation_player()
	if player == null:
		# A model without clips is animated by AntModelAnimation instead
		if find_child("AntModelAnimation", true, false) != null:
			return
		push_warning("Ant3D: no AnimationPlayer found in the model. Is the model a child of this node?")
		return
	var chosen := _resolve_clip(player, idle_animation)
	if chosen == &"":
		# No idle clip under that name: fall back to whatever the model offers
		var names := player.get_animation_list()
		if names.is_empty():
			return
		chosen = names[0]
	_play_clip(chosen, idle_speed)

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
	# The chosen action takes over from walking
	stop_walking()
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
