class_name Chunk
extends Node3D

# ============ BASIC CHUNK CHARACTERISTICS ============

enum chunk_state {PROCESSING, ACTIVE, RETIRING, READY_TO_DIE}

## The amount of points along the x, y, and z axis
var size: int
## Seed of the terrain generation
var world_seed: int
## noise volume to use for generating mesh data
var scalar: WorldNoise = null
## The value of the scalar field that represents the surface of the mesh
var isosurface := 0.0
## Chunk space offset to apply to vertex positions
var offset := Vector3(0, 0, 0)
## The scale/resolution of the chunk. For use in octree traversal for LODs
var lod_step: int
## The data for the mesh of this chunk. Generated in _generate_mesh_data
var mesh_data: ArrayMesh
## Is either PROCESSING, ACTIVE, or PENDING and is used to ensure that other chunks are loaded in before this chunk free itself to prevent LOD "popping"
var state := chunk_state.PROCESSING:
	set(new_state):
		state = new_state
		# If state is set to ACTIVE, reset volume counter
		if new_state == chunk_state.ACTIVE:
			volume_counter = 0
## When retiring, ACTIVE chunks will check to see if this chunk is a parent. If so, it will add to the volume counter. Once volume_counter == size * lod_step, then this chunk can be removed.
var volume_counter := 0
## A 6-bit value defining what faces need to implement transition cells to fix seams between chunks of different resolutions
var desired_transition_mask := -1
## A 6-bit value defining the faces that are currently implementing transition cells
var built_transition_mask := -1
## The ID of the worker thread that is constructing the mesh data. When -1, there is no thread and therefore the chunk is not building any mesh data.
var thread_id := -1

var y_stride: int
var x_stride: int
var face_stride: int

func _init(_size: int, _noise: WorldNoise, _offset: Vector3, _lod_step: int):
	self.size = _size
	self.scalar = _noise
	self.offset = _offset
	self.lod_step = _lod_step
	self.y_stride = size + 1
	self.x_stride = (size + 1) * (size + 1)
	self.face_stride = 2 * size + 1

func _determine_if_cell_is_empty() -> bool:
	var axis_length := size * lod_step
	var opposite_corner := offset + Vector3(axis_length, axis_length, axis_length)
	var minimum_distance: float = scalar.center.clamp(offset, opposite_corner).distance_to(scalar.center)
	var min_bias: float = scalar.get_bias_from_distance(minimum_distance)
	if min_bias > scalar.BIAS_THRESHOLD: mesh_data = null; return true

	var max_x: float = abs(offset.x - scalar.center.x)
	var min_x: float = abs((offset.x + (size) * lod_step) - scalar.center.x)
	var xm: float
	if max_x > min_x: xm = max_x
	else: xm = min_x

	var max_y: float = abs(offset.y - scalar.center.y)
	var min_y: float = abs((offset.y + (size) * lod_step) - scalar.center.y)
	var ym: float
	if max_y > min_y: ym = max_y
	else: ym = min_y

	var max_z: float = abs(offset.z - scalar.center.z)
	var min_z: float = abs((offset.z + (size) * lod_step) - scalar.center.z)
	var zm: float
	if max_z > min_z: zm = max_z
	else: zm = min_z

	var max_bias := scalar.get_bias_from_distance(sqrt(xm * xm + ym * ym + zm * zm))
	if max_bias < -scalar.BIAS_THRESHOLD: mesh_data = null; return true

	return false

class SampleSetReturnType:
	var corner_samples: PackedFloat32Array
	var transition_samples: Array[PackedFloat32Array]

