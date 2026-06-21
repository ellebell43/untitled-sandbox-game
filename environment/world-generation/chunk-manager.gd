extends Node3D
class_name ChunkManager

@export var verbose := false

## The size of each chunk
var chunk_size: int
## The number of chunks on each axis
var chunk_count: int
var noise: WorldNoise
var player: Player
var render_distance: int

var loaded_chunks: Dictionary[Vector3, Chunk] = {}

func _init( _player: Player, _seed: int, _render_distance: int = 5, _chunk_size: int = 25, _chunk_count: int = 10,) -> void:
	self.chunk_size = _chunk_size
	self.chunk_count = _chunk_count
	self.noise = WorldNoise.new(_seed, _chunk_count * _chunk_size)
	self.player = _player
	self.render_distance = _render_distance

func _ready() -> void:
	if verbose: print("Chunk manager ready. Total chunk count: ", pow(chunk_count, 3))
	if verbose: print("Chunk manager located at ", self.global_position)

func _process(_delta: float) -> void:
	var player_chunk_pos = get_player_chunk_pos()
	for x in chunk_count:
		for y in chunk_count:
			for z in chunk_count:
				var current_chunk_pos = Vector3(x, y, z)
				# If current_chunk_pos is within the render distance of the player_chunk_pos, and it's not in the loaded dictionary, load the chunk
				if abs((player_chunk_pos).distance_to(current_chunk_pos)) < render_distance and not loaded_chunks.get(current_chunk_pos):
					load_chunk(current_chunk_pos)
				if abs((player_chunk_pos).distance_to(current_chunk_pos)) > render_distance and loaded_chunks.get(current_chunk_pos):
					unload_chunk(current_chunk_pos)

func get_player_chunk_pos() -> Vector3:
	return (to_local(player.global_position) / chunk_size)

func load_chunk(chunk_pos: Vector3) -> void:
	if verbose: print("Loading chunk at chunk position ", chunk_pos)
	var new_chunk = Chunk.new(chunk_size, noise, chunk_pos * chunk_size)
	self.add_child(new_chunk)
	new_chunk.position = chunk_pos * chunk_size
	if verbose: print("Chunk global pos: ", new_chunk.global_position)
	if verbose: print("Player global pos: ", player.global_position)
	loaded_chunks.set(chunk_pos, new_chunk)
	
	# use threads to populate chunk node with mesh
	var task_id = WorkerThreadPool.add_task(new_chunk.genrate_mesh_data)
	WorkerThreadPool.wait_for_task_completion(task_id)
	if new_chunk != null and new_chunk.mesh_data != null:
		new_chunk.build_mesh()

func unload_chunk(chunk_pos: Vector3) -> void:
	if verbose: print("Unloading chunk at chunk position ", chunk_pos)
	var chunk_to_unload: Chunk = loaded_chunks.get(chunk_pos)
	if chunk_to_unload: chunk_to_unload.queue_free()
	loaded_chunks.erase(chunk_pos)
