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
