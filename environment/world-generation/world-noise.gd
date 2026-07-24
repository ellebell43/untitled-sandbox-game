class_name WorldNoise
extends RefCounted

var terrain_noise := FastNoiseLite.new()
## where the general floor is located, relative to the center of the world
var floor_distance: float
## center of the 3D volume
var center: Vector3
## How strong fall the bias is towards being inside or outside of the volume relative to floor_distance
const FLOOR_BIAS := .2
# Used in Chunk._determine_if_cell_is_empty() to precompute if a cell is empty before sampling.
const BIAS_THRESHOLD := 1.1

func _init(_seed: int, size: float):
	# ======= BASE NOISE PROPERTIES =======
	terrain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	# Frequency defines a "zoom level" for the noise. the lower the value, the smoother and larger features are. Higher values makes features small and sharp
	terrain_noise.frequency = 0.01
	# Fequency Octaves is the number of frequency layers that are stacked together, multiplying frequencies together while decreasing in strength along each octive.
	terrain_noise.fractal_octaves = 1
	# Fractal Lacunariy is the multiplier from one octave to another. High values makes higher octives produce finer, roughter features. Default is 2.0
	terrain_noise.fractal_lacunarity = 2.0
	# Fractal Gain is how much each successive octave contributes. Lower values emphasize lower octaves. Default is 0.5
	terrain_noise.fractal_gain = 0.25
	terrain_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	# ======= DOMAIN WARP PROPERTIES =======
	terrain_noise.domain_warp_enabled = true
	terrain_noise.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	terrain_noise.domain_warp_frequency = 0.1
	terrain_noise.domain_warp_fractal_octaves = 4
	terrain_noise.domain_warp_fractal_lacunarity = 2.0
	terrain_noise.domain_warp_fractal_gain = 0.25
	terrain_noise.domain_warp_amplitude = 2.5
	terrain_noise.seed = _seed
	center = Vector3(size / 2, size / 2, size / 2)
	floor_distance = size / 2 / 2

## Get a noise sample biased towards a world shape at a specific Vec3 of the noise volume
func sample(x: float, y: float, z: float) -> float:
	var _sample := terrain_noise.get_noise_3d(x, y, z)
	var pos := Vector3(x, y, z)
	var bias := (pos.distance_to(center) - floor_distance) * FLOOR_BIAS
	return _sample + bias

func get_bias_from_distance(distance: float) -> float:
	return (distance - floor_distance) * FLOOR_BIAS
