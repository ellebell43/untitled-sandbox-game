class_name Point2D
extends Sprite2D

var above_iso = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if above_iso:
		self.modulate = Color.WEB_GREEN
	else:
		self.modulate = Color.DARK_RED
