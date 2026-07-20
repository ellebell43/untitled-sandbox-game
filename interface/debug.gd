extends Control

@export var player: Player

@onready var chunk_info_label := %ChunkInfo

func _process(_delta: float) -> void:
	set_chunk_info_label()

## Gets the current chunk manager for the player's current world, then get's the key for the chunk the player is currently in. Sets the text of ChunkInfo to show that information on screen.
func set_chunk_info_label() -> void:
	var chunk_manager := player.current_world.chunk_manager
	if chunk_manager == null:
		chunk_info_label.text = "chunk_pos: not found.\nlod_step: not found"
	else:
		var player_chunk_key := chunk_manager.get_player_chunk_key()
		if player_chunk_key.size() == 0:
			chunk_info_label.text = "chunk_pos: not found.\nlod_step: not found"
		else:
			var chunk_pos: Vector3i = player_chunk_key[0]
			var chunk_lod_step: int = player_chunk_key[1]
			chunk_info_label.text = "chunk_pos: %s\nlod_step: %d" % [str(chunk_pos), chunk_lod_step]
