extends Node
## Smoke test: level flow, shot recording and replay playback.
##
## Boots the real game scene, clears level 1, checks that doing so leaves the
## range live, drives the replay viewer through a full scrub, then moves on to
## level 2 and measures how far the crosswind pushes an identical shot. Run this scene directly (F6) after touching
## anything in scenes/replay/, scenes/game/ or the rocket's flight model.
## Results go to stdout and to res://tools/last_replay_test.log.

const LOG_PATH: String = "res://tools/last_replay_test.log"
const SHOT_TIMEOUT: float = 18.0
## Elevation that puts a rocket on the level 1 bullseye in still air.
const HIT_ANGLE: float = 12.0
## Elevations to try per level, and the lead needed to beat the level 2 wind.
const LEVEL1_ANGLES: Array[float] = [12.0, 12.5, 11.5, 13.0]
const LEVEL2_ANGLES: Array[float] = [14.5, 15.0, 14.0, 15.5, 13.5]
const LEVEL2_LEAD_DEG: float = 2.1

@onready var levels: LevelManager = $Main/LevelManager
@onready var replay_view: ReplayView = $Main/ShotReplay

var _lines: PackedStringArray = []
var _impacts: int = 0
var _last_report: Dictionary = {}
var _completed: Array[int] = []


func _ready() -> void:
	EventBus.explosion_happened.connect(_on_explosion)
	EventBus.target_hit.connect(_on_report)
	EventBus.level_completed.connect(_on_level_completed)
	_run.call_deferred()


func _on_explosion(_at: Vector3, _radius: float, _strength: float) -> void:
	_impacts += 1


func _on_report(report: Dictionary) -> void:
	_last_report = report


func _on_level_completed(index: int, _report: Dictionary, _attempts: int) -> void:
	_completed.append(index)


