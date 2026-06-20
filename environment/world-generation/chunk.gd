class_name Chunk
extends Node3D

## The amount of points along the x, y, and z axis
@export var size := 50
## Seed of the terrain generation
@export var world_seed := 1
## True means the vertex positions will be interpolated, creating a much smoother surface. False means the steps will be much harder and blockier.
@export var interpolated := true
## Smooths out normals to remove the "blocky" lighting
@export var shade_smooth := false
## When true, display the scalar field as 3D point objects, colored to show which points are above/below the surface of the mesh
@export var show_points := false
## Print out extra information to the console
@export var verbose := false

## noise volume to use for generating mesh data
var scalar: WorldNoise = null
## The value of the scalar field that represents the surface of the mesh
var isosurface := 0.0
var offset := Vector3(0, 0, 0)

# Arrays for storing generated mesh data
var mesh_vertices: PackedVector3Array = []
var mesh_normals: PackedVector3Array = []
var scalar_samples: Array = []
var should_skip: bool = false

# MeshInstance3D scene for showing visble data points on the screen when you run the scene
var point_scene: PackedScene = preload("res://environment/terrain/3d/point-3d.tscn")

func _init(_size: int, _noise: WorldNoise, _offset: Vector3):
	self.size = _size
	self.scalar = _noise
	self.offset = _offset

func _ready() -> void:
	if not scalar: scalar = WorldNoise.new(world_seed, size)
	if show_points: _display_visual_scalar_volume()
	_construct_sample_set()
	if should_skip: return # determined in _construct_sample_set()
	_generate_mesh_data()
	# if any mesh data is generated, build a mesh. otherwise, skip.
	if mesh_vertices.size() > 0: _build_mesh()

## Create a volume of Point3D nodes to display a visual of the scalar field. Green points are inside the surface and red points are outside the surface.
func _display_visual_scalar_volume() -> void:
	if verbose: print("creating ", size * size * size, " points")
	for x in size:
		for y in size:
			for z in size:
				var scalar_value = scalar.sample(x, y, z)
				var point := point_scene.instantiate()
				if scalar_value >= isosurface: point.above_iso = true # shows point as red
				else: point.above_iso = false # shows point as green
				add_child(point)
				point.position = Vector3(x, y, z)

## Fill an array with one copy of all needed scalar values to avoid sampling the same point multiple times. Also check if all points are above/below the iso. If so, should_skip = true
func _construct_sample_set():
	var is_all_above = true
	var is_all_below = true
	for x in size +  1:
		for y in size +  1:
			for z in size +  1:
				var sample = scalar.sample(x + offset.x, y + offset.y, z + offset.z)
				scalar_samples.append(sample)
				if sample > isosurface: is_all_below = false
				if sample < isosurface: is_all_above = false
	
	if is_all_above or is_all_below: 
		should_skip = true
		if verbose: print("skipping chunk.\nAll above: ", is_all_above, "\nAll below: ", is_all_below)

## Uses the scalar property and isosurface property to generate mesh vertices and normals. Assignes the generated data to mesh_vertices and mesh_data
func _generate_mesh_data() -> void:
	if verbose: print("marching cubes through ", size * size * size, " points...")
	
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
	
	# Loop through each cube and generate vertices and normals for that cube
	for x in size:# - 1:
		for y in size:# - 1:
			for z in size:# - 1:
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
				var c0_pos = Vector3(x, y, z)
				var c1_pos = Vector3((x + 1), y, z)
				var c2_pos = Vector3((x + 1), y, (z + 1))
				var c3_pos = Vector3(x, y, (z + 1))
				var c4_pos = Vector3(x, (y + 1), z)
				var c5_pos = Vector3((x + 1), (y + 1), z)
				var c6_pos = Vector3((x + 1), (y + 1), (z + 1))
				var c7_pos = Vector3(x, (y + 1), (z + 1))
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
				
				# determine where vertices go in real space and determine normals for each vertex
				var i:= 0
				while i < segment.size() and segment[i] != -1:
					var edge_a = segment [i]
					var edge_b = segment [i + 1]
					var edge_c = segment [i + 2]
					var vertex_a: Vector3
					var vertex_b: Vector3
					var vertex_c: Vector3
					
					if not interpolated:
						# place vertices at the midway point along the cube edge
						vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], 0.5)
						vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], 0.5)
						vertex_c = corner_pos[EDGE_CORNERS[edge_c][0]].lerp(corner_pos[EDGE_CORNERS[edge_c][1]], 0.5)
					else:
						# determine interpolation ratio
						var t_a = (isosurface - corner_scalars[EDGE_CORNERS[edge_a][0]]) / (corner_scalars[EDGE_CORNERS[edge_a][1]] - corner_scalars[EDGE_CORNERS[edge_a][0]])
						var t_b = (isosurface - corner_scalars[EDGE_CORNERS[edge_b][0]]) / (corner_scalars[EDGE_CORNERS[edge_b][1]] - corner_scalars[EDGE_CORNERS[edge_b][0]])
						var t_c = (isosurface - corner_scalars[EDGE_CORNERS[edge_c][0]]) / (corner_scalars[EDGE_CORNERS[edge_c][1]] - corner_scalars[EDGE_CORNERS[edge_c][0]])
						# apply interpolation ratio when determining vertex position
						vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], t_a)
						vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], t_b)
						vertex_c = corner_pos[EDGE_CORNERS[edge_c][0]].lerp(corner_pos[EDGE_CORNERS[edge_c][1]], t_c)
					
					var verts = [vertex_a, vertex_c, vertex_b]
					if shade_smooth:
						var sample_step = 0.1
						for v in verts:
							var sample_x_1 := scalar.sample(v.x + sample_step, v.y, v.z)
							var sample_x_2 := scalar.sample(v.x - sample_step, v.y, v.z)
							var sample_y_1 := scalar.sample(v.x, v.y + sample_step, v.z)
							var sample_y_2 := scalar.sample(v.x, v.y - sample_step, v.z)
							var sample_z_1 := scalar.sample(v.x, v.y, v.z + sample_step)
							var sample_z_2 := scalar.sample(v.x, v.y, v.z - sample_step)
							var gradient = Vector3(sample_x_1 - sample_x_2, sample_y_1 - sample_y_2, sample_z_1 - sample_z_2)
							var normal = gradient.normalized()
							mesh_normals.append(normal)
					else:
						var normal = (vertex_b - vertex_a).cross(vertex_c - vertex_a)
						mesh_normals.append(normal)
						mesh_normals.append(normal)
						mesh_normals.append(normal)
					
					mesh_vertices.append(vertex_a)
					mesh_vertices.append(vertex_c)
					mesh_vertices.append(vertex_b)
					
					i += 3

## Creates an ArrayMesh and assigned generated data to it. Then, creates a MeshInstance3D, assigns the ArrayMesh to it, and adds it to the scene
func _build_mesh() -> void:
	if verbose: print("building mesh from ", mesh_vertices.size(), " vertices...")
	
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
	
	# create the mesh instance, assign the mesh to it, and add it to the scene
	var mesh_instace = MeshInstance3D.new()
	mesh_instace.mesh = array_mesh
	self.add_child(mesh_instace)
	mesh_instace.create_trimesh_collision()
	var collision_instance: StaticBody3D = mesh_instace.get_child(0)
	collision_instance.set_collision_layer_value(2, true) # planet collision layer
	collision_instance.set_collision_mask_value(1, true) # player collisions
