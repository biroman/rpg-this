class_name Player
extends CharacterBody3D
## First-person character controller.
##
## Movement is fully tunable from the inspector. Nothing here reaches outside
## the player except registering itself with GameState on ready.

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var crouch_speed: float = 2.6
## How fast horizontal velocity chases the input direction while grounded.
@export var ground_accel: float = 14.0
## Same, but airborne. Lower = floatier, less control mid-jump.
@export var air_accel: float = 3.0
## Deceleration when there is no input and we are on the floor (m/s^2).
@export var ground_friction: float = 40.0

@export_group("Jump")
## The player runs on its own gravity, not the project's. Project gravity stays
## realistic (9.8) so rockets and debris behave, while the player gets a
## snappier fall.
@export var gravity: float = 24.0
@export var jump_height: float = 1.15
## Grace period after walking off a ledge where a jump still works.
@export var coyote_time: float = 0.12
## Jump pressed slightly before landing still fires on touchdown.
@export var jump_buffer_time: float = 0.12

@export_group("Look")
@export_range(0.0005, 0.01, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(50.0, 89.9, 0.1) var pitch_limit_deg: float = 89.0
@export var invert_y: bool = false

@export_group("Feel")
@export var head_bob_enabled: bool = true
@export var head_bob_amplitude: float = 0.05
@export var head_bob_frequency: float = 2.1
@export var base_fov: float = 75.0
@export var sprint_fov: float = 84.0

@export_group("Recoil")
## How fast the weapon's camera kick decays back to where you were aiming.
@export var recoil_recovery: float = 5.0
## How fast the view catches up to the kick.
@export var recoil_snap: float = 22.0

@export_group("Camera shake")
@export var shake_decay: float = 1.7
@export var shake_pitch_deg: float = 1.5
@export var shake_yaw_deg: float = 1.3
@export var shake_roll_deg: float = 2.4

const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.15
const STAND_EYE: float = 1.62
const CROUCH_EYE: float = 1.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var body_collision: CollisionShape3D = $CollisionShape3D
@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var ceiling_check: RayCast3D = $CeilingCheck
@onready var interact_ray: RayCast3D = $Head/Camera3D/InteractRay
@onready var weapon_rig: WeaponRig = %WeaponRig

## Mouse movement this frame, in pixels. The viewmodel reads it for sway.
var look_delta: Vector2 = Vector2.ZERO

var _pitch: float = 0.0
var _recoil: Vector2 = Vector2.ZERO
var _recoil_target: Vector2 = Vector2.ZERO
var _trauma: float = 0.0
var _shake_time: float = 0.0
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _bob_time: float = 0.0
var _is_crouching: bool = false
var _capsule: CapsuleShape3D


func _ready() -> void:
	# Duplicate so tweaking the capsule at runtime never edits the shared resource.
	_capsule = (body_collision.shape as CapsuleShape3D).duplicate()
	body_collision.shape = _capsule
	camera.fov = base_fov
	_set_height(STAND_HEIGHT, STAND_EYE)
	EventBus.explosion_happened.connect(_on_explosion)
	GameState.register_player(self)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_apply_look(event.relative)


func _process(delta: float) -> void:
	_update_recoil(delta)
	_update_shake(delta)
	_apply_view_offsets()
	look_delta = look_delta.lerp(Vector2.ZERO, clampf(18.0 * delta, 0.0, 1.0))


func _physics_process(delta: float) -> void:
	_handle_weapon_input()
	_tick_timers(delta)
	_update_crouch()
	_apply_gravity(delta)
	_try_jump()
	_apply_movement(delta)
	move_and_slide()
	_update_head_bob(delta)
	_update_fov(delta)


# --- look ---------------------------------------------------------------

func _apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * mouse_sensitivity)

	var dir: float = 1.0 if invert_y else -1.0
	var limit: float = deg_to_rad(pitch_limit_deg)
	_pitch = clampf(_pitch + relative.y * mouse_sensitivity * dir, -limit, limit)
	look_delta += relative


# --- movement -----------------------------------------------------------

func _tick_timers(delta: float) -> void:
	if is_on_floor():
		_coyote_timer = coyote_time
	else:
		_coyote_timer = maxf(_coyote_timer - delta, 0.0)

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = jump_buffer_time
	else:
		_jump_buffer_timer = maxf(_jump_buffer_timer - delta, 0.0)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0


func _try_jump() -> void:
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0 and not _is_crouching:
		velocity.y = sqrt(2.0 * gravity * jump_height)
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0


func _apply_movement(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var wish_dir: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y))
	wish_dir.y = 0.0
	wish_dir = wish_dir.normalized()

	var speed: float = _current_speed(input_dir)
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z)

	if wish_dir.length_squared() > 0.0:
		var accel: float = ground_accel if is_on_floor() else air_accel
		horizontal = horizontal.lerp(wish_dir * speed, clampf(accel * delta, 0.0, 1.0))
	elif is_on_floor():
		horizontal = horizontal.move_toward(Vector3.ZERO, ground_friction * delta)

	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _current_speed(input_dir: Vector2) -> float:
	if _is_crouching:
		return crouch_speed
	if Input.is_action_pressed("sprint") and input_dir.y < -0.1:
		return sprint_speed
	return walk_speed


