class_name Point3D
extends MeshInstance3D

@onready var green_mat = preload("res://assets/textures/plain-green.tres")
@onready var red_mat = preload("res://assets/textures/plain-red.tres")

var above_iso = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if above_iso:
		material_override = green_mat
	else:
		material_override = red_mat
