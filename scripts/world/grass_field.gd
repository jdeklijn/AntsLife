extends MultiMeshInstance3D

# Stylized 3D grass: a handful of small blade tufts is scattered over every grass cell,
# all in one MultiMesh (one draw call). The shader lets each tuft sway in the wind, which
# is what the flat texture cannot do.
#
# The tufts only supply the detail: the grass texture underneath supplies the colour, so
# keep it calm. There are two ways to use this node:
#  - as a child of the terrain MeshInstance3D: it follows that node's level and its
#    rebuilt signal, so peeled layers lose their grass too, and it fills the plain all
#    around the level as well;
#  - anywhere else (the main menu, for example): it covers the square area_min/area_max
#    at surface_height.

# Tufts per grass block. A cover of many small tufts reads better than a few tall ones.
@export_range(0, 20) var tufts_per_cell: int = 10
# Height of a tuft, in blocks (1 block = 1 cell)
@export_range(0.05, 0.8, 0.01) var tuft_height: float = 0.13
# Blades in the generated tuft mesh
@export_range(1, 12) var blades_per_tuft: int = 6
# How far the tips sway, in blocks
@export_range(0.0, 0.4, 0.01) var wind_strength: float = 0.05
@export_range(0.2, 5.0, 0.1) var wind_speed: float = 1.4
# Colours of the blades, from the root to the tip
@export var root_color: Color = Color(0.08, 0.16, 0.02)
@export var tip_color: Color = Color(0.26, 0.40, 0.06)
# Random size and colour spread, so no two tufts look the same (0 = all identical)
@export_range(0.0, 0.6, 0.01) var variation: float = 0.25
# Fixes the layout, so a rebuild puts every tuft back in the same spot
@export var random_seed: int = 1
# Night colour, faded in by the day/night clock so the tufts darken with the rest
@export var night_tint: Color = Color(0.35, 0.40, 0.55)

@export_group("Area")
# Blocks of plain grass around the level. Only used when this node sits under the level
# view. Enough to fill the view when zoomed out, without planting the whole world.
@export_range(0, 64) var plain_margin: int = 40
# The last blocks of the field thin out instead of stopping dead, so the plain never
# ends with a visible line of tufts.
@export_range(1, 40) var edge_fade: int = 16
# Height of the ground and the square that is covered, in blocks, when there is no level
# above this node.
@export var surface_height: float = 0.0
@export var area_min: Vector2 = Vector2(-30.0, -30.0)
@export var area_max: Vector2 = Vector2(30.0, 30.0)

const WIND_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float wind_strength = 0.1;
uniform float wind_speed = 1.4;
uniform vec4 tint : source_color = vec4(1.0);

varying float brightness;

void vertex() {
	// INSTANCE_CUSTOM.g is the random wind phase of this tuft, .r its brightness
	float phase = INSTANCE_CUSTOM.g * 62.83;
	float t = TIME * wind_speed + phase;
	float sway = sin(t) + 0.35 * sin(t * 2.3 + 1.7);
	// The tips move, the roots stay put
	float bend = VERTEX.y * VERTEX.y;
	VERTEX.x += sway * wind_strength * bend;
	VERTEX.z += cos(t * 0.8 + 2.0) * wind_strength * 0.45 * bend;
	brightness = mix(1.0 - 0.3, 1.0 + 0.3, INSTANCE_CUSTOM.r);
}

