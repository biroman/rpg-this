extends Control
## Heads-up display: crosshair, ammo, reload progress, hit reports, score line,
## the level banner and the wind gauge.

@export_group("Crosshair")
@export var crosshair_radius: float = 9.0
@export var crosshair_thickness: float = 2.0
## The pip in the middle. It is what you actually aim with; the ring around it
## is there to be findable against a pale sky.
@export var crosshair_dot: float = 1.6
@export var crosshair_color: Color = Color(0.137255, 0.14902, 0.172549, 0.65)
@export var crosshair_empty_color: Color = Color(0.956863, 0.321569, 0.431373, 0.85)

@export_group("Hit report")
@export var report_hold: float = 2.6
@export var report_fade: float = 0.8
## Report colours, dark enough to read as type on the paper the world is made
## of rather than bright enough to glow on a dark one.
@export var color_direct: Color = Color(0.686275, 0.443137, 0.00784314)
@export var color_blast: Color = Color(0.780392, 0.227451, 0.333333)
@export var color_miss: Color = Color(0.482353, 0.505882, 0.552941)

@export_group("Hint")
@export var hint_seconds: float = 12.0

@export_group("Level banner")
@export var banner_hold: float = 3.2
@export var banner_fade: float = 0.9

@export_group("Wind gauge")
## Centre of the compass rose, in pixels from the top-left of the screen.
@export var wind_gauge_origin: Vector2 = Vector2(74.0, 118.0)
@export var wind_gauge_radius: float = 30.0
@export var wind_color: Color = Color(0.231373, 0.290196, 0.419608, 1)
@export var wind_dial_color: Color = Color(0.137255, 0.14902, 0.172549, 0.18)

@onready var hint: Label = $Hint
@onready var ammo_label: Label = $Ammo
@onready var reload_bar: ProgressBar = $ReloadBar
@onready var score_label: Label = $Score
@onready var report: Control = $HitReport
@onready var report_title: Label = $HitReport/Title
@onready var report_detail: Label = $HitReport/Detail
@onready var banner: Control = $Banner
@onready var banner_title: Label = $Banner/Title
@onready var banner_brief: Label = $Banner/Brief
@onready var wind_label: Label = $WindLabel

## The controls line authored on the label, kept so each level can add its
## own briefing underneath it.
var _controls_hint: String = ""

