extends Node3D
class_name ChunkManager

## The size of each chunk in meters
var chunk_size := 20
## The number of chunks on each axis. Determined from passed in _max_octree_depth in _init()
var chunk_count: int
## Scalar field that is used to determine the shape of the mesh along the chunks.
var noise: WorldNoise
## Reference to the player node
var player: Player

# ========== CHUNK MANAGEMENT VARIABLES ==========

## Stores all marching cube tasks waiting to be completed off the main thread. int is the task ID, Chunk is the actual Chunk node waiting on the task
var pending_tasks: Dictionary[int, Chunk] = {}
## Tracks total tasks completed and stops increasing after a set number of tasks (defined in the moment, further down)
var total_tasks_completed := 0
## Maximum "task completed" signals to emit.
var max_signals_emitted := 1000
## When true, total_tasks_completed will no longer be tracked. Every time a task completes a signal is emitted. For use in a loading screen.
var final_signal_emitted := false
## How eagerly chunks split into finer chunks. The higher the number, the greater the distance gate to determine how fine the chunk is. 
var distance_factor := 1.5
## The total size of the noise volume, and therefore the size of the root octree node. Where the entire volume is treated as 1 chunk_size chunk
var root_node_size: int
## The maximum depth that the octree will go to. Same as Planet.size. (20 * 2^size = WorldNoise.size)
var max_octree_depth: int
## The previously recorder player position. Used to only iterate through the octree when the player moves player_movement_threshold meters
var prev_player_pos: Vector3
## Used to determine when the octree should be iterated through to prevent a per-frame iteration.
var player_movement_threshold := 10
var first_iteration_complete := false

# ========== CHUNK SET DICTIONARIES ==========

# Dictionary[[position, lod_level], chunk].
var new_chunk_set: Dictionary[Array, int] = {} # value int is unimportant and never used
var pending_chunk_set: Dictionary[Array, Chunk] = {}
var active_chunk_set: Dictionary[Array, Chunk] = {}
var retiring_chunk_set: Dictionary[Array, Chunk] = {}
var ready_to_die_chunk_set: Dictionary[Array, Chunk] = {}

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
	# If a player position hasn't been recorded yet, iterate through the octree for the first time, compare leaf sets (loads new_chunk_set into current_chunk_set to load chunks in), and record player position
	if not first_iteration_complete:
		octree_iterate()
		load_new_chunks()
		prev_player_pos = player.position
		first_iteration_complete = true
	# When the player passes the movement threshold, store the new position, clear the new leaf set, re-iterate through the octree, and compare leaf sets to update chunks
	if player.position.distance_to(prev_player_pos) >= player_movement_threshold:
		prev_player_pos = player.position
		new_chunk_set.clear()
		octree_iterate()
		load_new_chunks()
	
	# unload_old_chunks()
	mark_retiring_chunks()
	check_retiring_chunks()
	kill_dead_chunks()

	# Iterate through pending tasks (created from current_chunk_set chunks; see load_octree_chunk()) and add a maximum of 10 meshes to the scene tree per frame
	const MAXIMUM_TASK_COMPLETIONS = 20
	var tasks_completed = 0
	var pending_keys = pending_tasks.keys()

	for id in pending_keys:
		if tasks_completed >= MAXIMUM_TASK_COMPLETIONS:
			break

		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
			
			var chunk: Chunk = pending_tasks.get(id)
			
			if chunk != null:
				chunk.state = Chunk.chunk_state.ACTIVE
				var key = [Vector3i(chunk.position), chunk.lod_step]
				if chunk.mesh_data != null: chunk.build_mesh()
				active_chunk_set.set(key, chunk)
				pending_chunk_set.erase(key)

			tasks_completed += 1
			# If we haven't emitted to max_signals_emitted, increment total_tasks completed and emit chunk_task_completed
			if not final_signal_emitted:
				total_tasks_completed += 1
				Utils.chunk_task_completed.emit(total_tasks_completed)
				if total_tasks_completed >= max_signals_emitted: final_signal_emitted = true

			# Remove the task from the set of pending tasks once it's finished
			pending_tasks.erase(id)

