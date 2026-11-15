class_name AntModelAnimation
extends Node

# Procedural animation for the block ant (ant_v3_compleet).
#
# That model has no Skeleton3D and no AnimationPlayer: it is a tree of loose block parts
# (lower_torso, upper_torso, head, four upper/lower legs, ...). So instead of playing clips
# we turn those parts a few degrees around their own joints every frame. Small rotations
# are enough to make the ant breathe and look around, and they keep the block style.
#
# The ant in the level uses the "idle", "walk", "dig", "carry" and "defend" motions below.
# The preview in the info panel uses the same script with no Ant3D above it, so it just
# idles there.

# Leave empty to search for the model root ("ant_root") under the parent
@export var model_path: NodePath
# Once the model has real clips (made in Blockbench), those win: this script stops moving
# the joints, so it never fights the AnimationPlayer
@export var disable_with_animation_player: bool = true
# How fast the idle motion runs
@export var idle_speed: float = 1.0
# Steps per second while walking
@export var walk_speed: float = 2.6
# How quickly the ant fades between standing still and walking
@export var walk_blend_speed: float = 5.0

# The joints we move, by node name. Every one of them is a group node; the mesh with the
# same name is its child and simply follows.
const JOINTS: Array[String] = [
	"upper_torso",
	"head",
	"upper_body",
	"but_end",
	"front_left_upper_leg",
	"front_right_upper_leg",
	"back_left_upper_leg",
	"back_right_upper_leg",
	"front_left_lower_leg",
	"front_right_lower_leg",
	"back_left_lower_leg",
	"back_right_lower_leg",
]

const LOCAL_X := Vector3(1.0, 0.0, 0.0)
const LOCAL_Y := Vector3(0.0, 1.0, 0.0)
const LOCAL_Z := Vector3(0.0, 0.0, 1.0)

var _ant: Node
var _root: Node3D
var _nodes: Dictionary = {}
var _rest: Dictionary = {}
var _offset: Dictionary = {}
var _time: float = 0.0
var _walk: float = 0.0
var _walk_target: float = 0.0
var _action: String = ""

func _ready() -> void:
	_ant = get_parent()
	if disable_with_animation_player and _has_clips():
		set_process(false)
		return
	_find_root()
	if _root == null:
		push_warning("AntModelAnimation: no ant model found. Set model_path or add it under the ant.")
		set_process(false)
		return
	_cache_rest_pose()

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

# For use without an Ant3D above this node (the info panel preview, for example)
func set_action(action: String) -> void:
	_action = action.to_lower()

func _find_root() -> void:
	if not model_path.is_empty():
		_root = get_node_or_null(model_path) as Node3D
	if _root != null:
		return
	var parent := get_parent()
	if parent != null:
		# The imported glTF scene is a child of the ant; its root node is ant_root
		_root = parent.find_child("ant_root", true, false) as Node3D

func _cache_rest_pose() -> void:
	for joint_name in JOINTS:
		var node := _find_joint(joint_name)
		if node == null:
			continue
		_nodes[joint_name] = node
		_rest[joint_name] = node.quaternion

# The group node and its mesh often share a name. The importer may add "@2" to one of
# them, so match the start of the name and take the one that has children (the group).
func _find_joint(joint_name: String) -> Node3D:
	for node in _root.find_children("*", "Node3D", true, false):
		var node_name := String(node.name)
		if node_name != joint_name and not node_name.begins_with(joint_name + "@"):
			continue
		if node.get_child_count() > 0:
			return node as Node3D
	return null

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

# Breathing, a slow look around and a bit of leg tapping
func _idle_motion() -> void:
	var t := _time
	var breathe := sin(t * 1.6)
	_rotate("upper_torso", LOCAL_X, 0.012 * breathe)
	_rotate("upper_body", LOCAL_X, 0.008 * sin(t * 1.6 + 0.5))
	_rotate("head", LOCAL_X, 0.016 * sin(t * 1.6 + 0.7))
	_rotate("head", LOCAL_Y, 0.055 * sin(t * 0.45))
	_rotate("but_end", LOCAL_X, 0.02 * sin(t * 1.2 + 1.4))
	_rotate("front_left_upper_leg", LOCAL_X, 0.02 * sin(t * 2.1))
	_rotate("front_right_upper_leg", LOCAL_X, 0.02 * sin(t * 2.1 + PI))

