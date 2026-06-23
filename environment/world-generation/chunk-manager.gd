extends Node3D
class_name ChunkManager


## The size of each chunk
var chunk_size := 20
## The number of chunks on each axis
var chunk_count: int
var noise: WorldNoise
var player: Player
var render_distance := 5

var verbose := true

var loaded_chunks: Dictionary[Vector3, Chunk] = {}
var pending_tasks: Dictionary[int, Chunk] = {}

func _init( _player: Player, _seed: int, _diameter: int) -> void:
	@warning_ignore("integer_division")
	self.chunk_count = (_diameter * 2) / chunk_size
	self.noise = WorldNoise.new(_seed, _diameter * 2)
	self.player = _player

func _ready() -> void:
	if verbose: print("Chunk manager ready. Total chunk count: ", pow(chunk_count, 3))		

func _process(_delta: float) -> void:
	var player_chunk_pos = get_player_chunk_pos()
	# Iterate through chunks in render distance and load them
	var chunk_min = player_chunk_pos - Vector3i(render_distance, render_distance, render_distance)
	var chunk_max = player_chunk_pos + Vector3i(render_distance, render_distance, render_distance)
	var chunk_x = chunk_min.x
	while chunk_x <= chunk_max.x:
		var chunk_y = chunk_min.y
		while chunk_y <= chunk_max.y:
			var chunk_z = chunk_min.z
			while chunk_z <= chunk_max.z:
				var current_chunk_pos = Vector3i(chunk_x, chunk_y, chunk_z)
				# If current_chunk_pos is within the render distance of the player_chunk_pos, and it's not in the loaded dictionary, load the chunk
				if (player_chunk_pos).distance_to(current_chunk_pos) < render_distance and not loaded_chunks.has(current_chunk_pos):
					#print("distance to chunk being loaded: ", current_chunk_pos.distance_to(player_chunk_pos))
					load_chunk(current_chunk_pos)
				chunk_z += 1
			chunk_y += 1
		chunk_x += 1
	
	# Iterate through loaded chunks and unload chunks that are out of render distance.
	var dict_keys = loaded_chunks.keys()
	for chunk_pos in dict_keys:
		if (player_chunk_pos).distance_to(chunk_pos) > render_distance and loaded_chunks.has(chunk_pos):
				unload_chunk(chunk_pos)
		
	if verbose: print("chunks loaded: ",loaded_chunks.size())
	
	# Iterate through pending tasks (completed chunk data generation) and add a maximum of 5 meshs to the scene tree per frame
	const MAXIMUM_TASK_COMPLETIONS = 10
	var tasks_completed = 0
	var pending_keys = pending_tasks.keys()
	for id in pending_keys:
		if tasks_completed >= MAXIMUM_TASK_COMPLETIONS:
			break
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			var chunk = pending_tasks.get(id)
			if chunk != null and chunk.mesh_data != null:
				chunk.build_mesh()
			tasks_completed += 1
			pending_tasks.erase(id)

func get_player_chunk_pos() -> Vector3i:
	return (to_local(player.global_position) / chunk_size)

func load_chunk(chunk_pos: Vector3i) -> void:
	var new_chunk = Chunk.new(chunk_size, noise, chunk_pos * chunk_size)
	self.add_child(new_chunk)
	new_chunk.position = chunk_pos * chunk_size
	loaded_chunks.set(chunk_pos, new_chunk)
	
	# use threads to generate mesh data
	var task_id = WorkerThreadPool.add_task(new_chunk.genrate_mesh_data)
	pending_tasks.set(task_id, new_chunk)

func unload_chunk(chunk_pos: Vector3i) -> void:
	#if verbose: print("Unloading chunk at chunk position ", chunk_pos)
	var chunk_to_unload: Chunk = loaded_chunks.get(chunk_pos)
	var task_id = pending_tasks.find_key(chunk_to_unload)
	if task_id: 
		WorkerThreadPool.wait_for_task_completion(task_id)
		pending_tasks.erase(task_id)
	loaded_chunks.erase(chunk_pos)
	if chunk_to_unload: chunk_to_unload.queue_free()
