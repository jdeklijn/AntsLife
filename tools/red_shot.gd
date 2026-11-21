extends Node

# Temporary: check the view around the field with the rock roof gone.

func shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tools/shot_%s.png" % name)

func _ready() -> void:
	var scene: Node = load("res://scenes/level/playfield.tscn").instantiate()
	add_child(scene)
	await get_tree().process_frame
	await get_tree().process_frame

	var view := get_tree().get_first_node_in_group("level_view")
	view.dig_cells([Vector3i(8, 19, 0), Vector3i(9, 19, 0), Vector3i(10, 19, 0),
		Vector3i(8, 18, 0), Vector3i(9, 18, 0), Vector3i(10, 18, 0),
		Vector3i(8, 17, 0), Vector3i(9, 17, 0),
		Vector3i(10, 18, 1), Vector3i(10, 17, 1), Vector3i(10, 18, 2)])
	scene.get_node("Camera3D").set_process(false)

	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 20.0
	cam.make_current()

	# The game's own start view, before switching to the close-up cameras
	scene.get_node("Camera3D").make_current()
	await shot("start")
	cam.make_current()

	cam.position = Vector3(10.4, 17.8, 51.3)
	cam.look_at(Vector3(10.4, 17.8, 0.0))
	await shot("window")

	cam.position = Vector3(10.4, 2.0, 51.3)
	cam.look_at(Vector3(10.4, 8.0, 0.0))
	await shot("deep")

	cam.position = Vector3(10.0, -40.0, -10.0)
	cam.look_at(Vector3(10.0, 0.0, -10.0))
	await shot("bottom")

	cam.position = Vector3(10.0, 30.0, -10.0)
	cam.look_at(Vector3(10.0, 0.0, -10.0))
	await shot("top")
	get_tree().quit()
