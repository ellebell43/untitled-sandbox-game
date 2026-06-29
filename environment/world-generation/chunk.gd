class_name Chunk
extends Node3D

# ============ BASIC CHUNK CHARACTERISTICS ============

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

func _init(_size: int, _noise: WorldNoise, _offset: Vector3, _lod_step: int):
	self.size = _size
	self.scalar = _noise
	self.offset = _offset
	self.lod_step = _lod_step

## Returns either an array of scalar values to use in generating mesh data. The array has one copy of all needed scalar values to avoid sampling the same point multiple times. Null is returned when all points are above or below the surface, so no mesh should be generated
func _construct_sample_set() -> PackedFloat32Array:
	var scalar_samples: PackedFloat32Array = []
	var is_all_above := true
	var is_all_below := true
	for x in size + 1:
		for y in size + 1:
			for z in size + 1:
				var sample := scalar.sample(
					x * lod_step + offset.x,
					y * lod_step + offset.y,
					z * lod_step + offset.z
				)
				scalar_samples.append(sample)
				if sample > isosurface: is_all_below = false
				if sample < isosurface: is_all_above = false
	
	if is_all_above or is_all_below:
		return []
	else:
		return scalar_samples

## Uses the scalar property and isosurface property to generate mesh vertices and normals. Assignes the generated data to mesh_vertices and mesh_data
func _generate_mesh_data(scalar_samples: PackedFloat32Array) -> ArrayMesh:
	#    c4---------e4-------------c5
	# e6 / |                    e5 /|
	#   /  |                      / | 
	# c7------------e6----------c6  |
	#  |   |                     |  |
	#  |   e8                    |  e9
	#  |   |                     |  |
	# e11  |                    e10 |
	#  |  c0----------e0---------|-c1
	#  |  / e3                   | /
	#  | /                       |/ e1
	# c3-----------e2-----------c2
	# 8-bit case index = c0*1 + c1*2 + c2*4 + c3*8 + c4*16 + c5*32 + c6*64 + c7*128
	# the two corners each edge connects
	const EDGE_CORNERS := [
		[0, 1],
		[1, 2],
		[2, 3],
		[3, 0],
		[4, 5],
		[5, 6],
		[6, 7],
		[7, 4],
		[0, 4],
		[1, 5],
		[2, 6],
		[3, 7]
	]
	# Arrays for storing generated mesh data
	var mesh_vertices: PackedVector3Array = []
	var mesh_normals: PackedVector3Array = []
	
	# Loop through each cube and generate vertices and normals for that cube
	for x in size: # - 1:
		for y in size: # - 1:
			for z in size: # - 1:
				if !scalar: return
				# cube corner scalar values
				var y_stride := size + 1
				var x_stride := int(pow(size + 1, 2))
				var c0 = scalar_samples[x * x_stride + y * y_stride + z]
				var c1 = scalar_samples[(x + 1) * x_stride + y * y_stride + z]
				var c2 = scalar_samples[(x + 1) * x_stride + y * y_stride + (z + 1)]
				var c3 = scalar_samples[x * x_stride + y * y_stride + (z + 1)]
				var c4 = scalar_samples[x * x_stride + (y + 1) * y_stride + z]
				var c5 = scalar_samples[(x + 1) * x_stride + (y + 1) * y_stride + z]
				var c6 = scalar_samples[(x + 1) * x_stride + (y + 1) * y_stride + (z + 1)]
				var c7 = scalar_samples[x * x_stride + (y + 1) * y_stride + (z + 1)]
				var corner_scalars = [c0, c1, c2, c3, c4, c5, c6, c7]
				
				# cube corner positions in space
				var c0_pos = Vector3(x, y, z) * lod_step
				var c1_pos = Vector3((x + 1), y, z) * lod_step
				var c2_pos = Vector3((x + 1), y, (z + 1)) * lod_step
				var c3_pos = Vector3(x, y, (z + 1)) * lod_step
				var c4_pos = Vector3(x, (y + 1), z) * lod_step
				var c5_pos = Vector3((x + 1), (y + 1), z) * lod_step
				var c6_pos = Vector3((x + 1), (y + 1), (z + 1)) * lod_step
				var c7_pos = Vector3(x, (y + 1), (z + 1)) * lod_step
				var corner_pos = [c0_pos, c1_pos, c2_pos, c3_pos, c4_pos, c5_pos, c6_pos, c7_pos]
				
				# determine case index
				var case_index = 0
				if c0 < isosurface: case_index |= (1 << 0)
				if c1 < isosurface: case_index |= (1 << 1)
				if c2 < isosurface: case_index |= (1 << 2)
				if c3 < isosurface: case_index |= (1 << 3)
				if c4 < isosurface: case_index |= (1 << 4)
				if c5 < isosurface: case_index |= (1 << 5)
				if c6 < isosurface: case_index |= (1 << 6)
				if c7 < isosurface: case_index |= (1 << 7)
				var segment = MarchingCubesLUT.TRI_TABLE[case_index]
				
				# determine where mesh vertices go in real space and determine normals for each mesh vertex (uses flat shading on purpose)
				var i := 0
				while i < segment.size() and segment[i] != -1:
					var edge_a = segment[i]
					var edge_b = segment[i + 1]
					var edge_c = segment[i + 2]
					var vertex_a: Vector3
					var vertex_b: Vector3
					var vertex_c: Vector3
					
					# determine interpolation ratio
					var t_a = (isosurface - corner_scalars[EDGE_CORNERS[edge_a][0]]) / (corner_scalars[EDGE_CORNERS[edge_a][1]] - corner_scalars[EDGE_CORNERS[edge_a][0]])
					var t_b = (isosurface - corner_scalars[EDGE_CORNERS[edge_b][0]]) / (corner_scalars[EDGE_CORNERS[edge_b][1]] - corner_scalars[EDGE_CORNERS[edge_b][0]])
					var t_c = (isosurface - corner_scalars[EDGE_CORNERS[edge_c][0]]) / (corner_scalars[EDGE_CORNERS[edge_c][1]] - corner_scalars[EDGE_CORNERS[edge_c][0]])
					# apply interpolation ratio when determining vertex position
					vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], t_a)
					vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], t_b)
					vertex_c = corner_pos[EDGE_CORNERS[edge_c][0]].lerp(corner_pos[EDGE_CORNERS[edge_c][1]], t_c)
					
					# append vertices to vertices array
					mesh_vertices.append(vertex_a)
					mesh_vertices.append(vertex_c)
					mesh_vertices.append(vertex_b)
					
					# determine normal and append to normals array
					var normal = (vertex_b - vertex_a).cross(vertex_c - vertex_a)
					mesh_normals.append(normal)
					mesh_normals.append(normal)
					mesh_normals.append(normal)
					
					i += 3
	
	# package data needed to create the mesh
	var mesh_indices: PackedInt32Array = []
	for i in range(mesh_vertices.size()):
		mesh_indices.append(i)
	var surface_arrays = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	surface_arrays[Mesh.ARRAY_INDEX] = mesh_indices
	surface_arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	
	# create the mesh and assign data to it
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	return array_mesh

## constructs ArrayMesh data for building a MeshInstance3D for this chunk. mesh_data will be null if no data is/should be generated. Should be done off the main game thread.
func generate_mesh_data() -> void:
	var scalar_samples = _construct_sample_set()
	if scalar_samples.size() == 0: mesh_data = null; return
	mesh_data = _generate_mesh_data(scalar_samples)

## Creates a MeshInstance3D from given ArrayMesh, adds it to the tree, and creates collisions for it. 
func build_mesh() -> void:
	# create the mesh instance, assign the mesh to it, and add it to the scene
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.mesh = mesh_data
	self.add_child(mesh_instance)
	
	if lod_step == 1:
		mesh_instance.create_trimesh_collision()
		var collision_instance: StaticBody3D = mesh_instance.get_child(0)
		collision_instance.set_collision_layer_value(2, true) # planet collision layer
		collision_instance.set_collision_mask_value(1, true) # player collisions
