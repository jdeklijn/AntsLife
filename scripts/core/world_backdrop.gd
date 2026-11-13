extends Node3D

# Sky and endless ground around the level. The ground lies exactly at the top of the
# grass, so the plain continues the grass surface and the horizon stays in line with
# the grass/soil border.
#
# Nothing here has to turn with the camera: a sky is drawn at infinity, and a horizontal
# ground keeps the same horizon height however the camera orbits around the level.

const DEFAULT_GRASS := preload("res://assests/world/textures/grass_a.png")
const DEFAULT_DIRT := preload("res://assests/world/textures/dirt_dark.png")

# Height of the grass surface. Negative means: read it from the level.
# Set it to the level's surface_y for a plain at the grass/soil border instead.
@export var surface_height: float = -1.0
@export var ground_size: float = 1000.0
@export var ground_texture: Texture2D = DEFAULT_GRASS
@export var ground_tint: Color = Color(1.0, 1.0, 1.0)
# The ground sits a hair under the grass, so the two never fight over the same pixels
@export var ground_epsilon: float = 0.01

@export_group("Sky")
@export var sky_top_color: Color = Color(0.36, 0.58, 0.88)
@export var sky_horizon_color: Color = Color(0.78, 0.87, 0.95)
# Below the horizon the sky hemisphere is painted as soil, so looking under the
# ground shows earth instead of more sky
@export var underground_horizon_color: Color = Color(0.24, 0.17, 0.12)
@export var underground_bottom_color: Color = Color(0.07, 0.05, 0.035)
@export var ambient_energy: float = 0.8
@export var fog_density: float = 0.002
# Fog in soil colors, so the distance never turns back into sky blue (which is what
# you would see underground)
@export var fog_color: Color = Color(0.26, 0.19, 0.13)

@export_group("Night")
# The same colours, but for the night. set_night_amount() blends between the day value
# above and the night value here: 0 = day, 1 = night.
@export var night_sky_top_color: Color = Color(0.03, 0.05, 0.13)
@export var night_sky_horizon_color: Color = Color(0.10, 0.13, 0.26)
@export var night_ambient_energy: float = 0.30
@export var night_fog_color: Color = Color(0.05, 0.06, 0.10)
@export var night_fog_density: float = 0.003
@export var night_ground_tint: Color = Color(0.35, 0.40, 0.55)
@export var night_ceiling_tint: Color = Color(0.30, 0.28, 0.26)
@export var night_wall_tint: Color = Color(0.28, 0.25, 0.23)
# Lights that are a sibling of the backdrop (the sun in the level) are dimmed too
@export var night_light_energy: float = 0.15
@export var night_light_color: Color = Color(0.55, 0.65, 1.0)

@export_group("Underground")
# Soil plane under the grass. It is only drawn from below, so above ground you never
# see it, but under ground it hides the sky and reads as the underside of the soil.
@export var ceiling_texture: Texture2D = DEFAULT_DIRT
@export var ceiling_tint: Color = Color(0.60, 0.54, 0.48)
# How far the soil roof sits below the grass surface
@export var ceiling_offset: float = 0.05
# Soil wall around the level, hanging from the grass downwards. Only visible from below
# the grass. Without it the horizon of the sky stays visible as a thin light stripe,
# because a horizontal plane can never cover a ray that runs exactly level.
@export var wall_radius: float = 420.0
@export var wall_depth: float = 60.0
@export var wall_tint: Color = Color(0.55, 0.49, 0.43)
@export var wall_segments: int = 64

var _environment: Environment
var _sky_material: ProceduralSkyMaterial
var _ground_material: StandardMaterial3D
var _ceiling_material: StandardMaterial3D
var _wall_material: StandardMaterial3D
var _lights: Array[Dictionary] = []

func _ready() -> void:
	var height := _surface_height()
	_build_environment()
	_build_ground(height)
	_build_ceiling(height)
	_build_wall(height)
	_collect_lights()

# In this level the grass is the top cell row, so its surface is surface_y + 1
func _surface_height() -> float:
	if surface_height >= 0.0:
		return surface_height
	var parent := get_parent()
	if parent != null:
		for node in parent.get_children():
			var level = node.get("level")
			if level is LevelData:
				return float(level.surface_y) + 1.0
	return float(Level01.SURFACE_Y) + 1.0

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = sky_horizon_color
	sky_material.sky_curve = 0.15
	# The lower half of the sky is the underground, not more sky
	sky_material.ground_horizon_color = underground_horizon_color
	sky_material.ground_bottom_color = underground_bottom_color
	sky_material.ground_curve = 0.35

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	# The far edge of the ground fades into soil-ish haze, so no edge shows
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_sky_affect = 0.0

	_environment = env
	_sky_material = sky_material

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

