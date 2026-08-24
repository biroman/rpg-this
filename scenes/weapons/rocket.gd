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

@export_group("Wind")
## Fraction of the level wind speed that becomes lateral acceleration, in
## m/s^2 per m/s of wind. Low enough that a crosswind is a lead problem rather
## than a coin flip.
@export var wind_response: float = 0.34

@export_group("Trail")
## How far the rocket must get from the tube before it starts laying smoke.
@export var trail_standoff: float = 5.0

@export_group("Impact")
@export var explosion_scene: PackedScene
## Contacts are ignored for this long so it cannot detonate on the shooter.
@export var arm_time: float = 0.04

@export_group("Audio")
## Looping motor. It is started when the sustainer lights rather than at launch,
## because the launch sound already covers the crack and the moment the motor
## catches - the same way the recording it was cut from is laid out.
@export var motor_sound: AudioStream
@export var motor_fade_in: float = 0.07
## Burnout is a fade, not a cut: the rocket coasts the last stretch in silence.
@export var motor_fade_out: float = 0.4

@onready var visual: Node3D = $Visual
@onready var flame: GPUParticles3D = $Visual/Flame
@onready var motor_light: OmniLight3D = $Visual/MotorLight
@onready var audio: AudioStreamPlayer3D = $Audio

var _age: float = 0.0
var _detonated: bool = false
var _hit_body: Node = null
var _exploded: bool = false
var _recording: ShotRecording = null
var _wind: Vector3 = Vector3.ZERO
## Speed the rocket was actually doing when it struck, captured before the
## physics solver gets a chance to bleed it off.
var _impact_velocity: Vector3 = Vector3.ZERO
var _trail: SmokeTrail = null
var _launch_origin: Vector3 = Vector3.ZERO
var _motor_running: bool = false
var _motor_volume_db: float = 0.0
var _motor_tween: Tween


func _ready() -> void:
	Rounded.soften(visual, 0.006)
	contact_monitor = true
	max_contacts_reported = 4
	continuous_cd = true
	can_sleep = false
	_motor_volume_db = audio.volume_db
	_set_motor_visible(false)


## Called by the weapon right after the rocket enters the tree.
func launch(direction: Vector3, inherited_velocity: Vector3 = Vector3.ZERO) -> void:
	linear_velocity = direction.normalized() * muzzle_speed + inherited_velocity
	angular_velocity = Vector3.ZERO
	var world: Node3D = GameState.world
	_wind = (world as World).wind if world is World else Vector3.ZERO
	_launch_origin = global_position
	_spawn_trail(world)
	_recording = ShotRecording.new()
	_recording.begin(global_position, direction, _wind)
	_record(false)                        # t=0, so the trail starts at the muzzle

	audio.stream = motor_sound


func _physics_process(delta: float) -> void:
	_age += delta

	if _age >= life_time:
		_detonate(global_position, Vector3.UP)
		return

	var burning: bool = _age >= ignition_delay and _age <= ignition_delay + burn_time
	_set_motor_visible(burning)
	_set_motor_audible(burning)

	if burning:
		var heading: Vector3 = -global_basis.z
		if linear_velocity.length_squared() > 0.25:
			heading = linear_velocity.normalized()
		apply_central_force(heading * thrust_acceleration * mass)

	if not _wind.is_zero_approx():
		apply_central_force(_wind * wind_response * mass)

	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

	_orient_to_flight()
	_feed_trail(burning)
	_record(burning)


