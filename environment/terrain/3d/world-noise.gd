class_name WorldNoise
extends  Node

var _noise := FastNoiseLite.new()
var _amplitude := 1
var _floor: float
var center: Vector3
var floor_bias := .2

func _init(_seed: int, size: float):
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 0.05
	_noise.fractal_octaves = 2
	_noise.fractal_lacunarity = 2
	_noise.fractal_gain = 0.5
	_noise.seed = _seed
	center = Vector3(size/2,size/2, size/2)
	_floor = size/2.5
	
func sample(x: float, y: float, z: float) -> float:
	var _sample := _noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var distance_to_center := pos.distance_to(center)
	var distance_to_floor = distance_to_center - _floor
	var bias = distance_to_floor * floor_bias
	return (_sample + bias) * _amplitude
