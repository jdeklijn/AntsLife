@tool
class_name Level01
extends RefCounted

# Builds the first level: a block of 10 x 12 x 10 cells.
# Rows y = 0..9 are soil (y = 9 is the grass surface), rows y = 10..11 are open air.

const SIZE := Vector3i(10, 12, 10)
const SURFACE_Y := 9

static func build() -> LevelData:
	var level := LevelData.new(SIZE)
	level.surface_y = SURFACE_Y
	level.fill_box(Vector3i(0, 0, 0), Vector3i(SIZE.x - 1, SURFACE_Y, SIZE.z - 1), LevelData.Cell.SOIL)	
	return level
