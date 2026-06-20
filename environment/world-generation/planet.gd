class_name Planet
extends Node3D

@export var player: Player
@export var world_seed: int = 1
## number of units on each axis that a chunk takes up
@export var chunk_size := 20
## number of chunks per axis.
@export var chunk_count := 10
## number of chunks to render out
@export var render_distance := 4
@export var rotation_speed := .04
@export var rotation_axis := Vector3(0, 0.5, 1).normalized()

@onready var gravity_shape := $GravityArea/GravityShape

var world_radius = (chunk_size * chunk_count) / 2.5

func _ready() -> void:
	var chunk_manager = ChunkManager.new(player, world_seed, render_distance, chunk_size, chunk_count)
	# determine overall size of volume and set the mesh to be at the center by placing that manager's origin and -radius
	chunk_manager.position = -Vector3(world_radius, world_radius, world_radius)
	self.add_child(chunk_manager)
	gravity_shape.shape.radius = world_radius * 3

func _physics_process(delta: float) -> void:
	self.global_rotate(rotation_axis, rotation_speed * delta)


func _on_gravity_area_body_entered(body: Node3D) -> void:
	if body is Player:
		body.current_world = self


func _on_gravity_area_body_exited(body: Node3D) -> void:
	if body is Player:
		body.current_world = null
