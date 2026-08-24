class_name Explosion
extends Node3D
## One-shot blast: physics impulse, fireball, light flash, scorch mark, shake.
##
## Spawn it, call `detonate(surface_normal)`, and it cleans itself up.
##
## The fireball and its smoke column are not sprites - they are solid instanced
## geometry (see `blast_cloud.gd`), the same substance the motor trail is made
## of, so the two match and you can walk through the smoke afterwards. Only the
## thrown embers stay as sprites: they are points of light, not volume, and
## streak better than geometry would.

@export_group("Blast")
@export var radius: float = 8.0
## Impulse at the epicentre, in newton-seconds per kilogram of target.
@export var impulse: float = 30.0
## Blast pushes bodies slightly upward so debris lifts instead of skidding.
@export var upward_bias: float = 0.35
## Physics layers the blast can push: world(1) + props(4).
@export_flags_3d_physics var affect_mask: int = 5

@export_group("Fireball")
## Puff counts for the blast cloud, before the blast radius scales them.
@export var fire_puffs: int = 80
@export var smoke_puffs: int = 64
## Blast radius the cloud is tuned against. The cloud scales from the ratio, so
## changing `radius` alone resizes the fireball with it.
@export var reference_radius: float = 9.0

@export_group("Shock ring")
@export var shock_reach: float = 1.15
@export var shock_time: float = 0.30
@export var shock_alpha: float = 0.1

@export_group("Feedback")
## Camera shake at the epicentre, 0..1.
@export var shake_strength: float = 1.0
@export var flash_energy: float = 11.0
@export var flash_time: float = 0.32
## How long the burning fireball keeps throwing light after the flash is gone.
@export var ember_glow_time: float = 1.6

@export_group("Scorch")
@export var decal_size: float = 6.0
@export var decal_lifetime: float = 22.0
@export var decal_fade_time: float = 6.0

@onready var sparks: GPUParticles3D = $Sparks
@onready var shock: MeshInstance3D = $ShockRing
@onready var flash: OmniLight3D = $Flash
@onready var scorch: Decal = $Scorch
@onready var audio: AudioStreamPlayer3D = $Audio


func _ready() -> void:
	flash.light_energy = 0.0
	scorch.visible = false
	shock.visible = false
	# Each blast fades its own shell, so it cannot share the scene's material.
	shock.material_override = shock.material_override.duplicate()
	# Opening a replay freezes the tree, and at 150 m the bang is still half a
	# second out. It has to land anyway, so it keeps running through it.
	audio.process_mode = Node.PROCESS_MODE_ALWAYS


## Fire everything off. `surface_normal` orients the scorch decal.
func detonate(surface_normal: Vector3 = Vector3.UP) -> void:
	_apply_blast()
	_place_scorch(surface_normal)
	_spawn_cloud()
	_expand_shock()

	sparks.restart()
	_bang_when_it_arrives()

	EventBus.explosion_happened.emit(global_position, radius, shake_strength)

	_flash_then_fade()


## The fireball, as geometry. It outlives this node, so it is parented alongside
## rather than underneath - a child would be freed with the scorch mark.
func _spawn_cloud() -> void:
	var host: Node = get_parent()
	if host == null:
		return

	var power: float = radius / maxf(reference_radius, 0.001)
	var cloud := BlastCloud.new()
	cloud.spawn_position = global_position
	cloud.power = power
	cloud.fire_count = maxi(8, roundi(fire_puffs * clampf(power, 0.6, 1.5)))
	cloud.smoke_count = maxi(8, roundi(smoke_puffs * clampf(power, 0.6, 1.5)))
	var world: Node3D = GameState.world
	cloud.wind = (world as World).wind if world is World else Vector3.ZERO
	host.add_child(cloud)


## You see it, then you hear it. At the level 1 target that is a third of a
## second, and at 150 m nearly half - long enough to feel like distance rather
## than like lag.
##
## The timer deliberately ignores pause, for the same reason the audio player
## does: a replay opened right after the hit would otherwise strand the bang
## halfway down the range.
func _bang_when_it_arrives() -> void:
	var world: World = GameState.world as World
	var delay: float = world.sound_delay(global_position) if world != null else 0.0
	if delay > 0.02:
		await get_tree().create_timer(delay).timeout
	if is_instance_valid(audio):
		audio.play()


## The overpressure shell: a sphere seen from the inside, punched outward and
## gone almost immediately. It is what sells the first frame as a detonation
## rather than as a fire starting.
func _expand_shock() -> void:
	shock.visible = true
	shock.scale = Vector3.ONE * 0.3
	var material: StandardMaterial3D = shock.material_override
	material.albedo_color.a = shock_alpha

	var tween := create_tween().set_parallel()
	var out := tween.tween_property(shock, "scale", Vector3.ONE * radius * shock_reach, shock_time)
	out.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	var dim := tween.tween_property(material, "albedo_color:a", 0.0, shock_time)
	dim.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


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
	# Three stages, because the fireball is a light source for as long as it
	# burns: the hard flash, the ball itself, then a dull ember glow inside the
	# smoke column.
	var tween := create_tween()
	tween.tween_property(flash, "light_energy", flash_energy, 0.03)
	var ball := tween.tween_property(flash, "light_energy", flash_energy * 0.28, flash_time)
	ball.set_ease(Tween.EASE_OUT)
	var embers := tween.tween_property(flash, "light_energy", 0.0, ember_glow_time)
	embers.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var fade := create_tween()
	fade.tween_interval(maxf(decal_lifetime - decal_fade_time, 0.0))
	fade.tween_property(scorch, "albedo_mix", 0.0, decal_fade_time)
	fade.tween_callback(queue_free)