func _run() -> void:
	_log("--- replay smoke test ---")
	await get_tree().create_timer(1.0).timeout

	var player: Player = GameState.player
	if player == null:
		return _fail("no player registered")

	# --- level 1 --------------------------------------------------------
	if levels.index != 0:
		return _fail("did not start on level 1")
	var target: Target = _find_target()
	if target == null:
		return _fail("level 1 spawned no target")
	_log("  level 1: %s, target %.0f m out, wind %.1f m/s"
		% [levels.config()["name"], target.range_from_spawn(), (GameState.world as World).wind.length()])

	if not await _hit_target(player, LEVEL1_ANGLES):
		return _fail("could not land a scoring hit on level 1")
	await get_tree().process_frame
	_log("  hit: %s, %.2f m from centre, %d shot(s)"
		% [_result_label(), float(_last_report.get("miss_distance", 0.0)), levels.attempts])

	if _completed != [0]:
		return _fail("level_completed fired %s, expected [0]" % str(_completed))
	# The whole point of the result card: the target is coming apart right now
	# and the player has to be able to watch it happen.
	if GameState.is_cinematic():
		return _fail("clearing a level froze the game")
	if not GameState.is_playing():
		return _fail("clearing a level left the game out of play")

	# Long enough for the blast to play out with the game still running.
	await get_tree().create_timer(2.5).timeout
	await _capture("result_card")
	if not GameState.is_playing():
		return _fail("the game stopped itself while the result card was up")

	# --- the recording --------------------------------------------------
	var rec: ShotRecording = Replay.last_recording
	if rec == null or not rec.is_valid():
		return _fail("no usable recording was filed")
	if not rec.has_impact():
		return _fail("recording never got an impact")
	if not rec.has_target:
		return _fail("recording was not tagged with the hit result")

	_log("")
	_log("  RECORDING")
	_log("  frames        %d over %.2f s" % [rec.frame_count(), rec.flight_time()])
	_log("  timeline      %.2f s (impact at %.2f s)" % [rec.duration(), rec.impact_time])
	_log("  top speed     %.1f m/s" % rec.top_speed())
	_log("  apex          %.1f m" % rec.apex())
	_log("  ground range  %.1f m" % rec.ground_range())

	var launch_gap: float = rec.sample(0.0)["position"].distance_to(rec.origin)
	if launch_gap > 0.01:
		return _fail("first sample is %.3f m from the muzzle" % launch_gap)
	var end_gap: float = rec.sample(rec.flight_time())["position"].distance_to(rec.impact_point)
	if end_gap > 0.01:
		return _fail("last sample is %.3f m from the impact point" % end_gap)

	# The rocket must not be recorded slowing down into the target: that means a
	# physics contact bled its speed off before the swept hit test saw it.
	var closing: float = float(rec.sample(rec.flight_time() - 0.05)["speed"])
	var struck_at: float = float(rec.sample(rec.flight_time())["speed"])
	_log("  impact speed  %.1f m/s (%.1f m/s a tick earlier)" % [struck_at, closing])
	if absf(struck_at - closing) > 0.15 * maxf(closing, 1.0):
		return _fail("impact speed %.1f m/s does not match the approach at %.1f m/s" % [struck_at, closing])

	# --- playback -------------------------------------------------------
	if not await _exercise_replay(rec):
		return

	# --- level 2 --------------------------------------------------------
	EventBus.next_level_requested.emit()
	await get_tree().process_frame
	if levels.index != 1:
		return _fail("did not advance to level 2")
	if GameState.is_cinematic():
		return _fail("advancing left the game frozen")

	var wind: Vector3 = (GameState.world as World).wind
	if wind.is_zero_approx():
		return _fail("level 2 has no wind")
	var target2: Target = _find_target()
	if target2 == null:
		return _fail("level 2 spawned no target")
	_log("")
	_log("  level 2: %s, target %.0f m out, wind %.1f m/s"
		% [levels.config()["name"], target2.range_from_spawn(), wind.length()])

	await get_tree().create_timer(0.6).timeout
	await _capture("level2_hud")

	# --- wind drift -----------------------------------------------------
	var still: Vector3 = rec.impact_point
	var blown: Dictionary = await _fire(player, HIT_ANGLE)
	if blown.is_empty():
		return _fail("level 2 shot never detonated")

	var drift: float = blown["impact"].x - still.x
	_log("  identical shot drifts %+.1f m downwind over %.0f m"
		% [drift, target2.range_from_spawn()])
	if drift < 1.0:
		return _fail("crosswind pushed the rocket %.2f m - it is not being felt" % drift)
	var blown_rec: ShotRecording = Replay.last_recording
	if blown_rec == null or blown_rec.wind.is_zero_approx():
		return _fail("the level 2 recording did not capture the wind")

	# --- clearing level 2 and wrapping round ----------------------------
	if not await _hit_target(player, LEVEL2_ANGLES, LEVEL2_LEAD_DEG):
		return _fail("could not land a scoring hit on level 2 with a %.1f deg lead" % LEVEL2_LEAD_DEG)
	_log("  hit with lead: %s, %.2f m from centre, %d shot(s)"
		% [_result_label(), float(_last_report.get("miss_distance", 0.0)), levels.attempts])

	if _completed != [0, 1]:
		return _fail("level_completed fired %s, expected [0, 1]" % str(_completed))

	EventBus.next_level_requested.emit()
	await get_tree().process_frame
	if levels.index != 0:
		return _fail("the last level did not wrap back round to level 1")
	if not (GameState.world as World).wind.is_zero_approx():
		return _fail("wrapping back to level 1 left the wind blowing")
	if _find_target() == null:
		return _fail("wrapping back to level 1 spawned no target")
	_log("  cleared the range and wrapped back to level 1 in still air")

	_log("")
	_log("--- PASS ---")
	# Let the last explosion finish playing, or its audio stream leaks at exit.
	await get_tree().create_timer(5.0).timeout
	get_tree().quit(0)


