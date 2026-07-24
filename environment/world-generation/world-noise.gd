class_name WorldNoise
extends RefCounted

var terrain_noise := FastNoiseLite.new()
## where the general floor is located, relative to the center of the world
var floor_distance: float
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to floor_distance
const FLOOR_BIAS := .2
const AMPLITUDE := 2

func _init(_seed: int, size: float):
	terrain_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	terrain_noise.frequency = 0.05
	terrain_noise.fractal_octaves = 4
	terrain_noise.fractal_lacunarity = 1.5
	terrain_noise.fractal_gain = 1
	terrain_noise.seed = _seed
	center = Vector3(size / 2, size / 2, size / 2)
	floor_distance = size / 2 / 2

## Get a noise sample biased towards a world shape at a specific Vec3 of the noise volume
func sample(x: float, y: float, z: float) -> float:
	var _sample := terrain_noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var distance_to_center := pos.distance_to(center)
	var bias := distance_to_center * FLOOR_BIAS
	return (_sample + bias) * AMPLITUDE

#func get_bias_at_point(point: Vector3, distance_target := center, bias_target := floor_distance, bias := FLOOR_BIAS) -> float:
	#var distance_to_center := point.distance_to(distance_target)
	#return get_bias_from_distance(distance_to_center, bias_target, bias)

func get_bias_from_distance(distance: float, bias_target := floor_distance, bias := FLOOR_BIAS) -> float:
	return (distance - bias_target) * bias
