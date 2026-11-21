@tool
class_name LevelData
extends RefCounted

# The level as pure data: a block of cells, one byte per cell.
# This is the single source of truth. Nothing here knows how it is displayed.

enum Cell { EMPTY, SOIL, ROCK }

# The six faces (sides) of the block, used for the camera views and for peeling layers
enum Face { FRONT, BACK, LEFT, RIGHT, TOP, BOTTOM }

# Width (x), height (y) and depth (z) of the block, in cells
var size: Vector3i
# The y of the top soil row (the grass). Rows above it are open air.
var surface_y: int = 0
var cells: PackedByteArray
# Cells that may not be taken away, drawn with a red edge. One flag per cell.
var forbidden_cells: PackedByteArray
# Goes up whenever a forbidden flag changes, so the level view knows to rebuild its red
# edges. Compare it with the last value you saw instead of polling every cell.
var forbidden_version: int = 0

func _init(p_size: Vector3i = Vector3i(10, 10, 10)) -> void:
	size = p_size
	cells = PackedByteArray()
	cells.resize(size.x * size.y * size.z)  # every cell starts as EMPTY (0)
	forbidden_cells = PackedByteArray()
	forbidden_cells.resize(size.x * size.y * size.z)  # every cell starts as allowed (0)

func in_bounds(p: Vector3i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.z >= 0 \
		and p.x < size.x and p.y < size.y and p.z < size.z

# Finds the level that a sibling of `node` built (the level view keeps it in `level`).
# Code that depends on the level size looks it up this way, so a level can change size
# without a constant that has to be edited in several scripts.
static func find_sibling(node: Node) -> LevelData:
	if node == null:
		return null
	var parent := node.get_parent()
	if parent == null:
		return null
	for sibling in parent.get_children():
		var level = sibling.get("level")
		if level is LevelData:
			return level
	return null

# Turns a 3D position into a position in the flat array.
# One layer (a fixed z) is size.x * size.y consecutive bytes.
func _index(p: Vector3i) -> int:
	return p.x + p.y * size.x + p.z * size.x * size.y

func get_cell(p: Vector3i) -> int:
	if not in_bounds(p):
		return Cell.EMPTY
	return cells[_index(p)]

func set_cell(p: Vector3i, type: int) -> void:
	if in_bounds(p):
		cells[_index(p)] = type

# A forbidden cell stays in the level but may not be dug away. The level view draws a
# light red edge around it, so a rule can show itself without touching the block itself.
func is_forbidden(p: Vector3i) -> bool:
	return in_bounds(p) and forbidden_cells[_index(p)] != 0

func set_forbidden(p: Vector3i, value: bool = true) -> void:
	if not in_bounds(p):
		return
	var index := _index(p)
	var flag := 1 if value else 0
	if forbidden_cells[index] == flag:
		return
	forbidden_cells[index] = flag
	forbidden_version += 1

# Sets every cell in the box from..to (both corners included)
func fill_box(from: Vector3i, to: Vector3i, type: int) -> void:
	for z in range(from.z, to.z + 1):
		for y in range(from.y, to.y + 1):
			for x in range(from.x, to.x + 1):
				set_cell(Vector3i(x, y, z), type)

# ---- Digging ----

const NEIGHBOURS: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]

# True when at least one side of the cell is open: air, or outside the block. Digging is
# only allowed there, so no invisible hole can appear inside solid ground and every dug
# cell stays visible from the side the camera looks from.
func has_open_neighbour(p: Vector3i) -> bool:
	for dir in NEIGHBOURS:
		if not in_bounds(p + dir) or get_cell(p + dir) == Cell.EMPTY:
			return true
	return false

# A cell may be dug when it is solid, not marked as forbidden, and reaches open air
func can_dig(p: Vector3i) -> bool:
	return in_bounds(p) and get_cell(p) != Cell.EMPTY \
		and not is_forbidden(p) and has_open_neighbour(p)

# Takes one block out of the level. Returns false when the block may not be dug.
func dig(p: Vector3i) -> bool:
	if not can_dig(p):
		return false
	set_cell(p, Cell.EMPTY)
	return true