func _build_ground(height: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)

	# Unshaded, like the block shader, so the plain matches the grass tiles in brightness
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ground_texture
	material.albedo_color = ground_tint
	material.uv1_scale = Vector3(ground_size, ground_size, 1.0)
	material.cull_mode = BaseMaterial3D.CULL_BACK
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = plane
	ground.material_override = material
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground.position = Vector3(0.0, height - ground_epsilon, 0.0)
	add_child(ground)
	_ground_material = material

# The underside of the ground. The grass plane is single-sided, so from below it is
# invisible and you would look straight into the sky. This plane is the mirror image
# of it: drawn only from below, dark soil, so an underground view shows earth overhead.
func _build_ceiling(height: float) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(ground_size, ground_size)

	var material := _soil_material(ceiling_tint)
	material.uv1_scale = Vector3(ground_size, ground_size, 1.0)

	var ceiling := MeshInstance3D.new()
	ceiling.name = "SoilCeiling"
	ceiling.mesh = plane
	ceiling.material_override = material
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ceiling.position = Vector3(0.0, height - ceiling_offset, 0.0)
	add_child(ceiling)
	_ceiling_material = material

# Closes off the sky at eye level. The soil ceiling cannot do that: a ray that runs
# exactly level never meets a horizontal plane, so the sky's horizon stays visible as a
# thin light stripe beside the level. A cylinder around the level catches those rays.
func _build_wall(height: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = wall_radius
	mesh.bottom_radius = wall_radius
	mesh.height = wall_depth
	mesh.radial_segments = maxi(wall_segments, 8)
	mesh.cap_top = false
	mesh.cap_bottom = false

	var material := _soil_material(wall_tint)
	# One texture tile per world unit, like the ground and the blocks
	material.uv1_scale = Vector3(TAU * wall_radius, wall_depth, 1.0)

	var wall := MeshInstance3D.new()
	wall.name = "SoilWall"
	wall.mesh = mesh
	wall.material_override = material
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Top edge flush with the soil ceiling, so the two form one closed shell
	wall.position = Vector3(0.0, height - ceiling_offset - wall_depth * 0.5, 0.0)
	add_child(wall)
	_wall_material = material

# Remembers the lights around the backdrop, so the night can dim them
func _collect_lights() -> void:
	_lights.clear()
	var parent := get_parent()
	if parent == null:
		return
	for node in parent.get_children():
		var light := node as Light3D
		if light == null:
			continue
		_lights.append({
			"node": light,
			"energy": light.light_energy,
			"color": light.light_color,
		})

# 0 = full day, 1 = full night. Blends the sky, the fog, the ambient light, the ground
# and the sun between the day and the night values.
func set_night_amount(amount: float) -> void:
	amount = clampf(amount, 0.0, 1.0)
	if _sky_material != null:
		_sky_material.sky_top_color = sky_top_color.lerp(night_sky_top_color, amount)
		_sky_material.sky_horizon_color = sky_horizon_color.lerp(night_sky_horizon_color, amount)
	if _environment != null:
		_environment.ambient_light_energy = lerpf(ambient_energy, night_ambient_energy, amount)
		_environment.fog_light_color = fog_color.lerp(night_fog_color, amount)
		_environment.fog_density = lerpf(fog_density, night_fog_density, amount)
	if _ground_material != null:
		_ground_material.albedo_color = ground_tint.lerp(night_ground_tint, amount)
	if _ceiling_material != null:
		_ceiling_material.albedo_color = ceiling_tint.lerp(night_ceiling_tint, amount)
	if _wall_material != null:
		_wall_material.albedo_color = wall_tint.lerp(night_wall_tint, amount)
	for entry in _lights:
		var light := entry["node"] as Light3D
		if light == null:
			continue
		light.light_energy = lerpf(float(entry["energy"]), night_light_energy, amount)
		light.light_color = (entry["color"] as Color).lerp(night_light_color, amount)

# Unshaded soil, drawn from the inside only: invisible above ground, dark underground
func _soil_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = ceiling_texture
	material.albedo_color = tint
	material.cull_mode = BaseMaterial3D.CULL_FRONT
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return material
