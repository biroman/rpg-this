extends Node
## Owns high level game state: pause, mouse capture, player registry.
##
## Autoloaded as `GameState`. Runs while the tree is paused so it can unpause.

enum State { BOOT, PLAYING, PAUSED, CINEMATIC }

var state: State = State.BOOT
var player: CharacterBody3D = null
var world: Node3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		var mode := DisplayServer.window_get_mode()
		if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()


## Called by Main once the level is loaded.
func start_play() -> void:
	state = State.PLAYING
	get_tree().paused = false
	capture_mouse()


func toggle_pause() -> void:
	if state == State.CINEMATIC:
		return
	set_paused(state != State.PAUSED)


func set_paused(value: bool) -> void:
	if state == State.BOOT or state == State.CINEMATIC:
		return
	if value == (state == State.PAUSED):
		return

	state = State.PAUSED if value else State.PLAYING
	get_tree().paused = value

	if value:
		release_mouse()
	else:
		capture_mouse()

	EventBus.game_paused.emit(value)


func is_playing() -> bool:
	return state == State.PLAYING


## Freezes the whole tree for a replay. Anything that has to keep running
## through it needs `PROCESS_MODE_ALWAYS`.
##
## This deliberately does not go through `set_paused()`: the pause menu must not
## appear on top of a cutscene, and Esc must not unfreeze it.
##
## Clearing a level does not use this. The target coming apart is the payoff for
## the shot, so the range stays live behind the result card and only the replay,
## which takes the camera anyway, stops the world.
func enter_cinematic() -> void:
	if state == State.CINEMATIC or state == State.BOOT:
		return
	state = State.CINEMATIC
	get_tree().paused = true
	release_mouse()
	EventBus.cinematic_changed.emit(true)


func exit_cinematic() -> void:
	if state != State.CINEMATIC:
		return
	state = State.PLAYING
	get_tree().paused = false
	capture_mouse()
	EventBus.cinematic_changed.emit(false)


func is_cinematic() -> bool:
	return state == State.CINEMATIC


func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func register_player(p: CharacterBody3D) -> void:
	player = p
	EventBus.player_spawned.emit(p)


func register_world(w: Node3D) -> void:
	world = w
	EventBus.world_ready.emit(w)


func restart() -> void:
	set_paused(false)
	state = State.BOOT
	get_tree().paused = false
	capture_mouse()
	get_tree().reload_current_scene()


func quit_game() -> void:
	get_tree().quit()
