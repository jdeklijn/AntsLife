extends Node3D
 
# Sleep in de Inspector de juiste nodes in deze velden
@export var board: MeshInstance3D
@export var label: Label3D
 
# Ruimte tussen de tekst en de rand van de plank (in meters)
@export var padding: Vector2 = Vector2(0.1, 0.06)
@export var board_depth: float = 0.04
 
func _ready() -> void:
	if board == null or label == null:
		push_error("EntranceSign: wijs 'board' en 'label' toe in de Inspector.")
		return
	# Label3D bouwt zijn tekstmesh pas na het eerste frame, dus even wachten
	await get_tree().process_frame
	fit_board()
 
func fit_board() -> void:
	var text_size: Vector3 = label.get_aabb().size
	var new_mesh := BoxMesh.new()
	new_mesh.material = (board.mesh as BoxMesh).material
	new_mesh.size = Vector3(
		text_size.x + padding.x * 2.0,
		text_size.y + padding.y * 2.0,
		board_depth
	)
	board.mesh = new_mesh
