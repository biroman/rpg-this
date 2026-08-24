class_name RocketLauncher
extends Weapon
## Shoulder-fired launcher. Spawns a self-propelled rocket into the main world.
##
## The weapon model lives in the viewmodel viewport, which has its own World3D,
## so the projectile is spawned through `World` rather than from the muzzle node.
## The muzzle is only used for the flash and backblast you actually see.

@export_group("Rocket")
@export var rocket_scene: PackedScene
## Spawn point relative to the player camera (right, up, forward).
@export var spawn_offset: Vector3 = Vector3(0.14, -0.1, -0.75)
## The rocket is aimed at whatever the crosshair is over, out to this range.
@export var aim_distance: float = 800.0
## Fraction of the player's own velocity the rocket inherits.
@export var inherit_velocity: float = 0.5

@export_group("Audio")
@export var launch_sound: AudioStream
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream

@onready var audio: AudioStreamPlayer = $Audio
@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash
@onready var muzzle_smoke: GPUParticles3D = $Muzzle/MuzzleSmoke
@onready var backblast: GPUParticles3D = $Backblast/BackblastParticles
@onready var loaded_rocket: Node3D = $Model/LoadedRocket


## Radius taken off every edge and rim on the launcher. Authored square because
## square is what you can place by eye; rounded here because nothing in this
## world has a hard edge.
@export var edge_radius: float = 0.01


func _ready() -> void:
	super()
	Rounded.soften($Model, edge_radius)
	EventBus.weapon_reload_finished.connect(_on_reload_finished)


func _process(delta: float) -> void:
	super(delta)
	# The warhead sticking out of the tube disappears while the tube is empty.
	loaded_rocket.visible = ammo_in_magazine > 0


func _shoot() -> void:
	var player: Player = GameState.player
	var world: World = GameState.world
	if player == null or world == null or rocket_scene == null:
		push_warning("RocketLauncher: missing player, world or rocket_scene.")
		return

	var cam: Camera3D = player.camera
	var cam_xform: Transform3D = cam.global_transform
	var origin: Vector3 = cam_xform * spawn_offset
	var direction: Vector3 = (_aim_point(cam) - origin).normalized()

	var rocket: Node3D = rocket_scene.instantiate() as Node3D
	# Set the transform before entering the tree so the body starts where we want.
	rocket.transform = Transform3D(basis_facing(direction), origin)
	world.add_projectile(rocket)
	rocket.call("launch", direction, player.velocity * inherit_velocity)

	_play(launch_sound)
	muzzle_flash.restart()
	muzzle_smoke.restart()
	backblast.restart()


func _on_empty() -> void:
	_play(empty_sound)


func _on_reload_started() -> void:
	_play(reload_sound)


func _on_reload_finished() -> void:
	pass


## Where the crosshair is pointing, so the rocket converges on it instead of
## flying parallel to the view.
func _aim_point(cam: Camera3D) -> Vector3:
	var from: Vector3 = cam.global_position
	var to: Vector3 = from - cam.global_basis.z * aim_distance

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 | 4          # world + props
	var skip: Array[RID] = []
	if GameState.player != null:
		skip.append(GameState.player.get_rid())
	query.exclude = skip

	var hit: Dictionary = cam.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]


func _play(stream: AudioStream) -> void:
	if stream == null:
		return
	audio.stream = stream
	audio.pitch_scale = randf_range(0.96, 1.04)
	audio.play()


## Basis whose -Z axis points along `dir`.
static func basis_facing(dir: Vector3) -> Basis:
	var z: Vector3 = -dir.normalized()
	var up: Vector3 = Vector3.UP
	if absf(z.dot(up)) > 0.999:
		up = Vector3.RIGHT
	var x: Vector3 = up.cross(z).normalized()
	var y: Vector3 = z.cross(x).normalized()
	return Basis(x, y, z)
