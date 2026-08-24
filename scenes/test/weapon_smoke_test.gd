extends Node
## Smoke test: ballistics table + target scoring.
##
## Boots the real game scene, points the view at fixed elevations, fires, and
## records where each rocket lands and how the target scored it. Run this scene
## directly (F6) after touching anything in scenes/weapons/ or scenes/props/.
## Results go to stdout and to res://tools/last_smoke_test.log.

const BALLISTIC_ANGLES: Array[float] = [0.0, 10.0, 20.0]
const TARGET_ANGLES: Array[float] = [10.0, 10.5, 11.0, 11.5, 12.0]
const SHOT_TIMEOUT: float = 18.0
const LOG_PATH: String = "res://tools/last_smoke_test.log"

var _lines: PackedStringArray = []
var _last_impact: Vector3 = Vector3.ZERO
var _impacts: int = 0
var _last_report: Dictionary = {}


func _ready() -> void:
	EventBus.explosion_happened.connect(_on_explosion)
	EventBus.target_hit.connect(_on_report)
	EventBus.target_missed.connect(_on_report)
	_run.call_deferred()


func _log(line: String) -> void:
	print(line)
	_lines.append(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()


func _on_explosion(at: Vector3, _radius: float, _strength: float) -> void:
	_last_impact = at
	_impacts += 1


func _on_report(report: Dictionary) -> void:
	_last_report = report


func _run() -> void:
	_log("--- weapon smoke test ---")
	await get_tree().create_timer(1.0).timeout

	var player: Player = GameState.player
	if player == null:
		return _fail("no player registered")
	if player.weapon_rig == null or player.weapon_rig.weapon == null:
		return _fail("no weapon on the rig")

	var world: World = GameState.world
	if world == null:
		return _fail("no world registered")

	var weapon: Weapon = player.weapon_rig.weapon
	_log("  weapon: %s   ammo %d/%d" % [weapon.display_name, weapon.ammo_in_magazine, weapon.ammo_reserve])

	var target: Target = _find_target(world)
	if target == null:
		return _fail("no Target in the world")
	_log("  target: %.0f m out, centre at y=%.2f"
		% [Vector2(target.global_position.x, target.global_position.z).length(),
		   target.get_node("Face/Centre").global_position.y])

	# --- ballistics -----------------------------------------------------
	_log("")
	_log("  BALLISTICS")
	_log("  elevation   flight time   range")
	for angle in BALLISTIC_ANGLES:
		var shot := await _fire_at(player, weapon, angle)
		if shot.is_empty():
			return _fail("no detonation at %.1f degrees" % angle)
		_log("  %6.1f deg   %9.2f s   %6.1f m" % [angle, shot["time"], shot["range"]])

	# --- target scoring -------------------------------------------------
	_log("")
	_log("  TARGET SCORING")
	_log("  elevation   result       distance from centre")
	var scored: int = 0
	var reported: int = 0
	for angle in TARGET_ANGLES:
		_last_report = {}
		var shot := await _fire_at(player, weapon, angle)
		if shot.is_empty():
			return _fail("no detonation at %.1f degrees" % angle)

		await get_tree().process_frame
		if _last_report.is_empty():
			_log("  %6.1f deg   (no report - landed outside the report radius)" % angle)
			continue

		reported += 1
		var direct: bool = bool(_last_report.get("direct", false))
		var blast: bool = bool(_last_report.get("blast", false))
		var label: String = "MISS"
		if direct:
			label = "DIRECT %s" % _last_report.get("ring", "")
		elif blast:
			label = "BLAST"
		if direct or blast:
			scored += 1

		_log("  %6.1f deg   %-16s %6.2f m %s  (+%d)" % [
			angle, label, float(_last_report.get("miss_distance", 0.0)),
			"short" if bool(_last_report.get("short", false)) else "long ",
			int(_last_report.get("points", 0))
		])

	_log("")
	_log("  Score: %d points, %d/%d hits (%d%%), best %.2f m"
		% [Score.points, Score.hits, Score.shots, roundi(Score.accuracy() * 100.0), Score.best_distance])

	if reported == 0:
		return _fail("target never reported a single impact")
	if scored == 0:
		return _fail("no elevation in %s scored on the target" % str(TARGET_ANGLES))

	_log("")
	_log("--- PASS: %d scoring hits out of %d target shots ---" % [scored, TARGET_ANGLES.size()])
	# Stay alive briefly so the runner can scrape the error stream.
	await get_tree().create_timer(8.0).timeout
	get_tree().quit(0)


## Fires one shot at the given elevation and waits for its detonation.
func _fire_at(player: Player, weapon: Weapon, angle: float) -> Dictionary:
	while weapon.is_reloading():
		await get_tree().process_frame

	# The window holds mouse capture, so re-assert the aim right before firing.
	player.set_look(0.0, angle)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	player.set_look(0.0, angle)

	var before: int = _impacts
	if not weapon.try_fire():
		return {}

	var origin: Vector3 = player.camera.global_position
	var elapsed: float = 0.0
	while _impacts == before and elapsed < SHOT_TIMEOUT:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	if _impacts == before:
		return {}

	return {
		"time": elapsed,
		"range": Vector2(_last_impact.x - origin.x, _last_impact.z - origin.z).length(),
		"impact": _last_impact,
	}


func _find_target(world: World) -> Target:
	for child in world.props_root.get_children():
		if child is Target:
			return child as Target
	return null


func _fail(reason: String) -> void:
	_log("--- FAIL: %s ---" % reason)
	push_error("SMOKE TEST FAILED: " + reason)
	get_tree().quit(1)