## Opens the replay, scrubs it end to end and checks it stays sane at every
## point on the timeline, including the parts with no rocket left to draw.
func _exercise_replay(rec: ShotRecording) -> bool:
	EventBus.replay_requested.emit(rec)
	await get_tree().process_frame

	if not replay_view.is_open:
		_fail("the replay never opened")
		return false
	if not replay_view.camera.current:
		_fail("the replay camera did not take over the view")
		return false
	if not GameState.is_cinematic():
		_fail("the replay did not freeze the game behind it")
		return false

	_log("")
	_log("  PLAYBACK")
	_log("  time     ghost   camera to rocket   speed")
	for fraction in [0.0, 0.25, 0.48, 0.52, 0.85, 1.0]:
		var at: float = rec.duration() * float(fraction)
		replay_view.seek(at)
		await get_tree().process_frame

		var eye: Vector3 = replay_view.camera.global_position
		if not _is_finite(eye):
			_fail("camera went to %s at t=%.2f" % [str(eye), at])
			return false

		var focus: Vector3 = rec.sample(minf(at, rec.flight_time()))["position"]
		await _capture("replay_%.2f" % at)
		_log("  %5.2f s  %-6s  %8.2f m         %3d m/s" % [
			at,
			"shown" if replay_view.ghost.visible else "gone",
			eye.distance_to(focus),
			roundi(float(rec.sample(minf(at, rec.flight_time()))["speed"])),
		])

	if replay_view.is_playing:
		_fail("scrubbing should pause playback")
		return false

	# Slow motion should advance the clock, but slowly.
	replay_view.seek(0.0)
	replay_view.set_speed(0.1)
	replay_view.toggle_play()
	var before: float = replay_view.time
	await get_tree().create_timer(0.5).timeout
	var moved: float = replay_view.time - before
	_log("  0.1x playback advanced %.3f s of footage in 0.5 s of real time" % moved)
	if moved <= 0.0:
		_fail("playback did not advance")
		return false
	if moved > 0.3:
		_fail("0.1x playback ran at %.2fx" % (moved / 0.5))
		return false

	replay_view.close()
	await get_tree().process_frame
	if replay_view.is_open:
		_fail("the replay would not close")
		return false
	var player: Player = GameState.player
	if player != null and not player.camera.current:
		_fail("closing the replay did not hand the view back to the player")
		return false
	if GameState.is_cinematic():
		_fail("closing the replay left the game frozen")
		return false
	return true


# --- helpers ------------------------------------------------------------

## Fires until the target reports a scoring hit, sweeping the elevation in case
## the flight model has been retuned since these angles were picked.
func _hit_target(player: Player, elevations: Array, yaw: float = 0.0) -> bool:
	for angle in elevations:
		_last_report = {}
		var shot: Dictionary = await _fire(player, float(angle), yaw)
		if shot.is_empty():
			continue
		await get_tree().process_frame
		if bool(_last_report.get("direct", false)) or bool(_last_report.get("blast", false)):
			return true
	return false


func _fire(player: Player, angle: float, yaw: float = 0.0) -> Dictionary:
	var weapon: Weapon = player.weapon_rig.weapon
	while weapon.is_reloading():
		await get_tree().process_frame

	player.set_look(yaw, angle)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	player.set_look(yaw, angle)

	var before: int = _impacts
	if not weapon.try_fire():
		return {}

	var elapsed: float = 0.0
	while _impacts == before and elapsed < SHOT_TIMEOUT:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	if _impacts == before:
		return {}

	var rec: ShotRecording = Replay.last_recording
	return {"time": elapsed, "impact": rec.impact_point if rec != null else Vector3.ZERO}


func _find_target() -> Target:
	for child in (GameState.world as World).props_root.get_children():
		if child is Target:
			return child as Target
	return null


func _result_label() -> String:
	if bool(_last_report.get("direct", false)):
		return "DIRECT %s" % _last_report.get("ring", "")
	if bool(_last_report.get("blast", false)):
		return "BLAST"
	return "MISS"


## Debug aid: run with `-- --shots` to dump what the replay actually looks like.
func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--shots"):
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("user://%s.png" % name)
	print("  saved user://%s.png" % name)


func _is_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _log(line: String) -> void:
	print(line)
	_lines.append(line)
	var f := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
		f.close()


func _fail(reason: String) -> void:
	_log("--- FAIL: %s ---" % reason)
	push_error("REPLAY TEST FAILED: " + reason)
	get_tree().quit(1)
