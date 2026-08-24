class_name Target
extends StaticBody3D
## Scoring target.
##
## Listens for rocket impacts and classifies each one:
##   direct - the rocket physically struck this target
##   blast  - the rocket landed elsewhere but the explosion reached the centre
##   miss   - neither, but close enough to be worth telling the player about
##
## Either way it measures how far the rocket itself landed from the centre, so
## a blast hit still tells you how much you were off by.

@export_group("Rings")
## Radii from the centre outward. Must be ascending and match `ring_names`.
@export var ring_radii: PackedFloat32Array = PackedFloat32Array([0.4, 0.8, 1.2, 1.6, 2.0])
@export var ring_names: PackedStringArray = PackedStringArray(["BULLSEYE", "INNER", "MID", "OUTER", "EDGE"])
@export var ring_points: PackedInt32Array = PackedInt32Array([10, 8, 6, 4, 2])

@export_group("Scoring")
## Best points a blast-only hit can earn.
@export var max_blast_points: int = 4
## Report near misses that land within this distance of the centre.
@export var report_miss_within: float = 120.0

@export_group("Feedback")
@export var hit_sound: AudioStream
@export var punch_scale: float = 1.14
@export var punch_time: float = 0.28
## Show the distance from the player spawn on the target itself.
@export var show_distance_label: bool = true

@onready var face: Node3D = $Face
@onready var centre: Marker3D = $Face/Centre
@onready var distance_label: Label3D = $Face/DistanceLabel
@onready var audio: AudioStreamPlayer3D = $Audio

var _punch: Tween


func _ready() -> void:
	EventBus.rocket_impact.connect(_on_rocket_impact)
	EventBus.world_ready.connect(_on_world_ready)
	distance_label.visible = show_distance_label
	audio.stream = hit_sound


func _on_world_ready(world: Node3D) -> void:
	if not show_distance_label or world == null:
		return
	var spawn: Vector3 = (world as World).get_spawn_transform().origin
	var flat := Vector2(centre.global_position.x - spawn.x, centre.global_position.z - spawn.z)
	distance_label.text = "%d m" % roundi(flat.length())


# --- scoring ------------------------------------------------------------

func _on_rocket_impact(impact_point: Vector3, _normal: Vector3, hit_body: Node, blast_radius: float) -> void:
	var distance: float = impact_point.distance_to(centre.global_position)
	var direct: bool = hit_body != null and (hit_body == self or is_ancestor_of(hit_body))
	var blast: bool = not direct and distance <= blast_radius

	if not direct and not blast:
		if distance <= report_miss_within:
			EventBus.target_missed.emit(_build_report(false, false, distance, impact_point, blast_radius))
		return

	var report := _build_report(direct, blast, distance, impact_point, blast_radius)
	EventBus.target_hit.emit(report)
	_react(direct)


func _build_report(direct: bool, blast: bool, distance: float, impact: Vector3, blast_radius: float) -> Dictionary:
	var ring_index: int = _ring_index(distance)
	var ring: String = ring_names[ring_index] if direct and ring_index >= 0 else ""
	var awarded: int = 0

	if direct and ring_index >= 0:
		awarded = ring_points[ring_index]
	elif direct:
		awarded = ring_points[ring_points.size() - 1]     # hit the post or the rim
	elif blast:
		var closeness: float = 1.0 - clampf(distance / maxf(blast_radius, 0.001), 0.0, 1.0)
		awarded = maxi(1, roundi(max_blast_points * closeness))

	return {
		"target": self,
		"direct": direct,
		"blast": blast,
		"ring": ring,
		"points": awarded,
		"miss_distance": distance,
		"impact": impact,
		"range": _range_from_player(),
		"short": _is_short(impact),
	}


func _ring_index(distance: float) -> int:
	for i in ring_radii.size():
		if distance <= ring_radii[i]:
			return i
	return -1


func _range_from_player() -> float:
	var player: Node3D = GameState.player
	if player == null:
		return 0.0
	var d := centre.global_position - player.global_position
	return Vector2(d.x, d.z).length()


## True when the rocket fell short of the target rather than sailing past it.
func _is_short(impact: Vector3) -> bool:
	var player: Node3D = GameState.player
	if player == null:
		return false
	var here := player.global_position
	return here.distance_to(impact) < here.distance_to(centre.global_position)


# --- feedback -----------------------------------------------------------

func _react(direct: bool) -> void:
	if audio.stream != null:
		audio.pitch_scale = 1.15 if direct else 0.82
		audio.play()

	if _punch != null and _punch.is_valid():
		_punch.kill()

	var overshoot: float = punch_scale if direct else 1.0 + (punch_scale - 1.0) * 0.45
	face.scale = Vector3.ONE
	_punch = create_tween()
	_punch.tween_property(face, "scale", Vector3.ONE * overshoot, punch_time * 0.25)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch.tween_property(face, "scale", Vector3.ONE, punch_time * 0.75)\
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
