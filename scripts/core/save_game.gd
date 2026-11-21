extends Node

# Stores the dug-out level and the colony stockpile, so a hole stays a hole after a
# restart. The level is saved as its whole cell grid: one byte per cell, exactly the data
# the level view draws. There is no separate list of dug blocks that could get out of
# sync with the terrain.
#
# Saving happens shortly after every change (so a drag of twenty blocks is written once)
# and immediately from the Save button. The file is written next to the old one first and
# then swapped in, so a crash while saving cannot leave a half-written colony behind.

const SAVE_DIR := "user://saves"
const SAVE_PATH := "user://saves/colony.save"
const SAVE_VERSION := 1
# Wait this long after the last change before writing
const AUTOSAVE_DELAY_MSEC := 600

signal saved

var _save_at_msec: int = 0

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

# Asks for a save in a moment. Calling it again before the moment only moves the moment,
# so a burst of changes writes one file.
func request_save() -> void:
	_save_at_msec = Time.get_ticks_msec() + AUTOSAVE_DELAY_MSEC

func _process(_delta: float) -> void:
	# Real time, not game time: a save still happens while the game is paused
	if _save_at_msec == 0 or Time.get_ticks_msec() < _save_at_msec:
		return
	_save_at_msec = 0
	save_now()

func save_now() -> bool:
	var level := _scene_level()
	if level == null:
		return false
	var data := {
		"version": SAVE_VERSION,
		"size": level.size,
		"surface_y": level.surface_y,
		"cells": level.cells,
		"forbidden": level.forbidden_cells,
		"resources": Colony.to_dict(),
	}
	var directory := ProjectSettings.globalize_path(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var temporary := ProjectSettings.globalize_path(SAVE_PATH + ".tmp")
	var target := ProjectSettings.globalize_path(SAVE_PATH)
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		push_warning("SaveGame: could not write %s" % temporary)
		return false
	file.store_var(data)
	file.close()
	if FileAccess.file_exists(target):
		DirAccess.remove_absolute(target)
	if DirAccess.rename_absolute(temporary, target) != OK:
		push_warning("SaveGame: could not replace the save file")
		return false
	saved.emit()
	return true

# The saved level, or null when there is no save yet. Loading also restores the colony
# stockpile, so the resource panel shows the amounts that belong to the terrain.
func load_level() -> LevelData:
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return null
	var data = file.get_var()
	file.close()
	if not (data is Dictionary):
		push_warning("SaveGame: the save file is not a colony")
		return null
	var saved_data: Dictionary = data
	if int(saved_data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveGame: the save file has another version")
		return null
	var saved_size = saved_data.get("size")
	if not (saved_size is Vector3i):
		return null
	var size: Vector3i = saved_size
	if size.x <= 0 or size.y <= 0 or size.z <= 0:
		return null
	var level := LevelData.new(size)
	level.surface_y = clampi(int(saved_data.get("surface_y", size.y - 1)), 0, size.y - 1)
	var expected := size.x * size.y * size.z
	var cells = saved_data.get("cells")
	if cells is PackedByteArray and cells.size() == expected:
		level.cells = cells
	var forbidden = saved_data.get("forbidden")
	if forbidden is PackedByteArray and forbidden.size() == expected:
		level.forbidden_cells = forbidden
	var resources = saved_data.get("resources")
	if resources is Dictionary:
		Colony.from_dict(resources)
	return level

func delete_save() -> void:
	if not has_save():
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# The level the level view is drawing, found through its group so a save never needs a
# hard reference to the scene
func _scene_level() -> LevelData:
	if not is_inside_tree():
		return null
	var view := get_tree().get_first_node_in_group("level_view")
	if view == null:
		return null
	var level = view.get("level")
	return level if level is LevelData else null
