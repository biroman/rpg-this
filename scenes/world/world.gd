class_name World
extends Node3D
## The level: a large flat plane.
##
## Anything you place in the level goes under `Props`. Keep the ground,
## lighting and environment on this scene; keep gameplay objects as their
## own scenes in `scenes/props/`.

@export_group("Extent")
## Half-size of the playable area in metres. 240 -> a 480x480 m field.
@export var half_extent: float = 240.0

@onready var props_root: Node3D = $Props
@onready var projectiles_root: Node3D = $Projectiles
@onready var spawn_point: Marker3D = $SpawnPoint


func _ready() -> void:
	GameState.register_world(self)


func get_spawn_transform() -> Transform3D:
	return spawn_point.global_transform


## Parents a projectile (or its explosion) into the level.
func add_projectile(node: Node) -> void:
	projectiles_root.add_child(node)


## Adds a scene instance to the level at the given point.
func spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var instance := scene.instantiate() as Node3D
	props_root.add_child(instance)
	instance.position = at
	return instance
