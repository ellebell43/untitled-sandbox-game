class_name WorldNoise
extends RefCounted

enum Biome {
	FROZEN,
	COLD,
	TEMPERATE,
	HOT,
	BURNING,
}

var terrain_noise := FastNoiseLite.new()
var temp_noise := FastNoiseLite.new()
var _amplitude := 2
## where the general floor is located, relative to the center of the world
var _floor: float
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to _floor
var floor_bias := .2
var temp_bias := .5
const BIAS_THRESHOLD := 1.1

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
	temp_noise.frequency = .005
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

func sample_biome(point: Vector3) -> float:
	var y_value: float
	if point.y > 0: y_value = center.y + _floor
	else: y_value = center.y - _floor
	var _sample := temp_noise.get_noise_3d(point.x, point.y, point.z)
	var bias := get_bias_at_point(point, Vector3(point.x, y_value, point.z), 0, temp_bias)
	return (_sample - bias) * _amplitude

func get_bias_at_point(point: Vector3, distance_target := center, bias_target := _floor, bias := floor_bias) -> float:
	var distance_to_center := point.distance_to(distance_target)
	return get_bias_from_distance(distance_to_center, bias_target, bias)

func get_bias_from_distance(distance: float, bias_target := _floor, bias := floor_bias) -> float:
	return (distance - bias_target) * bias

func get_biome(sample_value: float) -> Biome:
	if sample_value <= -0.25:
		return Biome.FROZEN
	if sample_value <= -0.75:
		return Biome.COLD
	if sample_value <= 0.25:
		return Biome.TEMPERATE
	if sample_value <= .75:
		return Biome.BURNING
	return Biome.HOT

func get_biome_color(biome: Biome) -> Color:
	match biome:
		Biome.FROZEN: return Color.WHITE
		Biome.COLD: return Color.LIGHT_BLUE
		Biome.TEMPERATE: return Color.YELLOW_GREEN
		Biome.HOT: return Color.ORANGE
	return Color.ORANGE_RED
