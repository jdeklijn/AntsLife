class_name AntAction
extends Resource

# Describes an action an ant can be given, plus the requirements to be allowed to do it.

@export var id: StringName
@export var label: String = ""
@export var icon: Texture2D
@export var min_level: int = 1
@export var required_tool: String = ""
# Empty = every category may do this action
@export var allowed_categories: Array[String] = []
