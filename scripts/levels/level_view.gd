extends TileMapLayer

# Tile source and atlas coordinates, taken from the TileSet in playfield.tscn
const SOURCE_ID := 9
const TILE_DIRT_A := Vector2i(0, 0)
const TILE_DIRT_B := Vector2i(0, 1)
const TILE_GRASS := Vector2i(0, 2)
const NO_TILE := Vector2i(-1, -1)

# Which layer of the block is shown (0 = front layer, higher = deeper)
@export var depth: int = 0

var level: LevelData

func _ready() -> void:
	level = Level01.build()
	redraw()

func redraw() -> void:
	clear()
	for y in level.size.y:
		for x in level.size.x:
			var p := Vector3i(x, y, depth)
			var tile := _tile_for(p)
			if tile != NO_TILE:
				# Screen row 0 is the top of the block, which is the highest y
				set_cell(Vector2i(x, level.size.y - 1 - y), SOURCE_ID, tile)

func _tile_for(p: Vector3i) -> Vector2i:
	# Empty cells get no tile, so the background shows through
	if level.get_cell(p) != LevelData.Cell.SOIL:
		return NO_TILE
	# The surface row is grass
	if p.y == level.surface_y:
		return TILE_GRASS
	# Pick a dirt variant from the position, so it looks the same every run
	if hash(p) % 5 == 0:
		return TILE_DIRT_B
	return TILE_DIRT_A
