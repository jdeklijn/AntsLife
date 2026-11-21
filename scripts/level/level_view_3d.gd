extends MeshInstance3D

const Face = LevelData.Face

const DEFAULT_GRANITE := preload("res://assets/world/textures/granite.png")

# Drag the textures into these fields in the Inspector
@export var grass_texture: Texture2D
@export var dirt_texture: Texture2D
# The rock the playfield is embedded in. The blocks around the level are real granite
# blocks; further out the backdrop continues the same rock.
@export var granite_texture: Texture2D = DEFAULT_GRANITE
# How many blocks of granite surround the playfield on every side. The blocks never lie
# inside the playfield, so they are outside the level data and can never be dug away.
@export_range(1, 8, 1) var granite_thickness: int = 2
# How many blocks one granite texture covers. 1 matches the rock of the backdrop, so the
# blocks around the level and the plain behind them read as one mass of stone.
@export_range(0.5, 4.0, 0.25) var granite_tile_blocks: float = 1.0

# The mine look of the tunnels the player digs. These textures are only used on block
# faces that touch a dug-out (empty) cell, so the untouched field keeps grass and dirt.
# The wall texture is for the sides of a tunnel, the floor texture for the block below a
# hole and the ceiling texture for the block above it.
const DEFAULT_WALL := preload("res://assets/ui/levels/walls/wall_basic.png")
const DEFAULT_FLOOR := preload("res://assets/ui/levels/walls/floor_basic.png")
const DEFAULT_CEILING := preload("res://assets/ui/levels/walls/ceiling_basic.png")
@export var wall_texture: Texture2D = DEFAULT_WALL
@export var floor_texture: Texture2D = DEFAULT_FLOOR
@export var ceiling_texture: Texture2D = DEFAULT_CEILING
# How many blocks one mine texture covers. The wall image carries two panels in each
# direction, so 4 makes every panel two blocks wide and the wooden frames read as support
# beams at intervals instead of a grid on every block. The floor and ceiling keep the
# finer 2-block scale.
@export_range(0.5, 4.0, 0.25) var mine_wall_tile_blocks: float = 4.0
@export_range(0.5, 4.0, 0.25) var mine_floor_tile_blocks: float = 2.0
# The ceilings point their faces down and would otherwise use the very dark bottom
# shade. A tunnel needs to stay readable, so they get their own brightness.
const SHADE_CEILING := 0.6

# The cut face of the rock: one flat cross-section exactly in the plane where the granite
# was cut away. It fills the view around the field from edge to edge, so the underground
# reads as a 2D playing field set in stone instead of a cavern with a far wall and a
# horizon. It reaches far past the playfield and has a hole exactly over it, so the soil
# stays visible. Like the granite shell it moves with the cut, so it keeps its parallax.
const CROSS_SECTION_PUSH := 0.01
# How far the cross-section reaches past the playfield, as a multiple of its largest side
const CROSS_SECTION_REACH := 3.0

# ---- Cursor around the block under the mouse ----
# Color of the outline around the block the mouse points at
@export var cursor_color: Color = Color(1.0, 0.95, 0.65, 0.95)
# Color of the outline around a forbidden block; the cursor takes this color as well
@export var forbidden_color: Color = Color(1.0, 0.38, 0.32, 0.95)
# Thickness of the outline, as a fraction of a face (0.05 is 5% of the block)
@export_range(0.01, 0.25, 0.01) var cursor_edge_width: float = 0.06
# How many blocks one grass texture covers. 1 draws the whole texture on every block, so
# the same tufts repeat on a strict grid and the field starts to shimmer. 2 makes the
# grass twice as large and repeats it only every two blocks.
@export_range(0.5, 4.0, 0.25) var grass_tile_blocks: float = 2.0

# Night colour of the blocks. The blocks are unshaded, so they cannot follow the sun;
# the day/night clock fades this colour in over them instead, in step with the plain.
@export var night_tint: Color = Color(0.35, 0.40, 0.55)

# Brightness of a face, depending on the way it points (1.0 = full brightness).
# "Front" is the side nearest to the starting camera. Change these to taste.
const SHADE_FRONT := 1.0
const SHADE_SIDE := 0.5    # left and right
const SHADE_BACK := 0.3
const SHADE_TOP := 1.0
const SHADE_BOTTOM := 0.1

# A switched-off layer is hidden completely: its blocks are simply not drawn. The layer
# behind it then shows its own faces, so it looks like the layer was taken away.