## Returns either an array of scalar values to use in generating mesh data. The array has one copy of all needed scalar values to avoid sampling the same point multiple times. Null is returned when all points are above or below the surface, so no mesh should be generated. Returns Array[corner_samples: PackedFloat32Array, transtion_samples: Array[PackedFloat32Array]]
func _construct_sample_set(mask: int = 0) -> SampleSetReturnType:
	# on grid samples used no matter that mask value
	var corner_samples: PackedFloat32Array = []
	corner_samples.resize((size + 1) * (size + 1) * (size + 1))
	# subdivided grid samples. Each array corresponds to a face of the chunk: x,y,z,-x,-y,-z
	var transition_samples: Array[PackedFloat32Array] = [[], [], [], [], [], []]
	for i in transition_samples.size():
		if (mask >> i) & 1 == 1: transition_samples[i].resize(face_stride * face_stride)
	# used at the end of the function. If all on-grid samples are above or if all are below, then an empty array is returned, signaling that this chunk can be skipped and no mesh is needed
	var is_all_above := true
	var is_all_below := true

	# ============ BEGIN ON-GRID SAMPLING ============

	# On each level (x, y, and z), find if a transition face applies and get the actual x,y,z value based on lod_step and offest. Also get the subdivided value of the current x, y, and z
	for x in size + 1:
		var x_value := x * lod_step + offset.x
		var x_negative_transition := x == 0 and (mask >> 3) & 1 == 1
		var x_positive_transition := x == size and (mask >> 0) & 1 == 1
		var xi = x * 2

		for y in size + 1:
			var y_value = y * lod_step + offset.y
			var y_negative_transition := y == 0 and (mask >> 4) & 1 == 1
			var y_positive_transition := y == size and (mask >> 1) & 1 == 1
			var yi = y * 2

			for z in size + 1:
				var z_value = z * lod_step + offset.z
				var z_negative_transition := z == 0 and (mask >> 5) & 1 == 1
				var z_positive_transition := z == size and (mask >> 2) & 1 == 1
				var zi = z * 2

				# Get corner sample and add it to corner samples array. Index is calculated instead of appended since the array is a specific size
				var corner_sample := scalar.sample(
					x_value,
					y_value,
					z_value
				)
				var index: int = (x * ((size + 1) * (size + 1))) + (y * (size + 1)) + z
				corner_samples[index] = corner_sample

				# ============ END ON-GRID SAMPLING ============ 
				# ============ BEGIN TRANSITION FACE SAMPLING ============ 
				#
				# TRANSITION FACE POINTS REFERENCE
				#
				#  6----------7  ----------8
				#  |          |            |
				#  |          |            |
				#  |          |            |
				#  |          |            |
				#
				#  3----------4  ----------5
				#  |          |            |
				#  |          |            |
				#  |          |            |
				#  |          |            |
				#  0----------1  ----------2 
				#
				# corners (0, 2, 6, 8) are on grid and can use normal z,y,z positions
				# 1, 2, 3, 4, and 7 are all transition values and are half steps between full grid positions
				#
				# A corner can project out and get half step values for transition faces
				# i.e. if this cell is on the outter most corner of the face -> 
				#     0 can get 1, 3, and 4. 
				#     2 can get 5. 
				#     8 would get no transition values, as it's the max value from each axis
				#
				# CHUNK FACE LABEL REFERENCE
				#
				#        o----------------------o
				#       /|                     /|
				#      / |       y+           / |
				#     /  |                   /  | 
				#    /   |                  /   | 
				#   o----------------------o    |
				#   |    |                 |    |
				#   |    |        z+       | x+ |  
				#   | x- |                 |    |
				#   |    |     z-          |    |
				#   |    o-----------------|----o
				#   |   /                  |   /
				#   |  /                   |  /
				#   | /         y-         | / 
				#   |/                     |/ 
				#   o----------------------o
				#
				# mask bits represet which face needs transition cells. 
				# 6 bits: x,y,z,-x,-y,-z. 1 = needs transtion cells, 0 = does not need transition cells

				# get transition samples and add them to their corresponding arrays on a per-transition-face basis
				if x_negative_transition:
					_get_transition_samples(transition_samples, 3, Vector3(x_value, y_value, z_value), 2, 1, zi, yi, z, y, corner_sample)
				if x_positive_transition:
					_get_transition_samples(transition_samples, 0, Vector3(x_value, y_value, z_value), 1, 2, yi, zi, y, z, corner_sample)
				if y_negative_transition:
					_get_transition_samples(transition_samples, 4, Vector3(x_value, y_value, z_value), 2, 0, zi, xi, z, x, corner_sample)
				if y_positive_transition:
					_get_transition_samples(transition_samples, 1, Vector3(x_value, y_value, z_value), 0, 2, xi, zi, x, z, corner_sample)
				if z_negative_transition:
					_get_transition_samples(transition_samples, 5, Vector3(x_value, y_value, z_value), 0, 1, xi, yi, x, y, corner_sample)
				if z_positive_transition:
					_get_transition_samples(transition_samples, 2, Vector3(x_value, y_value, z_value), 1, 0, yi, xi, y, x, corner_sample)

				if corner_sample > isosurface: is_all_below = false
				if corner_sample < isosurface: is_all_above = false
	
				# ============ END TRANSITION FACE SAMPLING ============ 
	
	# return an empty array if all on-grid points are above/below the surface. Otherwise, return sample data
	if is_all_above or is_all_below:
		return null
	else:
		var return_data := SampleSetReturnType.new()
		return_data.corner_samples = corner_samples
		return_data.transition_samples = transition_samples
		return return_data

