class_name Explosion
extends Node3D
## One-shot blast: physics impulse, particles, light flash, scorch mark, shake.
##
## Spawn it, call `detonate(surface_normal)`, and it cleans itself up.

@export_group("Blast")
@export var radius: float = 8.0
## Impulse at the epicentre, in newton-seconds per kilogram of target.
@export var impulse: float = 30.0
## Blast pushes bodies slightly upward so debris lifts instead of skidding.
@export var upward_bias: float = 0.35
## Physics layers the blast can push: world(1) + props(4).
@export_flags_3d_physics var affect_mask: int = 5

@export_group("Feedback")
## Camera shake at the epicentre, 0..1.
@export var shake_strength: float = 1.0
@export var flash_energy: float = 24.0
@export var flash_time: float = 0.32

@export_group("Scorch")
@export var decal_size: float = 6.0
@export var decal_lifetime: float = 22.0
@export var decal_fade_time: float = 6.0

@onready var fireball: GPUParticles3D = $Fireball
@onready var smoke: GPUParticles3D = $Smoke
@onready var sparks: GPUParticles3D = $Sparks
@onready var flash: OmniLight3D = $Flash
@onready var scorch: Decal = $Scorch
@onready var audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	flash.light_energy = 0.0
	scorch.visible = false


## Fire everything off. `surface_normal` orients the scorch decal.
func detonate(surface_normal: Vector3 = Vector3.UP) -> void:
	_apply_blast()
	_place_scorch(surface_normal)

	fireball.restart()
	smoke.restart()
	sparks.restart()
	audio.play()

	EventBus.explosion_happened.emit(global_position, radius, shake_strength)

	_flash_then_fade()


func _apply_blast() -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var sphere := SphereShape3D.new()
	sphere.radius = radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis(), global_position)
	query.collision_mask = affect_mask
	query.collide_with_bodies = true
	query.collide_with_areas = false

	var seen: Dictionary = {}
	for hit in space.intersect_shape(query, 48):
		var body: Object = hit.get("collider")
		if body == null or seen.has(body.get_instance_id()):
			continue
		seen[body.get_instance_id()] = true

		if body is RigidBody3D:
			_push_rigid_body(body as RigidBody3D)


func _push_rigid_body(body: RigidBody3D) -> void:
	var to_body: Vector3 = body.global_position - global_position
	var distance: float = to_body.length()
	var falloff: float = clampf(1.0 - distance / radius, 0.0, 1.0)
	falloff *= falloff                                  # inverse-square-ish

	var direction: Vector3 = Vector3.UP
	if distance > 0.001:
		direction = (to_body / distance + Vector3.UP * upward_bias).normalized()

	body.apply_impulse(direction * impulse * falloff * body.mass)
	body.apply_torque_impulse(
		Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
		* impulse * falloff * body.mass * 0.08
	)


func _place_scorch(surface_normal: Vector3) -> void:
	var n: Vector3 = surface_normal.normalized()
	if n.length_squared() < 0.5:
		n = Vector3.UP

	# A Decal projects along its own -Y, so +Y has to be the surface normal.
	var reference: Vector3 = Vector3.FORWARD
	if absf(n.dot(reference)) > 0.99:
		reference = Vector3.RIGHT
	var x: Vector3 = n.cross(reference).normalized()
	var z: Vector3 = x.cross(n).normalized()

	var b := Basis(x, n, z).rotated(n, randf() * TAU)
	var jitter: float = randf_range(0.85, 1.2)
	scorch.size = Vector3(decal_size * jitter, decal_size * 0.6, decal_size * jitter)
	scorch.global_transform = Transform3D(b, global_position + n * 0.06)
	scorch.visible = true


func _flash_then_fade() -> void:
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", flash_energy, 0.03)
	tween.tween_property(flash, "light_energy", 0.0, flash_time).set_ease(Tween.EASE_OUT)

	var fade := create_tween()
	fade.tween_interval(maxf(decal_lifetime - decal_fade_time, 0.0))
	fade.tween_property(scorch, "albedo_mix", 0.0, decal_fade_time)
	fade.tween_callback(queue_free)