# Each face of a cell: the neighbouring cell that would hide it, its outward normal
# (world space) and its four corners as seen from outside: bottom-left, top-left,
# top-right, bottom-right (clockwise, which is what Godot treats as the front).
# World z is the negative of the cell z, so layer z = 0 is the one nearest to a
# camera that looks along -z from the positive side (the "front").
const FACES := [
	{ "dir": Vector3i(0, 1, 0), "normal": Vector3(0, 1, 0),
		"corners": [Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1)] },
	{ "dir": Vector3i(0, -1, 0), "normal": Vector3(0, -1, 0),
		"corners": [Vector3(1, 0, 1), Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1)] },
	{ "dir": Vector3i(0, 0, -1), "normal": Vector3(0, 0, 1),
		"corners": [Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1)] },
	{ "dir": Vector3i(0, 0, 1), "normal": Vector3(0, 0, -1),
		"corners": [Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0)] },
	{ "dir": Vector3i(1, 0, 0), "normal": Vector3(1, 0, 0),
		"corners": [Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0)] },
	{ "dir": Vector3i(-1, 0, 0), "normal": Vector3(-1, 0, 0),
		"corners": [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1)] },
]

# Texture coordinates for the four corners, in the same order as above
const UVS := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
# A quad is two triangles
const TRIANGLE_INDICES := [0, 1, 2, 0, 2, 3]

# The mesh has six surfaces: grass, dirt, granite and the three mine textures
const SURFACE_GRASS := 0
const SURFACE_DIRT := 1
const SURFACE_GRANITE := 2
const SURFACE_WALL := 3
const SURFACE_FLOOR := 4
const SURFACE_CEILING := 5
const SURFACE_COUNT := 6

# Draws the texture on each face and scales its brightness by the direction the face
# points in. It is unshaded on purpose: the brightness comes only from the values above,
# not from the lights in the scene.
const BLOCK_SHADER_CODE := """
shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float shade_front = 1.0;
uniform float shade_side = 0.82;
uniform float shade_back = 0.62;
uniform float shade_top = 1.0;
uniform float shade_bottom = 0.5;
// Multiplied over the whole block. The day/night clock uses it to darken the blocks
// along with the plain and the grass, which are unshaded as well.
uniform vec4 tint : source_color = vec4(1.0);

varying vec3 model_normal;

void vertex() {
	model_normal = NORMAL;
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;

	float shade = shade_side;
	if (model_normal.z > 0.5) {
		shade = shade_front;
	} else if (model_normal.z < -0.5) {
		shade = shade_back;
	} else if (model_normal.y > 0.5) {
		shade = shade_top;
	} else if (model_normal.y < -0.5) {
		shade = shade_bottom;
	}

	ALBEDO = tex * shade * tint.rgb;
}
"""

# The outline around the block under the mouse (and around forbidden blocks). It is drawn
# as one quad per visible face of the cell, a hair in front of the face, transparent
# except for a band along the face's four edges. Because it uses the same face geometry
# as the terrain, the band lines up with the block exactly.
const CURSOR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.65, 0.95);
uniform float edge_width = 0.06;