void fragment() {
	ALBEDO = COLOR.rgb * brightness * tint.rgb;
}
"""

var _view: Node
var _mesh: ArrayMesh
var _material: ShaderMaterial


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh = _make_mesh()
	_material = ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = WIND_SHADER_CODE
	_material.shader = shader
	_material.set_shader_parameter("wind_strength", wind_strength)
	_material.set_shader_parameter("wind_speed", wind_speed)
	_material.set_shader_parameter("tint", Color.WHITE)
	material_override = _material
	_view = get_parent()
	if _view != null and _view.has_signal("rebuilt"):
		_connect_view.call_deferred()
	else:
		# No level above us: cover our own square
		_view = null
		rebuild()


func _connect_view() -> void:
	_view.rebuilt.connect(rebuild)
	rebuild()


# Called by the day/night clock, the same signal the plain and the blocks follow
func set_cycle(night_amount: float, _sun_angle: float) -> void:
	if _material == null:
		return
	_material.set_shader_parameter("tint",
		Color.WHITE.lerp(night_tint, clampf(night_amount, 0.0, 1.0)))


func rebuild() -> void:
	visible = false
	multimesh = null
	var spots := _spots()
	var total := 0
	for spot: Vector4 in spots:
		total += int(spot.w)
	if total == 0:
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = total
	var index := 0
	for spot: Vector4 in spots:
		var base := Vector3(spot.x, spot.y, spot.z)
		var rng := RandomNumberGenerator.new()
		# The same spot always gets the same tufts, even after a rebuild
		rng.seed = random_seed + int(hash(base))
		for i in int(spot.w):
			# Slightly across the cell edges, so the block grid does not show up as gaps
			# between rows of tufts
			var position := base + Vector3(
				rng.randf_range(-0.1, 1.1), 0.0, rng.randf_range(-0.1, 1.1))
			var size := tuft_height * rng.randf_range(1.0 - variation, 1.0 + variation)
			var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
			# A slight random lean, so the field does not look planted
			basis = basis.rotated(Vector3.RIGHT, rng.randf_range(-0.18, 0.18))
			basis = basis.rotated(Vector3.FORWARD, rng.randf_range(-0.18, 0.18))
			basis = basis.scaled(Vector3.ONE * size)
			mm.set_instance_transform(index, Transform3D(basis, position))
			mm.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), 0.0, 0.0))
			index += 1
	multimesh = mm
	visible = true


# The base position of every tuft cell and how many tufts it gets: the grass on top of
# the level, and the plain around it. The plain skips the level's footprint, because the
# blocks are there.
func _spots() -> Array:
	if _view == null:
		return _area_spots()
	var level: LevelData = _view.get("level")
	if level == null:
		return []
	var surface := float(level.surface_y + 1)
	var spots := []
	for cell: Vector3i in _view.get("grass_cells"):
		spots.append(Vector4(cell.x, surface, -cell.z - 1.0, float(tufts_per_cell)))
	var margin := plain_margin
	for x in range(-margin, level.size.x + margin):
		for z in range(-level.size.z - margin, margin):
			if x >= 0 and x < level.size.x and z >= -level.size.z and z < 0:
				continue
			var count := _edge_count(x, z, level)
			if count > 0:
				spots.append(Vector4(x, surface, z, float(count)))
	return spots


# How many tufts the plain block at x/z gets, going by its distance to the edge of the
# field. Blocks close to the level are full, the last edge_fade blocks thin out.
func _edge_count(x: int, z: int, level: LevelData) -> int:
	var dx := 0
	if x < 0:
		dx = -x
	elif x >= level.size.x:
		dx = x - level.size.x + 1
	var dz := 0
	if z < -level.size.z:
		dz = -level.size.z - z
	elif z >= 0:
		dz = z + 1
	return _tapered_count(plain_margin - maxi(dx, dz))


# Full density well inside the field, fading to nothing at its edge
func _tapered_count(edge: int) -> int:
	if edge >= edge_fade:
		return tufts_per_cell
	var t := clampf(float(edge) / float(maxi(edge_fade, 1)), 0.0, 1.0)
	return roundi(tufts_per_cell * t * t)


# The square this node covers when it does not follow a level
func _area_spots() -> Array:
	var spots := []
	var min_x := floori(area_min.x)
	var max_x := ceili(area_max.x)
	var min_z := floori(area_min.y)
	var max_z := ceili(area_max.y)
	for x in range(min_x, max_x):
		for z in range(min_z, max_z):
			var edge := mini(mini(x - min_x, max_x - 1 - x),
				mini(z - min_z, max_z - 1 - z))
			var count := _tapered_count(edge)
			if count > 0:
				spots.append(Vector4(x, surface_height, z, float(count)))
	return spots


# One tuft: blades that fan out in every direction, so the tuft reads as a clump from any
# camera angle. Height is 1, so the instance scale is the tuft height in blocks.
func _make_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261115
	var dark := root_color.darkened(0.45)
	for b in blades_per_tuft:
		var angle := TAU * float(b) / blades_per_tuft + rng.randf_range(-0.5, 0.5)
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var side := Vector3(-out.z, 0.0, out.x)
		var height := rng.randf_range(0.65, 1.0)
		var bend := rng.randf_range(0.10, 0.30)
		var root := out * rng.randf_range(0.0, 0.10)
		var mid := root + Vector3(0.0, height * 0.55, 0.0) + out * bend * 0.4
		var tip := root + Vector3(0.0, height, 0.0) + out * bend
		var width := rng.randf_range(0.07, 0.11)
		var mid_width := width * 0.55
		_add_quad(st,
			root - side * width, root + side * width,
			mid - side * mid_width, mid + side * mid_width,
			dark, root_color)
		_add_quad(st,
			mid - side * mid_width, mid + side * mid_width,
			tip, tip,
			root_color, tip_color)
	return st.commit()


# A quad from a bottom edge to a top edge, both given left and right. The top edge may be
# a single point (the tip of the blade).
func _add_quad(st: SurfaceTool, bottom_left: Vector3, bottom_right: Vector3,
		top_left: Vector3, top_right: Vector3,
		bottom_color: Color, top_color: Color) -> void:
	var corners := [bottom_left, bottom_right, top_right, top_left]
	var colors := [bottom_color, bottom_color, top_color, top_color]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_color(colors[i])
		st.add_vertex(corners[i])