## Gets and injects transition samples accoriding to given parameters. `transition_samples` is a reference to the 6 nested arrays thatwill contain sample data for each transition face, keyed to the transition mas convention of x,y,z,-x,-y,-z. `child_arr` is the index of one of those 6 nested arrays that the gotten samples will be injected into. `loop_values` is the x, y, and z values used to get a sample at an on-grid position. `u_axis`and `v_axis` are the 2D axes of the transition face and is used to specify which axes to manipulate when determining the s1, s3, and s4 positions; should be either 0, 1, or 2 for x, y, or z. `ui` and `vi` are the origin index values of the current loop position, translated into transition space (*2). `u` and `v` are the values of `x`, `y`, or `z` directly from the loop iteration and are used to conditional inject corner, s1, s3, and s4 samples. `corner_sample` is the origin of the 2D transition cell and is an on-grid sample determined in the primary `for` loops
func _get_transition_samples(
		transition_samples: Array[PackedFloat32Array], child_arr: int,
		loop_values: Vector3,
		u_axis: int, v_axis: int,
		ui: int, vi: int,
		u: int, v: int,
		corner_sample: float
	) -> void:
	var s1_position := loop_values
	var s3_position := loop_values
	var s4_position := loop_values

	# Manipulate sample positions based on TRANSITION FACE POINTS REFERENCE
	s1_position[u_axis] += lod_step / 2.0
	s3_position[v_axis] += lod_step / 2.0
	s4_position[u_axis] += lod_step / 2.0
	s4_position[v_axis] += lod_step / 2.0

	# sample and inject to the correct array depending on where this point is located. 
	# If u,v are below their axes' maximum, sample/inject all points
	if u < size and v < size:
		var s1_sample := scalar.sample(s1_position.x, s1_position.y, s1_position.z)
		var s3_sample := scalar.sample(s3_position.x, s3_position.y, s3_position.z)
		var s4_sample := scalar.sample(s4_position.x, s4_position.y, s4_position.z)
		# add corner + all 3 transition samples to transition face array
		_inject_transition_samples(transition_samples, child_arr, ui, vi, corner_sample, s1_sample, s3_sample, s4_sample)
	# If only u is below is axis' maximum, sample/inject only s1 and corner_sample
	elif u < size and not v < size:
		var s1_sample := scalar.sample(s1_position.x, s1_position.y, s1_position.z)
		_inject_transition_samples(transition_samples, child_arr, ui, vi, corner_sample, s1_sample, null, null)
	# If only v is below is axis' maximum, sample/inject only s3 and corner_sample
	elif not u < size and v < size:
		var s3_sample := scalar.sample(s3_position.x, s3_position.y, s3_position.z)
		_inject_transition_samples(transition_samples, child_arr, ui, vi, corner_sample, null, s3_sample, null)
	# If both u,v are at their axes' maximum, sample/inject only corner_sample
	else:
		_inject_transition_samples(transition_samples, child_arr, ui, vi, corner_sample, null, null, null)

