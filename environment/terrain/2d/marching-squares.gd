extends Node2D

@onready var generated_mesh := $GeneratedMesh

## How far apart each point is in real space
@export var point_distance := 15
## The amount of points along the x axis
@export var x_length := 80
## The amount of points along the y axis
@export var y_length := 60
@export var isosurface := 0.05
@export var verbose := true

var point_scene := preload("res://environment/terrain/2d/point.tscn")

func _ready() -> void:
	var scalar := FastNoiseLite.new()
	scalar.noise_type = FastNoiseLite.TYPE_PERLIN
	var mesh_vertices: PackedVector2Array = []
	
	# Place visible points that show where each scalar point is and if it's above/below the isosurface
	for x in x_length:
		for y in y_length:
			var scalar_value := scalar.get_noise_2d(x, y)
			var point := point_scene.instantiate()
			if scalar_value <= isosurface: point.above_iso = false
			else: point.above_iso = true
			point.global_position = Vector2(x * point_distance, y * point_distance)
			add_child(point)
	
	# ====== ITERATE THROUGH SQUARES ======
	
	# Convention (must match how you sample corners and interpolate edges):
	#   Corners, counter-clockwise from bottom-left:
	#     c0 = bottom-left, c1 = bottom-right, c2 = top-right, c3 = top-left
	#   Edges, each between two adjacent corners:
	#     e0 = bottom (c0-c1), e1 = right (c1-c2), e2 = top (c2-c3), e3 = left (c3-c0)
	#   case = c0*1 + c1*2 + c2*4 + c3*8   (bit set when that corner is inside)
	
	# c3-----e2-----c2
	# |              |
	# |              |
	# e3            e1
	# |              |
	# |              |
	# c0-----e0-----c1
	
	if verbose: print("Marching through squares...")
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
			
			# determine case index for segment look up table
			var case_index = 0
			if c0 > isosurface: case_index |= (1 << 0)
			if c1 > isosurface: case_index |= (1 << 1)
			if c2 > isosurface: case_index |= (1 << 2)
			if c3 > isosurface: case_index |= (1 << 3)
			
			# determine where the vetices go in real space based on segment data and real position of the squares' corners
			const EDGE_CORNERS := [[0, 1], [1, 2], [2, 3], [3, 0]]  # the two corners each edge connects
			var segment = MarchingSqauresLUT.SEGMENT_TABLE[case_index]
			if segment[0] == -1: pass
			var i := 0
			while i < segment.size() and segment[i] != -1:
				var edge_a = segment[i]
				var edge_b = segment[i + 1]
				var vertex_a = (corner_pos[EDGE_CORNERS[edge_a][0]] + corner_pos[EDGE_CORNERS[edge_a][1]]) / 2
				var vertex_b = (corner_pos[EDGE_CORNERS[edge_b][0]] + corner_pos[EDGE_CORNERS[edge_b][1]]) / 2
				mesh_vertices.append(vertex_a)
				mesh_vertices.append(vertex_b)
				i += 2
	
	# ====== CONSTRUCT THE MESH ======
	
	if verbose: print("generating mesh...")
	var array_mesh := ArrayMesh.new()
	var mesh_indices: PackedInt32Array = []
	for i in range(mesh_vertices.size()):
		mesh_indices.append(i)
	var surface_arrays = []
	surface_arrays.resize(Mesh.ARRAY_MAX)
	surface_arrays[Mesh.ARRAY_VERTEX] = mesh_vertices
	surface_arrays[Mesh.ARRAY_INDEX] = mesh_indices
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, surface_arrays)
	generated_mesh.mesh = array_mesh
