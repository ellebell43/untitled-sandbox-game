extends Node3D
class_name ChunkManager

## The size of each chunk
var chunk_size := 20
## The number of chunks on each axis
var chunk_count: int
## Scalar field that is used to determine the shape of the mesh along the chunks.
var noise: WorldNoise
## Reference to the palyer node
var player: Player
## The chunk scale distance a chunk must be in to be rendered at full resolution
var render_distance := 5

var verbose := false

var loaded_chunks: Dictionary[Vector3, Chunk] = {}
var pending_tasks: Dictionary[int, Chunk] = {}
var total_tasks_completed := 0
var final_signal_emmited := false

func _init( _player: Player, _seed: int, _diameter: int) -> void:
	@warning_ignore("integer_division")
	self.chunk_count = (_diameter * 2) / chunk_size
	self.noise = WorldNoise.new(_seed, _diameter * 2)
	self.player = _player
	self.root_node_size = chunk_count * chunk_size

func _ready() -> void:
	if verbose: print("Chunk manager ready. Total chunk count: ", pow(chunk_count, 3))

func _process(_delta: float) -> void:
	if not final_signal_emmited:
		Utils.chunk_task_completed.emit(total_tasks_completed)
		if total_tasks_completed >= 400: final_signal_emmited = true
	
	octree_iterate()
	
	#var player_chunk_pos = get_player_chunk_pos()
	## Iterate through chunks in render distance and load them
	#var chunk_min = player_chunk_pos - Vector3i(render_distance, render_distance, render_distance)
	#var chunk_max = player_chunk_pos + Vector3i(render_distance, render_distance, render_distance)
	#var chunk_x = chunk_min.x
	#while chunk_x <= chunk_max.x:
		#var chunk_y = chunk_min.y
		#while chunk_y <= chunk_max.y:
			#var chunk_z = chunk_min.z
			#while chunk_z <= chunk_max.z:
				#var current_chunk_pos = Vector3i(chunk_x, chunk_y, chunk_z)
				## If current_chunk_pos is within the render distance of the player_chunk_pos, and it's not in the loaded dictionary, load the chunk
				#if (player_chunk_pos).distance_to(current_chunk_pos) < render_distance and not loaded_chunks.has(current_chunk_pos):
					#load_chunk(current_chunk_pos)
				#chunk_z += 1
			#chunk_y += 1
		#chunk_x += 1
	#
	## Iterate through loaded chunks and unload chunks that are out of render distance.
	#var dict_keys = loaded_chunks.keys()
	#for chunk_pos in dict_keys:
		#if (player_chunk_pos).distance_to(chunk_pos) > render_distance and loaded_chunks.has(chunk_pos):
				#unload_chunk(chunk_pos)
		#
	#if verbose: print("chunks loaded: ",loaded_chunks.size())
	
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
			if not final_signal_emmited: total_tasks_completed += 1
			pending_tasks.erase(id)

#func get_player_chunk_pos() -> Vector3i:
	#return (to_local(player.global_position) / chunk_size)
#
#func load_chunk(chunk_pos: Vector3i) -> void:
	#var new_chunk = Chunk.new(chunk_size, noise, chunk_pos * chunk_size)
	#self.add_child(new_chunk)
	#new_chunk.position = chunk_pos * chunk_size
	#loaded_chunks.set(chunk_pos, new_chunk)
	#
	## use threads to generate mesh data
	#var task_id = WorkerThreadPool.add_task(new_chunk.genrate_mesh_data)
	#pending_tasks.set(task_id, new_chunk)
#
#func unload_chunk(chunk_pos: Vector3i) -> void:
	##if verbose: print("Unloading chunk at chunk position ", chunk_pos)
	#var chunk_to_unload: Chunk = loaded_chunks.get(chunk_pos)
	#var task_id = pending_tasks.find_key(chunk_to_unload)
	#if task_id: 
		#WorkerThreadPool.wait_for_task_completion(task_id)
		#pending_tasks.erase(task_id)
	#loaded_chunks.erase(chunk_pos)
	#if chunk_to_unload: chunk_to_unload.queue_free()

# Octree variables
var distance_factor := 1
var root_node_size : int
## Dictionary[[position, lod_level], chunk]
var leaf_set: Dictionary[Array, Chunk] = {}

func octree_iterate(depth: int = 1, parent_pos: Vector3 = self.position):
	var cell_size := root_node_size / pow(2, depth)
	# Array[position: Vector3, lod_level: int] <- equates to a key to be set in the current leaf dictionary
	var new_leaf_set: Array = []
	# iterate through cells at this octree depth and either continue iterating, or append to new leaf set depending on distance to player
	for _x in 2:
		for _y in 2:
			for _z in 2:
				var cell_pos = parent_pos + Vector3(cell_size * _x, cell_size * _y, cell_size * _z)
				var cell_center = cell_pos + Vector3(cell_size / 2, cell_size / 2, cell_size / 2)
				if cell_center.distance_to(player.global_position) < cell_size * distance_factor and depth < chunk_count:
					octree_iterate(depth + 1, cell_pos)
				else:
					var lod_step := cell_size / chunk_size
					new_leaf_set.append([cell_pos, lod_step])
	
	var keys = leaf_set.keys()
	# key : Array[chunk_pos, lod_step]
	for key in keys:
		# if key cannot be found in new_leaf_set, unload that chunk
		var should_stay_in_set := new_leaf_set.find(key)
		if should_stay_in_set == -1:
			unload_octree_chunk(key[0], key[1])
	# el : Array[chunk_pos, lod_step]
	for el in new_leaf_set:
		# if item in new leaf set isn't in the dictionary, load it.
		if not leaf_set.has(el):
			load_octree_chunk(el[0], el[1])

func load_octree_chunk(chunk_pos: Vector3i, lod_step: int) -> void:
	var new_chunk = Chunk.new(chunk_size, noise, chunk_pos * chunk_size, lod_step)
	self.add_child(new_chunk)
	new_chunk.position = chunk_pos * chunk_size
	leaf_set.set([chunk_pos, lod_step], new_chunk)
	
	# use threads to generate mesh data
	var task_id = WorkerThreadPool.add_task(new_chunk.genrate_mesh_data)
	pending_tasks.set(task_id, new_chunk)

func unload_octree_chunk(chunk_pos: Vector3i, lod_step: int) -> void:
	var chunk_to_unload: Chunk = leaf_set.get([chunk_pos, lod_step])
	
	# ensure thread task is complete before removing the chunk
	var task_id = pending_tasks.find_key(chunk_to_unload)
	if task_id: 
		WorkerThreadPool.wait_for_task_completion(task_id)
		pending_tasks.erase(task_id)
		
	# remove chunk from leaf set and remove Chunk from scene tree if possible.
	leaf_set.erase([chunk_pos, lod_step])
	if chunk_to_unload: chunk_to_unload.queue_free()
