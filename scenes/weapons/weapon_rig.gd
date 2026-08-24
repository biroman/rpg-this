class_name WeaponRig
extends Node3D
## Viewmodel holder. Everything that makes the gun feel handheld lives here:
## look sway, walk bob, recoil kick and the lower-the-weapon reload pose.
##
## This node sits inside the viewmodel SubViewport, so it never collides with
## or is occluded by the real world.

@export var rest_position: Vector3 = Vector3(0.2, -0.17, -0.28)
@export var rest_rotation_deg: Vector3 = Vector3(0.0, -2.0, 0.0)

@export_group("Sway")
## Metres of lag per pixel of mouse movement.
@export var sway_amount: float = 0.0016
@export var sway_limit: float = 0.055
@export var sway_speed: float = 9.0

@export_group("Bob")
@export var bob_amount: float = 0.012
@export var bob_frequency: float = 1.9

@export_group("Recoil")
## How fast the weapon springs back to rest.
@export var recoil_recovery: float = 9.0

@export_group("Reload pose")
@export var reload_offset: Vector3 = Vector3(0.02, -0.14, 0.07)
@export var reload_tilt_deg: Vector3 = Vector3(-26.0, 8.0, 16.0)
@export var reload_blend_speed: float = 7.0

@onready var weapon: Weapon = $RocketLauncher

var _sway: Vector3 = Vector3.ZERO
var _bob: Vector3 = Vector3.ZERO
var _bob_time: float = 0.0
var _recoil_position: Vector3 = Vector3.ZERO
var _recoil_rotation: Vector3 = Vector3.ZERO
var _reload_blend: float = 0.0


func _ready() -> void:
	position = rest_position
	rotation = _deg(rest_rotation_deg)
	EventBus.weapon_fired.connect(_on_weapon_fired)


func _process(delta: float) -> void:
	var player: Player = GameState.player
	var look: Vector2 = Vector2.ZERO
	var speed: float = 0.0
	var grounded: bool = true

	if player != null:
		look = player.look_delta
		speed = player.get_horizontal_speed()
		grounded = player.is_on_floor()

	_update_sway(delta, look)
	_update_bob(delta, speed, grounded)
	_update_recoil(delta)
	_update_reload_pose(delta)

	position = rest_position + _sway + _bob + _recoil_position + reload_offset * _reload_blend
	rotation = _deg(rest_rotation_deg) + _recoil_rotation + _deg(reload_tilt_deg) * _reload_blend


func _update_sway(delta: float, look: Vector2) -> void:
	var target := Vector3(
		clampf(-look.x * sway_amount, -sway_limit, sway_limit),
		clampf(look.y * sway_amount, -sway_limit, sway_limit),
		0.0
	)
	_sway = _sway.lerp(target, clampf(sway_speed * delta, 0.0, 1.0))


func _update_bob(delta: float, speed: float, grounded: bool) -> void:
	var target := Vector3.ZERO
	if grounded and speed > 0.5:
		_bob_time += delta * bob_frequency * speed
		target = Vector3(
			cos(_bob_time) * bob_amount,
			sin(_bob_time * 2.0) * bob_amount * 0.55,
			0.0
		)
	_bob = _bob.lerp(target, clampf(10.0 * delta, 0.0, 1.0))


func _update_recoil(delta: float) -> void:
	var t: float = clampf(recoil_recovery * delta, 0.0, 1.0)
	_recoil_position = _recoil_position.lerp(Vector3.ZERO, t)
	_recoil_rotation = _recoil_rotation.lerp(Vector3.ZERO, t)


func _update_reload_pose(delta: float) -> void:
	var target: float = 1.0 if weapon != null and weapon.is_reloading() else 0.0
	_reload_blend = lerpf(_reload_blend, target, clampf(reload_blend_speed * delta, 0.0, 1.0))


func _on_weapon_fired(fired: Node3D) -> void:
	if fired != weapon:
		return
	_recoil_position += Vector3(randf_range(-0.012, 0.012), 0.028, weapon.recoil_push)
	_recoil_rotation += Vector3(
		deg_to_rad(weapon.recoil_pitch),
		deg_to_rad(randf_range(-3.5, 3.5)),
		deg_to_rad(randf_range(-5.0, 5.0))
	)

	var player: Player = GameState.player
	if player != null:
		player.add_recoil(weapon.recoil_camera.x, weapon.recoil_camera.y)


func _deg(v: Vector3) -> Vector3:
	return Vector3(deg_to_rad(v.x), deg_to_rad(v.y), deg_to_rad(v.z))
