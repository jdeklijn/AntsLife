extends MeshInstance3D

const Face = LevelData.Face

# Drag the textures into these fields in the Inspector
@export var grass_texture: Texture2D
@export var dirt_texture: Texture2D

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

# A switched-off layer is not removed but drawn as a faint ghost, so you keep your
# bearings. This is how visible it stays (1.0 = fully visible, 0.0 = gone).
const GHOST_ALPHA := 0.2
# The edges of ghost blocks are a bit more visible, so you can still count the blocks
const GHOST_EDGE_ALPHA := 0.25

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

# The mesh has four surfaces: grass and dirt, each as solid blocks and as ghost blocks
const SURFACE_GRASS := 0
const SURFACE_DIRT := 1
const SURFACE_GHOST_GRASS := 2
const SURFACE_GHOST_DIRT := 3

# Draws the texture on each face and scales its brightness by the direction the face
# points in. It is unshaded on purpose: the brightness comes only from the values above,
# not from the lights in the scene. The two GHOST markers are filled in for ghost blocks.
const BLOCK_SHADER_CODE := """
shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float edge_width = 0.05;
uniform float shade_front = 1.0;
uniform float shade_side = 0.82;
uniform float shade_back = 0.62;
uniform float shade_top = 1.0;
uniform float shade_bottom = 0.5;
// Multiplied over the whole block. The day/night clock uses it to darken the blocks
// along with the plain and the grass, which are unshaded as well.
uniform vec4 tint : source_color = vec4(1.0);
//GHOST_UNIFORMS

varying vec3 model_normal;

void vertex() {
	model_normal = NORMAL;
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;

	// Only the ghost blocks use the edge band, to stay readable when they fade out
	vec2 d = min(UV, vec2(1.0) - UV);
	float edge = 1.0 - smoothstep(0.0, edge_width, min(d.x, d.y));

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
	//GHOST_ALPHA
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

var level: LevelData
var _shaders: Array[Shader] = [null, null]  # [solid, ghost]
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

func _ready() -> void:
	for face in Face.values():
		_peeled[face] = 0
	level = Level01.build()
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
	_update_cursor()
	_update_forbidden()

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
# count, so the outline only appears over the field itself.
func _update_cursor() -> void:
	if _cursor == null or level == null:
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
			if _is_solid(cell + dir):
				continue
			_add_quad(st, origin, face, OVERLAY_PUSH)
			quads += 1
	if quads == 0:
		return null
	return st.commit()

# Draws the first solid cell that the ray from the camera through the mouse enters.
# It steps cell by cell (Amanatides & Woo), so it also works on the side walls and
# through switched-off ghost layers. World z is mirrored, hence the flip below.
func _ray_cell(camera: Camera3D, mouse: Vector2) -> Vector3i:
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	var o := Vector3(origin.x, origin.y, -origin.z)
	var d := Vector3(direction.x, direction.y, -direction.z)
	if d.length_squared() < 0.000001:
		return NO_CELL
	d = d.normalized()
	var cell := Vector3i(floori(o.x), floori(o.y), floori(o.z))
	if _is_solid(cell):
		return cell
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
		if _is_solid(cell):
			return cell
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

# True when the ray has left the level on an axis and is heading further away, so it can
# never come back in
func _past_level(cell: Vector3i, step: Vector3i) -> bool:
	return (cell.x < 0 and step.x <= 0) or (cell.x >= level.size.x and step.x >= 0) \
		or (cell.y < 0 and step.y <= 0) or (cell.y >= level.size.y and step.y >= 0) \
		or (cell.z < 0 and step.z <= 0) or (cell.z >= level.size.z and step.z >= 0)

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
	var counts: Array[int] = [0, 0, 0, 0]
	for i in 4:
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(surface_tool)
	grass_cells.clear()

	for z in level.size.z:
		for y in level.size.y:
			for x in level.size.x:
				var p := Vector3i(x, y, z)
				if level.get_cell(p) == LevelData.Cell.EMPTY:
					continue
				var ghost := _is_switched_off(p)
				var origin := Vector3(x, y, -z - 1)
				for face in FACES:
					var dir: Vector3i = face["dir"]
					var neighbour := p + dir
					if ghost:
						# A ghost block only shows its outside. Faces towards other blocks are
						# left out, so they do not lie on top of the surface behind them.
						if level.get_cell(neighbour) != LevelData.Cell.EMPTY:
							continue
					elif _is_solid(neighbour):
						# A face between two solid cells can never be seen
						continue
					# Only the top of the surface row is grass
					var is_grass := dir == Vector3i(0, 1, 0) and y == level.surface_y
					var surface := (SURFACE_GRASS if is_grass else SURFACE_DIRT) + (2 if ghost else 0)
					_add_quad(surface_tools[surface], origin, face, 0.0,
						_grass_uvs(p, face) if is_grass else [])
					counts[surface] += 1
					if is_grass and not ghost:
						grass_cells.append(p)

	var new_mesh := ArrayMesh.new()
	_materials.clear()
	for surface in 4:
		if counts[surface] == 0:
			continue
		var texture := grass_texture if surface % 2 == SURFACE_GRASS else dirt_texture
		surface_tools[surface].set_material(_make_material(texture, surface >= SURFACE_GHOST_GRASS))
		surface_tools[surface].commit(new_mesh)
	mesh = new_mesh
	rebuilt.emit()

# Cells outside the block, and cells in a switched-off layer, do not count as solid.
# So the outside of the block is drawn, and so is the surface that a removed layer uncovers.
func _is_solid(p: Vector3i) -> bool:
	return level.get_cell(p) != LevelData.Cell.EMPTY and not _is_switched_off(p)

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

# Called every frame by the day/night clock, the same signal the backdrop follows.
# sun_angle is not used here: the blocks get their brightness from the shader, not the sun.
func set_cycle(night_amount: float, _sun_angle: float) -> void:
	_tint = Color.WHITE.lerp(night_tint, clampf(night_amount, 0.0, 1.0))
	for material in _materials:
		material.set_shader_parameter("tint", _tint)

func _shader_code(ghost: bool) -> String:
	var code := BLOCK_SHADER_CODE
	if ghost:
		code = code.replace("//GHOST_UNIFORMS",
			"uniform float ghost_alpha = 0.15;\nuniform float ghost_edge_alpha = 0.15;")
		code = code.replace("//GHOST_ALPHA",
			"ALPHA = clamp(ghost_alpha + edge * ghost_edge_alpha, 0.0, 1.0);")
	else:
		code = code.replace("//GHOST_UNIFORMS", "").replace("//GHOST_ALPHA", "")
	return code

func _make_material(texture: Texture2D, ghost: bool) -> ShaderMaterial:
	if texture == null:
		push_error("LevelView3D: assign the grass and dirt textures in the Inspector.")
	var index := 1 if ghost else 0
	if _shaders[index] == null:
		var shader := Shader.new()
		shader.code = _shader_code(ghost)
		_shaders[index] = shader
	var material := ShaderMaterial.new()
	material.shader = _shaders[index]
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("shade_front", SHADE_FRONT)
	material.set_shader_parameter("shade_side", SHADE_SIDE)
	material.set_shader_parameter("shade_back", SHADE_BACK)
	material.set_shader_parameter("shade_top", SHADE_TOP)
	material.set_shader_parameter("shade_bottom", SHADE_BOTTOM)
	material.set_shader_parameter("tint", _tint)
	if ghost:
		material.set_shader_parameter("ghost_alpha", GHOST_ALPHA)
		material.set_shader_parameter("ghost_edge_alpha", GHOST_EDGE_ALPHA)
	_materials.append(material)
	return material
