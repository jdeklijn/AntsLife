@tool
class_name Level01
extends RefCounted

# Builds the first level: a block of 20 x 22 x 20 cells.
# The top AIR_ROWS rows stay open air; the row below them is the grass surface.

const SIZE := Vector3i(20, 22, 20)
# Open rows above the grass, so the ants and the camera have room
const AIR_ROWS := 2

# The y of the grass row. Everything above it is air.
static func surface_y() -> int:
	return SIZE.y - 1 - AIR_ROWS

static func build() -> LevelData:
	var level := LevelData.new(SIZE)
	level.surface_y = surface_y()
	level.fill_box(Vector3i(0, 0, 0), Vector3i(SIZE.x - 1, level.surface_y, SIZE.z - 1), LevelData.Cell.SOIL)
	return level
