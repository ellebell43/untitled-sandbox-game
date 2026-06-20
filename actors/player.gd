class_name Player
extends CharacterBody3D

@export var spawn_world: Planet

const SPEED = 10.0
const JUMP_VELOCITY = 4.5
const ROTATION_SPEED = 3
const LOOK_SENSITIVITY = 0.005

@onready var camera = $Camera3D

func _ready() -> void:
	if spawn_world:
		global_position = Vector3(spawn_world.world_radius, spawn_world.world_radius, spawn_world.world_radius) + Vector3(20, 20, 21)

func _physics_process(delta):
	# orient player with planets surface
	up_direction = -get_gravity().normalized()
	var target_basis := get_planet_aligned_basis()
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * ROTATION_SPEED).orthonormalized()
	
	if not is_on_floor():
		velocity = get_gravity()
	
	# get movement direction based on input and apply it
	var direction := Input.get_vector("move_forward", "move_back", "move_left", "move_right").normalized()
	if direction: 
		var x_v = target_basis.x * direction.y * SPEED
		var z_v = target_basis.z * direction.x * SPEED
		velocity = x_v + z_v
		velocity += get_gravity() * delta * SPEED
	elif is_on_floor(): velocity = Vector3(0, 0, 0)
	
	move_and_slide()

var current_rotation: float = 0
var rotation_limit = deg_to_rad(90)
func _input(event):
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed(("ui_cancel")):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# If the mouse is captured, accept mouse input for looking around
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			current_rotation += -event.relative.y * LOOK_SENSITIVITY
			if current_rotation > rotation_limit: return
			if current_rotation < -rotation_limit: return
			camera.rotate_x(-event.relative.y * LOOK_SENSITIVITY)
			self.global_rotate(self.up_direction, -event.relative.x * LOOK_SENSITIVITY)
	
func get_planet_aligned_basis() -> Basis:
	var new_y := -get_gravity().normalized()
	var new_x := new_y.cross(global_transform.basis.z).normalized()
	var new_z := new_x.cross(new_y).normalized()
	return Basis(new_x, new_y, new_z)