func _inject_transition_samples(transition_samples: Array[PackedFloat32Array], child_arr: int, ui: int, vi: int, corner_sample: float, s1 = null, s3 = null, s4 = null) -> void:
	transition_samples[child_arr][ui * face_stride + vi] = corner_sample
	if s1 != null: transition_samples[child_arr][(ui + 1) * face_stride + vi] = s1
	if s3 != null: transition_samples[child_arr][ui * face_stride + (vi + 1)] = s3
	if s4 != null: transition_samples[child_arr][(ui + 1) * face_stride + (vi + 1)] = s4

## Uses the scalar property and isosurface property to generate mesh vertices and normals. Assigns the generated data to mesh_vertices and mesh_data
func _generate_mesh_data(corner_samples: PackedFloat32Array, transition_mask: int, transition_samples: Array[PackedFloat32Array]) -> ArrayMesh:
	#    c6----------------------c7
	#    / |                     /|
	#   /  |                    / | 
	# c4----------------------c5  |
	#  |   |                   |  |
	#  |   |                   |  |  
	#  |   |                   |  |
	#  |   |                   |  |
	#  |  c2-------------------|-c3
	#  |  /                    | /
	#  | /                     |/ 
	# c0----------------------c1
	# Arrays for storing generated mesh data
	var mesh_vertices: PackedVector3Array = []
	var mesh_normals: PackedVector3Array = []
	
	# Initialized arrays and stride values to 
	var scalar_values: PackedFloat32Array = []
	scalar_values.resize(8)
	var cell_corner_set: PackedVector3Array = []
	cell_corner_set.resize(8)
	var vertex_set: PackedVector3Array = []

	# Loop through each cube and generate vertices and normals for that cube
	for x in size: # - 1:
		var x_scalar_stride_zero := x * x_stride
		var x_scalar_stride_one := (x + 1) * x_stride
		for y in size: # - 1:
			var y_scalar_stride_one := (y + 1) * y_stride
			var y_scalar_stride_zero := y * y_stride
			for z in size: # - 1:
				# cube corner scalar values
				scalar_values[0] = corner_samples[x_scalar_stride_zero + y_scalar_stride_zero + z]
				scalar_values[1] = corner_samples[x_scalar_stride_one + y_scalar_stride_zero + z]
				scalar_values[2] = corner_samples[x_scalar_stride_zero + y_scalar_stride_zero + (z + 1)]
				scalar_values[3] = corner_samples[x_scalar_stride_one + y_scalar_stride_zero + (z + 1)]
				scalar_values[4] = corner_samples[x_scalar_stride_zero + y_scalar_stride_one + z]
				scalar_values[5] = corner_samples[x_scalar_stride_one + y_scalar_stride_one + z]
				scalar_values[6] = corner_samples[x_scalar_stride_zero + y_scalar_stride_one + (z + 1)]
				scalar_values[7] = corner_samples[x_scalar_stride_one + y_scalar_stride_one + (z + 1)]
				
				# determine regular class index
				var class_index := 0
				if scalar_values[0] < isosurface: class_index |= (1 << 0)
				if scalar_values[1] < isosurface: class_index |= (1 << 1)
				if scalar_values[2] < isosurface: class_index |= (1 << 2)
				if scalar_values[3] < isosurface: class_index |= (1 << 3)
				if scalar_values[4] < isosurface: class_index |= (1 << 4)
				if scalar_values[5] < isosurface: class_index |= (1 << 5)
				if scalar_values[6] < isosurface: class_index |= (1 << 6)
				if scalar_values[7] < isosurface: class_index |= (1 << 7)
				
				# Skip empty cells
				if class_index == 0 or class_index == 255:
					continue
				
				# cube corner positions in space
				cell_corner_set[0] = Vector3(x, y, z) * lod_step
				cell_corner_set[1] = Vector3((x + 1), y, z) * lod_step
				cell_corner_set[2] = Vector3(x, y, (z + 1)) * lod_step
				cell_corner_set[3] = Vector3((x + 1), y, (z + 1)) * lod_step
				cell_corner_set[4] = Vector3(x, (y + 1), z) * lod_step
				cell_corner_set[5] = Vector3((x + 1), (y + 1), z) * lod_step
				cell_corner_set[6] = Vector3(x, (y + 1), (z + 1)) * lod_step
				cell_corner_set[7] = Vector3((x + 1), (y + 1), (z + 1)) * lod_step

				# use class_index to determine the cell class, construct cell data, and get vertex count
				var cell_class: int = TransvoxelLUT.REG_CELL_CLASS[class_index]
				var vertex_count := TransvoxelLUT.get_vertex_count(TransvoxelLUT.REG_CELL_DATA[cell_class][0])

				# Construct a set of vertices to be used for this cell
				for i in vertex_count:
					var vertex_data: int = TransvoxelLUT.REG_VERTEX_DATA[class_index][i]
					# Use data in the low byte to construct an edge
					var low_byte := vertex_data & 0xFF
					var corner_a := low_byte >> 4
					var corner_b := low_byte & 0x0F

					# determine interpolation ratio
					var interpolation_ratio: float = (isosurface - scalar_values[corner_a]) / (scalar_values[corner_b] - scalar_values[corner_a])
					var vertex: Vector3 = cell_corner_set[corner_a].lerp(cell_corner_set[corner_b], interpolation_ratio)

					vertex_set.append(vertex)
				
				## Using the vertex set and cell_data append vertices to the mesh_vertices array to create triangles and calculate flat normals.
				var vertex_indices = TransvoxelLUT.REG_CELL_DATA[cell_class][1]
				var i := 0
				while i < vertex_indices.size():
					var vertex_a := vertex_set[vertex_indices[i]]
					var vertex_b := vertex_set[vertex_indices[i + 1]]
					var vertex_c := vertex_set[vertex_indices[i + 2]]

					# append vertices to vertices array
					mesh_vertices.append(vertex_a)
					mesh_vertices.append(vertex_b)
					mesh_vertices.append(vertex_c)
					
					# determine normal and append to normals array
					var normal := - (vertex_b - vertex_a).cross(vertex_c - vertex_a).normalized()
					mesh_normals.append(normal)
					mesh_normals.append(normal)
					mesh_normals.append(normal)
					
					i += 3
				
				vertex_set.clear()
	
	var surface_arrays: Array = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	surface_arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	
	# create the mesh and assign data to it
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	return array_mesh

