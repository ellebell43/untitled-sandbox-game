extends Node3D
class_name ChunkManager

## The size of each chunk in meters
var chunk_size := 20
## The number of chunks on each axis. Determined from passed in _max_octree_depth in _init()
var chunk_count: int
## Scalar field that is used to determine the shape of the mesh along the chunks.
var noise: WorldNoise
## Reference to the palyer node
var player: Player

# ========== CHUNK MANAGEMENT VARIABLES ==========

## Stores all marching cube tasks waiting to be completed off the main thread. int is the task ID, Chunk is the actual Chunk node waiting on the task
var pending_tasks: Dictionary[int, Chunk] = {}
## Tracks total tasks completed and stops increasing after a set number of tasks (defined in the moment, further down)
var total_tasks_completed := 0
## Maximum "task completed" signals to emit.
var max_signals_emmited := 1000
## When true, total_tasks_completed will no longer be tracked. Everytime a task completes a signal is emmited. For use in a loading screen.
var final_signal_emmited := false
## How eagerly chunks split into finer chunks. The higher the number, the greater the distance gate to determine how fine the chunk is. 
var distance_factor := 2
## The total size of the noise volume, and therefore the size of the root octree node. Where the entire volume is treated as 1 chunk_size chunk
var root_node_size: int
## Dictionary[[position, lod_level], chunk]. The current set of octree chunks loaded into the scene
var leaf_set: Dictionary[Array, Chunk] = {}
## Array[position: Vector3, lod_level: int] <- equates to a key to be set in the current leaf dictionary. Is used to compare against leaf_set and unload chunks that should no longer be loaded in
var new_leaf_set: Array = []
## The maximum depth that the octree will go to. Same as Planet.size. (20 * 2^size = WorldNoise.size)
var max_octree_depth: int
## The previously recorder player position. Used to only iterate through the octree when the player moves player_movement_threshold meters
var prev_player_pos: Vector3
## Used to determine when the octree should be iterated through to prevent a per-frame iteration.
var player_movement_threshold := 10

func _init(_player: Player, _seed: int, _max_octree_depth: int) -> void:
	self.max_octree_depth = _max_octree_depth
	self.chunk_count = int(pow(2, max_octree_depth))
	self.noise = WorldNoise.new(_seed, chunk_size * pow(2, max_octree_depth))
	self.player = _player
	self.root_node_size = int(chunk_size * pow(2, max_octree_depth))

func _ready() -> void:
	# if global Util.verbose is true, print total chunk count volume
	if Utils.verbose: print("Chunk manager ready. Total chunk count: ", int(pow(chunk_count, 3)))

func _process(_delta: float) -> void:
	# If a player position hasn't been recorded yet, iterate through the octree for the first time, compare leaf sets (loads new_leaf_set into leaf_set to load chunks in), and record player position
	if not prev_player_pos:
		octree_iterate()
		compare_leaf_sets()
		prev_player_pos = player.position
	# When the player passes the movement threshold, store the new position, clear the new leaf set, re-iterate through the octree, and compare leaf sets to update chunks
	if player.position.distance_to(prev_player_pos) >= player_movement_threshold:
		prev_player_pos = player.position
		new_leaf_set = []
		octree_iterate()
		compare_leaf_sets()
	
	# Iterate through pending tasks (created from leaf_set chunks; see load_octree_chunk()) and add a maximum of 10 meshs to the scene tree per frame
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
			# If we haven't emited to max_signals_emitted, increment total_tasks completed and emit chunk_task_completed
			if not final_signal_emmited:
				total_tasks_completed += 1
				Utils.chunk_task_completed.emit(total_tasks_completed)
				if total_tasks_completed >= max_signals_emmited: final_signal_emmited = true

			# Remove the task from the set of pending tasks once it's finished
			pending_tasks.erase(id)

## Iterate through the octree, starting at the root node, and determine what chunks need to be split until depth reaches max_octree_depth. Add chunks to new_leaf_set to be compared against leaf_set later
func octree_iterate(depth: int = 0, parent_pos: Vector3i = Vector3.ZERO) -> void:
	var cell_size := int(root_node_size / pow(2, depth))
	# iterate through cells at this octree depth and either continue iterating, or append to new leaf set depending on distance to player
	# Each cell can be split into 8 cells, then each of those can be split into finer 8 cells depending on distance to player and distance_factor
	for _x in 2:
		for _y in 2:
			for _z in 2:
				var cell_pos = parent_pos + Vector3i(cell_size * _x, cell_size * _y, cell_size * _z)
				var cell_center = cell_pos + Vector3i(cell_size / 2, cell_size / 2, cell_size / 2)
				if cell_center.distance_to(to_local(player.global_position)) < cell_size * distance_factor and depth < max_octree_depth:
					octree_iterate(depth + 1, cell_pos)
				else:
					var lod_step := cell_size / chunk_size
					new_leaf_set.append([Vector3i(cell_pos), lod_step])

## Take new_leaf_set and leaf_set and determine chunks to load and unload
func compare_leaf_sets() -> void:
	var keys = leaf_set.keys()
	# el : Array[chunk_pos, lod_step]
	for el in new_leaf_set:
		# if item in new leaf set isn't in the dictionary, load it.
		if not leaf_set.has(el):
			load_octree_chunk(el[0], el[1])
	# key : Array[chunk_pos, lod_step]
	for key in keys:
		# if key cannot be found in new_leaf_set, unload that chunk
		var should_stay_in_set := new_leaf_set.find(key)
		if should_stay_in_set == -1:
			unload_octree_chunk(key[0], key[1])

## Create a new Chunk node, add it to the tree, then set its mesh generation to be outside the main thread.
func load_octree_chunk(chunk_pos: Vector3i, lod_step: int) -> void:
	var new_chunk = Chunk.new(chunk_size, noise, chunk_pos, lod_step)
	self.add_child(new_chunk)
	new_chunk.position = chunk_pos
	leaf_set.set([chunk_pos, lod_step], new_chunk)
	
	# use threads to generate mesh data
	var task_id = WorkerThreadPool.add_task(new_chunk.generate_mesh_data)
	pending_tasks.set(task_id, new_chunk)

## Ensure a Chunks pending thread task is completed, then remove the chunk from the scene and the leaf set. Remove the task id from pending tasks as well.
func unload_octree_chunk(chunk_pos: Vector3i, lod_step: int) -> void:
	var chunk_to_unload: Chunk = leaf_set.get([chunk_pos, lod_step])
	
	# ensure thread task is complete before removing the chunk
	var task_id = pending_tasks.find_key(chunk_to_unload)
	if task_id != null:
		WorkerThreadPool.wait_for_task_completion(task_id)
		pending_tasks.erase(task_id)
		
	# remove chunk from leaf set and remove Chunk from scene tree if possible.
	leaf_set.erase([chunk_pos, lod_step])
	if chunk_to_unload: chunk_to_unload.queue_free()
