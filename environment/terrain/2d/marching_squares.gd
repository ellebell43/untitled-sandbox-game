extends Node2D

@export var point_distance = 30
@export var x_length = 20
@export var y_length = 20

var point_scene := preload("res://environment/terrain/2d/point.tscn")

func _ready() -> void:
	var scalar = FastNoiseLite.new()
	for x in x_length:
		for y in y_length:
			var scalar_value = scalar.get_noise_2d(x, y)
			var point = point_scene.instantiate()
			if scalar_value <= 0: point.above_iso = false
			else: point.above_iso = true
			point.global_position = Vector2(x * point_distance, y * point_distance)
			add_child(point)
