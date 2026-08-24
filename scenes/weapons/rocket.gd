class_name Rocket
extends RigidBody3D
## Fin-stabilised rocket with a real flight model.
##
## Phases, matching an RPG-style weapon:
##   1. Booster kicks it out of the tube at `muzzle_speed` - slow, very visible.
##   2. After `ignition_delay` the sustainer motor lights and pushes along the
##      current heading for `burn_time`.
##   3. Motor burns out and it coasts as a ballistic body until it hits.
##
## Thrust follows the velocity vector rather than the spawn direction, which is
## what a fin-stabilised rocket actually does: it weathervanes into the airflow,
## so gravity bends the whole trajectory instead of just the tail.

@export_group("Flight")
## Speed leaving the tube, before the motor lights.
@export var muzzle_speed: float = 25.0
## Delay before the sustainer motor ignites.
@export var ignition_delay: float = 0.12
## How long the motor burns.
@export var burn_time: float = 1.2
## Motor acceleration while burning (m/s^2).
@export var thrust_acceleration: float = 34.0
## Hard cap so a long burn cannot run away.
@export var max_speed: float = 95.0
## Self-destruct if it never hits anything.
@export var life_time: float = 16.0

@export_group("Impact")
@export var explosion_scene: PackedScene
## Contacts are ignored for this long so it cannot detonate on the shooter.
@export var arm_time: float = 0.04

@export_group("Audio")
@export var motor_sound: AudioStream

@onready var visual: Node3D = $Visual
@onready var flame: GPUParticles3D = $Visual/Flame
@onready var motor_light: OmniLight3D = $Visual/MotorLight
@onready var smoke_trail: GPUParticles3D = $SmokeTrail
@onready var audio: AudioStreamPlayer3D = $Audio

var _age: float = 0.0
var _detonated: bool = false
var _hit_body: Node = null


func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	can_sleep = false
	_set_motor_visible(false)


## Called by the weapon right after the rocket enters the tree.
func launch(direction: Vector3, inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	linear_velocity = direction.normalized() * muzzle_speed + inherited_velocity
	angular_velocity = Vector3.ZERO
	smoke_trail.emitting = true
	if motor_sound != null:
		audio.stream = motor_sound
		audio.play()


func _physics_process(delta: float) -> void:
	_age += delta

	if _age >= life_time:
		_detonate(global_position, Vector3.UP)
		return

	var burning: bool = _age >= ignition_delay and _age <= ignition_delay + burn_time
	_set_motor_visible(burning)

	if burning:
		var heading: Vector3 = -global_basis.z
		if linear_velocity.length_squared() > 0.25:
			heading = linear_velocity.normalized()
		apply_central_force(heading * thrust_acceleration * mass)

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	_orient_to_flight()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _detonated or _age < arm_time or state.get_contact_count() == 0:
		return

	var point: Vector3 = state.get_contact_local_position(0)
	var normal: Vector3 = state.get_contact_local_normal(0)
	# Make sure the normal points back out of the surface we just hit.
	if normal.dot(-linear_velocity.normalized()) < 0.0:
		normal = -normal

	_detonated = true
	_hit_body = state.get_contact_collider_object(0) as Node
	call_deferred("_detonate", point, normal)


func _detonate(point: Vector3, normal: Vector3) -> void:
	if not is_inside_tree():
		return
	_detonated = true

	var blast_radius: float = 0.0
	if explosion_scene != null:
		var boom: Explosion = explosion_scene.instantiate() as Explosion
		boom.transform = Transform3D(Basis(), point)
		get_parent().add_child(boom)
		blast_radius = boom.radius
		boom.detonate(normal)

	# Scoring listens for this: it carries both the exact impact point and what
	# the rocket physically struck, so a direct hit can be told from a blast hit.
	EventBus.rocket_impact.emit(point, normal, _hit_body, blast_radius)

	queue_free()


func _orient_to_flight() -> void:
	if linear_velocity.length_squared() < 1.0:
		return
	var dir: Vector3 = linear_velocity.normalized()
	var up: Vector3 = Vector3.UP if absf(dir.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
	visual.look_at(global_position + dir, up)


func _set_motor_visible(on: bool) -> void:
	flame.emitting = on
	motor_light.visible = on
