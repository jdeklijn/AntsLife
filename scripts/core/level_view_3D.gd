extends MeshInstance3D

const Face = LevelData.Face

# Drag the textures into these fields in the Inspector
@export var grass_texture: Texture2D
@export var dirt_texture: Texture2D

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

# Draws the texture on each face, scales its brightness by the direction the face
# points in, and darkens the edges a little so neighbouring cells read as separate
# blocks. It is unshaded on purpose: the brightness comes only from the values above,
# not from the lights in the scene. The two GHOST markers are filled in for ghost blocks.
const BLOCK_SHADER_CODE := """
shader_type spatial;
render_mode unshaded;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform float edge_width = 0.05;
uniform float edge_darkness = 0.5;
uniform float shade_front = 1.0;
uniform float shade_side = 0.82;
uniform float shade_back = 0.62;
uniform float shade_top = 1.0;
uniform float shade_bottom = 0.5;
//GHOST_UNIFORMS

varying vec3 model_normal;

void vertex() {
	model_normal = NORMAL;
}

void fragment() {
	vec3 tex = texture(albedo_texture, UV).rgb;

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

	ALBEDO = tex * shade * (1.0 - edge * edge_darkness);
	//GHOST_ALPHA
}
"""

var level: LevelData
var _shaders: Array[Shader] = [null, null]  # [solid, ghost]
var _peeled := {}  # face -> number of switched-off layers, counted from that face inwards

func _ready() -> void:
	for face in Face.values():
		_peeled[face] = 0
	level = Level01.build()
	rebuild()
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
	rebuild()

func rebuild() -> void:
	var surface_tools: Array[SurfaceTool] = []
	var counts: Array[int] = [0, 0, 0, 0]
	for i in 4:
		var surface_tool := SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools.append(surface_tool)

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
					_add_quad(surface_tools[surface], origin, face)
					counts[surface] += 1

	var new_mesh := ArrayMesh.new()
	for surface in 4:
		if counts[surface] == 0:
			continue
		var texture := grass_texture if surface % 2 == SURFACE_GRASS else dirt_texture
		surface_tools[surface].set_material(_make_material(texture, surface >= SURFACE_GHOST_GRASS))
		surface_tools[surface].commit(new_mesh)
	mesh = new_mesh
	print("LevelView3D: quads per surface %s" % [counts])  # temporary debug

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

func _add_quad(st: SurfaceTool, origin: Vector3, face: Dictionary) -> void:
	var corners: Array = face["corners"]
	var normal: Vector3 = face["normal"]
	for i in TRIANGLE_INDICES:
		var corner: Vector3 = corners[i]
		st.set_normal(normal)
		st.set_uv(UVS[i])
		st.add_vertex(origin + corner)

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
	if ghost:
		material.set_shader_parameter("ghost_alpha", GHOST_ALPHA)
		material.set_shader_parameter("ghost_edge_alpha", GHOST_EDGE_ALPHA)
	return material
