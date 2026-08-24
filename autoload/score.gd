extends Node
## Running range statistics.
##
## Autoloaded as `Score`. It only listens - nothing has to report to it directly,
## which keeps weapons and targets unaware that scoring exists.

var shots: int = 0
var hits: int = 0
var direct_hits: int = 0
var blast_hits: int = 0
var points: int = 0
## Closest any rocket has physically landed to a target centre, in metres.
var best_distance: float = INF
## Distance of the most recent shot that was measured against a target.
var last_distance: float = INF


func _ready() -> void:
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.target_hit.connect(_on_target_hit)
	EventBus.target_missed.connect(_on_target_missed)


func accuracy() -> float:
	if shots <= 0:
		return 0.0
	return float(hits) / float(shots)


func reset() -> void:
	shots = 0
	hits = 0
	direct_hits = 0
	blast_hits = 0
	points = 0
	best_distance = INF
	last_distance = INF
	EventBus.score_changed.emit()


func _on_weapon_fired(_weapon: Node3D) -> void:
	shots += 1
	EventBus.score_changed.emit()


func _on_target_hit(report: Dictionary) -> void:
	hits += 1
	points += int(report.get("points", 0))
	if bool(report.get("direct", false)):
		direct_hits += 1
	else:
		blast_hits += 1
	_record_distance(report)
	EventBus.score_changed.emit()


func _on_target_missed(report: Dictionary) -> void:
	_record_distance(report)
	EventBus.score_changed.emit()


func _record_distance(report: Dictionary) -> void:
	var d: float = float(report.get("miss_distance", INF))
	last_distance = d
	best_distance = minf(best_distance, d)
