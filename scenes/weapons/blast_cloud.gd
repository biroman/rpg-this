class_name BlastCloud
extends MultiMeshInstance3D
## The fireball and its smoke column, as solid 3D blobs - the same geometry the
## motor trail uses, so the two read as the same substance.
##
## The shape of a real detonation comes from a few behaviours, all of them here:
##   * the fireball punches outward fast and then stalls almost immediately as
##     drag kills it, so it is over in well under a second
##   * hot gas is buoyant, so the ball lifts and rolls into a rising column;
##     buoyancy is proportional to how hot each puff still is
##   * puffs cool from the outside in, so the shell turns to black smoke while
##     the core is still glowing
##   * the whole thing keeps expanding as it cools and entrains air
##
## Ported from the SeaHunter project and rescaled: `power` is driven off the
## explosion's own blast radius, so the cloud is always the size of the thing
## that actually went off.

const PUFF_SHADER: Shader = preload("res://assets/materials/blast_cloud.gdshader")

## All of these are set before `add_child()`.
var spawn_position: Vector3 = Vector3.ZERO
var power: float = 1.0
## Split between the two populations. The fire goes first and burns out; the
## soot lags in behind it and is what you are left looking at.
var fire_count: int = 80
var smoke_count: int = 64
## Carried off by the level wind, like the motor trail.
var wind: Vector3 = Vector3.ZERO

var drag: float = 2.6
var buoyancy: float = 11.0
var turbulence: float = 1.4

var _pts: Array[Dictionary] = []
var _mm: MultiMesh
var _mat: ShaderMaterial


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-400, -400, -400), Vector3(800, 800, 800))

	_mat = ShaderMaterial.new()
	_mat.shader = PUFF_SHADER
	# Finer than the trail's blob: there are far fewer of these and they end up
	# much bigger on screen, so the silhouette has to hold up on its own.
	var blob: ArrayMesh = PuffMesh.blob(13, 22)
	blob.surface_set_material(0, _mat)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = blob
	_mm.instance_count = fire_count + smoke_count
	_mm.visible_instance_count = 0
	multimesh = _mm

	EventBus.replay_active.connect(_on_replay_active)
	_populate()


## Frozen mid-expansion behind the replay's own blast, this would just be a
## second, wrong-sized fireball sitting in the shot.
func _on_replay_active(is_active: bool) -> void:
	visible = not is_active


func _rand_dir() -> Vector3:
	var d := Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if d.length_squared() < 1e-6:
		return Vector3.UP
	return d.normalized()


func _populate() -> void:
	# --- the fire -----------------------------------------------------------
	# Every one of these starts at full incandescence, so the first instant is a
	# solid ball of flame rather than a mottle of hot and cold. They then HOLD at
	# peak before cooling - a real fireball plateaus while the charge is still
	# burning - and the core holds longest, so it dies from the outside in.
	for i in fire_count:
		# Cube root keeps the sample uniform through the volume instead of
		# bunching everything up against the shell.
		var frac: float = pow(randf(), 1.0 / 3.0)
		var dir: Vector3 = _rand_dir()
		var speed: float = lerpf(7.0, 26.0, frac) * power * randf_range(0.75, 1.25)
		_pts.append({
			"pos": spawn_position + dir * frac * 1.4 * power,
			"vel": dir * speed + Vector3(0.0, randf_range(0.0, 4.0), 0.0),
			"age": 0.0,
			"delay": 0.0,
			"life": randf_range(1.8, 3.0),
			"heat0": randf_range(0.92, 1.0),
			"heat": 1.0,
			# A warhead this small is a flash, not a fuel fire: the plateau is
			# brief. SeaHunter's missile warheads burn several times longer.
			"hold": lerpf(0.30, 0.10, frac) * randf_range(0.7, 1.3),
			# Cooling rate rises with distance from the centre, so the shell is
			# already black smoke while the core is still burning. Staggering
			# the hold alone was not enough - the whole ball went out at once.
			"cool": lerpf(0.55, 1.6, frac) * randf_range(0.85, 1.15),
			# Fire keeps a clean silhouette for as long as it burns.
			"erode": 0.60,
			"rise": 0.0,
			"seed": randf(),
			"rot": Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
			"tumble": Vector3(randf_range(-1.2, 1.2), randf_range(-1.2, 1.2), randf_range(-1.2, 1.2)),
			"r0": randf_range(0.8, 1.7) * power,
			"expand": randf_range(1.5, 2.5),
			"wander": Vector3(randf_range(-1.0, 1.0), randf_range(-0.3, 1.0), randf_range(-1.0, 1.0)),
		})

	# --- the soot -----------------------------------------------------------
	# Never hot, slower, longer lived, and released on a stagger so the black
	# column builds up behind the flame instead of appearing with it.
	for i in smoke_count:
		var frac: float = pow(randf(), 1.0 / 3.0)
		var dir: Vector3 = _rand_dir()
		var speed: float = lerpf(3.0, 13.0, frac) * power * randf_range(0.7, 1.3)
		_pts.append({
			"pos": spawn_position + dir * frac * 1.8 * power,
			"vel": dir * speed,
			"age": 0.0,
			"delay": randf_range(0.05, 0.45),
			# Short lives, and a narrow spread of them: a wide spread leaves a
			# few stragglers hanging on well after the rest has gone, which
			# reads as the smoke refusing to clear.
			"life": randf_range(3.0, 4.2),
			"heat0": 0.0,
			"heat": 0.0,
			"hold": 0.0,
			"cool": 1.0,
			# Soot starts breaking up almost straight away. Without this the
			# column keeps a crisp spherical edge and reads as a boulder rather
			# than as smoke.
			"erode": 0.28,
			"rise": randf_range(1.2, 3.0) * power,
			"seed": randf(),
			"rot": Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
			"tumble": Vector3(randf_range(-0.9, 0.9), randf_range(-0.9, 0.9), randf_range(-0.9, 0.9)),
			"r0": randf_range(0.8, 1.7) * power,
			"expand": randf_range(2.0, 3.2),
			"wander": Vector3(randf_range(-1.0, 1.0), randf_range(-0.2, 1.0), randf_range(-1.0, 1.0)),
		})


