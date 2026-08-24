extends Node
## Entry point. Wires the level, the player and the UI together.

@onready var world: World = $World
@onready var player: Player = $Player


func _ready() -> void:
	player.teleport_to(world.get_spawn_transform())
	GameState.start_play()
