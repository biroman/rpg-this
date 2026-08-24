class_name ShotRecording
extends RefCounted
## One rocket flight, captured as plain data.
##
## The rocket samples itself into this every physics tick and hands it to the
## `Replay` autoload when it detonates. Nothing here points at a live node, so a
## recording stays valid long after the rocket that made it has been freed.
##
## Playback asks for `sample(t)` at any time in `[0, duration()]` and gets an
## interpolated pose back, which is what makes scrubbing and slow motion work.

## Seconds of timeline kept after the impact so the blast can play out.
const TAIL_SECONDS: float = 1.8

# --- shot context -------------------------------------------------------

var origin: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD
var wind: Vector3 = Vector3.ZERO
var level_index: int = 0
var level_name: String = ""

# --- impact -------------------------------------------------------------

## Negative until the rocket detonates.
var impact_time: float = -1.0
var impact_point: Vector3 = Vector3.ZERO
var impact_normal: Vector3 = Vector3.UP
var blast_radius: float = 0.0

# --- result (attached by the level once scoring has run) ----------------

var target_centre: Vector3 = Vector3.ZERO
var has_target: bool = false
var result: Dictionary = {}

# --- flight samples -----------------------------------------------------

var _times := PackedFloat32Array()
var _positions := PackedVector3Array()
var _rotations: Array[Quaternion] = []
var _velocities := PackedVector3Array()
var _burning := PackedByteArray()


func begin(from: Vector3, dir: Vector3, world_wind: Vector3) -> void:
	origin = from
	direction = dir.normalized()
	wind = world_wind


## Called once per physics tick by the rocket. `t` is seconds since launch.
func add_frame(t: float, position: Vector3, rotation: Quaternion, velocity: Vector3, burning: bool) -> void:
	_times.append(t)
	_positions.append(position)
	_rotations.append(rotation)
	_velocities.append(velocity)
	_burning.append(1 if burning else 0)


## Closes the recording. The impact point is appended as a final frame so the
## flight ends exactly where the explosion happens rather than a tick short.
## `velocity` is what the rocket was doing on the way in, so the replay can
## report the speed it actually struck at.
func finish(t: float, point: Vector3, normal: Vector3, radius: float, velocity: Vector3) -> void:
	if impact_time >= 0.0:
		return
	var count: int = _rotations.size()
	var last_rotation: Quaternion = _rotations[count - 1] if count > 0 else Quaternion.IDENTITY
	var closing: Vector3 = velocity if not velocity.is_zero_approx() else direction
	if _times.is_empty() or t > _times[_times.size() - 1]:
		add_frame(t, point, last_rotation, closing, false)

	impact_time = t
	impact_point = point
	impact_normal = normal
	blast_radius = radius


## Called by the level once the target has scored the shot.
func attach_result(report: Dictionary, centre: Vector3, index: int, level: String) -> void:
	result = report
	target_centre = centre
	has_target = true
	level_index = index
	level_name = level


# --- queries ------------------------------------------------------------

func is_valid() -> bool:
	return _times.size() >= 2


func frame_count() -> int:
	return _times.size()


func has_impact() -> bool:
	return impact_time >= 0.0


## Seconds from launch to impact (or to the last sample if it never hit).
func flight_time() -> float:
	if _times.is_empty():
		return 0.0
	return _times[-1]


## Full scrubbable length, including the post-impact tail.
func duration() -> float:
	return flight_time() + TAIL_SECONDS


func top_speed() -> float:
	var best: float = 0.0
	for v in _velocities:
		best = maxf(best, v.length())
	return best


func apex() -> float:
	var best: float = -INF
	for p in _positions:
		best = maxf(best, p.y)
	return best if best > -INF else 0.0


## Ground distance the rocket covered.
func ground_range() -> float:
	if _positions.is_empty():
		return 0.0
	var d: Vector3 = _positions[-1] - origin
	return Vector2(d.x, d.z).length()


## Distance from the rocket to the target centre at time `t`, or -1 with no target.
func distance_to_target(t: float) -> float:
	if not has_target:
		return -1.0
	return (Vector3(sample(t)["position"]) - target_centre).length()


## Interpolated pose at `t`. Times outside the flight clamp to its ends, so the
## post-impact tail simply holds the last frame.
func sample(t: float) -> Dictionary:
	var count: int = _times.size()
	if count == 0:
		return {
			"position": origin,
			"rotation": Quaternion.IDENTITY,
			"velocity": direction,
			"speed": 0.0,
			"burning": false,
		}

	var clamped: float = clampf(t, _times[0], _times[count - 1])
	var i: int = _index_at(clamped)
	if i >= count - 1:
		return _frame(count - 1)

	var span: float = _times[i + 1] - _times[i]
	if span <= 0.0001:
		return _frame(i)

	var f: float = (clamped - _times[i]) / span
	var velocity: Vector3 = _velocities[i].lerp(_velocities[i + 1], f)
	return {
		"position": _positions[i].lerp(_positions[i + 1], f),
		"rotation": _rotations[i].slerp(_rotations[i + 1], f),
		"velocity": velocity,
		"speed": velocity.length(),
		"burning": _burning[i] == 1,
	}


## The flown path up to `t`, with the interpolated tip appended so the trail
## always reaches the rocket instead of snapping between samples.
func path_until(t: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var count: int = _times.size()
	if count == 0:
		return out

	var clamped: float = clampf(t, _times[0], _times[count - 1])
	for i in count:
		if _times[i] > clamped:
			break
		out.append(_positions[i])

	var tip: Vector3 = sample(clamped)["position"]
	if out.is_empty() or out[-1].distance_squared_to(tip) > 0.0001:
		out.append(tip)
	return out


## The whole path, used to draw the arc the shot took.
func path() -> PackedVector3Array:
	return _positions


func _frame(i: int) -> Dictionary:
	return {
		"position": _positions[i],
		"rotation": _rotations[i],
		"velocity": _velocities[i],
		"speed": _velocities[i].length(),
		"burning": _burning[i] == 1,
	}


## Index of the last sample at or before `t`.
func _index_at(t: float) -> int:
	var low: int = 0
	var high: int = _times.size() - 1
	while low < high:
		var mid: int = (low + high + 1) / 2
		if _times[mid] <= t:
			low = mid
		else:
			high = mid - 1
	return low
