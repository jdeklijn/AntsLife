class_name AntModelAnimation
extends Node

# Procedural animation for the ant model.
#
# Two kinds of models work with this script:
#  - a skinned model with a Skeleton3D (ant_v4): we turn bones around their joints
#  - a model built out of loose parts (ant_v3_compleet): we turn those group nodes
# Either way the motions below talk about body parts, not about bone or node names, so a
# renamed rig keeps working. See PARTS for the names that are understood.
#
# The ant in the level uses the "idle", "walk", "dig", "carry" and "defend" motions below.
# The previews in the info panel and the sidebar use the same script with no Ant3D above
# it, so they just idle (or walk, in the sidebar).

# Leave empty to search for the skeleton, or the model root of a model without one
@export var model_path: NodePath
# Once the model has real clips (made in Blender), those win: this script stops moving the
# joints, so it never fights the AnimationPlayer
@export var disable_with_animation_player: bool = true
# How fast the idle motion runs
@export var idle_speed: float = 1.0
# Steps per second while walking. The model's legs swing once per 2*PI / walk_speed
# seconds, so a higher number makes a quicker step without changing how fast it walks
@export var walk_speed: float = 4.5
# How quickly the ant fades between standing still and walking
@export var walk_blend_speed: float = 5.0

# Every body part the motions use, with the names a model may give it (first match wins).
# No part may claim a joint another part already took, which is what makes the two
# different naming styles below work: the block ant calls its chest "upper_torso" and its
# waist "upper_body", while the skinned ant uses "upper_body" and "lower_body".
const PARTS: Dictionary = {
	"chest": ["upper_torso", "upper_body"],
	"waist": ["upper_body", "lower_body"],
	"abdomen": ["but_end", "backend"],
	"head": ["head"],
	"antenna_left": ["antenna_l", "antenna_left"],
	"antenna_right": ["antenna_r", "antenna_right"],
	"front_left_upper_leg": ["front_left_upper_leg"],
	"front_right_upper_leg": ["front_right_upper_leg"],
	"back_left_upper_leg": ["back_left_upper_leg"],
	"back_right_upper_leg": ["back_right_upper_leg"],
	"front_left_lower_leg": ["front_left_lower_leg"],
	"front_right_lower_leg": ["front_right_lower_leg"],
	"back_left_lower_leg": ["back_left_lower_leg"],
	"back_right_lower_leg": ["back_right_lower_leg"],
	"front_left_foot": ["front_left_foot"],
	"front_right_foot": ["front_right_foot"],
	"back_left_foot": ["back_left_foot"],
	"back_right_foot": ["back_right_foot"],
}

# The axes the motions turn around, in the ant's own space: X is left to right, Y is up
# and Z points the way the ant looks
const AXIS_X := 0
const AXIS_Y := 1
const AXIS_Z := 2

# One joint we can turn: a bone of the skeleton, or a group node of the block ant
class Joint:
	var bone: int = -1
	var node: Node3D
	var rest: Quaternion = Quaternion.IDENTITY
	var axis_x: Vector3 = Vector3.RIGHT
	var axis_y: Vector3 = Vector3.UP
	var axis_z: Vector3 = Vector3.BACK
	var offset: Quaternion = Quaternion.IDENTITY

var _ant: Node
var _skeleton: Skeleton3D
var _joints: Dictionary = {}
var _time: float = 0.0
var _walk: float = 0.0
var _walk_target: float = 0.0
var _action: String = ""

func _ready() -> void:
	_ant = get_parent()
	if disable_with_animation_player and _has_clips():
		set_process(false)
		return
	_skeleton = _find_skeleton()
	if _skeleton != null:
		_cache_bones()
	else:
		_cache_nodes()
	if _joints.is_empty():
		push_warning("AntModelAnimation: no joints found in the ant model. Set model_path or add the model under the ant.")
		set_process(false)
		return

# True as soon as the imported model brings an AnimationPlayer with clips of its own
func _has_clips() -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	var player := parent.find_child("AnimationPlayer", true, false) as AnimationPlayer
	return player != null and not player.get_animation_list().is_empty()

# The Ant3D node, when there is one, has get_current_action()
func _current_action() -> String:
	if _ant != null and _ant.has_method("get_current_action"):
		return str(_ant.get_current_action()).to_lower()
	return _action

# Called by a movement script when the ant starts or stops walking
func set_walking(walking: bool) -> void:
	_walk_target = 1.0 if walking else 0.0

func is_walking() -> bool:
	return _walk_target > 0.0

