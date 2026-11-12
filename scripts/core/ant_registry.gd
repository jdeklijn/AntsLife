extends Node

# Central list of every ant in the game and the action it is doing. Other systems can
# ask for the ants without walking the scene tree, and the info panel can rename one.
#
# State lives on the ant itself (ant_name and current_action); this node mirrors it so
# there is one place to look them all up.

signal ant_registered(ant: Node)
signal ant_unregistered(ant: Node)
signal ant_changed(ant: Node)   # the name or the action of this ant changed

var _ants: Array[Node] = []
var _names: Dictionary = {}     # ant -> String
var _actions: Dictionary = {}   # ant -> String ("" means idle)

func register(ant: Node) -> void:
	if _ants.has(ant):
		return
	_ants.append(ant)
	_names[ant] = str(ant.call("get_ant_name")) if ant.has_method("get_ant_name") else str(ant.name)
	_actions[ant] = str(ant.call("get_current_action")) if ant.has_method("get_current_action") else ""
	ant_registered.emit(ant)

func unregister(ant: Node) -> void:
	if not _ants.has(ant):
		return
	_ants.erase(ant)
	_names.erase(ant)
	_actions.erase(ant)
	ant_unregistered.emit(ant)

func get_ants() -> Array[Node]:
	var copy: Array[Node] = []
	copy.append_array(_ants)
	return copy

func count() -> int:
	return _ants.size()

func get_ant_name(ant: Node) -> String:
	return str(_names.get(ant, ""))

func get_action(ant: Node) -> String:
	return str(_actions.get(ant, ""))

func get_actions() -> Dictionary:
	return _actions.duplicate()

# One entry per ant: { "ant": Node, "name": String, "action": String }
func snapshot() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for ant in _ants:
		entries.append({
			"ant": ant,
			"name": str(_names.get(ant, "")),
			"action": str(_actions.get(ant, "")),
		})
	return entries

func set_ant_name(ant: Node, new_name: String) -> void:
	if not _ants.has(ant):
		return
	_names[ant] = new_name
	ant_changed.emit(ant)

func set_action(ant: Node, action: String) -> void:
	if not _ants.has(ant):
		return
	_actions[ant] = action
	ant_changed.emit(ant)
