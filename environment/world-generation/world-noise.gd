class_name WorldNoise
extends RefCounted

var _noise := FastNoiseLite.new()
var _amplitude := 2
## where the general floor is located, relative to the center of the world
var _floor: float
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to _floor
var floor_bias := .5
const BIAS_THRESHOLD := 1.2

func _init(_seed: int, size: float):
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.05
	_noise.fractal_octaves = 2
	_noise.fractal_lacunarity = 2
	_noise.fractal_gain = 0.5
	_noise.seed = _seed
	center = Vector3(size / 2, size / 2, size / 2)
	_floor = size / 2 / 2

## Get a noise sample biased towards a world shape at a specific Vec3 of the noise volume
func sample(x: float, y: float, z: float) -> float:
	var _sample := _noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var bias := get_bias_at_point(pos)
	return (_sample + bias) * _amplitude

func get_bias_at_point(point: Vector3) -> float:
	var distance_to_center := point.distance_to(center)
	return get_bias_from_distance(distance_to_center)

func get_bias_from_distance(distance: float) -> float:
	return (distance - _floor) * floor_bias