# For use without an Ant3D above this node (the previews, for example)
func set_action(action: String) -> void:
	_action = action.to_lower()

# ---- Finding the joints ----

# A skinned model brings a skeleton; a model of loose parts does not
func _find_skeleton() -> Skeleton3D:
	var search := _search_root()
	if search == null:
		return null
	var found := search.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Skeleton3D

# Where to look for the model: the node the user pointed at, or the ant above this script
func _search_root() -> Node:
	if not model_path.is_empty():
		var chosen := get_node_or_null(model_path)
		if chosen != null:
			return chosen
	return get_parent()

# The bones of the skinned ant, with the swings turned into each bone's own space: a bone
# points along its own Y axis, so "turn around X" only means a forward swing once the
# axis is expressed the way that bone is oriented
func _cache_bones() -> void:
	var taken := {}
	for part in PARTS:
		for candidate in PARTS[part]:
			if taken.has(candidate):
				continue
			var index := _skeleton.find_bone(candidate)
			if index < 0:
				continue
			taken[candidate] = true
			var joint := Joint.new()
			joint.bone = index
			joint.rest = _skeleton.get_bone_rest(index).basis.get_rotation_quaternion()
			# A rest basis is orthonormal, so the transpose is its inverse
			var inverse: Basis = _skeleton.get_bone_global_rest(index).basis.transposed()
			joint.axis_x = (inverse * Vector3.RIGHT).normalized()
			joint.axis_y = (inverse * Vector3.UP).normalized()
			joint.axis_z = (inverse * Vector3.BACK).normalized()
			_joints[part] = joint
			break

# The group nodes of the block ant, which are turned around their own axes
func _cache_nodes() -> void:
	var root := _find_model_root()
	if root == null:
		return
	var taken := {}
	for part in PARTS:
		for candidate in PARTS[part]:
			if taken.has(candidate):
				continue
			var node := _find_part_node(root, candidate)
			if node == null:
				continue
			taken[candidate] = true
			var joint := Joint.new()
			joint.node = node
			joint.rest = node.quaternion
			_joints[part] = joint
			break

func _find_model_root() -> Node3D:
	var search := _search_root()
	if search == null:
		return null
	var named := search.find_child("ant_root", true, false) as Node3D
	if named != null:
		return named
	for child in search.get_children():
		if child is Node3D and not child.find_children("*", "MeshInstance3D", true, false).is_empty():
			return child as Node3D
	return null

# The group node and its mesh often share a name. The importer may add "@2" to one of
# them, so match the start of the name and take the one that has children (the group).
func _find_part_node(root: Node3D, part_name: String) -> Node3D:
	for node in root.find_children("*", "Node3D", true, false):
		var node_name := String(node.name)
		if node_name != part_name and not node_name.begins_with(part_name + "@"):
			continue
		if node.get_child_count() > 0:
			return node as Node3D
	return null

# ---- Per frame ----

func _process(delta: float) -> void:
	_time += delta * idle_speed
	_walk = move_toward(_walk, _walk_target, walk_blend_speed * delta)

	_idle_motion()
	if _walk > 0.001:
		_walk_motion(_walk)
	match _current_action():
		"dig":
			_dig_motion()
		"carry":
			_carry_motion()
		"defend":
			_defend_motion()
	_apply_pose()

# ---- Motions ----

# Breathing, a slow look around, a bit of leg tapping and feelers sweeping
func _idle_motion() -> void:
	var t := _time
	var breathe := sin(t * 1.6)
	_rotate("chest", AXIS_X, 0.012 * breathe)
	_rotate("waist", AXIS_X, 0.008 * sin(t * 1.6 + 0.5))
	_rotate("head", AXIS_X, 0.016 * sin(t * 1.6 + 0.7))
	_rotate("head", AXIS_Y, 0.055 * sin(t * 0.45))
	_rotate("abdomen", AXIS_X, 0.02 * sin(t * 1.2 + 1.4))
	_rotate("front_left_upper_leg", AXIS_X, 0.02 * sin(t * 2.1))
	_rotate("front_right_upper_leg", AXIS_X, 0.02 * sin(t * 2.1 + PI))
	_rotate("antenna_left", AXIS_Y, 0.05 * sin(t * 0.9))
	_rotate("antenna_right", AXIS_Y, 0.05 * sin(t * 0.9 + 1.1))

