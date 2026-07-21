class_name WorldNoise
extends RefCounted

enum TEMPERATURE {
	COLD,
	TEMPERATE,
	HOT,
}

var terrain_noise := FastNoiseLite.new()
var _amplitude := 2
## where the general floor is located, relative to the center of the world
var _floor: float
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to _floor
var floor_bias := .2
const BIAS_THRESHOLD := 1.1

var temp_noise := FastNoiseLite.new()
var temp_amplitude := 4
const TEMP_BIAS_WEIGHT := 1
const HOT_THRESHOLD := .7
const TEMPERATE_THRESHOLD := 0
const COLD_THRESHOLD := -.8

var print_count := 0

func _init(_seed: int, size: float):
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrain_noise.frequency = 0.05
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_lacunarity = 1.5
	terrain_noise.fractal_gain = 1
	terrain_noise.seed = _seed
	center = Vector3(size / 2, size / 2, size / 2)
	_floor = size / 2 / 2
	
	temp_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	temp_noise.frequency = 0
	temp_noise.fractal_octaves = 4
	temp_noise.fractal_lacunarity = 2
	temp_noise.fractal_gain = 0.5
	temp_noise.seed = _seed

## Get a noise sample biased towards a world shape at a specific Vec3 of the noise volume
func sample(x: float, y: float, z: float) -> float:
	var _sample := terrain_noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var bias := get_bias_at_point(pos)
	return (_sample + bias) * _amplitude

# TO DO: change funciton name to sample temperature. Biome will be a construction of multiple values such as temperature and humidity.
func sample_biome(point: Vector3) -> float:
	var _sample := temp_noise.get_noise_3d(point.x, point.y, point.z)
	var equator := center.y
	var distance_to_equator = abs(point.y - equator)
	if distance_to_equator < _floor * 0.2:
		# HOT. Bias toward 0.75 - 0.25 (+0.5)
		return bias_temperature_value(_sample, HOT_THRESHOLD, TEMP_BIAS_WEIGHT)
	elif distance_to_equator < _floor * 0.75:
		# TEMPERATE. Bias toward -0.25 - 0.25 (0)
		return bias_temperature_value(_sample, TEMPERATE_THRESHOLD, TEMP_BIAS_WEIGHT)
	else:
		# COLD. Bias toward -0.75 - -0.25 (-0.5)
		return bias_temperature_value(_sample, COLD_THRESHOLD, TEMP_BIAS_WEIGHT)

func bias_temperature_value(_sample: float, bias_target: float, bias_strength: float) -> float:
	return lerp(_sample, bias_target, bias_strength)

func get_bias_at_point(point: Vector3, distance_target := center, bias_target := _floor, bias := floor_bias) -> float:
	var distance_to_center := point.distance_to(distance_target)
	return get_bias_from_distance(distance_to_center, bias_target, bias)

func get_bias_from_distance(distance: float, bias_target := _floor, bias := floor_bias) -> float:
	return (distance - bias_target) * bias

func get_biome(sample_value: float) -> TEMPERATURE:
	if sample_value <= COLD_THRESHOLD:
		return TEMPERATURE.COLD
	elif sample_value <= TEMPERATE_THRESHOLD:
		return TEMPERATURE.TEMPERATE
	else:
		return TEMPERATURE.HOT

func get_biome_color(biome: TEMPERATURE) -> Color:
	match biome:
		TEMPERATURE.COLD: return Color.SKY_BLUE
		TEMPERATURE.TEMPERATE: return Color.LAWN_GREEN
		TEMPERATURE.HOT: return Color.RED
	return Color.HOT_PINK
