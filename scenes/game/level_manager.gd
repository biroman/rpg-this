class_name LevelManager
extends Node
## Runs the range one level at a time.
##
## A level is a target at a distance plus the weather it has to be shot through.
## Hitting the target finishes the level; the flow after that (result card,
## replay, next level) is driven entirely through EventBus so this node never
## has to know what the UI looks like.
##
## Clearing a level does not stop play. The target coming apart is the payoff
## for the shot, and freezing on the hit is the one thing guaranteed to hide it,
## so the range stays live and the player leaves when they choose to.

## Levels in order. `wind` is metres per second in world space; the player
## spawns at the origin looking down -Z, so +X is a left-to-right crosswind.
const LEVELS: Array[Dictionary] = [
	{
		"name": "FIRST SHOT",
		"distance": 100.0,
		"target_scale": 1.0,
		"wind": Vector3.ZERO,
		"brief": "The rocket arcs on the way out - aim above the bullseye.",
	},
	{
		"name": "CROSSWIND",
		"distance": 150.0,
		"target_scale": 1.25,
		"wind": Vector3(6.0, 0.0, 0.0),
		"brief": "A crosswind pushes the rocket downrange - lead it into the wind.",
	},
]

@export var target_scene: PackedScene
## Off for automated tests: levels still build, but clearing one does not ask
## the UI for a decision, so a harness can keep firing.
@export var interactive: bool = true

## Index of the level being played.
var index: int = 0
## Rockets fired since this level started.
var attempts: int = 0

var _target: Target = null
var _cleared: bool = false


func _ready() -> void:
	EventBus.weapon_fired.connect(_on_weapon_fired)
	EventBus.target_hit.connect(_on_target_hit)
	EventBus.next_level_requested.connect(_on_next_level_requested)
	# World and Player both run `_ready` before this deferred call, so the
	# spawn point and the player are in place by the time the target lands.
	start_level.call_deferred(0)


func config() -> Dictionary:
	return LEVELS[index]


func level_count() -> int:
	return LEVELS.size()


## Tears down the current level and builds level `at`. Wraps around the list.
func start_level(at: int) -> void:
	var world: World = GameState.world as World
	if world == null:
		push_warning("LevelManager: no world registered, cannot start a level.")
		return

	index = wrapi(at, 0, LEVELS.size())
	attempts = 0
	_cleared = false

	var cfg: Dictionary = LEVELS[index]
	_clear_target()
	world.clear_projectiles()
	world.set_wind(cfg.get("wind", Vector3.ZERO))

	_target = world.spawn(target_scene, Vector3(0.0, 0.0, -float(cfg["distance"]))) as Target
	_target.scale = Vector3.ONE * float(cfg.get("target_scale", 1.0))
	_target.refresh_distance_label.call_deferred()

	_reset_player()
	EventBus.level_started.emit(index, cfg)


func _clear_target() -> void:
	if is_instance_valid(_target):
		_target.queue_free()
	_target = null


## Every level starts from the firing line with a loaded tube.
func _reset_player() -> void:
	var player: Player = GameState.player as Player
	var world: World = GameState.world as World
	if player == null or world == null:
		return
	player.teleport_to(world.get_spawn_transform())
	if player.weapon_rig != null and player.weapon_rig.weapon != null:
		player.weapon_rig.weapon.refill()


# --- progress -----------------------------------------------------------

func _on_weapon_fired(_weapon: Node3D) -> void:
	if not _cleared:
		attempts += 1


func _on_target_hit(report: Dictionary) -> void:
	if _cleared or report.get("target") != _target:
		return
	_cleared = true

	# The rocket files its recording before scoring runs, so the shot that just
	# landed is the newest one. Tag it with how it scored for the replay.
	var recording: ShotRecording = Replay.last_recording
	if recording != null:
		recording.attach_result(report, _target.centre.global_position, index, String(config()["name"]))

	if not interactive:
		return

	EventBus.level_completed.emit(index, report, attempts)


func _on_next_level_requested() -> void:
	# A no-op unless the player came straight out of a replay, which is the only
	# thing that freezes the game now.
	GameState.exit_cinematic()
	var next: int = index + 1
	var wrapped: bool = next >= LEVELS.size()
	start_level(next)
	# After the level, so the "you finished the range" note is not immediately
	# cleared by the new level's banner.
	if wrapped:
		EventBus.range_completed.emit()
