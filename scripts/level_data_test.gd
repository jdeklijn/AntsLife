@tool
extends EditorScript

func _run() -> void:
	var level := Level01.build()
	var soil := level.cells.count(LevelData.Cell.SOIL)
	var empty := level.cells.count(LevelData.Cell.EMPTY)
	print("Total: ", level.cells.size(), " soil: ", soil, " empty: ", empty)