# Alternating pairs: front left with back right, front right with back left
func _walk_motion(blend: float) -> void:
	var p := _time * walk_speed
	var a := sin(p) * blend
	var b := sin(p + PI) * blend
	_rotate("front_left_upper_leg", LOCAL_X, 0.30 * a)
	_rotate("back_right_upper_leg", LOCAL_X, 0.26 * a)
	_rotate("front_right_upper_leg", LOCAL_X, 0.30 * b)
	_rotate("back_left_upper_leg", LOCAL_X, 0.26 * b)
	# The knee follows the swing a little, so the foot does not slide over the ground
	_rotate("front_left_lower_leg", LOCAL_X, -0.16 * maxf(a, 0.0))
	_rotate("back_right_lower_leg", LOCAL_X, -0.14 * maxf(a, 0.0))
	_rotate("front_right_lower_leg", LOCAL_X, -0.16 * maxf(b, 0.0))
	_rotate("back_left_lower_leg", LOCAL_X, -0.14 * maxf(b, 0.0))
	# Body roll and a small bounce, twice per step
	_rotate("upper_torso", LOCAL_Z, 0.025 * sin(p))
	_rotate("upper_torso", LOCAL_X, 0.015 * sin(p * 2.0))
	_rotate("head", LOCAL_Y, 0.05 * sin(p))
	_rotate("but_end", LOCAL_Z, 0.04 * sin(p))

# Front legs scrape at the ground, the head follows the work
func _dig_motion() -> void:
	var t := _time * 9.0
	_rotate("upper_torso", LOCAL_X, -0.05)
	_rotate("head", LOCAL_X, -0.03 + 0.05 * sin(t))
	_rotate("front_left_upper_leg", LOCAL_X, 0.30 * sin(t))
	_rotate("front_right_upper_leg", LOCAL_X, 0.30 * sin(t + PI))
	_rotate("front_left_lower_leg", LOCAL_X, 0.18 * sin(t + 0.6))
	_rotate("front_right_lower_leg", LOCAL_X, 0.18 * sin(t + PI + 0.6))

# Standing a bit taller, holding something up
func _carry_motion() -> void:
	var t := _time
	_rotate("upper_torso", LOCAL_X, 0.04)
	_rotate("head", LOCAL_X, -0.03 + 0.02 * sin(t * 1.6))
	_rotate("but_end", LOCAL_X, -0.03)
	_rotate("upper_body", LOCAL_Z, 0.02 * sin(t * 1.2))

# Head up, front legs raised, ready to push back
func _defend_motion() -> void:
	var t := _time * 2.2
	_rotate("upper_torso", LOCAL_X, 0.07)
	_rotate("head", LOCAL_X, 0.05)
	_rotate("front_left_upper_leg", LOCAL_X, -0.32 + 0.04 * sin(t))
	_rotate("front_right_upper_leg", LOCAL_X, -0.32 + 0.04 * sin(t + PI))
	_rotate("front_left_lower_leg", LOCAL_X, 0.12)
	_rotate("front_right_lower_leg", LOCAL_X, 0.12)

# ---- Pose helpers ----

# Adds a rotation around one of the joint's own axes, on top of the rest pose
func _rotate(joint_name: String, axis: Vector3, angle: float) -> void:
	if not _nodes.has(joint_name):
		return
	var current: Quaternion = _offset.get(joint_name, Quaternion.IDENTITY)
	_offset[joint_name] = current * Quaternion(axis, angle)

func _apply_pose() -> void:
	for joint_name in _nodes:
		var node := _nodes[joint_name] as Node3D
		var rest: Quaternion = _rest[joint_name]
		var offset: Quaternion = _offset.get(joint_name, Quaternion.IDENTITY)
		node.quaternion = rest * offset
	_offset.clear()