# --- crouch -------------------------------------------------------------

func _update_crouch() -> void:
	var want_crouch: bool = Input.is_action_pressed("crouch")

	if want_crouch and not _is_crouching:
		_is_crouching = true
		_set_height(CROUCH_HEIGHT, CROUCH_EYE)
	elif not want_crouch and _is_crouching and not _blocked_above():
		_is_crouching = false
		_set_height(STAND_HEIGHT, STAND_EYE)


func _blocked_above() -> bool:
	ceiling_check.force_raycast_update()
	return ceiling_check.is_colliding()


func _set_height(height: float, eye: float) -> void:
	_capsule.height = height
	body_collision.position.y = height * 0.5
	body_mesh.position.y = height * 0.5
	if body_mesh.mesh is CapsuleMesh:
		var m: CapsuleMesh = body_mesh.mesh as CapsuleMesh
		if not m.resource_local_to_scene:
			body_mesh.mesh = m.duplicate()
		(body_mesh.mesh as CapsuleMesh).height = height
	head.position.y = eye


# --- juice --------------------------------------------------------------

func _update_head_bob(delta: float) -> void:
	if not head_bob_enabled:
		camera.position.y = 0.0
		return

	var speed_2d: float = Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and speed_2d > 0.5:
		_bob_time += delta * head_bob_frequency * speed_2d
		var offset: float = sin(_bob_time) * head_bob_amplitude
		camera.position.y = lerpf(camera.position.y, offset, 0.35)
	else:
		camera.position.y = lerpf(camera.position.y, 0.0, 0.15)


func _update_fov(delta: float) -> void:
	var speed_2d: float = Vector2(velocity.x, velocity.z).length()
	var target: float = base_fov
	if speed_2d > walk_speed + 0.5:
		target = sprint_fov
	camera.fov = lerpf(camera.fov, target, clampf(8.0 * delta, 0.0, 1.0))


# --- weapon, recoil and shake -------------------------------------------

func _handle_weapon_input() -> void:
	if weapon_rig == null or weapon_rig.weapon == null:
		return
	weapon_rig.weapon.handle_fire_input(
		Input.is_action_pressed("fire"),
		Input.is_action_just_pressed("fire")
	)
	if Input.is_action_just_pressed("reload"):
		weapon_rig.weapon.start_reload()


## Called by the weapon: pitch kick in degrees, random yaw spread in degrees.
func add_recoil(pitch_deg: float, yaw_spread_deg: float) -> void:
	_recoil_target += Vector2(
		deg_to_rad(pitch_deg),
		deg_to_rad(randf_range(-yaw_spread_deg, yaw_spread_deg))
	)


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _update_recoil(delta: float) -> void:
	_recoil_target = _recoil_target.lerp(Vector2.ZERO, clampf(recoil_recovery * delta, 0.0, 1.0))
	_recoil = _recoil.lerp(_recoil_target, clampf(recoil_snap * delta, 0.0, 1.0))


func _update_shake(delta: float) -> void:
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	_shake_time += delta


func _apply_view_offsets() -> void:
	head.rotation.x = clampf(_pitch + _recoil.x, -PI * 0.5, PI * 0.5)

	var s: float = _trauma * _trauma
	camera.rotation = Vector3(
		sin(_shake_time * 37.0) * s * deg_to_rad(shake_pitch_deg),
		_recoil.y + sin(_shake_time * 29.3 + 1.7) * s * deg_to_rad(shake_yaw_deg),
		sin(_shake_time * 21.1 + 3.4) * s * deg_to_rad(shake_roll_deg)
	)


func _on_explosion(at: Vector3, radius: float, strength: float) -> void:
	var distance: float = global_position.distance_to(at)
	var falloff: float = clampf(1.0 - distance / (radius * 4.5), 0.0, 1.0)
	add_trauma(strength * falloff * falloff)


# --- helpers for other systems -----------------------------------------

## Node currently under the crosshair, or null.
func get_looked_at() -> Node3D:
	if interact_ray.is_colliding():
		return interact_ray.get_collider() as Node3D
	return null


## Point the view at an exact yaw/pitch. Used by tests and cutscenes.
func set_look(yaw_degrees: float, pitch_degrees: float) -> void:
	rotation.y = deg_to_rad(yaw_degrees)
	_pitch = clampf(deg_to_rad(pitch_degrees), -deg_to_rad(pitch_limit_deg), deg_to_rad(pitch_limit_deg))
	_recoil = Vector2.ZERO
	_recoil_target = Vector2.ZERO
	_trauma = 0.0
	_apply_view_offsets()


func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


func teleport_to(target: Transform3D) -> void:
	velocity = Vector3.ZERO
	global_transform = target
	_pitch = 0.0
	head.rotation.x = 0.0