## Iterate through the octree, starting at the root node, and determine what chunks need to be split until depth reaches max_octree_depth. Add chunks to new_chunk_set to be compared against current_chunk_set later
func octree_iterate(depth: int = 0, parent_pos: Vector3i = Vector3.ZERO) -> void:
	var cell_size := int(root_node_size / pow(2, depth))
	# iterate through cells at this octree depth and either continue iterating, or append to new leaf set depending on distance to player
	# Each cell can be split into 8 cells, then each of those can be split into finer 8 cells depending on distance to player and distance_factor
	for _x in 2:
		for _y in 2:
			for _z in 2:
				# Get distance to edge of cell and use that to determine if the cell should render or split
				var cell_pos = Vector3(parent_pos) + Vector3(cell_size * _x, cell_size * _y, cell_size * _z)
				var player_pos := to_local(player.global_position)
				var player_pos_clamped := player_pos.clamp(cell_pos, Vector3(cell_size, cell_size, cell_size) + cell_pos)
				if player_pos_clamped.distance_to(to_local(player.global_position)) < cell_size * distance_factor and depth < max_octree_depth:
					octree_iterate(depth + 1, cell_pos)
				else:
					@warning_ignore("integer_division")
					var lod_step := cell_size / chunk_size
					new_chunk_set.set([Vector3i(cell_pos), lod_step], 0)

## Compare new_chunk_set vs pending_chunk_set and active_chunk_set to determine chunks to load and then load them
func load_new_chunks() -> void:
	# key : Array[chunk_pos, lod_step]
	for key in new_chunk_set.keys():
		if ready_to_die_chunk_set.has(key):
			active_chunk_set.set(key, ready_to_die_chunk_set[key])
			active_chunk_set.get(key).state = Chunk.chunk_state.ACTIVE
			ready_to_die_chunk_set.erase(key)
		elif retiring_chunk_set.has(key):
			active_chunk_set.set(key, retiring_chunk_set[key])
			active_chunk_set.get(key).state = Chunk.chunk_state.ACTIVE
			retiring_chunk_set.erase(key)
		elif not pending_chunk_set.has(key) and not active_chunk_set.has(key):
			load_octree_chunk(key[0], key[1])

## Compare active_chunk_set with new_chunk_set and move chunks from active to retiring.
func mark_retiring_chunks() -> void:
	var keys_to_move = []

	# Intentionally do not scan through pending chunks, as they most likely have a thread that cannot be killed part way through.
	for key in active_chunk_set.keys(): # key: [pos: Vector3, lod_step: int]
		var stay_active := new_chunk_set.has(key)
		if not stay_active and active_chunk_set[key].state != Chunk.chunk_state.RETIRING:
			keys_to_move.append(key)
	
	for key in keys_to_move:
		var chunk: Chunk = active_chunk_set.get(key)
		active_chunk_set.erase(key)
		chunk.state = Chunk.chunk_state.RETIRING
		retiring_chunk_set.set(key, chunk)

