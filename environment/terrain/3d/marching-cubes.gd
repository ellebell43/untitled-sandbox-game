extends Node3D

@onready var generated_mesh := $GeneratedMesh

## How far apart each point is in real space
@export var point_distance := 0.5
## The amount of points along the x, y, and z axis
@export var size := 25
## The value of the scalar field that represents the surface of the mesh
@export var isosurface := .2
## True means the vertex positions will be interpolated, creating a much smoother surface. False means the steps will be much harder and blockier.
@export var interpolated := true
## Print out extra information to the console
@export var verbose := true
@export var show_points := false
@export var shade_smooth := false

# MeshInstance3D scene for showing visble data points on the screen when you run the scene
var point_scene: PackedScene = preload("res://environment/terrain/3d/point-3d.tscn")

func _ready() -> void:
	# ====== INITIALIZE DATA ======
	
	# Create a noise object to use as a scalar field
	var scalar := FastNoiseLite.new()
	scalar.noise_type = FastNoiseLite.TYPE_PERLIN
	# Initialize an array to store vertices in for our mesh and another to store normals
	var mesh_vertices: PackedVector3Array = []
	var mesh_normals: PackedVector3Array = []
	
	
	# ====== CREATE VISIBLE DATA POINTS ======
	
	if show_points:
		if verbose: print("creating ", size * size * size, " points")
		for x in size:
			for y in size:
				for z in size:
					var scalar_value = scalar.get_noise_3d(x, y, z)
					var point := point_scene.instantiate()
					if scalar_value <= isosurface: point.above_iso = true # shows point as red
					else: point.above_iso = false # shows point as green
					add_child(point)
					point.global_position = Vector3(x * point_distance, y * point_distance, z * point_distance)
	
	# ====== ITERATE THROUGH CUBES ======
	
	#    c4---------e4-----------c5
	# e6 / |                  e5 /|
	#   /  |                    / | 
	# c7----------e6----------c6  |
	#  |   |                   |  |
	#  |   e8                  |  e9
	#  |   |                   |  |
	# e11  |                  e10 |
	#  |  c0--------e0---------|-c1
	#  |  / e3                 | /
	#  | /                     |/ e1
	# c3-----------e2---------c2
	
	# 8-bit case index = c0*1 + c1*2 + c2*4 + c3*8 + c4*16 + c5*32 + c6*64 + c7*128
	
	if verbose: print("marching cubes through ", size * size * size, " points...")
	
	const EDGE_CORNERS := [ # the two corners each edge connects
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
	
	for x in size - 1:
		for y in size - 1:
			for z in size - 1:
				# cube corner positions in space
				var c0_pos = Vector3(x * point_distance, y * point_distance, z * point_distance)
				var c1_pos = Vector3((x + 1) * point_distance, y * point_distance, z * point_distance)
				var c2_pos = Vector3((x + 1) * point_distance, y * point_distance, (z + 1) * point_distance)
				var c3_pos = Vector3(x * point_distance, y * point_distance, (z + 1) * point_distance)
				var c4_pos = Vector3(x * point_distance, (y + 1) * point_distance, z * point_distance)
				var c5_pos = Vector3((x + 1) * point_distance, (y + 1) * point_distance, z * point_distance)
				var c6_pos = Vector3((x + 1) * point_distance, (y + 1) * point_distance, (z + 1) * point_distance)
				var c7_pos = Vector3(x * point_distance, (y + 1) * point_distance, (z + 1) * point_distance)
				var corner_pos = [c0_pos, c1_pos, c2_pos, c3_pos, c4_pos, c5_pos, c6_pos, c7_pos]
				
				# cube corner scalar values
				var c0 = scalar.get_noise_3d(x, y, z)
				var c1 = scalar.get_noise_3d(x + 1, y, z)
				var c2 = scalar.get_noise_3d(x + 1, y, z + 1)
				var c3 = scalar.get_noise_3d(x, y, z + 1)
				var c4 = scalar.get_noise_3d(x, y + 1, z)
				var c5 = scalar.get_noise_3d(x + 1, y + 1, z)
				var c6 = scalar.get_noise_3d(x + 1, y + 1, z + 1)
				var c7 = scalar.get_noise_3d(x, y + 1, z + 1)
				var corner_scalars = [c0, c1, c2, c3, c4, c5, c6, c7]
				
				# determine case index
				var case_index = 0
				if c0 > isosurface: case_index |= (1 << 0)
				if c1 > isosurface: case_index |= (1 << 1)
				if c2 > isosurface: case_index |= (1 << 2)
				if c3 > isosurface: case_index |= (1 << 3)
				if c4 > isosurface: case_index |= (1 << 4)
				if c5 > isosurface: case_index |= (1 << 5)
				if c6 > isosurface: case_index |= (1 << 6)
				if c7 > isosurface: case_index |= (1 << 7)
				
				# determine where vertices go in real space
				var segment = MarchingCubesLUT.TRI_TABLE[case_index]
				
				var i:= 0
				while i < segment.size() and segment[i] != -1:
					var edge_a = segment [i]
					var edge_b = segment [i + 1]
					var edge_c = segment [i + 2]
					var vertex_a: Vector3
					var vertex_b: Vector3
					var vertex_c: Vector3
					
					if not interpolated:
						vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], 0.5)
						vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], 0.5)
						vertex_c = corner_pos[EDGE_CORNERS[edge_c][0]].lerp(corner_pos[EDGE_CORNERS[edge_c][1]], 0.5)
					else:
						# determine interpolation ratio
						var t_a = (isosurface - corner_scalars[EDGE_CORNERS[edge_a][0]]) / (corner_scalars[EDGE_CORNERS[edge_a][1]] - corner_scalars[EDGE_CORNERS[edge_a][0]])
						var t_b = (isosurface - corner_scalars[EDGE_CORNERS[edge_b][0]]) / (corner_scalars[EDGE_CORNERS[edge_b][1]] - corner_scalars[EDGE_CORNERS[edge_b][0]])
						var t_c = (isosurface - corner_scalars[EDGE_CORNERS[edge_c][0]]) / (corner_scalars[EDGE_CORNERS[edge_c][1]] - corner_scalars[EDGE_CORNERS[edge_c][0]])
						vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], t_a)
						vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], t_b)
						vertex_c = corner_pos[EDGE_CORNERS[edge_c][0]].lerp(corner_pos[EDGE_CORNERS[edge_c][1]], t_c)
					
					var verts = [vertex_a, vertex_b, vertex_c]
					if shade_smooth:
						var sample_step = 0.1
						for v in verts:
							var noise_position = v / point_distance
							var sample_x_1 := scalar.get_noise_3d(noise_position.x + sample_step, noise_position.y, noise_position.z)
							var sample_x_2 := scalar.get_noise_3d(noise_position.x - sample_step, noise_position.y, noise_position.z)
							var sample_y_1 := scalar.get_noise_3d(noise_position.x, noise_position.y + sample_step, noise_position.z)
							var sample_y_2 := scalar.get_noise_3d(noise_position.x, noise_position.y - sample_step, noise_position.z)
							var sample_z_1 := scalar.get_noise_3d(noise_position.x, noise_position.y, noise_position.z + sample_step)
							var sample_z_2 := scalar.get_noise_3d(noise_position.x, noise_position.y, noise_position.z - sample_step)
							var gradient = Vector3(sample_x_1 - sample_x_2, sample_y_1 - sample_y_2, sample_z_1 - sample_z_2)
							var normal = gradient.normalized()
							mesh_normals.append(normal)
					else:
						var normal = -(vertex_b - vertex_a).cross(vertex_c - vertex_a)
						mesh_normals.append(normal)
						mesh_normals.append(normal)
						mesh_normals.append(normal)
					
					mesh_vertices.append(vertex_a)
					mesh_vertices.append(vertex_b)
					mesh_vertices.append(vertex_c)
					
					i += 3
	
	# ====== BUILD MESH ======
	
	if verbose: print("building mesh from ", mesh_vertices.size(), " vertices...")
	
	# initialize mesh array
	var array_mesh := ArrayMesh.new()
	
	# package data needed to create the mesh
	var mesh_indices: PackedInt32Array = []
	for i in range(mesh_vertices.size()):
		mesh_indices.append(i)
	var surface_arrays = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	surface_arrays[Mesh.ARRAY_INDEX] = mesh_indices
	surface_arrays[Mesh.ARRAY_NORMAL] = mesh_normals
	
	# assign the data to the mesh and mesh instance
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_arrays)
	generated_mesh.mesh = array_mesh
