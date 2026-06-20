class_name Player
extends CharacterBody3D

@export var spawn_world: Planet

const SPEED = 7.0
const JUMP_VELOCITY = 4.5
const ROTATION_SPEED = 3
const LOOK_SENSITIVITY = 0.005
var friction = 14.0

@onready var camera = $Camera3D

func _ready() -> void:
	if spawn_world:
		global_position = Vector3(spawn_world.world_radius, spawn_world.world_radius, spawn_world.world_radius) + Vector3(20, 20, 20)

func _physics_process(delta):
	# set new up for floor detection
	self.up_direction = -get_gravity().normalized()
	# align self with planet
	transform.basis = global_transform.basis.slerp(get_planet_aligned_basis(), delta * ROTATION_SPEED)

	# Add the gravity.
	if not is_on_floor():
		velocity += self.get_gravity() * delta

	## Handle Jump.
	#if Input.is_action_pressed("ui_accept"):
		#velocity.y = JUMP_VELOCITY
	#elif Input.is_key_pressed(KEY_SHIFT):
		#velocity.y = -JUMP_VELOCITY
	#else: velocity.y = 0

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	if direction:
		velocity = direction * SPEED
	else:
		velocity = velocity.move_toward(Vector3(0, 0, 0), delta * friction)

	move_and_slide()
	
func _input(event):
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	elif event.is_action_pressed(("ui_cancel")):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		# If the mouse is captured, accept mouse input for looking around
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			#camera.rotate_x(-event.relative.y * LOOK_SENSITIVITY)
			#camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(90), deg_to_rad(90))
			self.rotate_y(-event.relative.x * LOOK_SENSITIVITY)
	
func get_planet_aligned_basis() -> Basis:
	var new_y := -get_gravity().normalized()
	var new_x := new_y.cross(global_transform.basis.z).normalized()
	var new_z := new_x.cross(new_y).normalized()
	return Basis(new_x, new_y, new_z)
	
