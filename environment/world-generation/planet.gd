class_name Planet
extends Node3D

@export var player: Player
@export var world_seed: int = 1
## 20 * 2^size = total_volume. totle_volume/2 = diameter. Size = max octree depth
@export var size := 5
@export var rotation_speed := .04
@export var rotation_axis := Vector3(randf(), randf(), randf()).normalized()

@onready var gravity_shape := $GravityArea/GravityShape

var chunk_manager: ChunkManager
var total_volume: Vector3
var diameter: int

func _ready() -> void:
	total_volume = Vector3(20 * pow(2, size), 20 * pow(2, size), 20 * pow(2, size))
	diameter = int(total_volume.x / 2)
	# determine overall size of volume and set the mesh to be at the center by placing that manager's origin and -radius
	chunk_manager = ChunkManager.new(player, world_seed, size)
	chunk_manager.position = -total_volume / 2 # place chunk_manger so that it's volumetric center lines up with the Planet node center
	self.add_child(chunk_manager)
	gravity_shape.shape.radius = diameter * 3

var n_tries = 0
## Called by Player to find a valid spawn point on this planet that places them 1m above a random point on the planet. Will cause an infinite loop is player is loaded in first. Ensure player is loaded in below all Planet nodes
func get_valid_spawn_point() -> Vector3:
	n_tries += 1
	print("searching for spawn ", n_tries)
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
			print("spawn location found: ", sample_pos)
			return sample_pos - volume_center + direction * 2 + global_position # set spawn to be 2 meters above the point found to ensure player is above the mesh.
		prev_scalar = sample_scalar
		i += 1
	
	if n_tries == 5:
		push_error("No valid spawn point found after 5 tries. Spawning player at 0, 0, 0")
		return Vector3(0,0,0)
	
	# if no valid spawn point is found, run the function again (which will choose a different random direction). This should never be run. Hopefully.
	return get_valid_spawn_point()

func _physics_process(delta: float) -> void:
	self.global_rotate(rotation_axis, rotation_speed * delta)

func _on_gravity_area_body_entered(body: Node3D) -> void:
	if body is Player:
		body.current_world = self


func _on_gravity_area_body_exited(body: Node3D) -> void:
	if body is Player:
		body.current_world = null