var _has_ammo: bool = true
## The hit that cleared the level, if one has. The result card reports it in
## full, so the centre-screen line does not say it a second time.
var _cleared_by: Dictionary = {}
var _wind: Vector3 = Vector3.ZERO
var _reload_tween: Tween
var _report_tween: Tween
var _banner_tween: Tween
var _hint_tween: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

	EventBus.game_paused.connect(_on_game_paused)
	EventBus.cinematic_changed.connect(_on_cinematic_changed)
	EventBus.weapon_ammo_changed.connect(_on_ammo_changed)
	EventBus.weapon_reload_started.connect(_on_reload_started)
	EventBus.weapon_reload_finished.connect(_on_reload_finished)
	EventBus.target_hit.connect(_on_target_hit)
	EventBus.target_missed.connect(_on_target_missed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.level_started.connect(_on_level_started)
	EventBus.level_completed.connect(_on_level_completed)
	EventBus.range_completed.connect(_on_range_completed)
	EventBus.wind_changed.connect(_on_wind_changed)

	_controls_hint = hint.text
	reload_bar.visible = false
	report.modulate.a = 0.0
	banner.modulate.a = 0.0
	_on_wind_changed(Vector3.ZERO)
	_on_score_changed()
	_fade_hint()
	# The weapon is ready before the HUD, so pull its state once on startup.
	call_deferred("_sync_from_weapon")


func _process(_delta: float) -> void:
	# The wind arrow is drawn relative to where the player is facing, so it has
	# to be repainted as they turn.
	if not _wind.is_zero_approx():
		queue_redraw()


func _draw() -> void:
	_draw_crosshair()
	_draw_wind()


func _draw_crosshair() -> void:
	var c: Vector2 = size * 0.5
	var col: Color = crosshair_color if _has_ammo else crosshair_empty_color
	draw_arc(c, crosshair_radius, 0.0, TAU, 48, col, crosshair_thickness, true)
	draw_circle(c, crosshair_dot, col)


# --- wind ---------------------------------------------------------------

func _on_wind_changed(wind: Vector3) -> void:
	_wind = wind
	if wind.is_zero_approx():
		wind_label.text = "NO WIND"
		wind_label.add_theme_color_override("font_color", Color(0.482353, 0.505882, 0.552941, 1))
	else:
		wind_label.text = "WIND  %d m/s" % roundi(wind.length())
		wind_label.add_theme_color_override("font_color", wind_color)
	queue_redraw()


## Compass rose showing which way the wind will push the rocket, rotated into
## the player's own view: an arrow to the right means it drifts right.
func _draw_wind() -> void:
	var centre: Vector2 = wind_gauge_origin
	var r: float = wind_gauge_radius
	draw_arc(centre, r, 0.0, TAU, 40, wind_dial_color, 1.5, true)

	if _wind.is_zero_approx():
		draw_circle(centre, 3.0, wind_dial_color)
		return

	var screen: Vector2 = _wind_screen_direction()
	if screen.length_squared() < 0.0001:
		return
	screen = screen.normalized()

	var tail: Vector2 = centre - screen * r * 0.72
	var tip: Vector2 = centre + screen * r * 0.72
	var head: Vector2 = tip - screen * 11.0
	var wing: Vector2 = screen.orthogonal() * 7.0

	draw_line(tail, head, wind_color, 3.0, true)
	draw_colored_polygon(PackedVector2Array([tip, head + wing, head - wing]), wind_color)


## The wind vector as the player sees it: +x to their right, -y away from them.
func _wind_screen_direction() -> Vector2:
	var player: Node3D = GameState.player
	if player == null:
		return Vector2(_wind.x, -_wind.z)
	var basis: Basis = player.global_basis
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x
	return Vector2(_wind.dot(right), -_wind.dot(forward))


# --- levels -------------------------------------------------------------

func _on_level_started(index: int, config: Dictionary) -> void:
	banner_title.text = "LEVEL %d  -  %s" % [index + 1, String(config.get("name", ""))]
	banner_brief.text = "%d m%s" % [
		roundi(float(config.get("distance", 0.0))),
		_wind_suffix(config.get("wind", Vector3.ZERO))
	]
	hint.text = _controls_hint + "\n" + String(config.get("brief", ""))
	hint.modulate.a = 1.0
	_fade_hint()

	# The last level ended with a hit report on screen; it must not bleed into
	# the new one.
	_clear_report()
	_cleared_by = {}

	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	banner.modulate.a = 0.0
	_banner_tween = create_tween()
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(banner_hold)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, banner_fade)


## `target_hit` and `level_completed` can reach the HUD in either order, so this
## both suppresses the line and takes it back down if it already went up.
func _on_level_completed(_index: int, hit: Dictionary, _attempts: int) -> void:
	_cleared_by = hit
	_clear_report()


func _clear_report() -> void:
	if _report_tween != null and _report_tween.is_valid():
		_report_tween.kill()
	report.modulate.a = 0.0


func _wind_suffix(wind: Variant) -> String:
	var w: Vector3 = wind
	if w.is_zero_approx():
		return "  -  still air"
	return "  -  %d m/s crosswind" % roundi(w.length())


func _on_range_completed() -> void:
	_show_report("RANGE COMPLETE", "every level cleared - back to the start", color_direct)


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
	if is_same(hit, _cleared_by):
		return

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


func _on_cinematic_changed(is_active: bool) -> void:
	visible = not is_active


func _fade_hint() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	_hint_tween = create_tween()
	_hint_tween.tween_interval(hint_seconds)
	_hint_tween.tween_property(hint, "modulate:a", 0.0, 1.2)
