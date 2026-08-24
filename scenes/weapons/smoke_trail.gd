class_name SmokeTrail
extends MultiMeshInstance3D
## Motor smoke as real 3D geometry: a few hundred solid lumpy spheres instanced
## along the rocket's path, shaded by `assets/materials/smoke_puff.gdshader`.
##
## Nothing here is a billboard. Fly around it, through it, or look along it and
## it holds up, because it genuinely is a volume - which matters a lot here,
## since the replay camera sits five metres behind the rocket and flies straight
## down the middle of the trail.
##
## Puffs are laid down per METRE TRAVELLED, and crucially they are INTERPOLATED
## along each step rather than sampled at it. `feed()` is called once per physics
## tick, so at 90 m/s the rocket has already moved 1.5 m by the time we hear
## about it. Sampling that gives a string of lonely blobs with 1.5 m holes
## between them; walking the segment in fixed strides gives one continuous rope
## at any speed, which is the whole trick.
##
## Ported from the missile trail in the SeaHunter project and rescaled: this
## rocket is an order of magnitude slower and shorter-ranged, so the puffs are
## smaller, tighter together and shorter lived.

const PUFF_SHADER: Shader = preload("res://assets/materials/smoke_puff.gdshader")

## Hard ceiling. Resampling normally keeps the count far below this.
const MAX_PUFFS: int = 900
## Metres between puffs along the path.
const SPACING: float = 0.18
## Guard against a teleport spawning thousands in one step.
const MAX_STEPS: int = 200
const RESAMPLE_INTERVAL: float = 0.25

@export_group("Life")
@export var life: float = 5.5
## Once the rocket is gone the trail has no reason to hang around, so it ages
## faster. Ramped in rather than switched, so nothing snaps at detonation.
@export var fade_speedup: float = 1.8
## Fraction of life before the puff starts breaking up.
@export var dissolve_start: float = 0.62

@export_group("Shape")
## Must be comfortably larger than SPACING, or the fresh end of the trail beads
## up before the puffs have had time to swell.
@export var radius_start: float = 0.30
@export var radius_end: float = 1.45
## Puffs swell fastest when young. Above 1 keeps the fresh trail tight for longer.
@export var growth_curve: float = 0.85
## Sideways scatter at birth, so the rope is a fat irregular column rather than
## beads threaded on a wire.
@export var lateral_spread: float = 0.09
## Size of the fragments the puff breaks into as it dies. The pattern is in
## unit-blob space, so a rocket this size needs a coarser one than a missile
## trail would - otherwise the trail shreds into confetti instead of thinning.
@export var dissolve_scale: float = 3.2

@export_group("Colour")
@export var color_hot: Color = Color(1.0, 1.0, 1.0)
@export var color_cold: Color = Color(0.80, 0.79, 0.77)

## How the smoke moves once it is off the rocket. The level wind is folded in
## here by whoever spawns the trail, so a crosswind is something you can see
## rather than just read off the gauge.
var drift: Vector3 = Vector3(0.0, 0.9, 0.0)

var _pts: Array[Dictionary] = []
var _mm: MultiMesh
var _mat: ShaderMaterial
var _feeding: bool = true
var _resample_cd: float = 0.0
var _age_rate: float = 1.0
var _frame: int = 0


func _ready() -> void:
	add_to_group("smoke_trail")
	# Puff positions are world space, so the node must not inherit a transform.
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The instances are placed by hand all over the level, so the automatic
	# bounds are meaningless - without this the whole trail culls at the wrong
	# moment and blinks out.
	custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))

	_mat = ShaderMaterial.new()
	_mat.shader = PUFF_SHADER
	_mat.set_shader_parameter("dissolve_scale", dissolve_scale)
	var blob: ArrayMesh = PuffMesh.blob(6, 11)
	blob.surface_set_material(0, _mat)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = blob
	_mm.instance_count = MAX_PUFFS
	_mm.visible_instance_count = 0
	multimesh = _mm

	EventBus.replay_active.connect(_on_replay_active)
	_claim_exclusive()


## The replay draws its own scrub-safe version of the trail, and its camera
## flies straight down the middle of the real one. Solid geometry cannot fade
## out near the lens the way that ribbon does, so the live smoke simply stands
## down for the duration.
func _on_replay_active(is_active: bool) -> void:
	visible = not is_active


## Only the round actually in the air lays smoke. Earlier trails are cut loose
## the moment a new one starts and clear out fast: several full-length trails at
## once is what costs, and in practice you only ever watch the newest.
func _claim_exclusive() -> void:
	for t in get_tree().get_nodes_in_group("smoke_trail"):
		if t != self and t.has_method("force_fade"):
			t.call("force_fade")


func force_fade() -> void:
	_feeding = false
	fade_speedup = maxf(fade_speedup, 6.0)


func stop_feeding() -> void:
	_feeding = false


## Lay smoke from the last point up to `p`, in fixed strides. Anything left over
## under one stride is kept for the next call, so spacing stays even across tick
## boundaries instead of resetting every frame.
func feed(p: Vector3, hot: float = 1.0) -> void:
	if not _feeding:
		return
	if _pts.is_empty():
		_emit(p, Vector3.FORWARD, hot)
		return

	var last: Vector3 = _pts[_pts.size() - 1]["pos"]
	var seg: Vector3 = p - last
	var dist: float = seg.length()
	if dist < SPACING:
		return

	var dir: Vector3 = seg / dist
	var steps: int = mini(int(dist / SPACING), MAX_STEPS)
	for k in range(1, steps + 1):
		_emit(last + dir * (SPACING * float(k)), dir, hot)

	if _pts.size() > MAX_PUFFS:
		_resample()
		# Last resort only: drop the very oldest, which are already breaking up.
		while _pts.size() > MAX_PUFFS:
			_pts.remove_at(0)