## constructs ArrayMesh data for building a MeshInstance3D for this chunk. mesh_data will be null if no data is/should be generated. Should be done off the main game thread.
func generate_mesh_data(transition_mask: int) -> void:
	built_transition_mask = transition_mask
	if _determine_if_cell_is_empty(): return
	# var start_time := Time.get_ticks_usec()
	var sample_data := _construct_sample_set(transition_mask)
	if sample_data == null: mesh_data = null; return
	mesh_data = _generate_mesh_data(sample_data.corner_samples, transition_mask, sample_data.transition_samples)
	# print("chunk gen time: ", Time.get_ticks_usec() - start_time)

## Creates a MeshInstance3D from given ArrayMesh, adds it to the tree, and creates collisions for it. 
func build_mesh() -> void:
	for child in get_children():
		if child is MeshInstance3D and child.name == "ChunkMesh":
			child.name = "ChunkMeshOld"
			child.queue_free()
			break

	# create the mesh instance, assign the mesh to it, and add it to the scene
	var mesh_instance := MeshInstance3D.new()
	self.add_child(mesh_instance)
	mesh_instance.name = "ChunkMesh"
	mesh_instance.mesh = mesh_data
	
	if lod_step == 1:
		mesh_instance.create_trimesh_collision()
		var collision_instance: StaticBody3D = mesh_instance.get_child(-1)
		collision_instance.set_collision_layer_value(2, true) # planet collision layer
		collision_instance.set_collision_mask_value(1, true) # player collisions
