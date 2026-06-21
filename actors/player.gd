class_name Player
extends CharacterBody3D

@export var spawn_world: Planet

const SPEED := 5.0
const JUMP_VELOCITY := 5.0
const ROTATION_SPEED := 3
const LOOK_SENSITIVITY := 0.005
const MAX_VELOCITY := Vector3(30, 30, 30)

var fly_mode := false
var current_world: Planet = null

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	if spawn_world:
		global_position = spawn_world.get_valid_spawn_point()
		var target_basis := get_planet_aligned_basis()
		global_transform.basis = target_basis
		#global_position = Vector3(spawn_world.world_radius, spawn_world.world_radius, spawn_world.world_radius)

func _physics_process(delta):
	# orient player with planets surface
	var target_basis := get_planet_aligned_basis()
	up_direction = -get_gravity().normalized()
	global_transform.basis = global_transform.basis.slerp(target_basis, delta * ROTATION_SPEED).orthonormalized()
	
	# preserve vertical velocity from previous velocity to allow it to decay
	var vertical_velocity = up_direction * velocity.dot(up_direction)
	
	# if the player is at a world, apply a tangential velocity to lock the player to the planets rotation
	var planet_rotation_v: Vector3
	if current_world:
		var angular_velocity_vector = current_world.rotation_axis * current_world.rotation_speed
		var displacement_vector = self.global_position - current_world.global_position
		planet_rotation_v = angular_velocity_vector.cross(displacement_vector)
	
	# get movement direction based on input and apply it
	var direction := Input.get_vector("move_forward", "move_back", "move_left", "move_right").normalized()
	# Assign velocity based on forward and side input (all horizontal velocity)
	if direction: 
		var x_v := target_basis.x * direction.y
		var z_v := target_basis.z * direction.x
		var v_sum = z_v + x_v
		velocity = (v_sum * SPEED) + planet_rotation_v
		if Input.is_action_pressed("sprint"): velocity *= 2
	else: 
		velocity = planet_rotation_v
	
	# Add back in the preserved vertical velocity unless flying
	if not fly_mode: velocity += vertical_velocity
	
	if not is_on_floor() and not fly_mode:
		velocity += get_gravity() * delta
	
	if Input.is_action_just_pressed("jump") and not fly_mode:
		var jump_velocity := up_direction * JUMP_VELOCITY
		velocity += jump_velocity
	elif Input.is_action_pressed("jump") and fly_mode:
		velocity += up_direction * JUMP_VELOCITY
	elif Input.is_action_pressed("crouch") and fly_mode:
		velocity -= up_direction * JUMP_VELOCITY
	
	move_and_slide()

var current_rotation: float = 0
var ROTATION_LIMIT = deg_to_rad(90)
func _input(event):
	# if F is pressed, toggle flight_mode
	if event.is_action_pressed("toggle_flight"):
		fly_mode = not fly_mode
	# if the game is clicked on, capture the mouse
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# if "esc" is pressed, release the mouse
	elif event.is_action_pressed(("ui_cancel")):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# If the mouse is captured, accept mouse input for looking around
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			current_rotation += -event.relative.y * LOOK_SENSITIVITY
			if current_rotation > ROTATION_LIMIT: current_rotation = ROTATION_LIMIT; return
			if current_rotation < -ROTATION_LIMIT: current_rotation = - ROTATION_LIMIT; return
			camera.rotate_x(-event.relative.y * LOOK_SENSITIVITY)
			self.global_rotate(self.up_direction, -event.relative.x * LOOK_SENSITIVITY)
	

func get_planet_aligned_basis() -> Basis:
	var new_y := -get_gravity().normalized()
	var new_x := new_y.cross(global_transform.basis.z).normalized()
	var new_z := new_x.cross(new_y).normalized()
	return Basis(new_x, new_y, new_z)