func _emit(pos: Vector3, dir: Vector3, hot: float) -> void:
	# Scatter each puff off the centreline so the column has some girth.
	var side: Vector3 = dir.cross(Vector3.UP)
	if side.length_squared() < 1e-6:
		side = Vector3.RIGHT
	side = side.normalized()
	var up: Vector3 = side.cross(dir).normalized()
	var off: Vector3 = (side * randf_range(-1.0, 1.0) + up * randf_range(-1.0, 1.0)) * lateral_spread

	_pts.append({
		"pos": pos + off,
		"age": 0.0,
		"seed": randf(),
		# A random orientation per instance, so one blob mesh reads as many.
		"rot": Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU)),
		"tumble": Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)),
		# `hot` thins the trail once the motor is out: a coasting rocket only
		# trickles residual smoke, it is not still making it.
		"grow": randf_range(0.78, 1.22) * lerpf(0.5, 1.0, clampf(hot, 0.0, 1.0)),
		"jit": Vector3(randf_range(-0.4, 0.4), randf_range(-0.15, 0.45), randf_range(-0.4, 0.4)),
	})


func _radius_of(pt: Dictionary) -> float:
	var a01: float = clampf(pt["age"] / life, 0.0, 1.0)
	return lerpf(radius_start, radius_end, pow(a01, growth_curve)) * float(pt["grow"])


## A rocket at 90 m/s lays 400 puffs a second, so the count has to come down -
## but decimating on a budget is what makes a trail visibly evaporate behind you.
## Instead: a puff is only dropped when its two NEIGHBOURS already overlap
## without it, so the rope is never left with a hole. Because puffs swell as they
## age this self-limits, settling at whatever sampling density the trail actually
## needs at each point along its length. Nothing pops.
func _resample() -> void:
	if _pts.size() < 3:
		return
	var i: int = 1
	while i < _pts.size() - 1:
		var prev: Dictionary = _pts[i - 1]
		var nxt: Dictionary = _pts[i + 1]
		var gap: float = (prev["pos"] as Vector3).distance_to(nxt["pos"])
		if gap < (_radius_of(prev) + _radius_of(nxt)):
			_pts.remove_at(i)
		# Either way step on, so two neighbours are never removed in a row.
		i += 1


func _process(delta: float) -> void:
	if not _feeding:
		_age_rate = minf(_age_rate + delta * 1.6, fade_speedup)
	var step: float = delta * _age_rate

	var dead: int = 0
	for pt in _pts:
		pt["age"] += step
		# Smoke rises and is carried off by the wind, easing in as it slows to
		# match the air rather than jumping to wind speed the instant it is laid.
		pt["pos"] += (drift + pt["jit"]) * delta * clampf(pt["age"] * 0.6, 0.0, 1.4)
		var tb: Vector3 = pt["tumble"]
		var rb: Basis = pt["rot"]
		pt["rot"] = rb.rotated(Vector3.UP, tb.y * delta).rotated(Vector3.RIGHT, tb.x * delta)
		if pt["age"] > life:
			dead += 1
	if dead > 0:
		_pts = _pts.slice(dead)

	# Keep the sampling density honest as the puffs grow, rather than waiting for
	# the budget to blow and then hacking chunks out of the trail.
	_resample_cd -= delta
	if _resample_cd <= 0.0:
		_resample_cd = RESAMPLE_INTERVAL
		_resample()

	if _pts.is_empty():
		_mm.visible_instance_count = 0
		if not _feeding:
			queue_free()
		return

	# Orphaned trails drift slowly and are usually behind you, so there is no
	# need to rewrite several hundred instance transforms every single frame.
	_frame += 1
	if _feeding or (_frame & 1) == 0:
		_rebuild()


func _rebuild() -> void:
	var n: int = mini(_pts.size(), MAX_PUFFS)
	_mm.visible_instance_count = n

	for i in n:
		var pt: Dictionary = _pts[i]
		var a01: float = clampf(pt["age"] / life, 0.0, 1.0)

		# A puff keeps swelling as it cools; per-point growth keeps the rope lumpy.
		var rad: float = _radius_of(pt)
		# Thin the very tip, so a new trail does not pop into existence.
		if _feeding and i > n - 4:
			rad *= clampf(float(n - i) / 4.0, 0.25, 1.0)

		var rb: Basis = pt["rot"]
		_mm.set_instance_transform(i, Transform3D(rb.scaled(Vector3(rad, rad, rad)), pt["pos"]))
		_mm.set_instance_color(i, color_hot.lerp(color_cold, clampf(a01 * 1.9, 0.0, 1.0)))

		# Erosion only starts once the puff is well down the trail.
		var dissolve: float = clampf(
			(a01 - dissolve_start) / maxf(1.0 - dissolve_start, 0.01), 0.0, 1.0)
		_mm.set_instance_custom_data(i, Color(float(pt["seed"]), 0.0, dissolve, 0.0))
