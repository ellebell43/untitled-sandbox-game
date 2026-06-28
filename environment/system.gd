extends Node3D

@onready var progress_bar: ProgressBar = %ProgressBar

@export var player: Player

#var ready_for_player := false:
	#set(is_ready):
		#if is_ready:
			##player.fly_mode = false
			#player.allow_inputs = true
			#progress_bar.get_parent().queue_free()
		#ready_for_player = is_ready
#
## Called when the node enters the scene tree for the first time.
#func _ready() -> void:
	#Utils.chunk_task_completed.connect(_on_chunk_task_completed)
	#
#func _process(_delta: float) -> void:
	#if progress_bar and progress_bar.value >= 100 and not ready_for_player: 
		#progress_bar.value = 100
		#ready_for_player = true
#
#func _on_chunk_task_completed(tasks_complete: int):
	#@warning_ignore("integer_division")
	#if tasks_complete > 0 and progress_bar: progress_bar.value = tasks_complete
