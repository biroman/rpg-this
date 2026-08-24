extends Node
## Global signal hub.
##
## Nodes emit and listen here instead of holding hard references to each other.
## Keep it to signals only - no state, no logic.

## Emitted once the player node is in the tree and ready.
@warning_ignore("unused_signal")
signal player_spawned(player: Node3D)

## Emitted whenever the game is paused or resumed.
@warning_ignore("unused_signal")
signal game_paused(is_paused: bool)

## Emitted when the debug overlay is toggled.
@warning_ignore("unused_signal")
signal debug_toggled(is_visible: bool)

## Emitted once the level finished generating.
@warning_ignore("unused_signal")
signal world_ready(world: Node3D)

# --- combat -------------------------------------------------------------

## A weapon fired a shot.
@warning_ignore("unused_signal")
signal weapon_fired(weapon: Node3D)

## Ammo changed: rounds in the tube, rounds in reserve.
@warning_ignore("unused_signal")
signal weapon_ammo_changed(in_magazine: int, reserve: int)

## Reload began; duration is in seconds.
@warning_ignore("unused_signal")
signal weapon_reload_started(duration: float)

## Reload completed.
@warning_ignore("unused_signal")
signal weapon_reload_finished()

## Something exploded. `strength` is 0..1 at the epicentre.
@warning_ignore("unused_signal")
signal explosion_happened(position: Vector3, radius: float, strength: float)

## A rocket detonated. `hit_body` is the body it struck, or null if it timed out.
@warning_ignore("unused_signal")
signal rocket_impact(position: Vector3, normal: Vector3, hit_body: Node, blast_radius: float)

# --- scoring ------------------------------------------------------------

## A target was hit. See `Target._build_report()` for the dictionary shape.
@warning_ignore("unused_signal")
signal target_hit(report: Dictionary)

## A shot landed near a target without scoring. Same dictionary shape.
@warning_ignore("unused_signal")
signal target_missed(report: Dictionary)

## Score totals changed.
@warning_ignore("unused_signal")
signal score_changed()

# --- levels -------------------------------------------------------------

## A level began. `config` is the entry from `LevelManager.LEVELS`.
@warning_ignore("unused_signal")
signal level_started(index: int, config: Dictionary)

## The level's target was hit. `report` is the target's hit dictionary.
@warning_ignore("unused_signal")
signal level_completed(index: int, report: Dictionary, attempts: int)

## Something asked to move on to the next level (result panel, replay skip).
@warning_ignore("unused_signal")
signal next_level_requested()

## The last level was cleared and the range wrapped back to the start.
@warning_ignore("unused_signal")
signal range_completed()

## The level's wind changed. Zero means still air.
@warning_ignore("unused_signal")
signal wind_changed(wind: Vector3)

# --- replay -------------------------------------------------------------

## A rocket finished its flight and filed a recording.
@warning_ignore("unused_signal")
signal shot_recorded(recording: ShotRecording)

## Somebody asked to watch a recording.
@warning_ignore("unused_signal")
signal replay_requested(recording: ShotRecording)

## The replay viewer opened or closed.
@warning_ignore("unused_signal")
signal replay_active(is_active: bool)

## Gameplay was frozen for a cutscene, panel or replay.
@warning_ignore("unused_signal")
signal cinematic_changed(is_active: bool)
