class_name Planet
extends Node3D

@export var player: Player
@export var world_seed: int = 1
## number of units on each axis that a chunk takes up
@export var chunk_size := 20
## number of chunks per axis.
@export var chunk_count := 10
var diameter := (chunk_size * chunk_count)
var size := Vector3(diameter, diameter, diameter)
## number of chunks to render out

@export var render_distance := 4
@export var rotation_speed := .04
@export var rotation_axis := Vector3(0, 0.5, 1).normalized()

@onready var gravity_shape := $GravityArea/GravityShape

var world_radius := (chunk_size * chunk_count) / 2.5 # 2.5 is where the floor value is in relation to the noise volume as a whole. see WorldNoise class
var chunk_manager: ChunkManager
var offset := -Vector3(world_radius, world_radius, world_radius)

func _ready() -> void:
	# determine overall size of volume and set the mesh to be at the center by placing that manager's origin and -radius
	chunk_manager = ChunkManager.new(player, world_seed, render_distance, chunk_size, chunk_count)
	chunk_manager.position = -size / 2 # place chunk_manger so that it's volumetric center lines up with the Planet node center
	self.add_child(chunk_manager)
	gravity_shape.shape.radius = world_radius * 3

## Called by Player to find a valid spawn point on this planet that places them 1m above a random point on the planet
func get_valid_spawn_point() -> Vector3:
	# create WorldNoise object with the same seed and size as planet. Cannot use chunk_manager since player may load in before chunk_manager
	var noise := WorldNoise.new(world_seed, chunk_count * chunk_size)
	# get a random direction vector
	var direction := Vector3(randf(), randf(), randf()).normalized()
	# get a starting position that is at the center of the volume to start sampling
	var starting_pos := size / 2
	
	# while loop variables
	var max_steps := diameter # don't sample beyond the diameter of the noise volume
	var prev_scalar: float
	var i := 1
	
	# sample scalars from the center of the volume, in random direction, to the edge of the volume and stop when the surface is found and return that value
	while i < max_steps:
		var sample_pos = starting_pos + direction * i
		var sample_scalar = noise.sample(sample_pos.x, sample_pos.y, sample_pos.z)
		if i != 1 and prev_scalar < 0 and sample_scalar > 0:
			return (sample_pos - starting_pos) + (direction * 2) # set spawn to be 2 meters above the point found to ensure player is above the mesh.
		prev_scalar = sample_scalar
		i += 1
	
	# if no valid spawn point is found, run the function again (which will choose a different random direction). This should never be run. Hopefully.
	return find_valid_spawn_point()

func _physics_process(delta: float) -> void:
	self.global_rotate(rotation_axis, rotation_speed * delta)

func _on_gravity_area_body_entered(body: Node3D) -> void:
	if body is Player:
		body.current_world = self


func _on_gravity_area_body_exited(body: Node3D) -> void:
	if body is Player:
		body.current_world = null
