extends Node3D

@export var player: Player
@export var world_seed: int = 1
## number of units on each axis that a chunk takes up
@export var chunk_size := 20
## number of chunks per axis.
@export var chunk_count := 10
## number of chunks to render out
@export var render_distance := 4

func _ready() -> void:
	var chunk_manager = ChunkManager.new(player, world_seed, render_distance, chunk_size, chunk_count)
	self.add_child(chunk_manager)
	var total_size = chunk_size
	global_position = -Vector3(total_size, total_size, total_size)
