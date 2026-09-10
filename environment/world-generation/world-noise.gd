class_name WorldNoise
extends RefCounted

var planet_shell_noise := FastNoiseLite.new()
var continent_noise := FastNoiseLite.new()
var hill_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to floor_distance
const FLOOR_BIAS := .1
# Used in Chunk._determine_if_cell_is_empty() to precompute if a cell is empty before sampling.
const BIAS_THRESHOLD := 9.0

var sea_level: int
var sea_level_modifier: int
var slope_curve: Curve

var continent_amplitude := 0.3
var hill_amplitude := 0.2
var detail_amplitude := .05

func _init(_seed: int, size: float, _sea_level, _sea_level_modifier: int, _slope_curve: Curve):
	# ======= PLANET SHELL NOISE PROPERTIES =======
	planet_shell_noise.seed = _seed
	planet_shell_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	planet_shell_noise.frequency = 0.0001
	planet_shell_noise.fractal_octaves = 1

	# ======= CONTINENT NOISE PROPERTIES =======
	continent_noise.seed = _seed
	continent_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	continent_noise.frequency = 0.005
	continent_noise.fractal_octaves = 3
	continent_noise.fractal_type = FastNoiseLite.FRACTAL_FBM

	# ======= HILL NOISE PROPERTIES =======
	hill_noise.seed = _seed
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	hill_noise.frequency = 0.02
	hill_noise.fractal_octaves = 5

	# ======= DETAIL NOISE PROPERTIES =======
	detail_noise.seed = _seed
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.05
	detail_noise.fractal_octaves = 3
	detail_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	detail_noise.domain_warp_enabled = false
	detail_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX_REDUCED
	detail_noise.domain_warp_amplitude = 1.75
	
	center = Vector3(size / 2, size / 2, size / 2)
	sea_level = _sea_level
	sea_level_modifier = _sea_level_modifier
	slope_curve = _slope_curve

## Get a noise sample biased towards a world shape at a specific Vec3 of the noise volume
func sample(x: float, y: float, z: float) -> float:
	var shell_sample := planet_shell_noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var shell_bias := (pos.distance_to(center) - sea_level) * FLOOR_BIAS

	var continent_sample = continent_noise.get_noise_3d(x, y, z)
	var continent_elevation = slope_curve.sample(continent_sample)
	var continent_contribution = - continent_elevation * continent_amplitude

	var hill_sample = hill_noise.get_noise_3d(x, y, z)
	var hill_contribution = hill_sample * hill_amplitude

	var detail_sample = detail_noise.get_noise_3d(x, y, z)
	var detail_contribution = detail_sample * detail_amplitude

	var complete_sample = shell_sample + shell_bias + continent_contribution + hill_contribution + detail_contribution
	return complete_sample

func get_bias_from_distance(distance: float) -> float:
	return (distance - sea_level) * FLOOR_BIAS

var dark_blue := Color("#30618c")
var blue := Color("#5696cf")
var sand := Color("#f7f0b2")
var green := Color("#7ae451")
var gray := Color("#9c9c9c")
func get_biome_color(_pos: Vector3) -> Color:
	var elevation: float = _pos.distance_to(center)
	if elevation < sea_level + sea_level_modifier - 15: return dark_blue
	elif elevation < sea_level + sea_level_modifier: return blue
	elif elevation > sea_level and elevation < sea_level + 1: return sand
	elif elevation > sea_level + 15: return gray
	else: return green