func _process(delta: float) -> void:
	var alive: int = 0
	for pt in _pts:
		pt["age"] += delta
		var t: float = float(pt["age"]) - float(pt["delay"])
		if t >= float(pt["life"]):
			continue
		alive += 1
		if t < 0.0:
			continue

		# Hold at peak while the charge burns, then cool from the outside in.
		var hold: float = pt["hold"]
		if t > hold:
			pt["heat"] = maxf(0.0, float(pt["heat0"]) - float(pt["cool"]) * (t - hold))
		else:
			pt["heat"] = pt["heat0"]

		var v: Vector3 = pt["vel"]
		v -= v * drag * delta                                   # overpressure dies fast
		v.y += buoyancy * float(pt["heat"]) * delta             # hot gas lifts
		v.y += float(pt["rise"]) * delta                        # soot keeps climbing
		v += (pt["wander"] as Vector3) * turbulence * delta     # roll and curl
		# Cold smoke gives itself up to the wind; the hot core is still moving
		# far too fast for the breeze to matter.
		v += wind * (1.0 - float(pt["heat"])) * delta
		pt["vel"] = v
		pt["pos"] = (pt["pos"] as Vector3) + v * delta

		var tb: Vector3 = pt["tumble"]
		var rb: Basis = pt["rot"]
		pt["rot"] = rb.rotated(Vector3.UP, tb.y * delta).rotated(Vector3.RIGHT, tb.x * delta)

	if alive == 0:
		queue_free()
		return

	_rebuild()


func _rebuild() -> void:
	var slot: int = 0
	for pt in _pts:
		var t: float = float(pt["age"]) - float(pt["delay"])
		if t < 0.0:
			continue
		var a01: float = clampf(t / float(pt["life"]), 0.0, 1.0)
		if a01 >= 1.0:
			continue

		# Blooms hard in the first quarter second, then keeps swelling slowly as
		# it entrains air.
		var surge: float = lerpf(0.45, 1.0, clampf(t / 0.25, 0.0, 1.0))
		var rad: float = float(pt["r0"]) * (surge + float(pt["expand"]) * pow(a01, 0.60))

		var rb: Basis = pt["rot"]
		_mm.set_instance_transform(slot, Transform3D(rb.scaled(Vector3(rad, rad, rad)), pt["pos"]))
		_mm.set_instance_color(slot, Color(1, 1, 1, 1))

		# Eased, not linear. Most of the erosion budget is spent late: early on it
		# only wants to rough up the silhouette so the cloud is not a boulder,
		# and a linear ramp instead leaves the thing scattering into hard chips
		# for the last second and a half of its life.
		var erode: float = float(pt["erode"])
		var eaten: float = clampf((a01 - erode) / maxf(1.0 - erode, 0.01), 0.0, 1.0)
		var dissolve: float = pow(eaten, 1.8)
		_mm.set_instance_custom_data(slot,
			Color(float(pt["seed"]), clampf(pt["heat"], 0.0, 1.0), dissolve, 0.0))
		slot += 1

	_mm.visible_instance_count = slot
