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

var verbose := false

# ========== CHUNK MANAGEMENT VARIABLES ==========

## Stores all marching cube tasks waiting to be completed off the main thread. int is the task ID, Chunk is the actual Chunk node waiting on the task
var pending_tasks: Dictionary[int, Chunk] = {}
var total_first_tasks: int
var tasks_emitted := 0
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
	var start_time = Time.get_ticks_usec()
	# If a player position hasn't been recorded yet, iterate through the octree for the first time, compare leaf sets (loads new_chunk_set into current_chunk_set to load chunks in), and record player position
	var iterate_time: int
	if not first_iteration_complete:
		octree_iterate()
		load_new_chunks()
		total_first_tasks = pending_tasks.size()
		if player.spawn_world == self.get_parent():
			Utils.emit_signal("chunk_task_count_found", total_first_tasks)
		prev_player_pos = player.position
		first_iteration_complete = true
		iterate_time = Time.get_ticks_usec() - start_time
		if verbose: print("octree iteration time: ", iterate_time)
	# When the player passes the movement threshold, store the new position, clear the new leaf set, re-iterate through the octree, and compare leaf sets to update chunks
	if player.position.distance_to(prev_player_pos) >= player_movement_threshold:
		prev_player_pos = player.position
		new_chunk_set.clear()
		octree_iterate()
		load_new_chunks()
		iterate_time = Time.get_ticks_usec() - start_time
		if verbose: print("octree iteration time: ", iterate_time)

	
	# unload_old_chunks()
	mark_retiring_chunks()
	var retirees_set_time: int
	if iterate_time: retirees_set_time = Time.get_ticks_usec() - start_time - iterate_time
	else: retirees_set_time = Time.get_ticks_usec() - start_time
	if verbose: print("retirees mark time: ", retirees_set_time)
	check_retiring_chunks()
	var check_retired_time = Time.get_ticks_usec() - retirees_set_time - start_time
	if verbose: print("retiree check time: ", check_retired_time)
	kill_dead_chunks()
	var chunks_killed_time = Time.get_ticks_usec() - check_retired_time - start_time
	if verbose: print("chunks killed time: ", chunks_killed_time)

	# Iterate through pending tasks (created from current_chunk_set chunks; see load_octree_chunk()) but stop after 3ms
	const MAXIMUM_BUILD_TIME = 3000 # time in microseconds
	var current_build_time = 0 
	var pending_keys = pending_tasks.keys()

	for id in pending_keys:
		if current_build_time >= MAXIMUM_BUILD_TIME:
			break

		if WorkerThreadPool.is_task_completed(id):
			var thread_start_time = Time.get_ticks_usec()
			WorkerThreadPool.wait_for_task_completion(id)
			
			var chunk: Chunk = pending_tasks.get(id)
			
			if chunk != null:
				chunk.state = Chunk.chunk_state.ACTIVE
				var key = [Vector3i(chunk.position), chunk.lod_step]
				if chunk.mesh_data != null: chunk.build_mesh()
				active_chunk_set.set(key, chunk)
				pending_chunk_set.erase(key)

			# Remove the task from the set of pending tasks once it's finished
			pending_tasks.erase(id)
			current_build_time += Time.get_ticks_usec() - thread_start_time
			if tasks_emitted < total_first_tasks and player.spawn_world == self.get_parent():
				tasks_emitted += 1
				Utils.emit_signal("chunk_task_completed", tasks_emitted)
	if verbose: print("mesh build time: ", current_build_time)

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
		# retiree variables
		var retiree: Chunk = retiring_chunk_set.get(key)

		var parent_key: Array # [pos: Vector3i, lod_step: int]

		# Add merge case chunks to keys_to_check calculating parent chunk depth and position
		var parent_cell_lod_step := retiree.lod_step * 2
		var parent_cell_size := chunk_size * parent_cell_lod_step
		var parent_pos_x: int = floor(retiree.position.x / parent_cell_size) * parent_cell_size # using floor() drops the decimal, giving us parent grid space position when we re-multiply by parent_cell_size
		var parent_pos_y: int = floor(retiree.position.y / parent_cell_size) * parent_cell_size
		var parent_pos_z: int = floor(retiree.position.z / parent_cell_size) * parent_cell_size
		parent_key = [Vector3i(parent_pos_x, parent_pos_y, parent_pos_z), parent_cell_lod_step]

		# If the parent is active, the retiree can be killed
		if active_chunk_set.has(parent_key):
			ready_to_die_chunk_set.set(key, retiree)
			chunks_to_remove.append(key)
			continue
		
		if retiree.lod_step == 1: continue
		@warning_ignore("integer_division")
		if split_test(retiree.lod_step / 2, retiree.position) == true:
			ready_to_die_chunk_set.set(key, retiree)
			chunks_to_remove.append(key)
			continue
	
	for key in chunks_to_remove:
		retiring_chunk_set.erase(key)

func split_test(lod_step: int, parent_pos: Vector3i) -> bool:
	if lod_step == 1: return false
	var cell_size := chunk_size * lod_step
	# iterate through cells at this octree depth and either continue iterating, or append to new leaf set depending on distance to player
	# Each cell can be split into 8 cells, then each of those can be split into finer 8 cells depending on distance to player and distance_factor
	for _x in 2:
		for _y in 2:
			for _z in 2:
				var cell_pos = parent_pos + Vector3i(_x, _y, _z) * cell_size
				if lod_step > 1 and not active_chunk_set.has([cell_pos, lod_step]):
					@warning_ignore("integer_division")
					split_test(lod_step / 2, cell_pos)
				elif lod_step == 1 and not active_chunk_set.has([cell_pos, lod_step]):
					return false
	return true
			
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
