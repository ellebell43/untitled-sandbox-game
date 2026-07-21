class_name Planet
extends Node3D

## Reference to the Player node. Used to find determine what LOD level to render chunks at.
@export var player: Player
## Determines the world that is generated
@export var world_seed: int = 1
## ChunkManager.chunk_size * 2^size = total_volume. total_volume/2 = suface diameter. size = max_octree_depth in the ChunkManager.chunk_size. (ChunkManager.chunk_size = 20)
@export var size := 5
## How quickly the planet rotates in radians/sec
@export var rotation_speed := 0.04
## The axis that the planet spins on
@export var rotation_axis := Vector3(randf(), randf(), randf()).normalized()

## Reference to the shape of the GravityArea Area3D node. Size is set to diameter * 2 in _ready()
@onready var gravity_shape := $GravityArea/GravityShape

enum WorldType {
	TEMPERATE,
	HOT,
	COLD,
	BARREN,
	GAS
}

## Reference to the local ChunkManager for this planet.
var chunk_manager: ChunkManager
## The size of the total noise volume on each axis. Determined by size: Vector3(20 * 2^size)
var total_volume: Vector3
## The general diameter of the planet mesh: (20 * 2^size) / 2
var diameter: int

func _ready() -> void:
	# initialize the chunk_manager
	chunk_manager = ChunkManager.new(player, world_seed, size)
	self.add_child(chunk_manager)
	# determine total volume, planet diameter, and gravity radius from self.size and chunk_manager.chunk_size
	var volume_length = chunk_manager.chunk_size * pow(2, size)
	total_volume = Vector3(volume_length, volume_length, volume_length)
	diameter = int(volume_length / 2)
	gravity_shape.shape.radius = diameter * 2
	# set the chunk_manager position so that the planet mesh is center at the node origin
	chunk_manager.position = - total_volume / 2

## The number of tries there has been to find a valid spawn point.
var n_tries = 0
## Called by Player to find a valid spawn point on this planet that places them 1m above a random point on the planet. Will cause an infinite loop if player is loaded in first. Ensure player is loaded in below all Planet nodes
func get_valid_spawn_point() -> Vector3:
	if Utils.debug: print("spawn planet is ", self)
	n_tries += 1
	if Utils.debug: print("searching for spawn ", n_tries)
	# create WorldNoise object with the same seed and size as planet. Cannot use chunk_manager since player may load in before chunk_manager
	var noise := WorldNoise.new(world_seed, total_volume.x)
	# get a random direction vector
	var direction := Vector3(randf(), randf(), randf()).normalized()
	# get a starting position that is at the center of the volume to start sampling + 1/4 of the way out of the volume
	var volume_center := total_volume / 2
	@warning_ignore("integer_division")
	var starting_pos = volume_center + direction * ((diameter / 2) - 50) # start 50 steps below the median surface level
	
	# while loop variables
	var max_steps := 100 # don't sample beyond 50 steps past the median surface level, 100 steps total
	var prev_scalar: float
	var i := 1
	
	# sample scalars from the center of the volume, in random direction, to the edge of the volume and stop when the surface is found and return that value
	while i < max_steps:
		var sample_pos = starting_pos + direction * i
		var sample_scalar = noise.sample(sample_pos.x, sample_pos.y, sample_pos.z)
		if i != 1 and prev_scalar < 0 and sample_scalar > 0:
			if Utils.debug: print("spawn location found: ", sample_pos)
			return sample_pos - volume_center + direction * 2 + global_position # set spawn to be 2 meters above the point found to ensure player is above the mesh.
		prev_scalar = sample_scalar
		i += 1
	
	## If a spawn point could not be found after 5 tries, throw error and return Vector.ZERO as spawn point.
	if n_tries == 5:
		push_error("No valid spawn point found after 5 tries. Spawning player at 0, 0, 0")
		return Vector3.ZERO
	
	# if no valid spawn point is found, run the function again (which will choose a different random direction). This should never be run. Hopefully.
	return get_valid_spawn_point()

func _physics_process(delta: float) -> void:
	# Rotate planet along the rotation_axis by the rotation_speed
	self.global_rotate(rotation_axis, rotation_speed * delta)

func _on_gravity_area_body_entered(body: Node3D) -> void:
	if body is Player:
		body.current_world = self

func _on_gravity_area_body_exited(body: Node3D) -> void:
	if body is Player:
		body.current_world = null
