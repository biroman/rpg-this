extends Control
## Pause overlay. Runs while the tree is paused, so it owns the pause hotkey.

@onready var resume_button: Button = $Center/Panel/Margin/VBox/Resume


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	EventBus.game_paused.connect(_on_game_paused)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameState.toggle_pause()
		get_viewport().set_input_as_handled()


func _on_game_paused(is_paused: bool) -> void:
	visible = is_paused
	if is_paused:
		resume_button.grab_focus()


func _on_resume_pressed() -> void:
	GameState.set_paused(false)


func _on_restart_pressed() -> void:
	GameState.restart()


func _on_quit_pressed() -> void:
	GameState.quit_game()
