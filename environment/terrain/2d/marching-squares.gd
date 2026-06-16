extends Node2D

@onready var generated_mesh := $GeneratedMesh

## How far apart each point is in real space
@export var point_distance := 5
## The amount of points along the x axis
@export var x_length := 240
## The amount of points along the y axis
@export var y_length := 180
## The value of the scalar field that represents the surface of the mesh
@export var isosurface := 0
## True means the vertex positions will be interpolated, creating a much smoother surface. False means the steps will be much harder and blockier.
@export var interpolated := false

# Sprite2D scene for showing visble data points on the screen when you run the scene
var point_scene := preload("res://environment/terrain/2d/point.tscn")

func _ready() -> void:
	# ====== INITIALIZE DATA ======
	
	# Create a noise object to use as a scalar field
	var scalar := FastNoiseLite.new()
	scalar.noise_type = FastNoiseLite.TYPE_PERLIN
	# Initialize a mesh to store vertices in for our mesh
	var mesh_vertices: PackedVector2Array = []
	
	# ====== CREATE VISIBLE DATA POINTS ======
	
	# Place visible points that show where each scalar point is and if it's above/below the isosurface
	for x in x_length:
		for y in y_length:
			var scalar_value := scalar.get_noise_2d(x, y)
			var point := point_scene.instantiate()
			if scalar_value <= isosurface: point.above_iso = false # shows point as red
			else: point.above_iso = true # shows point as green
			point.global_position = Vector2(x * point_distance, y * point_distance)
			add_child(point)
	
	# ====== ITERATE THROUGH SQUARES ======
	
	# Convention (must match how you sample corners and interpolate edges):
	#   Corners, counter-clockwise from bottom-left:
	#     c0 = bottom-left, c1 = bottom-right, c2 = top-right, c3 = top-left
	#   Edges, each between two adjacent corners:
	#     e0 = bottom (c0-c1), e1 = right (c1-c2), e2 = top (c2-c3), e3 = left (c3-c0)
	#   case = c0*1 + c1*2 + c2*4 + c3*8   (bit set when that corner is inside)
	
	# c1-----e2-----c2
	# |              |
	# |              |
	# e2            e3
	# |              |
	# |              |
	# c0-----e0-----c3
	
	for x in x_length - 1:
		for y in y_length - 1:
			# square corner positions in space
			var c0_pos := Vector2(x * point_distance, y * point_distance) # bottom-left
			var c1_pos := Vector2(x * point_distance, (y + 1) * point_distance) # top-left
			var c2_pos := Vector2((x + 1) * point_distance, (y + 1) * point_distance) # top-right
			var c3_pos := Vector2((x + 1) * point_distance, y * point_distance) # bottom right
			var corner_pos: PackedVector2Array = [c0_pos, c1_pos, c2_pos, c3_pos]
			
			# square corner scalar values
			var c0 := scalar.get_noise_2d(x, y)
			var c1 := scalar.get_noise_2d(x, y + 1)
			var c2 := scalar.get_noise_2d(x + 1, y + 1)
			var c3 := scalar.get_noise_2d(x + 1, y)
			var corner_scalars := [c0, c1, c2, c3]
			
			# determine case index to find the correct segment in the look up table
			var case_index = 0
			if c0 > isosurface: case_index |= (1 << 0)
			if c1 > isosurface: case_index |= (1 << 1)
			if c2 > isosurface: case_index |= (1 << 2)
			if c3 > isosurface: case_index |= (1 << 3)
			
			# determine where the vetices go in real space based on segment data and real position of the squares' corners
			const EDGE_CORNERS := [[0, 1], [1, 2], [2, 3], [3, 0]]  # the two corners each edge connects
			var segment = MarchingSqauresLUT.SEGMENT_TABLE[case_index]
			var i := 0
			while i < segment.size() and segment[i] != -1:
				var edge_a = segment[i]
				var edge_b = segment[i + 1]
				var vertex_a: Vector2
				var vertex_b: Vector2
				
				if not interpolated:
					vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], 0.5)
					vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], 0.5)
				else:
					# determine interpolation ratio
					var t_a = (isosurface - corner_scalars[EDGE_CORNERS[edge_a][0]]) / (corner_scalars[EDGE_CORNERS[edge_a][1]] - corner_scalars[EDGE_CORNERS[edge_a][0]])
					var t_b = (isosurface - corner_scalars[EDGE_CORNERS[edge_b][0]]) / (corner_scalars[EDGE_CORNERS[edge_b][1]] - corner_scalars[EDGE_CORNERS[edge_b][0]])
					vertex_a = corner_pos[EDGE_CORNERS[edge_a][0]].lerp(corner_pos[EDGE_CORNERS[edge_a][1]], t_a)
					vertex_b = corner_pos[EDGE_CORNERS[edge_b][0]].lerp(corner_pos[EDGE_CORNERS[edge_b][1]], t_b)
				
				mesh_vertices.append(vertex_a)
				mesh_vertices.append(vertex_b)
				
				i += 2
	
	# ====== CONSTRUCT THE MESH ======
	
	# initialize the array mesh
	var array_mesh := ArrayMesh.new()
	# package data needed to create the mesh
	var mesh_indices: PackedInt32Array = []
	for i in range(mesh_vertices.size()):
		mesh_indices.append(i)
	var surface_arrays = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	surface_arrays[Mesh.ARRAY_INDEX] = mesh_indices
	# assign the data to the mesh and render it with lines (wireframe)
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, surface_arrays)
	# assign the mesh object to the mesh instance
	generated_mesh.mesh = array_mesh
