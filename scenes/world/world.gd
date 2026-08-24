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

@export_group("Weather")
## Steady wind, in metres per second. Only projectiles feel it.
@export var wind: Vector3 = Vector3.ZERO
## Metres per second. Sound is not instant out here: a blast 150 m downrange
## flashes first and reaches you nearly half a second later.
@export var speed_of_sound: float = 343.0

@onready var props_root: Node3D = $Props
@onready var projectiles_root: Node3D = $Projectiles
@onready var spawn_point: Marker3D = $SpawnPoint


func _ready() -> void:
	GameState.register_world(self)


## Sets the level wind. Anything that cares listens for `wind_changed`.
func set_wind(value: Vector3) -> void:
	wind = value
	EventBus.wind_changed.emit(wind)


## How long a sound made at `from` takes to reach the player.
##
## This is flat open ground with nothing to bounce off, so travel time is the
## whole of it - no reverb, no slapback, just the delay and the distance
## rolloff the 3D audio already applies.
func sound_delay(from: Vector3) -> float:
	var player: Node3D = GameState.player
	if player == null or speed_of_sound <= 0.0:
		return 0.0
	return from.distance_to(player.global_position) / speed_of_sound


func get_spawn_transform() -> Transform3D:
	return spawn_point.global_transform


## Parents a projectile (or its explosion) into the level.
func add_projectile(node: Node) -> void:
	projectiles_root.add_child(node)


## Removes any rockets in flight and the scorch marks they left behind. Called
## when a level restarts so nothing carries over from the last one.
func clear_projectiles() -> void:
	for child in projectiles_root.get_children():
		child.queue_free()


## Adds a scene instance to the level at the given point.
func spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var instance := scene.instantiate() as Node3D
	props_root.add_child(instance)
	instance.position = at
	return instance