## Look through retiring chunks and see if their space is filled by ACTIVE chunks. If so, move to ready_to_die_chunks
func check_retiring_chunks() -> void:
	# Keep track of chunks that will need to be removed
	var chunks_to_remove: Array = []
	# For each retiring chunk, see if it's inside an active chunk or if it contains 8 active chunks. If so, add to chunks_to_remove
	for key in retiring_chunk_set.keys():
		var should_continue := false # Used to keep track of if a merge condition was met
		var candidate_chunks: Array[Chunk] = [] # Stores chunks that are inside the retiree chunk

		# retiree variables
		var retiree: Chunk = retiring_chunk_set.get(key)
		var retiree_axis_size: int = key[1] * chunk_size # key[1] = lod_step
		var retiree_axis_size_vector := Vector3(retiree_axis_size, retiree_axis_size, retiree_axis_size)
		var retiree_min := retiree.position
		var retiree_max := retiree.position + retiree_axis_size_vector

		for candidate: Chunk in active_chunk_set.values():
			# Candidate variables
			var candidate_axis_size := candidate.lod_step * chunk_size
			var candidate_axis_vector := Vector3(candidate_axis_size, candidate_axis_size, candidate_axis_size)
			var candidate_min := candidate.position
			var candidate_max := candidate.position + candidate_axis_vector

			# bools if retiree is/isn't inside the candidate per axis
			var retiree_x_is_in_candidate := retiree_min.x >= candidate_min.x and retiree_max.x <= candidate_max.x
			var retiree_y_is_in_candidate := retiree_min.y >= candidate_min.y and retiree_max.y <= candidate_max.y
			var retiree_z_is_in_candidate := retiree_min.z >= candidate_min.z and retiree_max.z <= candidate_max.z

			# Check merge condition. If it's inside an ACTIVE candidate, then the retiree can be killed
			var retiree_is_in_candidate := retiree_x_is_in_candidate and retiree_y_is_in_candidate and retiree_z_is_in_candidate
			if retiree_is_in_candidate:
				should_continue = true
				ready_to_die_chunk_set.set(key, retiree)
				chunks_to_remove.append(key)
				break
			
			# bools if candidate is/isn't inside the retiree per axis
			var candidate_x_is_in_retiree := candidate_min.x >= retiree_min.x and candidate_max.x <= retiree_max.x
			var candidate_y_is_in_retiree := candidate_min.y >= retiree_min.y and candidate_max.y <= retiree_max.y
			var candidate_z_is_in_retiree := candidate_min.z >= retiree_min.z and candidate_max.z <= retiree_max.z
			
			# Check split condition. If the ACTIVE candidate is inside the retiree, add to candidate_chunks
			var candidate_is_in_retiree = candidate_x_is_in_retiree and candidate_y_is_in_retiree and candidate_z_is_in_retiree
			if candidate_is_in_retiree: candidate_chunks.append(candidate)
		# If the merge condition had been matched, continue to next retiree chunk
		if should_continue: continue
		# If 8 ACTIVE candidates were found, add to chunks_to_remove and ready_to_die_chunk_set
		if candidate_chunks.size() == 8:
			ready_to_die_chunk_set.set(key, retiree)
			chunks_to_remove.append(key)
		
	# Remove READY_TO_DIE chunks from the retiring_chunk_set
	for key in chunks_to_remove:
		retiring_chunk_set.erase(key)
			
			
## Unload chunks in ready_to_die
func kill_dead_chunks() -> void:
	for key in ready_to_die_chunk_set.keys():
		unload_octree_chunk(key)

## Create a new Chunk node, add it to the tree, then set its mesh generation to be outside the main thread.
func load_octree_chunk(chunk_pos: Vector3i, lod_step: int) -> void:
	var new_chunk = Chunk.new(chunk_size, noise, chunk_pos, lod_step)
	self.add_child(new_chunk)
	new_chunk.position = chunk_pos
	pending_chunk_set.set([chunk_pos, lod_step], new_chunk)
	
	# use threads to generate mesh data
	var task_id = WorkerThreadPool.add_task(new_chunk.generate_mesh_data)
	pending_tasks.set(task_id, new_chunk)

## Ensure a Chunks pending thread task is completed, then remove the chunk from the scene and the leaf set. Remove the task id from pending tasks as well.
func unload_octree_chunk(key: Array) -> void:
	var chunk_to_unload: Chunk = ready_to_die_chunk_set.get(key)
	
	# ensure thread task is complete before removing the chunk
	var task_id = pending_tasks.find_key(chunk_to_unload)
	if task_id != null:
		WorkerThreadPool.wait_for_task_completion(task_id)
		pending_tasks.erase(task_id)
		
	# remove chunk from leaf set and remove Chunk from scene tree if possible.
	ready_to_die_chunk_set.erase(key)
	if chunk_to_unload:
		var mesh_instance = chunk_to_unload.find_child("ChunkMesh", true, false)
		#print(chunk_to_unload.get_children(true))
		if mesh_instance:
			var tween = create_tween()
			tween.tween_property(mesh_instance, "transparency", 1, 1)
			tween.tween_callback(chunk_to_unload.queue_free)
		else:
			chunk_to_unload.queue_free()
		
		#chunk_to_unload.queue_free()