# Alternating pairs: front left with back right, front right with back left. Each leg is
# swung forward through the air with the knee bent, then plants and pushes the body along,
# which is what makes it a step instead of a shuffle.
const WALK_HIP_SWING := 0.65
const WALK_KNEE_LIFT := 0.75
# How far the ant covers on the ground in one full step with the swing above, in world
# units. Ant3D uses this to run the legs at the speed the ant really walks, so the feet do
# not slide over the grass while the body moves.
const WALK_STRIDE := 0.155

func _walk_motion(blend: float) -> void:
	var p := _time * walk_speed
	# Front and back legs on the same side lift by bending the knee the other way round,
	# because their joints rest mirrored
	_step_leg("front_left", p, -1.0, blend)
	_step_leg("back_right", p, 1.0, blend)
	_step_leg("front_right", p + PI, -1.0, blend)
	_step_leg("back_left", p + PI, 1.0, blend)
	# Body roll and a small bounce, twice per step
	_rotate("chest", AXIS_Z, 0.025 * sin(p))
	_rotate("chest", AXIS_X, 0.015 * sin(p * 2.0))
	_rotate("head", AXIS_Y, 0.05 * sin(p))
	_rotate("abdomen", AXIS_Z, 0.04 * sin(p))
	_rotate("antenna_left", AXIS_Y, 0.08 * sin(p * 0.5))
	_rotate("antenna_right", AXIS_Y, 0.08 * sin(p * 0.5 + 1.1))

# One leg of the walk cycle. The hip sweeps from the back of the step (phase 0) through the
# air to the front (phase PI) and back along the ground, while the knee only bends during
# the part where the foot is off the ground.
func _step_leg(prefix: String, phase: float, knee_direction: float, blend: float) -> void:
	var hip := WALK_HIP_SWING * cos(phase) * blend
	var knee := knee_direction * WALK_KNEE_LIFT * maxf(sin(phase), 0.0) * blend
	_rotate(prefix + "_upper_leg", AXIS_X, hip)
	_rotate(prefix + "_lower_leg", AXIS_X, knee)
	# The foot keeps its angle to the ground, so it lands flat instead of on its toes
	_rotate(prefix + "_foot", AXIS_X, -(hip + knee))

# Front legs scrape at the ground, the head follows the work
func _dig_motion() -> void:
	var t := _time * 9.0
	_rotate("chest", AXIS_X, -0.05)
	_rotate("head", AXIS_X, -0.03 + 0.05 * sin(t))
	_rotate("front_left_upper_leg", AXIS_X, 0.30 * sin(t))
	_rotate("front_right_upper_leg", AXIS_X, 0.30 * sin(t + PI))
	_rotate("front_left_lower_leg", AXIS_X, 0.18 * sin(t + 0.6))
	_rotate("front_right_lower_leg", AXIS_X, 0.18 * sin(t + PI + 0.6))

# Standing a bit taller, holding something up
func _carry_motion() -> void:
	var t := _time
	_rotate("chest", AXIS_X, 0.04)
	_rotate("head", AXIS_X, -0.03 + 0.02 * sin(t * 1.6))
	_rotate("abdomen", AXIS_X, -0.03)
	_rotate("waist", AXIS_Z, 0.02 * sin(t * 1.2))

# Head up, front legs raised, ready to push back
func _defend_motion() -> void:
	var t := _time * 2.2
	_rotate("chest", AXIS_X, 0.07)
	_rotate("head", AXIS_X, 0.05)
	_rotate("front_left_upper_leg", AXIS_X, -0.32 + 0.04 * sin(t))
	_rotate("front_right_upper_leg", AXIS_X, -0.32 + 0.04 * sin(t + PI))
	_rotate("front_left_lower_leg", AXIS_X, 0.12)
	_rotate("front_right_lower_leg", AXIS_X, 0.12)

# ---- Pose helpers ----

# Adds a rotation around one of the ant's own axes, on top of the rest pose
func _rotate(part: String, axis: int, angle: float) -> void:
	var joint: Joint = _joints.get(part)
	if joint == null:
		return
	var turn := joint.axis_x
	if axis == AXIS_Y:
		turn = joint.axis_y
	elif axis == AXIS_Z:
		turn = joint.axis_z
	joint.offset = joint.offset * Quaternion(turn, angle)

func _apply_pose() -> void:
	for part in _joints:
		var joint: Joint = _joints[part]
		var wanted := joint.rest * joint.offset
		if joint.bone >= 0:
			_skeleton.set_bone_pose_rotation(joint.bone, wanted)
		elif joint.node != null:
			joint.node.quaternion = wanted
		joint.offset = Quaternion.IDENTITY
