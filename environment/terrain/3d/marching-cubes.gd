extends Node3D

@onready var generated_mesh := $GeneratedMesh

## How far apart each point is in real space
@export var point_distance := .5
## The amount of points along the x, y, and z axis
@export var size := 25
## The value of the scalar field that represents the surface of the mesh
@export var isosurface := .2
## True means the vertex positions will be interpolated, creating a much smoother surface. False means the steps will be much harder and blockier.
@export var interpolated := false
## Print out extra information to the console
@export var verbose := true

# MeshInstance3D scene for showing visble data points on the screen when you run the scene
var point_scene: PackedScene = preload("res://environment/terrain/3d/point-3d.tscn")

func _ready() -> void:
	# ====== INITIALIZE DATA ======
	
	# Create a noise object to use as a scalar field
	var scalar := FastNoiseLite.new()
	scalar.noise_type = FastNoiseLite.TYPE_PERLIN
	# Initialize a mesh to store vertices in for our mesh
	var mesh_vertices: PackedVector3Array = []
	
	# ====== CREATE VISIBLE DATA POINTS ======
	
	if verbose: print("creating ", size * size * size, " points")
	for x in size:
		for y in size:
			for z in size:
				var scalar_value = scalar.get_noise_3d(x, y, z)
				var point := point_scene.instantiate()
				if scalar_value <= isosurface: point.above_iso = false # shows point as red
				else: point.above_iso = true # shows point as green
				add_child(point)
				point.global_position = Vector3(x * point_distance, y * point_distance, z * point_distance)
				
