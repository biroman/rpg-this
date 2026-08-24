extends CanvasLayer
## F3 stats overlay. Autoloaded, so it survives scene changes.

@onready var label: Label = $Panel/Margin/Label

var _fps_accum: float = 0.0
var _refresh: float = 0.15


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible
		EventBus.debug_toggled.emit(visible)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not visible:
		return

	_fps_accum += delta
	if _fps_accum < _refresh:
		return
	_fps_accum = 0.0

	var lines: PackedStringArray = []
	lines.append("FPS        %d" % Engine.get_frames_per_second())
	lines.append("Frame      %.2f ms" % (delta * 1000.0))
	lines.append("State      %s" % GameState.State.keys()[GameState.state])

	var p := GameState.player
	if is_instance_valid(p):
		var pos := p.global_position
		lines.append("Position   %.1f, %.1f, %.1f" % [pos.x, pos.y, pos.z])
		lines.append("Speed      %.2f m/s" % p.get_horizontal_speed())
		lines.append("Grounded   %s" % ("yes" if p.is_on_floor() else "no"))
	else:
		lines.append("Position   -")

	var w := GameState.world
	if is_instance_valid(w):
		var rockets: int = 0
		for child in w.projectiles_root.get_children():
			if child is Rocket:
				rockets += 1
		lines.append("Rockets    %d in flight" % rockets)

	if is_instance_valid(p) and p.weapon_rig != null and p.weapon_rig.weapon != null:
		var weapon: Weapon = p.weapon_rig.weapon
		lines.append("Ammo       %d / %d%s" % [
			weapon.ammo_in_magazine, weapon.ammo_reserve,
			"  (reloading)" if weapon.is_reloading() else ""
		])

	lines.append("Draw calls %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	lines.append("Objects    %d" % RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME))

	label.text = "\n".join(lines)