## Swept collision.
##
## The rocket is a 9 cm sphere crossing a target face 28 cm thick at up to
## 90 m/s - well over a metre per physics tick. Godot's own `continuous_cd`
## does not catch that, so the rocket checks its own path: at the start of every
## physics step it casts along the motion that step is about to make, and
## detonates on the first thing in the way.
##
## Doing it here rather than in `_physics_process` matters. It runs before the
## solver, so the rocket never penetrates anything and never has its velocity
## bled off by a contact - the impact point and the impact speed are both the
## real ones, which is what scoring and the replay read.
func _sweep_step(state: PhysicsDirectBodyState3D) -> bool:
	if _detonated or _age < arm_time:
		return false

	var from: Vector3 = state.transform.origin
	var to: Vector3 = from + state.linear_velocity * state.step
	if from.distance_squared_to(to) < 0.000001:
		return false

	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	var skip: Array[RID] = [get_rid()]
	query.exclude = skip

	var hit: Dictionary = state.get_space_state().intersect_ray(query)
	if hit.is_empty():
		return false

	_detonated = true
	_hit_body = hit["collider"] as Node
	_impact_velocity = state.linear_velocity
	call_deferred("_detonate", hit["position"], hit["normal"])
	return true


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _sweep_step(state):
		return

	# Fallback for anything the sweep cannot see, such as geometry the rocket is
	# already touching when it comes to rest.
	if _detonated or _age < arm_time or state.get_contact_count() == 0:
		return

	var point: Vector3 = state.get_contact_local_position(0)
	var normal: Vector3 = state.get_contact_local_normal(0)
	# Make sure the normal points back out of the surface we just hit.
	if normal.dot(-linear_velocity.normalized()) < 0.0:
		normal = -normal

	_detonated = true
	_hit_body = state.get_contact_collider_object(0) as Node
	_impact_velocity = state.linear_velocity
	call_deferred("_detonate", point, normal)


func _detonate(point: Vector3, normal: Vector3) -> void:
	# Both the sweep and a physics contact can call this for the same rocket.
	if _exploded or not is_inside_tree():
		return
	_detonated = true
	_exploded = true

	var blast_radius: float = 0.0
	if explosion_scene != null:
		var boom: Explosion = explosion_scene.instantiate() as Explosion
		boom.transform = Transform3D(Basis(), point)
		get_parent().add_child(boom)
		blast_radius = boom.radius
		boom.detonate(normal)

	if _trail != null and is_instance_valid(_trail):
		_trail.stop_feeding()

	# File the recording before scoring runs, so whatever handles the hit can
	# reach `Replay.last_recording` and attach its result to it.
	if _recording != null:
		_recording.finish(_age, point, normal, blast_radius, _impact_velocity)
		Replay.submit(_recording)

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


## The motor trail is solid instanced geometry that outlives the rocket, so it
## belongs to the level rather than to this node - parented here it would vanish
## the instant the rocket detonated.
func _spawn_trail(world: Node3D) -> void:
	if world == null:
		return
	_trail = SmokeTrail.new()
	# Smoke ends up going wherever the air is going, which is what makes a
	# crosswind level readable: you can watch your own trail being blown sideways.
	_trail.drift = Vector3(0.0, 0.9, 0.0) + _wind * 0.55
	(world as World).add_projectile(_trail)


func _feed_trail(burning: bool) -> void:
	if _trail == null or not is_instance_valid(_trail):
		return
	# This is fired off a shoulder, not out of a silo: without a standoff the
	# first puffs are laid roughly inside the player's head, and since they are
	# solid geometry they fill the entire screen. Nothing is laid until the
	# rocket is clear, which is also about where the sustainer lights and the
	# real smoke starts.
	if global_position.distance_squared_to(_launch_origin) < trail_standoff * trail_standoff:
		return
	# Lay it from the exhaust rather than from the centre of mass.
	var tail: Vector3 = global_position + visual.global_basis.z * 0.2
	_trail.feed(tail, 1.0 if burning else 0.3)


## One sample per physics tick. The pose comes from `visual`, which is what the
## replay draws, not from the body basis (the body tumbles, the visual does not).
func _record(burning: bool) -> void:
	if _recording == null or _detonated:
		return
	_recording.add_frame(
		_age,
		global_position,
		visual.global_basis.get_rotation_quaternion(),
		linear_velocity,
		burning
	)


func _set_motor_visible(on: bool) -> void:
	flame.emitting = on
	motor_light.visible = on


## Brings the looping motor up as the sustainer catches and lets it die away at
## burnout, instead of running flat out for the whole flight.
func _set_motor_audible(on: bool) -> void:
	if on == _motor_running or audio.stream == null:
		return
	_motor_running = on

	if _motor_tween != null and _motor_tween.is_valid():
		_motor_tween.kill()
	_motor_tween = create_tween()

	if on:
		audio.volume_db = _motor_volume_db - 18.0
		audio.play()
		_motor_tween.tween_property(audio, "volume_db", _motor_volume_db, motor_fade_in)
	else:
		_motor_tween.tween_property(audio, "volume_db", _motor_volume_db - 40.0, motor_fade_out)
		_motor_tween.tween_callback(audio.stop)
