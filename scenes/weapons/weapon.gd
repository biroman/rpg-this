class_name Weapon
extends Node3D
## Base class for held weapons.
##
## Owns firing cadence, ammo and reload timing. Subclasses override `_shoot()`
## to actually spawn something. The visual rig (sway, bob, recoil) is handled
## by the parent WeaponRig so this stays about behaviour.

@export_group("Identity")
@export var display_name: String = "Weapon"

@export_group("Firing")
## Seconds between shots.
@export var fire_cooldown: float = 0.85
## Hold the fire button to keep shooting.
@export var automatic: bool = false

@export_group("Ammo")
@export var magazine_size: int = 1
@export var reserve_ammo: int = 12
@export var reload_time: float = 2.4
## Start reloading automatically when the tube runs dry.
@export var auto_reload: bool = true

@export_group("Recoil")
## Camera kick in degrees: x = pitch up, y = max random yaw.
@export var recoil_camera: Vector2 = Vector2(4.5, 1.2)
## Viewmodel kickback in metres along the weapon's local +Z.
@export var recoil_push: float = 0.16
## Viewmodel pitch kick in degrees.
@export var recoil_pitch: float = 9.0

@onready var muzzle: Marker3D = $Muzzle

var ammo_in_magazine: int = 0
var ammo_reserve: int = 0

var _cooldown: float = 0.0
var _reload_timer: float = 0.0
var _is_reloading: bool = false


func _ready() -> void:
	ammo_in_magazine = magazine_size
	ammo_reserve = reserve_ammo
	_announce_ammo()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

	if _is_reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()


## Called by the player every frame with the current fire input state.
func handle_fire_input(pressed: bool, just_pressed: bool) -> void:
	var wants: bool = pressed if automatic else just_pressed
	if wants:
		try_fire()


func try_fire() -> bool:
	if _is_reloading or _cooldown > 0.0:
		return false

	if ammo_in_magazine <= 0:
		_on_empty()
		if auto_reload:
			start_reload()
		return false

	ammo_in_magazine -= 1
	_cooldown = fire_cooldown
	_shoot()
	_announce_ammo()
	EventBus.weapon_fired.emit(self)

	if ammo_in_magazine <= 0 and auto_reload:
		start_reload()
	return true


func start_reload() -> void:
	if _is_reloading or ammo_in_magazine >= magazine_size or ammo_reserve <= 0:
		return
	_is_reloading = true
	_reload_timer = reload_time
	_on_reload_started()
	EventBus.weapon_reload_started.emit(reload_time)


func is_reloading() -> bool:
	return _is_reloading


## 0..1 progress through the current reload.
func reload_progress() -> float:
	if not _is_reloading or reload_time <= 0.0:
		return 1.0
	return clampf(1.0 - _reload_timer / reload_time, 0.0, 1.0)


func _finish_reload() -> void:
	var needed: int = magazine_size - ammo_in_magazine
	var taken: int = mini(needed, ammo_reserve)
	ammo_in_magazine += taken
	ammo_reserve -= taken
	_is_reloading = false
	_announce_ammo()
	EventBus.weapon_reload_finished.emit()


func _announce_ammo() -> void:
	EventBus.weapon_ammo_changed.emit(ammo_in_magazine, ammo_reserve)


# --- overridable --------------------------------------------------------

## Spawn the projectile / trace the shot. Override in subclasses.
func _shoot() -> void:
	pass


## Feedback when the trigger is pulled on an empty tube.
func _on_empty() -> void:
	pass


func _on_reload_started() -> void:
	pass
