extends Control
## Heads-up display: crosshair, ammo, reload progress, hit reports, score line.

@export_group("Crosshair")
@export var crosshair_length: float = 7.0
@export var crosshair_thickness: float = 2.0
@export var crosshair_gap: float = 4.0
@export var crosshair_color: Color = Color(1, 1, 1, 0.7)
@export var crosshair_empty_color: Color = Color(1, 0.45, 0.35, 0.75)

@export_group("Hit report")
@export var report_hold: float = 2.6
@export var report_fade: float = 0.8
@export var color_direct: Color = Color(1, 0.827451, 0.278431)
@export var color_blast: Color = Color(1, 0.560784, 0.25)
@export var color_miss: Color = Color(0.741176, 0.776471, 0.823529)

@export_group("Hint")
@export var hint_seconds: float = 12.0

@onready var hint: Label = $Hint
@onready var ammo_label: Label = $Ammo
@onready var reload_bar: ProgressBar = $ReloadBar
@onready var score_label: Label = $Score
@onready var report: Control = $HitReport
@onready var report_title: Label = $HitReport/Title
@onready var report_detail: Label = $HitReport/Detail

var _has_ammo: bool = true
var _reload_tween: Tween
var _report_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

	EventBus.game_paused.connect(_on_game_paused)
	EventBus.weapon_ammo_changed.connect(_on_ammo_changed)
	EventBus.weapon_reload_started.connect(_on_reload_started)
	EventBus.weapon_reload_finished.connect(_on_reload_finished)
	EventBus.target_hit.connect(_on_target_hit)
	EventBus.target_missed.connect(_on_target_missed)
	EventBus.score_changed.connect(_on_score_changed)

	reload_bar.visible = false
	report.modulate.a = 0.0
	_on_score_changed()
	_fade_hint()
	# The weapon is ready before the HUD, so pull its state once on startup.
	call_deferred("_sync_from_weapon")


func _draw() -> void:
	var c: Vector2 = size * 0.5
	var t: float = crosshair_thickness
	var g: float = crosshair_gap
	var l: float = crosshair_length
	var col: Color = crosshair_color if _has_ammo else crosshair_empty_color

	draw_rect(Rect2(c.x - g - l, c.y - t * 0.5, l, t), col)
	draw_rect(Rect2(c.x + g, c.y - t * 0.5, l, t), col)
	draw_rect(Rect2(c.x - t * 0.5, c.y - g - l, t, l), col)
	draw_rect(Rect2(c.x - t * 0.5, c.y + g, t, l), col)


# --- ammo ---------------------------------------------------------------

func _sync_from_weapon() -> void:
	var player: Player = GameState.player
	if player == null or player.weapon_rig == null or player.weapon_rig.weapon == null:
		return
	var w: Weapon = player.weapon_rig.weapon
	_on_ammo_changed(w.ammo_in_magazine, w.ammo_reserve)


func _on_ammo_changed(in_magazine: int, reserve: int) -> void:
	ammo_label.text = "%d / %d" % [in_magazine, reserve]
	_has_ammo = in_magazine > 0
	queue_redraw()


func _on_reload_started(duration: float) -> void:
	reload_bar.visible = true
	reload_bar.value = 0.0
	if _reload_tween != null and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = create_tween()
	_reload_tween.tween_property(reload_bar, "value", 100.0, duration)


func _on_reload_finished() -> void:
	reload_bar.visible = false


# --- scoring ------------------------------------------------------------

func _on_target_hit(hit: Dictionary) -> void:
	var is_direct: bool = bool(hit.get("direct", false))
	var ring: String = String(hit.get("ring", ""))

	var title: String = "DIRECT HIT" if is_direct else "BLAST HIT"
	if is_direct and ring != "":
		title += " - " + ring
	title += "   +%d" % int(hit.get("points", 0))

	_show_report(title, _distance_line(hit), color_direct if is_direct else color_blast)


func _on_target_missed(hit: Dictionary) -> void:
	_show_report("MISS", _distance_line(hit), color_miss)


## The "hit calculator": always says how far the rocket itself landed from the
## centre, even when the blast did the damage.
func _distance_line(hit: Dictionary) -> String:
	var distance: float = float(hit.get("miss_distance", 0.0))
	var line: String = "rocket landed %s from centre" % _metres(distance)
	# Short/long only means anything when the rocket missed the face itself.
	if not bool(hit.get("direct", false)) and distance > 2.0:
		line += "  (%s)" % ("short" if bool(hit.get("short", false)) else "long")
	return line


func _metres(value: float) -> String:
	if value < 10.0:
		return "%.2f m" % value
	return "%.1f m" % value


func _show_report(title: String, detail: String, colour: Color) -> void:
	report_title.text = title
	report_title.add_theme_color_override("font_color", colour)
	report_detail.text = detail

	if _report_tween != null and _report_tween.is_valid():
		_report_tween.kill()
	report.modulate.a = 1.0
	_report_tween = create_tween()
	_report_tween.tween_interval(report_hold)
	_report_tween.tween_property(report, "modulate:a", 0.0, report_fade)


func _on_score_changed() -> void:
	var best: String = "-" if is_inf(Score.best_distance) else _metres(Score.best_distance)
	score_label.text = "SCORE %d     HITS %d/%d (%d%%)     BEST %s" % [
		Score.points, Score.hits, Score.shots, roundi(Score.accuracy() * 100.0), best
	]


# --- misc ---------------------------------------------------------------

func _on_game_paused(is_paused: bool) -> void:
	visible = not is_paused


func _fade_hint() -> void:
	var tween := create_tween()
	tween.tween_interval(hint_seconds)
	tween.tween_property(hint, "modulate:a", 0.0, 1.2)
