class_name Planet
extends Node3D

@export var player: Player
@export var world_seed: int = 1
## number of units on each axis that a chunk takes up
@export var chunk_size := 20
## number of chunks per axis.
@export var chunk_count := 10
## number of chunks to render out
@export var render_distance := 4

@onready var gravity_shape := $GravityArea/GravityShape

var world_radius = (chunk_size * chunk_count) / 2.5

func _ready() -> void:
	var chunk_manager = ChunkManager.new(player, world_seed, render_distance, chunk_size, chunk_count)
	# determine overall size of volume and set the mesh to be at the center by placing that manager's origin and -radius
	chunk_manager.position = -Vector3(world_radius, world_radius, world_radius)
	self.add_child(chunk_manager)
	#var total_size = chunk_size
	#global_position = -Vector3(total_size, total_size, total_size)
	gravity_shape.shape.radius = world_radius * 3
