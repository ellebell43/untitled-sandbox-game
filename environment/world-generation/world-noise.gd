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
# Used in Chunk._determine_if_cell_is_empty() to precompute if a cell is empty before sampling.
const BIAS_THRESHOLD := 1.1

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
	var bias := (pos.distance_to(center) - floor_distance) * FLOOR_BIAS
	return (_sample + bias) * AMPLITUDE

func get_bias_from_distance(distance: float) -> float:
	return (distance - floor_distance) * FLOOR_BIAS