void fragment() {
	vec2 d = min(UV, vec2(1.0) - UV);
	float edge = 1.0 - smoothstep(0.0, edge_width, min(d.x, d.y));
	ALBEDO = edge_color.rgb;
	ALPHA = edge_color.a * edge;
}
"""

# How far the outline floats in front of a block face, so the depth test keeps it visible
const OVERLAY_PUSH := 0.003

# The row of blocks the dig tool has selected. Orange, so it stands apart from the pale
# outline that follows the mouse.
const DIG_SELECTION_COLOR := Color(1.0, 0.62, 0.18, 0.95)

var level: LevelData
var _shader: Shader  # one shader for all block materials
var _materials: Array[ShaderMaterial] = []  # all block materials, for the night tint
var _tint: Color = Color.WHITE
var _peeled := {}  # face -> number of switched-off layers, counted from that face inwards

# The cell under the mouse, or NO_CELL when the mouse points at nothing solid. Digging
# and other cell tools can read this without doing their own ray.
const NO_CELL := Vector3i(-1, -1, -1)
var hovered_cell: Vector3i = NO_CELL
# Emitted whenever the mouse moves to another block, so tools can update their own preview
signal hover_changed(cell: Vector3i)
# Emitted after the mesh has been rebuilt, so decorations (grass tufts) can follow it
signal rebuilt
# The top cells of the grass row that are drawn as solid grass. Decorations read this
# instead of walking the whole level themselves.
var grass_cells: Array[Vector3i] = []

var _cursor: MeshInstance3D
var _cursor_material: ShaderMaterial
var _cursor_shader: Shader
var _cursor_is_forbidden: bool = false
var _forbidden_overlay: MeshInstance3D
var _forbidden_version: int = -1
# The orange row of blocks the dig tool has selected while the mouse button is held
var _dig_overlay: MeshInstance3D
var _dig_preview_active: bool = false
# The side of the playfield the camera looks from. The granite there is left out, so the
# soil stays visible from every view. (0, 0, 0) means nothing is cut away.
var _granite_cut: Vector3i = Vector3i.ZERO

func _ready() -> void:
	# The save system finds the level through this group
	add_to_group("level_view")
	for face in Face.values():
		_peeled[face] = 0
	# For testing, every start of the level is a fresh field with an empty stockpile,
	# so all the ground that was dug away comes back. The save code is still here for
	# later; only loading it on start is switched off.
	level = Level01.build()
	Colony.reset()
	_granite_cut = _camera_cut()
	rebuild()
	_make_cursor()
	# The HUD may not be ready yet, so connect to it a moment later
	_connect_hud.call_deferred()

func _connect_hud() -> void:
	var hud := get_tree().get_first_node_in_group("layer_hud")
	if hud == null:
		push_warning("LevelView3D: no layer HUD found, layers cannot be switched off.")
		return
	hud.connect("layers_changed", _on_layers_changed)

func _on_layers_changed(peeled: Dictionary) -> void:
	_peeled = peeled
	# The visible faces may have moved, so both outlines have to be built again
	hovered_cell = NO_CELL
	_forbidden_version = -1
	rebuild()

func _process(_delta: float) -> void:
	var cut := _camera_cut()
	if cut != _granite_cut:
		_granite_cut = cut
		rebuild()
	_update_grass_visibility()
	_update_cursor()
	_update_forbidden()

# The tufts stand up from the grass surface. Seen from below they would hang in the sky
# over the field, so they only show while the camera is above the surface.
func _update_grass_visibility() -> void:
	if level == null:
		return
	var grass := get_node_or_null("Grass") as Node3D
	var camera := get_viewport().get_camera_3d()
	if grass == null or camera == null:
		return
	grass.visible = camera.global_position.y >= float(level.surface_y + 1)

# ---- Cursor around the block under the mouse ----

func _make_cursor() -> void:
	_cursor = MeshInstance3D.new()
	_cursor.name = "BlockCursor"
	_cursor_material = _make_cursor_material(cursor_color)
	_cursor.material_override = _cursor_material
	_cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cursor.visible = false
	add_child(_cursor)

	_forbidden_overlay = MeshInstance3D.new()
	_forbidden_overlay.name = "ForbiddenBlocks"
	_forbidden_overlay.material_override = _make_cursor_material(forbidden_color)
	_forbidden_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_forbidden_overlay.visible = false
	add_child(_forbidden_overlay)

	# The row the dig tool selects while the mouse button is held
	_dig_overlay = MeshInstance3D.new()
	_dig_overlay.name = "DigSelection"
	_dig_overlay.material_override = _make_cursor_material(DIG_SELECTION_COLOR)
	_dig_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_dig_overlay.visible = false
	add_child(_dig_overlay)

func _make_cursor_material(color: Color) -> ShaderMaterial:
	if _cursor_shader == null:
		_cursor_shader = Shader.new()
		_cursor_shader.code = CURSOR_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _cursor_shader
	material.set_shader_parameter("edge_color", color)
	material.set_shader_parameter("edge_width", cursor_edge_width)
	return material

# Moves the outline to the block under the mouse. A click on the HUD panels does not
# count, so the outline only appears over the field itself. While a dig selection is
# being dragged, the orange row takes over and the pale outline stays out of the way.
func _update_cursor() -> void:
	if _cursor == null or level == null:
		return
	if _dig_preview_active:
		_cursor.visible = false
		return
	var viewport := get_viewport()
	var mouse := viewport.get_mouse_position()
	var camera := viewport.get_camera_3d()
	var cell := NO_CELL
	if camera != null and viewport.get_visible_rect().has_point(mouse) \
			and viewport.gui_get_hovered_control() == null:
		cell = _ray_cell(camera, mouse)
	if cell == hovered_cell:
		return
	hovered_cell = cell
	var mesh: ArrayMesh = _build_face_overlay([cell]) if cell != NO_CELL else null
	_cursor.mesh = mesh
	_cursor.visible = mesh != null
	if mesh != null:
		var forbidden := level.is_forbidden(cell)
		if forbidden != _cursor_is_forbidden:
			_cursor_is_forbidden = forbidden
			_cursor_material.set_shader_parameter("edge_color",
				forbidden_color if forbidden else cursor_color)
	hover_changed.emit(cell)

# One slightly raised quad per face of the given cells that is open to the air, with the
# same corners and UVs as the terrain. That gives a border around every visible face of
# the block, also where it meets a neighbouring block.
func _build_face_overlay(cells: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	for cell in cells:
		var origin := Vector3(cell.x, cell.y, -cell.z - 1)
		for face in FACES:
			var dir: Vector3i = face["dir"]
			if _is_block(cell + dir):
				continue
			_add_quad(st, origin, face, OVERLAY_PUSH)
			quads += 1
	if quads == 0:
		return null
	return st.commit()

# Draws the first solid cell that the ray from the camera through the mouse enters.
# It steps cell by cell (Amanatides & Woo), so it also works on the side walls and
# through hidden (switched-off) layers. World z is mirrored, hence the flip below.
func _ray_cell(camera: Camera3D, mouse: Vector2) -> Vector3i:
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var o := Vector3(origin.x, origin.y, -origin.z)
	var d := Vector3(direction.x, direction.y, -direction.z)
	if d.length_squared() < 0.000001:
		return NO_CELL
	d = d.normalized()
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	if _is_block(cell):
		return cell if _is_solid(cell) else NO_CELL
	var step := Vector3i(_step_axis(d.x), _step_axis(d.y), _step_axis(d.z))
	var t_max := Vector3(
		_boundary_distance(o.x, d.x, cell.x, step.x),
		_boundary_distance(o.y, d.y, cell.y, step.y),
		_boundary_distance(o.z, d.z, cell.z, step.z))
	var t_delta := Vector3(
		_delta_distance(d.x), _delta_distance(d.y), _delta_distance(d.z))
	# Enough steps to cross the level from any side, even from far outside
	for i in 512:
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t_max.y += t_delta.y
		else:
			cell.z += step.z
			t_max.z += t_delta.z
		if _is_block(cell):
			# Granite stops the ray, so the cursor does not reach into the rock behind the
			# playfield. It is not part of the level, so it cannot be dug away either.
			return cell if _is_solid(cell) else NO_CELL
		if _past_level(cell, step):
			break
	return NO_CELL

func _step_axis(value: float) -> int:
	if value > 0.0:
		return 1
	if value < 0.0:
		return -1
	return 0

# Distance along the ray to the next cell boundary on this axis (INF when it never crosses)
func _boundary_distance(origin: float, direction: float, cell: int, step: int) -> float:
	if step == 0:
		return INF
	var boundary := float(cell + (1 if step > 0 else 0))
	return (boundary - origin) / direction

# How far the ray travels for every cell it crosses on this axis
func _delta_distance(direction: float) -> float:
	return absf(1.0 / direction) if absf(direction) > 0.000001 else INF

# True when the ray has left the granite around the level on an axis and is heading
# further away, so it can never come back in
func _past_level(cell: Vector3i, step: Vector3i) -> bool:
	var low := -granite_thickness
	var high_x := level.size.x - 1 + granite_thickness
	var high_z := level.size.z - 1 + granite_thickness
	return (cell.x < low and step.x <= 0) or (cell.x > high_x and step.x >= 0) \
		or (cell.y < low and step.y <= 0) or (cell.y > level.surface_y and step.y >= 0) \
		or (cell.z < low and step.z <= 0) or (cell.z > high_z and step.z >= 0)

# ---- Digging ----

# The first level cell that the ray from the camera through this screen position enters,
# as { "cell": Vector3i, "normal": Vector3 } where the normal is the face it entered
# through. An empty dictionary means there is nothing diggable under the mouse: granite
# and switched-off layers stop the ray without a result, because they cannot be dug.
func ray_hit(camera: Camera3D, mouse: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var o := Vector3(origin.x, origin.y, -origin.z)
	var d := Vector3(direction.x, direction.y, -direction.z)
	if d.length_squared() < 0.000001:
		return {}
	d = d.normalized()
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	if _is_block(cell):
		# The camera itself is inside a block: pick the face we would see from here
		if _is_granite(cell) or not _is_solid(cell):
			return {}
		return { "cell": cell, "normal": _entry_normal(d) }
	var step := Vector3i(_step_axis(d.x), _step_axis(d.y), _step_axis(d.z))
	var t_max := Vector3(
		_boundary_distance(o.x, d.x, cell.x, step.x),
		_boundary_distance(o.y, d.y, cell.y, step.y),
		_boundary_distance(o.z, d.z, cell.z, step.z))
	var t_delta := Vector3(
		_delta_distance(d.x), _delta_distance(d.y), _delta_distance(d.z))
	# Enough steps to cross the level from any side, even from far outside
	for i in 512:
		var axis := 0
		if t_max.x < t_max.y and t_max.x < t_max.z:
			cell.x += step.x
			t_max.x += t_delta.x
		elif t_max.y < t_max.z:
			cell.y += step.y
			t_max.y += t_delta.y
			axis = 1
		else:
			cell.z += step.z
			t_max.z += t_delta.z
			axis = 2
		if _is_block(cell):
			if _is_granite(cell) or not _is_solid(cell):
				return {}
			# The face we came in through looks back along the step we just took. The ray
			# works in level space, where z runs the other way than in the world, so the
			# z of the normal has to be mirrored back.
			var normal := Vector3.ZERO
			match axis:
				0: normal.x = -float(step.x)
				1: normal.y = -float(step.y)
				_: normal.z = -float(step.z)
			normal.z = -normal.z
			return { "cell": cell, "normal": normal }
		if _past_level(cell, step):
			break
	return {}

# The face a ray enters through when it starts inside a block: the face that points back
# at the camera, on the axis the ray travels along the most. The direction is in level
# space, so the z of the normal is mirrored back to world space.
func _entry_normal(direction: Vector3) -> Vector3:
	var absolute := direction.abs()
	var normal: Vector3
	if absolute.x >= absolute.y and absolute.x >= absolute.z:
		normal = Vector3(-signf(direction.x), 0.0, 0.0)
	elif absolute.y >= absolute.z:
		normal = Vector3(0.0, -signf(direction.y), 0.0)
	else:
		normal = Vector3(0.0, 0.0, -signf(direction.z))
	normal.z = -normal.z
	return normal

# The plane of the outer surface of one face of a cell, in world space. The dig tool uses
# it to turn a dragged mouse position into blocks on that same visible face.
func face_plane(cell: Vector3i, normal: Vector3) -> Plane:
	var point := Vector3(cell.x, cell.y, -cell.z)
	if normal.z < -0.5:
		point.z -= 1.0
	elif normal.x > 0.5:
		point.x += 1.0
	elif normal.y > 0.5:
		point.y += 1.0
	return Plane(normal, normal.dot(point))

# The cell on that face under a world point. The coordinate across the face stays at the
# cell the drag started on, so a selection never jumps to another layer.
func point_to_cell_on_face(point: Vector3, start: Vector3i, normal: Vector3) -> Vector3i:
	if absf(normal.z) > 0.5:
		return Vector3i(floori(point.x), floori(point.y), start.z)
	if absf(normal.x) > 0.5:
		return Vector3i(start.x, floori(point.y), floori(-point.z))
	return Vector3i(floori(point.x), start.y, floori(-point.z))

# Shows the orange outline around the blocks the dig tool has selected
func show_dig_preview(cells: Array) -> void:
	if _dig_overlay == null:
		return
	var shown := []
	for cell in cells:
		if level.get_cell(cell) != LevelData.Cell.EMPTY and not level.is_forbidden(cell) \
			and not _is_switched_off(cell):
			shown.append(cell)
	_dig_overlay.mesh = _build_face_overlay(shown) if not shown.is_empty() else null
	_dig_overlay.visible = _dig_overlay.mesh != null
	_dig_preview_active = true
	_update_cursor()

func clear_dig_preview() -> void:
	_dig_preview_active = false
	# Force the pale outline to find the block under the mouse again
	hovered_cell = NO_CELL
	if _dig_overlay == null:
		return
	_dig_overlay.mesh = null
	_dig_overlay.visible = false

# Digs every block in the list that may be dug, then rebuilds once and adds the sand to
# the colony. Returns how many blocks really went away.
func dig_cells(cells: Array) -> int:
	var count := 0
	for cell in cells:
		# A layer that is switched off cannot be dug while it is out of sight
		if _is_switched_off(cell):
			continue
		if level.dig(cell):
			count += 1
	if count == 0:
		return 0
	hovered_cell = NO_CELL
	rebuild()
	Colony.add("sand", count)
	SaveGame.request_save()
	return count

# ---- Granite around the playfield ----

# Which side of the playfield the camera is on, as a step along one axis. The granite on
# that side is left out, so the soil is not hidden behind rock: from the front you look
# into the field, from the left you look at its left face, and so on.
func _camera_cut() -> Vector3i:
	if level == null:
		return Vector3i.ZERO
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3i.ZERO
	var forward := -camera.global_basis.z
	# Straight down: the granite already lies under the grass, nothing has to go
	if forward.y < -0.9:
		return Vector3i.ZERO
	# Straight up: open the floor, so the underside of the field stays visible
	if forward.y > 0.9:
		return Vector3i(0, -1, 0)
	var centre := Vector3(level.size.x * 0.5, level.surface_y * 0.5, -level.size.z * 0.5)
	var dir := camera.global_position - centre
	if absf(dir.x) > absf(dir.z):
		return Vector3i(1 if dir.x > 0.0 else -1, 0, 0)
	return Vector3i(0, 0, 1 if dir.z > 0.0 else -1)

# True when this granite cell lies on the camera's side of the field and is left out
func _is_cut(p: Vector3i) -> bool:
	if _granite_cut.x > 0:
		return p.x >= level.size.x
	if _granite_cut.x < 0:
		return p.x < 0
	if _granite_cut.z > 0:
		return p.z < 0
	if _granite_cut.z < 0:
		return p.z >= level.size.z
	if _granite_cut.y < 0:
		return p.y < 0
	return false

# The granite is a shell of solid rock around the level data: it never lies inside the
# playfield, so the level itself stays exactly as big as before and nothing can dig it.
func _is_granite(p: Vector3i) -> bool:
	if level == null or level.in_bounds(p):
		return false
	if p.y < -granite_thickness or p.y > level.surface_y:
		return false
	if p.x < -granite_thickness or p.x >= level.size.x + granite_thickness:
		return false
	if p.z < -granite_thickness or p.z >= level.size.z + granite_thickness:
		return false
	return not _is_cut(p)

# ---- Forbidden blocks ----

# Rebuilds the red outlines only when the level says a forbidden flag changed
func _update_forbidden() -> void:
	if _forbidden_overlay == null or level == null:
		return
	if _forbidden_version == level.forbidden_version:
		return
	_forbidden_version = level.forbidden_version
	_rebuild_forbidden()

func _rebuild_forbidden() -> void:
	var cells := []
	for z in level.size.z:
		for y in level.size.y:
			for x in level.size.x:
				var cell := Vector3i(x, y, z)
				if level.get_cell(cell) != LevelData.Cell.EMPTY and level.is_forbidden(cell):
					cells.append(cell)
	_forbidden_overlay.mesh = _build_face_overlay(cells)
	_forbidden_overlay.visible = _forbidden_overlay.mesh != null

func rebuild() -> void:
	var surface_tools: Array[SurfaceTool] = []
	var counts: Array[int] = []
	for i in SURFACE_COUNT:
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(surface_tool)
		counts.append(0)
	grass_cells.clear()

	for z in level.size.z:
		for y in level.size.y:
			for x in level.size.x:
				var p := Vector3i(x, y, z)
				if level.get_cell(p) == LevelData.Cell.EMPTY:
					continue
				# A switched-off layer is invisible: skip it completely, so the layer
				# behind it shows its own faces
				if _is_switched_off(p):
					continue
				var origin := Vector3(x, y, -z - 1)
				for face in FACES:
					var dir: Vector3i = face["dir"]
					var neighbour := p + dir
					if _is_block(neighbour):
						# A face between two solid cells can never be seen
						continue
					# Only the top of the surface row is grass
					var is_grass := dir == Vector3i(0, 1, 0) and y == level.surface_y
					var surface := SURFACE_GRASS if is_grass else SURFACE_DIRT
					var uvs: Array = _grass_uvs(p, face) if is_grass else []
					# A face that looks into a dug-out cell is a tunnel wall, floor or
					# ceiling, so it gets the mine texture
					if not is_grass and _touches_dug_cell(neighbour):
						surface = _mine_surface(dir)
						uvs = _mine_uvs(p, face, mine_wall_tile_blocks
							if surface == SURFACE_WALL else mine_floor_tile_blocks)
					_add_quad(surface_tools[surface], origin, face, 0.0, uvs)
					counts[surface] += 1
					if is_grass:
						grass_cells.append(p)

	# The granite shell around the playfield. Its top lies under the grass plain, so it is
	# never drawn; every other face that does not touch another block is.
	for z in range(-granite_thickness, level.size.z + granite_thickness):
		for y in range(-granite_thickness, level.surface_y + 1):
			for x in range(-granite_thickness, level.size.x + granite_thickness):
				var p := Vector3i(x, y, z)
				if not _is_granite(p):
					continue
				var origin := Vector3(x, y, -z - 1)
				for face in FACES:
					var dir: Vector3i = face["dir"]
					if dir == Vector3i(0, 1, 0):
						continue
					if _is_block(p + dir):
						continue
					_add_quad(surface_tools[SURFACE_GRANITE], origin, face, 0.0,
						_granite_uvs(p, face))
					counts[SURFACE_GRANITE] += 1

	# The flat rock face where the granite was cut away. It stands in for all the rock that
	# would otherwise show as a far wall with a horizon, so the underground view is stone
	# from edge to edge.
	counts[SURFACE_GRANITE] += _add_cross_section(surface_tools[SURFACE_GRANITE])

	var new_mesh := ArrayMesh.new()
	_materials.clear()
	for surface in SURFACE_COUNT:
		if counts[surface] == 0:
			continue
		var texture := _surface_texture(surface)
		if texture == null:
			texture = dirt_texture
		surface_tools[surface].set_material(_make_material(
			texture, SHADE_CEILING if surface == SURFACE_CEILING else SHADE_BOTTOM))
		surface_tools[surface].commit(new_mesh)
	mesh = new_mesh
	rebuilt.emit()

# Cells outside the block, and cells in a switched-off layer, do not count as solid.
# So the outside of the block is drawn, and so is the surface that a hidden layer uncovers.
func _is_solid(p: Vector3i) -> bool:
	return level.get_cell(p) != LevelData.Cell.EMPTY and not _is_switched_off(p)

# Everything that hides a face: the level's own blocks and the granite around them
func _is_block(p: Vector3i) -> bool:
	return _is_solid(p) or _is_granite(p)

# A cell is switched off when it lies in one of the layers that were taken away,
# counted from any of the six faces. Note that the level z is the front layer at 0.
func _is_switched_off(p: Vector3i) -> bool:
	return p.z < _peeled[Face.FRONT] \
		or p.z >= level.size.z - _peeled[Face.BACK] \
		or p.x < _peeled[Face.LEFT] \
		or p.x >= level.size.x - _peeled[Face.RIGHT] \
		or p.y > level.surface_y - _peeled[Face.TOP] \
		or p.y < _peeled[Face.BOTTOM]

# Adds one quad of a cell face. `push` moves it along the face normal, which the outline
# uses to float just in front of the block. `uvs` overrides the usual 0..1 per face.
func _add_quad(st: SurfaceTool, origin: Vector3, face: Dictionary, push: float = 0.0,
		uvs: Array = []) -> void:
	var corners: Array = face["corners"]
	var normal: Vector3 = face["normal"]
	var offset := normal * push
	for i in TRIANGLE_INDICES:
		var corner: Vector3 = corners[i]
		st.set_normal(normal)
		st.set_uv(uvs[i] if not uvs.is_empty() else UVS[i])
		st.add_vertex(origin + corner + offset)

# The grass texture is laid over the whole surface instead of once per block. With
# grass_tile_blocks = 2 the same texture covers 2 x 2 blocks, so the tufts become larger
# than one block and the field no longer repeats its pattern on every block. The UVs
# come from the world position, so the blocks stay seamless. World z is the negative of
# cell z, hence the flipped v: it runs the same way as the v of the plain around the
# level, so the texture continues without a mirror line at the edge.
func _grass_uvs(cell: Vector3i, face: Dictionary) -> Array:
	if grass_tile_blocks <= 0.0:
		return UVS
	var uvs := []
	for corner in face["corners"]:
		uvs.append(Vector2(
			(cell.x + corner.x) / grass_tile_blocks,
			(cell.z + 1.0 - corner.z) / grass_tile_blocks))
	return uvs

# ---- Mine textures on the dug-out tunnels ----

# True when the neighbouring cell is part of the level and was dug away. Only then does
# the face look into a tunnel; the open air above the field is not a mine.
func _touches_dug_cell(neighbour: Vector3i) -> bool:
	return level.in_bounds(neighbour) and level.get_cell(neighbour) == LevelData.Cell.EMPTY

# The top face of the block below a hole is the floor of the tunnel, the bottom face of
# the block above it is the ceiling, and every side face is a wall.
func _mine_surface(dir: Vector3i) -> int:
	if dir.y > 0:
		return SURFACE_FLOOR
	if dir.y < 0:
		return SURFACE_CEILING
	return SURFACE_WALL

# The mine textures repeat over the position of every corner, like the grass, so the
# wooden frames continue across the blocks instead of restarting on each one.
func _mine_uvs(cell: Vector3i, face: Dictionary, tile: float) -> Array:
	var dir: Vector3i = face["dir"]
	var uvs := []
	for corner in face["corners"]:
		var p := Vector3(cell.x + corner.x, cell.y + corner.y, cell.z + corner.z)
		var uv: Vector2
		if absi(dir.y) > 0:
			uv = Vector2(p.x, p.z)
		elif absi(dir.x) > 0:
			uv = Vector2(p.z, p.y)
		else:
			uv = Vector2(p.x, p.y)
		uvs.append(uv / tile)
	return uvs

# The granite is one continuous mass of rock, so its UVs come from the world position of
# every corner instead of from the block. Sides use the height as one axis and the top
# the two horizontal ones; the blocks then form one rock face without seams.
func _granite_uvs(cell: Vector3i, face: Dictionary) -> Array:
	var dir: Vector3i = face["dir"]
	var uvs := []
	for corner in face["corners"]:
		var p := Vector3(cell.x + corner.x, cell.y + corner.y, -cell.z - 1.0 + corner.z)
		var uv: Vector2
		if absi(dir.y) > 0:
			uv = Vector2(p.x, p.z)
		elif absi(dir.x) > 0:
			uv = Vector2(p.z, p.y)
		else:
			uv = Vector2(p.x, p.y)
		uvs.append(uv / granite_tile_blocks)
	return uvs

# The cross-section of the rock at the side the camera looks from: a flat U-shaped face in
# the cut plane, with a rectangular hole over the playfield itself. Its three (or, seen
# from below, four) strips fill the view around the field with stone. Because the face is
# exactly in the plane the granite blocks end at, its texture continues theirs without a
# seam and the view keeps the flat look of a 2D field.
func _add_cross_section(st: SurfaceTool) -> int:
	var hx0 := 0.0
	var hx1 := float(level.size.x)
	var hy0 := 0.0
	var hy1 := float(level.surface_y + 1)
	var hz0 := float(-level.size.z)
	var hz1 := 0.0
	var reach := float(maxi(level.size.x, maxi(level.size.y, level.size.z))) \
		* CROSS_SECTION_REACH
	var ox0 := hx0 - reach
	var ox1 := hx1 + reach
	var oy0 := hy0 - reach
	var oz0 := hz0 - reach
	var oz1 := hz1 + reach

	if _granite_cut.z != 0:
		# Front or back face: the plane hangs in world x/y at the near or far side.
		var normal := Vector3(0.0, 0.0, signf(float(_granite_cut.z)))
		var plane_z := hz1 + CROSS_SECTION_PUSH if _granite_cut.z > 0 \
			else hz0 - CROSS_SECTION_PUSH
		_cross_section_rect(st, normal, plane_z, ox0, hx0, oy0, hy1)
		_cross_section_rect(st, normal, plane_z, hx1, ox1, oy0, hy1)
		_cross_section_rect(st, normal, plane_z, hx0, hx1, oy0, hy0)
		return 3
	if _granite_cut.x != 0:
		# Left or right face: the plane hangs in world z/y.
		var normal := Vector3(signf(float(_granite_cut.x)), 0.0, 0.0)
		var plane_x := hx1 + CROSS_SECTION_PUSH if _granite_cut.x > 0 \
			else hx0 - CROSS_SECTION_PUSH
		_cross_section_rect(st, normal, plane_x, oz0, hz0, oy0, hy1)
		_cross_section_rect(st, normal, plane_x, hz1, oz1, oy0, hy1)
		_cross_section_rect(st, normal, plane_x, hz0, hz1, oy0, hy0)
		return 3
	if _granite_cut.y < 0:
		# Seen from below the cut is the floor: the plane is horizontal, with the hole of
		# the field and stone on all four sides of it.
		var normal := Vector3(0.0, -1.0, 0.0)
		var plane_y := hy0 - CROSS_SECTION_PUSH
		_cross_section_rect(st, normal, plane_y, ox0, hx0, oz0, oz1)
		_cross_section_rect(st, normal, plane_y, hx1, ox1, oz0, oz1)
		_cross_section_rect(st, normal, plane_y, hx0, hx1, oz0, hz0)
		_cross_section_rect(st, normal, plane_y, hx0, hx1, hz1, oz1)
		return 4
	return 0

# One rectangle of the cross-section, lying in a plane at `constant` and given by its two
# in-plane axes: (x, y) for a front or back face, (z, y) for a side face and (x, z) for the
# floor. The rectangle's winding is fixed up so its face looks along `normal`.
func _cross_section_rect(st: SurfaceTool, normal: Vector3, constant: float,
		a0: float, a1: float, b0: float, b1: float) -> void:
	var a: Vector3
	var b: Vector3
	var c: Vector3
	var d: Vector3
	if absf(normal.z) > 0.5:
		a = Vector3(a0, b0, constant)
		b = Vector3(a1, b0, constant)
		c = Vector3(a1, b1, constant)
		d = Vector3(a0, b1, constant)
	elif absf(normal.x) > 0.5:
		a = Vector3(constant, b0, a0)
		b = Vector3(constant, b0, a1)
		c = Vector3(constant, b1, a1)
		d = Vector3(constant, b1, a0)
	else:
		a = Vector3(a0, constant, b0)
		b = Vector3(a1, constant, b0)
		c = Vector3(a1, constant, b1)
		d = Vector3(a0, constant, b1)
	_cross_section_quad(st, a, b, c, d, normal)

# Adds the quad, turning its winding if needed. Godot treats a clockwise winding as the
# front of a face, so the corners of a face that looks along its normal have a cross
# product that points the other way. The block shader takes the brightness from the
# normal, and the granite faces are culled from behind.
func _cross_section_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap := b
		b = d
		d = swap
	for p in [a, b, c, a, c, d]:
		st.set_normal(normal)
		st.set_uv(_granite_uv_at(p, normal))
		st.add_vertex(p)

# The granite UV at a world position on a face with this normal, on the same scale as the
# blocks of the shell, so the texture of the cross-section continues theirs.
func _granite_uv_at(p: Vector3, normal: Vector3) -> Vector2:
	var uv: Vector2
	if absf(normal.y) > 0.5:
		uv = Vector2(p.x, p.z)
	elif absf(normal.x) > 0.5:
		uv = Vector2(p.z, p.y)
	else:
		uv = Vector2(p.x, p.y)
	return uv / granite_tile_blocks

# Called every frame by the day/night clock, the same signal the backdrop follows.
# sun_angle is not used here: the blocks get their brightness from the shader, not the sun.
func set_cycle(night_amount: float, _sun_angle: float) -> void:
	_tint = Color.WHITE.lerp(night_tint, clampf(night_amount, 0.0, 1.0))
	for material in _materials:
		material.set_shader_parameter("tint", _tint)

# The texture that belongs to a mesh surface
func _surface_texture(surface: int) -> Texture2D:
	match surface:
		SURFACE_GRANITE: return granite_texture
		SURFACE_GRASS: return grass_texture
		SURFACE_WALL: return wall_texture
		SURFACE_FLOOR: return floor_texture
		SURFACE_CEILING: return ceiling_texture
	return dirt_texture

# The block materials share one shader: the texture, the face brightness and the tint are
# settings of the material. The ceiling passes a brighter bottom shade so a tunnel does
# not turn black overhead.
func _make_material(texture: Texture2D, bottom_shade: float = SHADE_BOTTOM) -> ShaderMaterial:
	if texture == null:
		push_error("LevelView3D: assign the grass, dirt and granite textures in the Inspector.")
	if _shader == null:
		_shader = Shader.new()
		_shader.code = BLOCK_SHADER_CODE
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("shade_front", SHADE_FRONT)
	material.set_shader_parameter("shade_side", SHADE_SIDE)
	material.set_shader_parameter("shade_back", SHADE_BACK)
	material.set_shader_parameter("shade_top", SHADE_TOP)
	material.set_shader_parameter("shade_bottom", bottom_shade)
	material.set_shader_parameter("tint", _tint)
	_materials.append(material)
	return material
